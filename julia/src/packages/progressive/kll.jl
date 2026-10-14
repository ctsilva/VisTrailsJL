"""
KLL quantile sketch (Karnin, Lang, Liberty 2016), the sketch behind
ProgressiVis' `Quantiles` and `KLLSketch` (which use Apache DataSketches'
`kll_floats_sketch`)

Levels of retained values; a value at level h stands for 2^(h-1) values of
the input. When a level outgrows its capacity (k at the top level, shrinking
by 2/3 per level below, at least 2), it is sorted and every other value
(odd or even positions, at random) moves up one level. The rank error is
about 1.65/k of n with high probability (k = 200: 0.8 %), and the sketch
keeps O(k) values. Sketches merge level by level, so folds over separate
pieces of rows can run in parallel.

Compactions draw from the sketch's own RNG, seeded at creation: results are
reproducible for a given order of updates and merges. NaN and missing values
are not counted.
"""

using Random

mutable struct KLL
    k::Int
    levels::Vector{Vector{Float64}}
    n::Int                 # values counted
    min::Float64
    max::Float64
    rng::Xoshiro
end

KLL(k::Int=200; seed::Integer=42) =
    (k >= 8 || throw(ArgumentError("KLL: k must be at least 8")); KLL(k, [Float64[]], 0, Inf, -Inf, Xoshiro(seed)))

kll_capacity(s::KLL, h::Int) = max(2, ceil(Int, s.k * (2 / 3)^(length(s.levels) - h)))

"""
    kll_update!(s::KLL, values) -> s

Count `values` (NaN and missing skipped).
"""
function kll_update!(s::KLL, values::AbstractVector)
    level = s.levels[1]
    n0 = length(level)
    for x in values
        x === missing && continue
        v = Float64(x)
        isnan(v) && continue
        push!(level, v)
    end
    added = length(level) - n0
    if added > 0
        s.n += added
        lo, hi = extrema(@view level[n0+1:end])
        s.min = min(s.min, lo)
        s.max = max(s.max, hi)
        kll_compress!(s)
    end
    return s
end

"""
    kll_merge!(a::KLL, b::KLL) -> a

Add the values counted by `b` to `a`.
"""
function kll_merge!(a::KLL, b::KLL)
    b.n == 0 && return a
    while length(a.levels) < length(b.levels)
        push!(a.levels, Float64[])
    end
    for (h, level) in enumerate(b.levels)
        append!(a.levels[h], level)
    end
    a.n += b.n
    a.min = min(a.min, b.min)
    a.max = max(a.max, b.max)
    kll_compress!(a)
    return a
end

# Compact levels over capacity, lowest first, until every level fits
function kll_compress!(s::KLL)
    h = 1
    while h <= length(s.levels)
        level = s.levels[h]
        if length(level) > kll_capacity(s, h)
            h == length(s.levels) && push!(s.levels, Float64[])
            sort!(level)
            keep = isodd(length(level)) ? pop!(level) : nothing   # an odd value stays
            append!(s.levels[h + 1], @view level[1 + rand(s.rng, 0:1):2:end])
            empty!(level)
            keep === nothing || push!(level, keep)
            h = 1        # a new level lowers the capacities below it
        else
            h += 1
        end
    end
    return s
end

# Retained values sorted, with the cumulative weight up to each one
function kll_sorted(s::KLL)
    values = Float64[]
    weights = Int[]
    for (h, level) in enumerate(s.levels)
        append!(values, level)
        append!(weights, fill(1 << (h - 1), length(level)))
    end
    order = sortperm(values)
    return values[order], cumsum(weights[order])
end

"""
    kll_quantiles(s::KLL, qs) -> Vector{Float64}

Approximate quantiles (0 ≤ q ≤ 1; 0 and 1 give the exact min and max). NaN
when nothing was counted.
"""
function kll_quantiles(s::KLL, qs)
    s.n == 0 && return fill(NaN, length(qs))
    values, cumulative = kll_sorted(s)
    total = last(cumulative)
    return map(qs) do q
        0 <= q <= 1 || throw(ArgumentError("quantile $q outside [0, 1]"))
        q == 0 && return s.min
        q == 1 && return s.max
        values[min(length(values), searchsortedfirst(cumulative, q * total))]
    end
end

"""
    kll_pmf(s::KLL, edges) -> Vector{Float64}

Approximate fraction of the values in each bin [edges[i], edges[i+1]) (the
last bin closed); values outside the edges are not in any bin.
"""
function kll_pmf(s::KLL, edges::AbstractVector)
    mass = zeros(length(edges) - 1)
    s.n == 0 && return mass
    for (h, level) in enumerate(s.levels), v in level
        b = searchsortedlast(edges, v)
        b == length(edges) && v == last(edges) && (b -= 1)
        1 <= b < length(edges) && (mass[b] += 1 << (h - 1))
    end
    return mass ./ sum(length(l) << (h - 1) for (h, l) in enumerate(s.levels))
end
