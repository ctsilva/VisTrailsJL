"""
Indexes and queries, after ProgressiVis' `table` modules

- `BinningIndex`: equal-width bins of row ids per column, kept up to date as
  rows arrive, change or go; its output `result` is a selection view of the
  indexed rows, carrying the index (`meta[:index]`) for the modules below;
  `min`, `max`: per column, from the extreme bins;
- `RangeQuery` (one column, `lower` ≤ value < `upper`), `RangeQuery2D`
  (two columns), `SimpleFilter` (`column op value`): selection views of the
  rows of an index that match; when a bound changes they re-query the index
  (whole bins inside the range, values checked only in the two boundary
  bins), and subscribers get only the difference; new rows are checked as
  they come;
- `CategoricalQuery`: rows whose `column` is one of `choice` (no index);
- `Intersection`: rows in every input view (views of the same table);
- `Percentiles`: exact percentiles of a column from its index (counts per
  bin, then a partial sort of one bin).

Bins are numbered by `floor((x - origin) / width)`, a monotone function of
x, so a bin strictly between the bins of the bounds holds only values
inside the range: results are exact. Only non-empty bins are stored. NaN and missing values are not
indexed. Outside a progressive run (one-shot engines), query inputs arrive
as plain tables without an index, and queries scan the rows.
"""

# ---------------------------------------------------------------- bins

# Only non-empty bins are stored (bin number → ids), with their numbers in
# order: data with far outliers (taxi coordinates at 0, 0) would otherwise
# need millions of empty bins
mutable struct BinIndex
    origin::Float64
    width::Float64
    bins::Dict{Int, Vector{Int}}   # row ids, per bin number
    numbers::Vector{Int}           # the non-empty bin numbers, sorted
    unsorted::Set{Int}             # bins whose ids are not in order
    count::Int
end

BinIndex(origin::Float64, width::Float64) = BinIndex(origin, width, Dict{Int, Vector{Int}}(), Int[], Set{Int}(), 0)

# The indexes of a BinningIndex module (one per column), behind one lock
struct ColumnIndex
    lock::ReentrantLock
    bins::Dict{Symbol, BinIndex}
end
ColumnIndex() = ColumnIndex(ReentrantLock(), Dict{Symbol, BinIndex}())

bin_number(ix::BinIndex, x::Real) = floor(Int, clamp((Float64(x) - ix.origin) / ix.width, -1e15, 1e15))

indexable(v) = v !== missing && !(v isa AbstractFloat && isnan(v))

# Bin width: `tol` > 0 is the width; `tol` < 0 is |tol| % of the range from
# the 5th to the 95th percentile of the first rows (ProgressiVis' rule)
function bin_width(values::Vector{Float64}, tol::Float64)
    tol > 0 && return tol
    sorted = sort(values)
    at(q) = sorted[clamp(round(Int, q * (length(sorted) - 1)) + 1, 1, length(sorted))]
    w = (at(0.95) - at(0.05)) * abs(tol) / 100
    w > 0 && return w
    w = (last(sorted) - first(sorted)) / 100
    return w > 0 ? w : 1.0
end

function index_add!(ix::BinIndex, ids::AbstractVector{Int}, values::AbstractVector)
    for (id, v) in zip(ids, values)
        indexable(v) || continue
        k = bin_number(ix, v)
        bin = get(ix.bins, k, nothing)
        if bin === nothing
            bin = ix.bins[k] = Int[]
            insert!(ix.numbers, searchsortedfirst(ix.numbers, k), k)
        end
        !isempty(bin) && id < last(bin) && push!(ix.unsorted, k)
        push!(bin, id)
        ix.count += 1
    end
    return ix
end

function index_remove!(ix::BinIndex, ids::RowIds)
    isempty(ids) && return ix
    for (k, bin) in ix.bins
        n = length(bin)
        filter!(id -> !(id in ids), bin)
        ix.count -= n - length(bin)
    end
    emptied = [k for (k, bin) in ix.bins if isempty(bin)]
    foreach(k -> delete!(ix.bins, k), emptied)
    filter!(k -> haskey(ix.bins, k), ix.numbers)
    return ix
end

function bin_ids(ix::BinIndex, k::Int)
    bin = ix.bins[k]
    k in ix.unsorted && (sort!(bin); delete!(ix.unsorted, k))
    return bin
end

"""
    range_ids(ix, col, lo, hi; lo_closed=true, hi_closed=false) -> Vector{Int}

Sorted ids of the indexed rows whose value is within the bounds (±Inf:
unbounded); `col` holds the values.
"""
function range_ids(ix::BinIndex, col::AbstractVector, lo::Float64, hi::Float64;
                   lo_closed::Bool=true, hi_closed::Bool=false)
    out = Int[]
    (isempty(ix.numbers) || lo > hi) && return out
    klo = lo == -Inf ? typemin(Int) : bin_number(ix, lo)
    khi = hi == Inf ? typemax(Int) : bin_number(ix, hi)
    first_ = searchsortedfirst(ix.numbers, klo)
    last_ = searchsortedlast(ix.numbers, khi)
    inside(v) = (lo_closed ? v >= lo : v > lo) && (hi_closed ? v <= hi : v < hi)
    for i in first_:last_
        k = ix.numbers[i]
        if klo < k < khi
            append!(out, bin_ids(ix, k))          # strictly between the bounds' bins: all inside
        else
            for id in ix.bins[k]
                inside(col[id]) && push!(out, id)
            end
        end
    end
    return sort!(out)
end

"""
    index_percentiles(ix, col, ps) -> Vector{Float64}

Exact percentiles (0-100): the value at sorted position
1 + floor(p / 100 · (n - 1)) of the indexed values (numpy's "lower").
"""
function index_percentiles(ix::BinIndex, col::AbstractVector, ps)
    n = ix.count
    n == 0 && return fill(NaN, length(ps))
    cumulative = cumsum(length(ix.bins[k]) for k in ix.numbers)
    return map(ps) do p
        0 <= p <= 100 || throw(ArgumentError("percentile $p outside [0, 100]"))
        rank = 1 + floor(Int, p / 100 * (n - 1))
        b = searchsortedfirst(cumulative, rank)
        within = rank - (b == 1 ? 0 : cumulative[b - 1])
        Float64(partialsort!([col[id] for id in ix.bins[ix.numbers[b]]], within))
    end
end

# Sorted, distinct ids → RowIds in one pass
function rowids_sorted(ids::AbstractVector{Int})
    s = RowIds()
    isempty(ids) && return s
    start = prev = first(ids)
    for id in Iterators.drop(ids, 1)
        if id != prev + 1
            push!(s.ranges, start:prev)
            start = id
        end
        prev = id
    end
    push!(s.ranges, start:prev)
    return s
end

# ---------------------------------------------------------------- BinningIndex

struct BinningIndexModule end
execution_style(::Type{BinningIndexModule}) = Progressive()
default_step_size(::Type{BinningIndexModule}) = 100_000

mutable struct BinningIndexState
    table::ProgressiveTable
    sub::TableSubscription
    columns::Vector{Symbol}
    view::ProgressiveTable
    index::ColumnIndex
    min::ProgressiveDict{Symbol, Any}
    max::ProgressiveDict{Symbol, Any}
    tol::Float64
    threshold::Int
end

function index_columns(ctx::StepContext)
    cols = param(ctx, "columns")
    cols === nothing && (cols = param(ctx, "column"))
    cols === nothing && error("$(ctx.mod.descriptor.name): parameter 'column' (or 'columns') is required")
    return as_symbols(cols)
end

function init_state(::Type{BinningIndexModule}, ctx::StepContext)
    table = input_container(ctx, "table")
    table isa ProgressiveTable || error("BinningIndex: input 'table' must be a table")
    view = set_output!(ctx, "result", selection_view(table))
    index = ColumnIndex()
    view.meta[:index] = index
    return BinningIndexState(table, input_subscription(ctx, "table"), index_columns(ctx), view, index,
                             set_output!(ctx, "min", ProgressiveDict{Symbol, Any}()),
                             set_output!(ctx, "max", ProgressiveDict{Symbol, Any}()),
                             as_float(param(ctx, "tol", -1.0)), as_int(param(ctx, "init_threshold", 10_000)))
end

# Bins are sized from the first `init_threshold` rows (or all, if fewer come)
ready_to_step(s::BinningIndexState, ctx::StepContext) =
    !isempty(s.index.bins) || pending(s.sub).created >= s.threshold || producers_done(ctx)

function step!(s::BinningIndexState, ctx::StepContext, budget::Int)
    if isempty(s.index.bins)
        created = next_created!(s.sub)
        isempty(created) && return StepResult(:blocked, 0)
        list = collect(created)
        lock(s.index.lock) do
            for c in s.columns
                values = s.table[created, c]
                finite = Float64[v for v in values if indexable(v)]
                ix = isempty(finite) ? BinIndex(0.0, 1.0) : BinIndex(minimum(finite), bin_width(finite, s.tol))
                index_add!(ix, list, values)
                s.index.bins[c] = ix
            end
        end
        select!(s.view, created)
        publish_bounds!(s)
        return StepResult(has_changes(s.sub) ? :ready : :blocked, length(list))
    end

    deleted = next_deleted!(s.sub)
    updated = next_updated!(s.sub, budget)
    created = next_created!(s.sub, max(0, budget - length(updated)))
    added = union(updated, created)
    values = Dict(c => s.table[added, c] for c in s.columns)
    lock(s.index.lock) do
        for c in s.columns
            ix = s.index.bins[c]
            index_remove!(ix, union(deleted, updated))
            index_add!(ix, collect(added), values[c])
        end
    end
    deselect!(s.view, deleted)
    touch!(s.view, updated)
    select!(s.view, created)
    publish_bounds!(s)
    items = length(deleted) + length(updated) + length(created)
    items == 0 && return StepResult(:blocked, 0)
    return StepResult(has_changes(s.sub) ? :ready : :blocked, items)
end

# Min and max per column, from the first and last non-empty bins
function publish_bounds!(s::BinningIndexState)
    lock(s.index.lock) do
        for (c, ix) in s.index.bins
            col = column(s.table, c)
            isempty(ix.numbers) && continue
            s.min[c] = minimum(col[id] for id in ix.bins[first(ix.numbers)])
            s.max[c] = maximum(col[id] for id in ix.bins[last(ix.numbers)])
        end
    end
end

consumed_rows(s::BinningIndexState) = lock(() -> setdiff(live_ids(s.table), s.sub.created), s.table.lock)
progress(s::BinningIndexState) = input_progress(s.table, s.sub)

# ---------------------------------------------------------------- queries

# A query's input: the result of a BinningIndex (a view with its index), or
# a plain table (scanned); in the one-shot engines, a table's values
function query_source(ctx::StepContext, port::String)
    c = input_container(ctx, port)
    if c isa ProgressiveTable
        return c, input_subscription(ctx, port), get(c.meta, :index, nothing)
    end
    c isa ProgressiveValue || error("$(ctx.mod.descriptor.name): input '$port' must be a table")
    table = ProgressiveTable(current_value(c))
    return table, subscribe!(table), nothing
end

# One condition on a column: lo (≤ or <) value (< or ≤) hi
struct Condition
    column::Symbol
    lo::Float64
    hi::Float64
    lo_closed::Bool
    hi_closed::Bool
end

holds(c::Condition, v) = indexable(v) && (c.lo_closed ? v >= c.lo : v > c.lo) && (c.hi_closed ? v <= c.hi : v < c.hi)

# A bound parameter: nothing, NaN or ±Inf means unbounded
function bound(x, unbounded::Float64)
    x === nothing && return unbounded
    v = x isa AbstractString ? (isempty(x) || x == "*" ? NaN : parse(Float64, x)) : Float64(x)
    return isfinite(v) ? v : unbounded
end

range_condition(ctx, col, lo, hi) =
    Condition(Symbol(required_param(ctx, col)), bound(param(ctx, lo), -Inf), bound(param(ctx, hi), Inf), true, false)

const SIMPLE_FILTER_OPS = ("<", "<=", ">", ">=", "==")

function filter_condition(ctx)
    column = Symbol(required_param(ctx, "column"))
    op = String(param(ctx, "op", "<"))
    v = Float64(as_float(required_param(ctx, "value")))
    op == "<" && return Condition(column, -Inf, v, true, false)
    op == "<=" && return Condition(column, -Inf, v, true, true)
    op == ">" && return Condition(column, v, Inf, false, true)
    op == ">=" && return Condition(column, v, Inf, true, true)
    op == "==" && return Condition(column, v, v, true, true)
    error("SimpleFilter: unknown op '$op' (use one of $(join(SIMPLE_FILTER_OPS, ", ")))")
end

const QUERY_CONDITIONS = Dict{Symbol, Function}(
    :RangeQuery => ctx -> [range_condition(ctx, "column", "lower", "upper")],
    :RangeQuery2D => ctx -> [range_condition(ctx, "x_column", "x_lower", "x_upper"),
                             range_condition(ctx, "y_column", "y_lower", "y_upper")],
    :SimpleFilter => ctx -> [filter_condition(ctx)])

struct IndexQueryModule{K} end
execution_style(::Type{<:IndexQueryModule}) = Progressive()
default_step_size(::Type{<:IndexQueryModule}) = 100_000

mutable struct IndexQueryState
    kind::Symbol
    source::ProgressiveTable
    sub::TableSubscription
    index::Union{Nothing, ColumnIndex}
    out::ProgressiveTable
    conditions::Vector{Condition}
    started::Bool
end

function init_state(::Type{IndexQueryModule{K}}, ctx::StepContext) where {K}
    source, sub, index = query_source(ctx, "index")
    out = set_output!(ctx, "result", selection_view(source))
    return IndexQueryState(K, source, sub, index, out, Condition[], false)
end

# Rows of `ids` that match every condition
function matching(s::IndexQueryState, ids::RowIds)
    isempty(ids) && return RowIds()
    list = collect(ids)
    keep = trues(length(list))
    for c in s.conditions
        values = s.source[ids, c.column]
        keep .&= holds.(Ref(c), values)
    end
    return rowids_sorted(list[keep])
end

# Every matching row: from the index (bins inside, boundary bins checked) or a scan
function query_all(s::IndexQueryState)
    usable = s.index !== nothing && all(c -> haskey(s.index.bins, c.column), s.conditions)
    usable || return matching(s, row_ids(s.source))
    lock(s.index.lock) do
        result = nothing
        for c in s.conditions
            ids = range_ids(s.index.bins[c.column], column(s.source, c.column), c.lo, c.hi;
                            lo_closed=c.lo_closed, hi_closed=c.hi_closed)
            set = rowids_sorted(ids)
            result = result === nothing ? set : intersect(result, set)
        end
        result
    end
end

function step!(s::IndexQueryState, ctx::StepContext, budget::Int)
    take_control_changes!(ctx, "index")
    conditions = QUERY_CONDITIONS[s.kind](ctx)
    if !s.started || conditions != s.conditions
        # New bounds: re-query everything indexed so far
        s.conditions, s.started = conditions, true
        consume_all!(s.sub)
        set_selection!(s.out, query_all(s))
        return StepResult(has_changes(s.sub) ? :ready : :blocked, max(1, length(s.out)))
    end
    deleted = next_deleted!(s.sub)
    updated = next_updated!(s.sub, budget)
    created = next_created!(s.sub, max(0, budget - length(updated)))
    deselect!(s.out, deleted)
    if !isempty(updated)
        hits = matching(s, updated)
        deselect!(s.out, setdiff(updated, hits))
        touch!(s.out, hits)
        select!(s.out, hits)
    end
    select!(s.out, matching(s, created))
    items = length(deleted) + length(updated) + length(created)
    items == 0 && return StepResult(:blocked, 0)
    return StepResult(has_changes(s.sub) ? :ready : :blocked, items)
end

consumed_rows(s::IndexQueryState) = lock(() -> setdiff(live_ids(s.source), s.sub.created), s.source.lock)
progress(s::IndexQueryState) = input_progress(s.source, s.sub)

# ---------------------------------------------------------------- CategoricalQuery

struct CategoricalQueryModule end
execution_style(::Type{CategoricalQueryModule}) = Progressive()
default_step_size(::Type{CategoricalQueryModule}) = 100_000

mutable struct CategoricalQueryState
    source::ProgressiveTable
    sub::TableSubscription
    out::ProgressiveTable
    column::Symbol
    choice::Union{Nothing, Set{Any}}
end

function init_state(::Type{CategoricalQueryModule}, ctx::StepContext)
    source, sub, _ = query_source(ctx, "table")
    out = set_output!(ctx, "result", selection_view(source))
    return CategoricalQueryState(source, sub, out, Symbol(required_param(ctx, "column")), nothing)
end

function chosen(s::CategoricalQueryState, ids::RowIds)
    isempty(ids) && return RowIds()
    list = collect(ids)
    return rowids_sorted(list[[v in s.choice for v in s.source[ids, s.column]]])
end

function step!(s::CategoricalQueryState, ctx::StepContext, budget::Int)
    take_control_changes!(ctx, "table")
    choice = Set{Any}(something(param(ctx, "choice"), Any[]))
    if s.choice === nothing || choice != s.choice
        s.choice = choice
        consume_all!(s.sub)
        set_selection!(s.out, chosen(s, row_ids(s.source)))
        return StepResult(has_changes(s.sub) ? :ready : :blocked, max(1, length(s.out)))
    end
    deleted = next_deleted!(s.sub)
    updated = next_updated!(s.sub, budget)
    created = next_created!(s.sub, max(0, budget - length(updated)))
    deselect!(s.out, deleted)
    hits = chosen(s, updated)
    deselect!(s.out, setdiff(updated, hits)); touch!(s.out, hits); select!(s.out, hits)
    select!(s.out, chosen(s, created))
    items = length(deleted) + length(updated) + length(created)
    items == 0 && return StepResult(:blocked, 0)
    return StepResult(has_changes(s.sub) ? :ready : :blocked, items)
end

consumed_rows(s::CategoricalQueryState) = lock(() -> setdiff(live_ids(s.source), s.sub.created), s.source.lock)
progress(s::CategoricalQueryState) = input_progress(s.source, s.sub)

# ---------------------------------------------------------------- Intersection

struct IntersectionModule end
execution_style(::Type{IntersectionModule}) = Progressive()

mutable struct IntersectionState
    inputs::Vector{ProgressiveTable}
    subs::Vector{AbstractSubscription}
    out::ProgressiveTable
end

function init_state(::Type{IntersectionModule}, ctx::StepContext)
    containers = get(ctx.inputs, "table", Any[])
    isempty(containers) && error("Intersection: connect at least one table to 'table'")
    # Row ids identify rows only in views: plain values (one-shot engines) do not have them
    length(containers) > 1 && !all(c -> c isa ProgressiveTable, containers) &&
        error("Intersection needs selection views of one table (the progressive engine)")
    inputs = ProgressiveTable[c isa ProgressiveTable ? c : ProgressiveTable(current_value(c)) for c in containers]
    out = set_output!(ctx, "result", selection_view(first(inputs)))
    subs = ctx.run === nothing ? AbstractSubscription[subscribe!(t) for t in inputs] : ctx.subscriptions["table"]
    return IntersectionState(inputs, subs, out)
end

# Recomputed from the inputs' selections at each change: O(rows) per step
function step!(s::IntersectionState, ctx::StepContext, budget::Int)
    any(has_changes, s.subs) || return StepResult(:blocked, 0)
    updated = RowIds()
    for sub in s.subs
        next_created!(sub); next_deleted!(sub)
        union!(updated, next_updated!(sub))
    end
    set_selection!(s.out, reduce(intersect, (row_ids(t) for t in s.inputs)))
    touch!(s.out, updated)
    return StepResult(:blocked, max(1, length(s.out)))
end

# ---------------------------------------------------------------- Percentiles

struct PercentilesModule end
execution_style(::Type{PercentilesModule}) = Progressive()

mutable struct PercentilesState
    source::ProgressiveTable
    sub::TableSubscription
    index::Union{Nothing, ColumnIndex}
    result::ProgressiveDict{Any, Any}
    computed::Bool
end

function init_state(::Type{PercentilesModule}, ctx::StepContext)
    source, sub, index = query_source(ctx, "index")
    return PercentilesState(source, sub, index, set_output!(ctx, "result", ProgressiveDict{Any, Any}()), false)
end

function step!(s::PercentilesState, ctx::StepContext, budget::Int)
    controls = take_control_changes!(ctx, "index")
    changed = has_changes(s.sub)
    (changed || controls || !s.computed) || return StepResult(:blocked, 0)
    consume_all!(s.sub)
    s.computed = true
    c = Symbol(required_param(ctx, "column"))
    ps = Float64.(something(param(ctx, "percentiles"), [25.0, 50.0, 75.0]))
    values = if s.index !== nothing && haskey(s.index.bins, c)
        lock(() -> index_percentiles(s.index.bins[c], column(s.source, c), ps), s.index.lock)
    else
        v = sort!(filter(indexable, s.source[row_ids(s.source), c]))
        [isempty(v) ? NaN : Float64(v[1 + floor(Int, p / 100 * (length(v) - 1))]) for p in ps]
    end
    for (p, v) in zip(ps, values)
        s.result[p] = v
    end
    return StepResult(:blocked, 1)
end

# ---------------------------------------------------------------- registration

function register_progressive_indexes!()
    P = PROGRESSIVE_PACKAGE
    index_params = [("column", String), ("columns", Vector{String}), ("tol", Float64), ("init_threshold", Int)]
    register_module!(ModuleDescriptor(P, "BinningIndex", BinningIndexModule,
        [InputPort("table", ProgressiveTable)],
        [OutputPort("result", ProgressiveTable), OutputPort("min", ProgressiveDict), OutputPort("max", ProgressiveDict)],
        Tuple{String, Type}[index_params...]))
    queries = (
        (:RangeQuery, [("column", String), ("lower", Float64), ("upper", Float64)]),
        (:RangeQuery2D, [("x_column", String), ("y_column", String), ("x_lower", Float64), ("x_upper", Float64),
                         ("y_lower", Float64), ("y_upper", Float64)]),
        (:SimpleFilter, [("column", String), ("op", String), ("value", Float64)]))
    for (name, parameters) in queries
        register_module!(ModuleDescriptor(P, String(name), IndexQueryModule{name},
            [InputPort("index", ProgressiveTable); control_ports(parameters)],
            [OutputPort("result", ProgressiveTable)],
            Tuple{String, Type}[parameters...]))
    end
    categorical = [("column", String), ("choice", Vector{Any})]
    register_module!(ModuleDescriptor(P, "CategoricalQuery", CategoricalQueryModule,
        [InputPort("table", ProgressiveTable); control_ports(categorical)],
        [OutputPort("result", ProgressiveTable)], Tuple{String, Type}[categorical...]))
    register_module!(ModuleDescriptor(P, "Intersection", IntersectionModule,
        [InputPort("table", ProgressiveTable)], [OutputPort("result", ProgressiveTable)], Tuple{String, Type}[]))
    percentiles = [("column", String), ("percentiles", Vector{Float64})]
    register_module!(ModuleDescriptor(P, "Percentiles", PercentilesModule,
        [InputPort("index", ProgressiveTable); control_ports(percentiles)],
        [OutputPort("result", ProgressiveDict)], Tuple{String, Type}[percentiles...]))
end
