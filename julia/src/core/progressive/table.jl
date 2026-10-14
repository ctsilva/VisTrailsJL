"""
ProgressiveTable: a growing columnar table with change tracking

The `PTable` of ProgressiVis, with storage that never moves:

- Columns are stored in fixed-size segments. A segment, once allocated, is
  never reallocated or moved, so a reader can keep reading rows while the
  producer appends (ProgressiVis grows columns with `np.resize`, which can
  reallocate under a reader).
- Appends are published after they are written: rows become visible (in
  `last_id`, in column lengths and in subscriptions) only once every column
  holds their values.
- Row ids are positions in the columns, start at 1 and are never reused;
  deleted rows keep their slot.

Thread safety: one producer writes (append!, setindex!, delete!) while any
number of consumers read published rows and use their subscriptions.
Writes and subscription operations are serialized by the table's lock;
reading published values takes no lock.
"""

using Tables

const DEFAULT_SEGMENT_SIZE = 65_536

"""
    SegmentedColumn{T}

Column storage in fixed-size segments. Indexing covers the published rows
`1:length(col)`. Adding a segment replaces the segment list with a new one
(copy-on-grow), so a reader always sees a consistent list.
"""
mutable struct SegmentedColumn{T} <: AbstractVector{T}
    @atomic segments::Vector{Vector{T}}
    @atomic length::Int        # published rows
    const segment_size::Int
end

SegmentedColumn{T}(segment_size::Int=DEFAULT_SEGMENT_SIZE) where {T} =
    SegmentedColumn{T}(Vector{T}[], 0, segment_size)

Base.size(c::SegmentedColumn) = (@atomic(c.length),)
Base.IndexStyle(::Type{<:SegmentedColumn}) = IndexLinear()

@inline function slot(c::SegmentedColumn, i::Int)
    k, j = divrem(i - 1, c.segment_size)
    return k + 1, j + 1
end

@inline function Base.getindex(c::SegmentedColumn, i::Int)
    @boundscheck checkbounds(c, i)
    k, j = slot(c, i)
    return @inbounds (@atomic c.segments)[k][j]
end

@inline function Base.setindex!(c::SegmentedColumn, v, i::Int)
    @boundscheck checkbounds(c, i)
    k, j = slot(c, i)
    @inbounds (@atomic c.segments)[k][j] = v
    return c
end

"""
    segment_views(c::SegmentedColumn, r::UnitRange{Int}) -> Vector{SubArray}

Contiguous views covering rows `r`, one per storage segment, for fast bulk
reads (e.g. `sum(sum, segment_views(col, r))`). Valid indefinitely, since
segments never move; `r` must be published rows.
"""
function segment_views(c::SegmentedColumn{T}, r::UnitRange{Int}) where {T}
    isempty(r) && return SubArray{T, 1, Vector{T}, Tuple{UnitRange{Int}}, true}[]
    checkbounds(c, r)
    segments = @atomic c.segments
    views = SubArray{T, 1, Vector{T}, Tuple{UnitRange{Int}}, true}[]
    i = first(r)
    while i <= last(r)
        k, j = slot(c, i)
        n = min(last(r) - i + 1, c.segment_size - j + 1)
        push!(views, view(segments[k], j:j+n-1))
        i += n
    end
    return views
end

"""
    gather(c::SegmentedColumn, ids::AbstractVector{<:Integer}) -> Vector

Values at arbitrary published row ids (e.g. the ids of a selection), loading
the segment list once rather than once per element.
"""
function gather(c::SegmentedColumn{T}, ids::AbstractVector{<:Integer}) where {T}
    n = @atomic c.length
    segments = @atomic c.segments
    out = Vector{T}(undef, length(ids))
    @inbounds for (k, id) in enumerate(ids)
        1 <= id <= n || throw(BoundsError(c, id))
        s, j = slot(c, Int(id))
        out[k] = segments[s][j]
    end
    return out
end

"""
    segment(c::SegmentedColumn, k::Int) -> Vector

The `k`-th storage segment (for tests and bulk readers).
"""
segment(c::SegmentedColumn, k::Int) = (@atomic c.segments)[k]

# Write values after the published rows, without publishing them
function write_unpublished!(c::SegmentedColumn{T}, values) where {T}
    i = @atomic c.length
    for v in values
        i += 1
        k, j = slot(c, i)
        segments = @atomic c.segments
        if k > length(segments)
            @atomic c.segments = vcat(segments, [Vector{T}(undef, c.segment_size)])
            segments = @atomic c.segments
        end
        @inbounds segments[k][j] = v
    end
    return c
end

publish!(c::SegmentedColumn, n::Int) = (@atomic c.length = n; c)

"""
    TableSubscription

A consumer's view of a table's changes: buffers of created, updated and
deleted row ids not yet read.
"""
mutable struct TableSubscription <: AbstractSubscription
    table::Any  # ProgressiveTable (defined below)
    created::RowIds
    updated::RowIds
    deleted::RowIds
end

"""
    ProgressiveTable(:x => Float64, :y => Int; segment_size=65536)
    ProgressiveTable(data; segment_size=65536)

A table with typed columns that grows by appending rows, and reports
created / updated / deleted row ids to each subscriber. The second form
creates the columns of a Tables.jl table (e.g. a `NamedTuple` of vectors)
and appends its rows.
"""
mutable struct ProgressiveTable
    names::Vector{Symbol}
    columns::Vector{SegmentedColumn}
    @atomic last_id::Int
    deleted::RowIds
    subscriptions::Vector{TableSubscription}
    lock::ReentrantLock
    base::Union{Nothing, ProgressiveTable}   # a selection view of this table
    meta::Dict{Symbol, Any}                  # what its producer attaches (e.g. an index)
end

ProgressiveTable(names, columns, last_id, deleted, subscriptions, lock) =
    ProgressiveTable(names, columns, last_id, deleted, subscriptions, lock, nothing, Dict{Symbol, Any}())

function ProgressiveTable(schema::Pair{Symbol, <:Type}...; segment_size::Int=DEFAULT_SEGMENT_SIZE)
    segment_size >= 1 || throw(ArgumentError("segment_size must be positive"))
    names = [first(p) for p in schema]
    allunique(names) || throw(ArgumentError("duplicate column names: $names"))
    columns = SegmentedColumn[SegmentedColumn{last(p)}(segment_size) for p in schema]
    return ProgressiveTable(names, columns, 0, RowIds(), TableSubscription[], ReentrantLock())
end

function ProgressiveTable(data; segment_size::Int=DEFAULT_SEGMENT_SIZE)
    Tables.istable(data) || throw(ArgumentError("expected a Tables.jl table"))
    cols = Tables.columns(data)
    names = collect(Symbol, Tables.columnnames(cols))
    t = ProgressiveTable((n => eltype(Tables.getcolumn(cols, n)) for n in names)...;
                         segment_size=segment_size)
    append!(t, data)
    return t
end

column_names(t::ProgressiveTable) = copy(t.names)

function column_index(t::ProgressiveTable, name::Symbol)
    i = findfirst(==(name), t.names)
    i === nothing && throw(KeyError(name))
    return i
end

"""
    column(t::ProgressiveTable, name::Symbol) -> SegmentedColumn

A column, indexed by row id over `1:last_id(t)` (deleted rows included).
"""
column(t::ProgressiveTable, name::Symbol) = t.columns[column_index(t, name)]
Base.getindex(t::ProgressiveTable, name::Symbol) = column(t, name)
Base.getindex(t::ProgressiveTable, id::Integer, name::Symbol) = column(t, name)[id]

"""
    t[ids::RowIds, name] -> Vector

Values of a column at the given row ids, in increasing id order.
"""
function Base.getindex(t::ProgressiveTable, ids::RowIds, name::Symbol)
    col = column(t, name)
    is_fragmented(ids) && return gather(col, collect(ids))
    out = Vector{eltype(col)}(undef, length(ids))
    i = 0
    for r in ranges(ids), v in segment_views(col, r)
        copyto!(out, i + 1, v, 1, length(v))
        i += length(v)
    end
    return out
end

"""
    is_fragmented(ids::RowIds) -> Bool

Whether `ids` are scattered (ranges of fewer than 32 ids on average, e.g. a
query's selection): such rows are read by gathering values, not range by
range.
"""
is_fragmented(ids::RowIds) = length(ids.ranges) > 1 && 32 * length(ids.ranges) > length(ids)

"""
    last_id(t::ProgressiveTable) -> Int

The highest published row id (deleted rows included).
"""
last_id(t::ProgressiveTable) = @atomic t.last_id

"""
    row_ids(t::ProgressiveTable) -> RowIds

The ids of the live (published, not deleted) rows.
"""
row_ids(t::ProgressiveTable) = @lock t.lock live_ids(t)
live_ids(t::ProgressiveTable) = setdiff!(RowIds(1:last_id(t)), t.deleted)

Base.length(t::ProgressiveTable) = @lock t.lock last_id(t) - length(t.deleted)
Base.isempty(t::ProgressiveTable) = length(t) == 0

"""
    append!(t::ProgressiveTable, data) -> UnitRange{Int}

Append the rows of a Tables.jl table (e.g. a `NamedTuple` of vectors) that
has (at least) the table's columns. Returns the new row ids.
"""
function Base.append!(t::ProgressiveTable, data)::UnitRange{Int}
    is_view(t) && throw(ArgumentError("append! to a selection view: append to its base table"))
    cols = Tables.columns(data)
    values = [Tables.getcolumn(cols, name) for name in t.names]
    n = isempty(values) ? 0 : length(first(values))
    all(v -> length(v) == n, values) || throw(DimensionMismatch("columns have different lengths"))

    @lock t.lock begin
        first_id = last_id(t) + 1
        new_last = first_id + n - 1
        for (col, v) in zip(t.columns, values)
            write_unpublished!(col, v)
        end
        # Publish only after every column holds the new rows
        for col in t.columns
            publish!(col, new_last)
        end
        @atomic t.last_id = new_last
        for sub in t.subscriptions
            add!(sub.created, first_id:new_last)
        end
        return first_id:new_last
    end
end

"""
    push!(t::ProgressiveTable, row::NamedTuple) -> Int

Append one row; returns its id.
"""
Base.push!(t::ProgressiveTable, row::NamedTuple) =
    first(append!(t, map(v -> [v], row)))

function check_live(t::ProgressiveTable, id::Integer)
    (1 <= id <= last_id(t) && !(id in t.deleted)) ||
        throw(ArgumentError("row $id does not exist or was deleted"))
end

"""
    t[id, name] = value

Update a value of a live row; reported as an update to subscribers that
have already read the row.
"""
function Base.setindex!(t::ProgressiveTable, value, id::Integer, name::Symbol)
    is_view(t) && throw(ArgumentError("setindex! on a selection view: update its base table"))
    col = column(t, name)
    @lock t.lock begin
        check_live(t, id)
        col[id] = value
        for sub in t.subscriptions
            id in sub.created || add!(sub.updated, Int(id))
        end
    end
    return value
end

"""
    delete!(t::ProgressiveTable, ids)

Delete live rows (an id, a range or an `RowIds`). Subscribers that had not
read a row yet never hear of it; the others get it as deleted.
"""
function Base.delete!(t::ProgressiveTable, ids::RowIds)
    @lock t.lock begin
        foreach(id -> check_live(t, id), ids)
        union!(t.deleted, ids)
        for sub in t.subscriptions
            unseen = intersect(ids, sub.created)
            setdiff!(sub.created, ids)
            setdiff!(sub.updated, ids)
            union!(sub.deleted, setdiff(ids, unseen))
        end
    end
    return t
end

Base.delete!(t::ProgressiveTable, ids::UnitRange{Int}) = delete!(t, RowIds(ids))
Base.delete!(t::ProgressiveTable, id::Integer) = delete!(t, RowIds(Int(id):Int(id)))

function Base.show(io::IO, t::ProgressiveTable)
    print(io, "ProgressiveTable(", length(t), " rows; ",
          join(("$n::$(eltype(c))" for (n, c) in zip(t.names, t.columns)), ", "), ")")
end

# Selection views

"""
    selection_view(base::ProgressiveTable) -> ProgressiveTable

A table of selected rows of `base` (ProgressiVis' `PTableSelectedView`):
it shares base's columns, and its rows are the base rows its producer
selects, with the same ids, so consumers read it like any table. Selecting
and deselecting rows (`select!`, `deselect!`, `set_selection!`) reach
subscribers as created and deleted rows; `touch!` reports updates of
selected rows (after the base's values changed). Rows can be selected again
after being deselected. Appends and writes go to the base table.

Unselected ids up to `last_id(view)` are its `deleted` set, so its length
and progress count only selected rows.
"""
function selection_view(base::ProgressiveTable)
    return ProgressiveTable(copy(base.names), base.columns, 0, RowIds(), TableSubscription[], ReentrantLock(),
                            base, Dict{Symbol, Any}())
end

is_view(t::ProgressiveTable) = t.base !== nothing

"""
    select!(view, ids::RowIds)

Add published rows of the base to a selection view (ids already selected
are ignored).
"""
function select!(v::ProgressiveTable, ids::RowIds)
    is_view(v) || throw(ArgumentError("select! needs a selection view"))
    isempty(ids) && return v
    last(ids) <= last_id(v.base) || throw(ArgumentError("rows after $(last_id(v.base)) are not published in the base"))
    @lock v.lock begin
        old_last = last_id(v)
        # Rows past the old end: new to every subscriber
        fresh = old_last < last(ids) ? intersect(ids, RowIds(old_last+1:last(ids))) : RowIds()
        if !isempty(fresh)
            union!(v.deleted, setdiff!(RowIds(old_last+1:last(ids)), fresh))
            @atomic v.last_id = last(ids)
        end
        # Rows deselected before, now selected again
        again = intersect(ids, v.deleted)
        isempty(fresh) || setdiff!(again, fresh)
        setdiff!(v.deleted, again)
        for sub in v.subscriptions
            union!(sub.created, fresh)
            isempty(again) && continue
            back = intersect(again, sub.deleted)       # deletion not read yet: an update
            setdiff!(sub.deleted, back)
            union!(sub.updated, back)
            union!(sub.created, setdiff(again, back))
        end
    end
    return v
end

"""
    deselect!(view, ids::RowIds)

Remove rows from a selection view (ids not selected are ignored).
"""
function deselect!(v::ProgressiveTable, ids::RowIds)
    is_view(v) || throw(ArgumentError("deselect! needs a selection view"))
    @lock v.lock begin
        gone = intersect(ids, live_ids(v))
        isempty(gone) && return v
        union!(v.deleted, gone)
        for sub in v.subscriptions
            unseen = intersect(gone, sub.created)
            setdiff!(sub.created, gone)
            setdiff!(sub.updated, gone)
            union!(sub.deleted, setdiff(gone, unseen))
        end
    end
    return v
end

"""
    set_selection!(view, ids::RowIds)

Make `ids` the selection: subscribers get only the difference.
"""
function set_selection!(v::ProgressiveTable, ids::RowIds)
    current = row_ids(v)
    deselect!(v, setdiff(current, ids))
    select!(v, setdiff(ids, current))
    return v
end

"""
    touch!(view, ids::RowIds)

Report the selected rows among `ids` as updated (their values changed in
the base).
"""
function touch!(v::ProgressiveTable, ids::RowIds)
    @lock v.lock begin
        changed = intersect(ids, live_ids(v))
        for sub in v.subscriptions
            union!(sub.updated, setdiff(changed, sub.created))
        end
    end
    return v
end

# Subscriptions

function subscribe!(t::ProgressiveTable)
    @lock t.lock begin
        sub = TableSubscription(t, live_ids(t), RowIds(), RowIds())
        push!(t.subscriptions, sub)
        return sub
    end
end

function unsubscribe!(sub::TableSubscription)
    t = sub.table
    @lock t.lock filter!(s -> s !== sub, t.subscriptions)
    return sub
end

has_changes(sub::TableSubscription) =
    @lock sub.table.lock !(isempty(sub.created) && isempty(sub.updated) && isempty(sub.deleted))

"""
    pending(sub::TableSubscription) -> (created, updated, deleted)

Number of unread changes of each kind.
"""
pending(sub::TableSubscription) =
    @lock sub.table.lock (created=length(sub.created), updated=length(sub.updated),
                          deleted=length(sub.deleted))

"""
    next_created!(sub, n=typemax(Int)) -> RowIds
    next_updated!(sub, n=typemax(Int)) -> RowIds
    next_deleted!(sub, n=typemax(Int)) -> RowIds

Take up to `n` unread changes of a kind, smallest ids first. The returned
rows are published, so their values can be read.
"""
next_created!(sub::TableSubscription, n::Integer=typemax(Int)) =
    @lock sub.table.lock take_first!(sub.created, n)
next_updated!(sub::TableSubscription, n::Integer=typemax(Int)) =
    @lock sub.table.lock take_first!(sub.updated, n)
next_deleted!(sub::TableSubscription, n::Integer=typemax(Int)) =
    @lock sub.table.lock take_first!(sub.deleted, n)

function reset!(sub::TableSubscription)
    t = sub.table
    @lock t.lock begin
        sub.created = live_ids(t)
        empty!(sub.updated)
        empty!(sub.deleted)
    end
    return sub
end

# Tables.jl interface: a snapshot of the live rows

Tables.istable(::Type{ProgressiveTable}) = true
Tables.columnaccess(::Type{ProgressiveTable}) = true

function Tables.columns(t::ProgressiveTable)
    ids = row_ids(t)
    return NamedTuple{Tuple(t.names)}(Tuple(t[ids, name] for name in t.names))
end

Tables.schema(t::ProgressiveTable) = Tables.Schema(t.names, [eltype(c) for c in t.columns])
