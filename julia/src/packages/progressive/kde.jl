"""
KernelDensity, after ProgressiVis' `KernelDensity` (k-nearest-neighbor
kernel density of 2-D points)

The points (`x_column`, `y_column` of `table`; default `x`, `y`) are
inserted into a spatial index as they arrive. Every `threshold` inserted rows
(default 1000) and when the input is read, the density is estimated at the
sample points: at each, the mean of Gaussian kernels (`bandwidth`, default
0.2, in data units) over its `knn` nearest points (default 100), as
ProgressiVis' `KNNKernelDensity`. The sample points are `samples` (a list of
[x, y]) or the centers of a `bins` × `bins` grid (default 32) over the
points' extent so far. Output `result`: one row per sample point (`x`, `y`,
`density`), updated in place.

ProgressiVis uses pynene's approximate neighbor index and fails on input
deletions; here neighbors are exact, and updates or deletions rebuild the
index. Non-finite points are skipped.
"""

# Points for nearest-neighbor queries, in sorted runs (the logarithmic
# method): each inserted batch becomes a run sorted along a Z-order curve,
# and a run is merged with the previous one while that one is at most twice
# its size, so a point is merged O(log n) times, in sequential passes. Each
# run has a static quadtree of ranges of its points (cells of the Z-order
# codes, split where points are dense) with the bounding box of each cell's
# points. The codes interleave the top 32 bits of the coordinates mapped to
# order-preserving integers: no bounds are needed, and far outliers do not
# coarsen the cells of dense regions (taxi pickups).
struct IndexRun
    code::Vector{UInt64}
    x::Vector{Float64}
    y::Vector{Float64}
    lo::Vector{Int}                  # nodes: range of points,
    hi::Vector{Int}
    first::Vector{Int}               # children (consecutive nodes; 0: leaf),
    count::Vector{Int}
    x0::Vector{Float64}              # bounding box of the points
    y0::Vector{Float64}
    x1::Vector{Float64}
    y1::Vector{Float64}
end

mutable struct PointIndex
    runs::Vector{IndexRun}
    n::Int
    xlo::Float64                     # the points' extent
    xhi::Float64
    ylo::Float64
    yhi::Float64
end

PointIndex() = PointIndex(IndexRun[], 0, Inf, -Inf, Inf, -Inf)

const INDEX_BUCKET = 32

@inline function sortable_bits(v::Float64)
    u = reinterpret(UInt64, v)
    return (u >> 63) == 1 ? ~u : u | 0x8000000000000000
end

@inline function spread_bits(v::UInt64)
    v = (v | (v << 16)) & 0x0000ffff0000ffff
    v = (v | (v << 8)) & 0x00ff00ff00ff00ff
    v = (v | (v << 4)) & 0x0f0f0f0f0f0f0f0f
    v = (v | (v << 2)) & 0x3333333333333333
    return (v | (v << 1)) & 0x5555555555555555
end

@inline zorder(x::Float64, y::Float64) = spread_bits(sortable_bits(x) >> 32) | (spread_bits(sortable_bits(y) >> 32) << 1)

function IndexRun(code::Vector{UInt64}, x::Vector{Float64}, y::Vector{Float64})
    r = IndexRun(code, x, y, Int[], Int[], Int[], Int[], Float64[], Float64[], Float64[], Float64[])
    isempty(code) || build_node!(r, add_run_node!(r, 1, length(code)), 62)
    return r
end

function add_run_node!(r::IndexRun, lo::Int, hi::Int)
    push!(r.lo, lo); push!(r.hi, hi); push!(r.first, 0); push!(r.count, 0)
    push!(r.x0, Inf); push!(r.y0, Inf); push!(r.x1, -Inf); push!(r.y1, -Inf)
    return length(r.lo)
end

# Split a node's range by the 2 code bits at `shift` (skipping levels where
# all its points fall in one cell); children first, then their subtrees
function build_node!(r::IndexRun, node::Int, shift::Int)
    lo, hi = r.lo[node], r.hi[node]
    while hi - lo + 1 > INDEX_BUCKET && shift >= 0 && (r.code[lo] >> shift) & 3 == (r.code[hi] >> shift) & 3
        shift -= 2
    end
    if hi - lo + 1 <= INDEX_BUCKET || shift < 0
        for i in lo:hi
            r.x0[node] = min(r.x0[node], r.x[i]); r.x1[node] = max(r.x1[node], r.x[i])
            r.y0[node] = min(r.y0[node], r.y[i]); r.y1[node] = max(r.y1[node], r.y[i])
        end
        return
    end
    ranges = UnitRange{Int}[]
    start = lo
    while start <= hi
        q = (r.code[start] >> shift) & 3
        stop = start
        while stop < hi && (r.code[stop + 1] >> shift) & 3 == q
            stop += 1
        end
        push!(ranges, start:stop)
        start = stop + 1
    end
    first = 0
    for rg in ranges
        c = add_run_node!(r, Base.first(rg), last(rg))
        first == 0 && (first = c)
    end
    r.first[node], r.count[node] = first, length(ranges)
    for c in first:first+length(ranges)-1
        build_node!(r, c, shift - 2)
        r.x0[node] = min(r.x0[node], r.x0[c]); r.x1[node] = max(r.x1[node], r.x1[c])
        r.y0[node] = min(r.y0[node], r.y0[c]); r.y1[node] = max(r.y1[node], r.y1[c])
    end
end

function merge_runs(a::IndexRun, b::IndexRun)
    n = length(a.code) + length(b.code)
    code, x, y = Vector{UInt64}(undef, n), Vector{Float64}(undef, n), Vector{Float64}(undef, n)
    i, j = 1, 1
    @inbounds for k in 1:n
        if j > length(b.code) || (i <= length(a.code) && a.code[i] <= b.code[j])
            code[k], x[k], y[k] = a.code[i], a.x[i], a.y[i]
            i += 1
        else
            code[k], x[k], y[k] = b.code[j], b.x[j], b.y[j]
            j += 1
        end
    end
    return IndexRun(code, x, y)
end

function insert_points!(g::PointIndex, xs::AbstractVector, ys::AbstractVector)
    keep = [isfinite(x) && isfinite(y) for (x, y) in zip(xs, ys)]
    x, y = Float64.(xs[keep]), Float64.(ys[keep])
    isempty(x) && return g
    code = zorder.(x, y)
    order = sortperm(code)
    push!(g.runs, IndexRun(code[order], x[order], y[order]))
    while length(g.runs) >= 2 && length(g.runs[end-1].code) <= 2 * length(g.runs[end].code)
        b = pop!(g.runs)
        g.runs[end] = merge_runs(g.runs[end], b)
    end
    g.n += length(x)
    (xlo, xhi), (ylo, yhi) = extrema(x), extrema(y)
    g.xlo, g.xhi, g.ylo, g.yhi = min(g.xlo, xlo), max(g.xhi, xhi), min(g.ylo, ylo), max(g.yhi, yhi)
    return g
end

# Keep the k smallest squared distances, sorted
@inline function offer!(best::Vector{Float64}, d::Float64, k::Int)
    if length(best) < k
        insert!(best, searchsortedfirst(best, d), d)
    elseif d < best[end]
        pop!(best)
        insert!(best, searchsortedfirst(best, d), d)
    end
end

@inline function node_distance2(r::IndexRun, n::Int, qx::Float64, qy::Float64)
    dx = max(r.x0[n] - qx, 0.0, qx - r.x1[n])
    dy = max(r.y0[n] - qy, 0.0, qy - r.y1[n])
    return dx * dx + dy * dy
end

# Squared distances to the k nearest points (sorted): in each run, depth
# first, nearest cells first, skipping cells farther than the k-th distance
function knn_distances(g::PointIndex, qx::Float64, qy::Float64, k::Int)
    best = Float64[]
    k <= 0 && return best
    stack = Tuple{Int, Float64}[]
    for r in g.runs
        push!(stack, (1, node_distance2(r, 1, qx, qy)))
        while !isempty(stack)
            node, d = pop!(stack)
            length(best) == k && d >= best[end] && continue
            c = r.first[node]
            if c == 0
                @inbounds for i in r.lo[node]:r.hi[node]
                    offer!(best, (r.x[i] - qx)^2 + (r.y[i] - qy)^2, k)
                end
            else
                base = length(stack)
                for m in c:c+r.count[node]-1
                    push!(stack, (m, node_distance2(r, m, qx, qy)))
                end
                # Nearest last, popped first
                sort!(view(stack, base+1:length(stack)); by=last, rev=true)
            end
        end
    end
    return best
end

function knn_density(g::PointIndex, x::Float64, y::Float64, k::Int, bandwidth::Float64)
    d2 = knn_distances(g, x, y, k)
    isempty(d2) && return 0.0
    return sum(d -> exp(-0.5 * d / bandwidth^2), d2) / (bandwidth * sqrt(2π)) / k
end

struct KernelDensityModule end
execution_style(::Type{KernelDensityModule}) = Progressive()
default_step_size(::Type{KernelDensityModule}) = 100_000

mutable struct KernelDensityState
    table::ProgressiveTable
    sub::TableSubscription
    xcol::Symbol
    ycol::Symbol
    index::PointIndex
    out::ProgressiveTable
    unscored::Int                    # rows inserted since the last estimate
end

function init_state(::Type{KernelDensityModule}, ctx::StepContext)
    table = input_container(ctx, "table")
    table isa ProgressiveTable || error("KernelDensity: input 'table' must be a table")
    xcol, ycol = Symbol(param(ctx, "x_column", "x")), Symbol(param(ctx, "y_column", "y"))
    for c in (xcol, ycol)
        c in column_names(table) || error("KernelDensity: no column '$c' in the input")
    end
    out = set_output!(ctx, "result", ProgressiveTable(:x => Float64, :y => Float64, :density => Float64))
    return KernelDensityState(table, input_subscription(ctx, "table"), xcol, ycol, PointIndex(), out, 0)
end

function sample_points(s::KernelDensityState, ctx)
    samples = param(ctx, "samples")
    samples === nothing || return Float64[as_float(p[1]) for p in samples], Float64[as_float(p[2]) for p in samples]
    bins = as_int(param(ctx, "bins", 32))
    x0, x1, y0, y1 = s.index.xlo, s.index.xhi, s.index.ylo, s.index.yhi
    xs = [x0 + (i - 0.5) * (x1 - x0) / bins for i in 1:bins]
    ys = [y0 + (j - 0.5) * (y1 - y0) / bins for j in 1:bins]
    return repeat(xs, outer=bins), repeat(ys, inner=bins)
end

function estimate!(s::KernelDensityState, ctx)
    s.unscored = 0
    s.index.n == 0 && return
    xs, ys = sample_points(s, ctx)
    k, bw = as_int(param(ctx, "knn", 100)), as_float(param(ctx, "bandwidth", 0.2))
    density = Vector{Float64}(undef, length(xs))
    Threads.@threads for i in eachindex(xs)
        density[i] = knn_density(s.index, xs[i], ys[i], k, bw)
    end
    if isempty(s.out)
        append!(s.out, (x=xs, y=ys, density=density))
    else
        update_rows!(s.out, collect(row_ids(s.out)), (x=xs, y=ys, density=density))
    end
end

function step!(s::KernelDensityState, ctx::StepContext, budget::Int)
    counts = pending(s.sub)
    if counts.updated > 0 || counts.deleted > 0 || take_control_changes!(ctx, "table")
        reset!(s.sub)
        s.index = PointIndex()
        s.unscored = 1                # estimate again even if no rows are left
    end
    ids = next_created!(s.sub, budget)
    isempty(ids) || insert_points!(s.index, s.table[ids, s.xcol], s.table[ids, s.ycol])
    s.unscored += length(ids)
    more = has_changes(s.sub)
    (s.unscored >= as_int(param(ctx, "threshold", 1000)) || (!more && s.unscored > 0)) && estimate!(s, ctx)
    return StepResult(more ? :ready : :blocked, length(ids))
end

consumed_rows(s::KernelDensityState) = lock(() -> setdiff(live_ids(s.table), s.sub.created), s.table.lock)
progress(s::KernelDensityState) = input_progress(s.table, s.sub)

function register_progressive_kde!()
    parameters = [("knn", Int), ("bandwidth", Float64), ("bins", Int), ("threshold", Int), ("samples", Any)]
    register_module!(ModuleDescriptor(PROGRESSIVE_PACKAGE, "KernelDensity", KernelDensityModule,
        [InputPort("table", ProgressiveTable); control_ports(parameters)],
        [OutputPort("result", ProgressiveTable)],
        vcat(Tuple{String, Type}[("x_column", String), ("y_column", String)], parameters)))
end
