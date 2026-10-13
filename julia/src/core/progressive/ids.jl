"""
RowIds: sets of row ids stored as sorted, disjoint ranges

Appends produce contiguous ids, so the common case is one or a few ranges;
scattered ids (updates, deletions) cost one range each. Plays the role of
ProgressiVis' `PIntSet` (roaring bitmaps).
"""

"""
    RowIds()
    RowIds(r::UnitRange{Int})
    RowIds(ids)

Set of positive integer ids, kept as sorted, non-overlapping, non-adjacent ranges.
"""
mutable struct RowIds
    ranges::Vector{UnitRange{Int}}
end

RowIds() = RowIds(UnitRange{Int}[])
RowIds(r::UnitRange{Int}) = isempty(r) ? RowIds() : RowIds([r])

function RowIds(ids)
    s = RowIds()
    for i in sort!(collect(Int, ids))
        add!(s, i)
    end
    return s
end

Base.copy(s::RowIds) = RowIds(copy(s.ranges))
Base.length(s::RowIds) = sum(length, s.ranges; init=0)
Base.isempty(s::RowIds) = isempty(s.ranges)
Base.empty!(s::RowIds) = (empty!(s.ranges); s)
Base.:(==)(a::RowIds, b::RowIds) = a.ranges == b.ranges
Base.eltype(::Type{RowIds}) = Int

"""
    ranges(s::RowIds) -> Vector{UnitRange{Int}}

The ranges making up the set, in increasing order (do not modify).
"""
ranges(s::RowIds) = s.ranges

function Base.iterate(s::RowIds, state=(1, 0))
    k, offset = state
    k > length(s.ranges) && return nothing
    r = s.ranges[k]
    id = first(r) + offset
    next = id == last(r) ? (k + 1, 0) : (k, offset + 1)
    return id, next
end

# Index of the first range whose end is >= id
first_range_ending_at_or_after(s::RowIds, id::Int) = searchsortedfirst(s.ranges, id, by=r -> r isa Int ? r : last(r))

function Base.in(id::Integer, s::RowIds)
    k = first_range_ending_at_or_after(s, Int(id))
    return k <= length(s.ranges) && first(s.ranges[k]) <= id
end

Base.first(s::RowIds) = first(first(s.ranges))
Base.last(s::RowIds) = last(last(s.ranges))

"""
    add!(s::RowIds, r::UnitRange{Int}) / add!(s::RowIds, id::Int)

Insert ids, merging with overlapping or adjacent ranges.
"""
function add!(s::RowIds, r::UnitRange{Int})
    isempty(r) && return s
    rs = s.ranges
    # Fast path: append after the last range
    if isempty(rs) || first(r) > last(rs[end]) + 1
        push!(rs, r)
        return s
    end
    # Ranges that overlap or touch r: those ending at or after first(r)-1 and
    # starting at or before last(r)+1
    lo = first_range_ending_at_or_after(s, first(r) - 1)
    hi = lo
    while hi <= length(rs) && first(rs[hi]) <= last(r) + 1
        hi += 1
    end
    if lo == hi
        insert!(rs, lo, r)
    else
        merged = min(first(r), first(rs[lo])):max(last(r), last(rs[hi - 1]))
        rs[lo] = merged
        deleteat!(rs, lo+1:hi-1)
    end
    return s
end

add!(s::RowIds, id::Integer) = add!(s, Int(id):Int(id))

"""
    remove!(s::RowIds, r::UnitRange{Int}) / remove!(s::RowIds, id::Int)

Remove ids (absent ids are ignored).
"""
function remove!(s::RowIds, r::UnitRange{Int})
    isempty(r) && return s
    rs = s.ranges
    lo = first_range_ending_at_or_after(s, first(r))
    lo > length(rs) && return s
    pieces = UnitRange{Int}[]
    hi = lo
    while hi <= length(rs) && first(rs[hi]) <= last(r)
        current = rs[hi]
        first(current) < first(r) && push!(pieces, first(current):first(r)-1)
        last(current) > last(r) && push!(pieces, last(r)+1:last(current))
        hi += 1
    end
    splice!(rs, lo:hi-1, pieces)
    return s
end

remove!(s::RowIds, id::Integer) = remove!(s, Int(id):Int(id))

function Base.union!(s::RowIds, t::RowIds)
    for r in t.ranges
        add!(s, r)
    end
    return s
end

function Base.setdiff!(s::RowIds, t::RowIds)
    for r in t.ranges
        remove!(s, r)
    end
    return s
end

Base.union(s::RowIds, t::RowIds) = union!(copy(s), t)
Base.setdiff(s::RowIds, t::RowIds) = setdiff!(copy(s), t)
Base.intersect(s::RowIds, t::RowIds) = setdiff(s, setdiff(s, t))

"""
    take_first!(s::RowIds, n::Integer) -> RowIds

Remove and return the (up to) `n` smallest ids.
"""
function take_first!(s::RowIds, n::Integer)
    taken = RowIds()
    rs = s.ranges
    while n > 0 && !isempty(rs)
        r = rs[1]
        if length(r) <= n
            push!(taken.ranges, r)
            n -= length(r)
            popfirst!(rs)
        else
            push!(taken.ranges, first(r):first(r)+n-1)
            rs[1] = first(r)+n:last(r)
            n = 0
        end
    end
    return taken
end

function Base.show(io::IO, s::RowIds)
    shown = join((length(r) == 1 ? string(first(r)) : "$(first(r)):$(last(r))" for r in first(s.ranges, 5)), ", ")
    more = length(s.ranges) > 5 ? ", …" : ""
    print(io, "RowIds(", shown, more, ")")
end
