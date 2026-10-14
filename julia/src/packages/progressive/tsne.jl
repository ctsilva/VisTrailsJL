"""
TSNE: a progressive t-SNE embedding, after ProgressiVis' `TSNE` (which
wraps pynene's `ProgressiVisTSNE`, Jo et al.'s progressive t-SNE)

The rows of `table` (`columns`, default numeric) are embedded into
`output_columns` (default `x`, `y`) of `result`, one row per input row,
moving in place as the optimization runs. Each step inserts up to its
budget of new rows, then runs `iterations` gradient iterations (default 1,
as ProgressiVis) on every row inserted so far:

- affinities: each row's `3 · perplexity` nearest rows (default perplexity
  30), exact, kept up to date as rows arrive (new rows can enter older
  rows' neighbor lists); conditional probabilities calibrated to the
  perplexity by bisection, symmetrized as usual;
- new rows start at the mean position of their nearest rows already
  embedded;
- gradient descent with momentum and gains (van der Maaten 2014), learning
  rate max(N / exaggeration / 4, 50) (sklearn's "auto"), early
  exaggeration 12 during the first `exaggeration_iterations` (250);
  repulsion by Barnes-Hut (`theta`, default 0.5) for 2-D outputs, exact
  otherwise.

After `max_iter` iterations (default 1000) without new rows, the module
stops until more arrive. Input updates and deletions restart it. Neighbors
are exact (pynene's are approximate): inserting costs O(rows · d) per row,
O(N² d) in all, practical up to some tens of thousands of rows.
"""

# Barnes-Hut quadtree over 2-D positions (arrays of nodes, rebuilt each iteration)

# A node as queries read it: center of mass, squared cell width, points, children
struct BHNode
    cx::Float64
    cy::Float64
    width2::Float64
    count::Int
    child::Int
end

mutable struct QuadTree
    count::Vector{Int}
    sx::Vector{Float64}              # sums of positions (center of mass × count)
    sy::Vector{Float64}
    midx::Vector{Float64}            # cell center and half width
    midy::Vector{Float64}
    half::Vector{Float64}
    child::Vector{Int}               # first of 4 children (0: leaf)
    point::Vector{Int}               # the point of a one-point leaf
    nodes::Vector{BHNode}            # what queries read, packed (after build!)
end
QuadTree() = QuadTree(Int[], Float64[], Float64[], Float64[], Float64[], Float64[], Int[], Int[], BHNode[])

const QUADTREE_MAX_DEPTH = 48

function add_node!(t::QuadTree, mx, my, h)
    push!(t.count, 0); push!(t.sx, 0.0); push!(t.sy, 0.0)
    push!(t.midx, mx); push!(t.midy, my); push!(t.half, h)
    push!(t.child, 0); push!(t.point, 0)
    return length(t.count)
end

quadrant(t::QuadTree, node, x, y) = t.child[node] + (x >= t.midx[node]) + 2 * (y >= t.midy[node])

function build!(t::QuadTree, Y)
    foreach(empty!, (t.count, t.sx, t.sy, t.midx, t.midy, t.half, t.child, t.point))
    (x0, x1), (y0, y1) = extrema(view(Y, 1, :)), extrema(view(Y, 2, :))
    h = max(x1 - x0, y1 - y0) / 2 * (1 + 1e-9) + 1e-12
    add_node!(t, (x0 + x1) / 2, (y0 + y1) / 2, h)
    for i in axes(Y, 2)
        insert_point!(t, Y, i)
    end
    resize!(t.nodes, length(t.count))
    @inbounds for k in eachindex(t.count)
        c = t.count[k]
        t.nodes[k] = BHNode(c > 0 ? t.sx[k] / c : 0.0, c > 0 ? t.sy[k] / c : 0.0, (2 * t.half[k])^2, c, t.child[k])
    end
    return t
end

function insert_point!(t::QuadTree, Y, i)
    x, y = Y[1, i], Y[2, i]
    node, depth = 1, 0
    while true
        if t.count[node] == 0
            t.count[node] = 1; t.sx[node] = x; t.sy[node] = y; t.point[node] = i
            return
        end
        if t.child[node] == 0 && depth < QUADTREE_MAX_DEPTH
            # A leaf with one point: split it
            p = t.point[node]
            t.point[node] = 0
            h = t.half[node] / 2
            first = 0
            for q in 0:3
                c = add_node!(t, t.midx[node] + (isodd(q) ? h : -h), t.midy[node] + (q >= 2 ? h : -h), h)
                q == 0 && (first = c)
            end
            t.child[node] = first
            c = quadrant(t, node, Y[1, p], Y[2, p])
            t.count[c] = 1; t.sx[c] = Y[1, p]; t.sy[c] = Y[2, p]; t.point[c] = p
        end
        t.count[node] += 1; t.sx[node] += x; t.sy[node] += y
        t.child[node] == 0 && return             # deepest leaf: coincident points
        node = quadrant(t, node, x, y)
        depth += 1
    end
end

function repulsion!(F, t::QuadTree, Y, i, theta, stack=Int[])
    x, y = Y[1, i], Y[2, i]
    total, fx, fy = 0.0, 0.0, 0.0
    theta2 = theta^2
    nodes = t.nodes
    empty!(stack)
    push!(stack, 1)
    @inbounds while !isempty(stack)
        nd = nodes[pop!(stack)]
        cnt = nd.count
        cnt == 0 && continue
        dx, dy = x - nd.cx, y - nd.cy
        d2 = dx * dx + dy * dy
        leaf = nd.child == 0
        if leaf || nd.width2 < theta2 * d2
            leaf && d2 < 1e-24 && (cnt -= 1)        # this point itself (and any coincident ones)
            cnt == 0 && continue
            q = 1 / (1 + d2)
            total += cnt * q
            fx += cnt * q * q * dx
            fy += cnt * q * q * dy
        else
            c = nd.child
            push!(stack, c, c + 1, c + 2, c + 3)
        end
    end
    F[1, i] += fx
    F[2, i] += fy
    return total
end

struct TSNEModule end
execution_style(::Type{TSNEModule}) = Progressive()
default_step_size(::Type{TSNEModule}) = 1_000

mutable struct TSNEState
    table::ProgressiveTable
    sub::TableSubscription
    columns::Vector{Symbol}
    names::Vector{Symbol}
    out::ProgressiveTable
    rng::Xoshiro
    n::Int                               # rows embedded
    X::Matrix{Float64}                   # d × capacity: their features
    sqnorm::Vector{Float64}
    Y::Matrix{Float64}                   # m × capacity: their positions
    update::Matrix{Float64}
    gains::Matrix{Float64}
    out_rows::Vector{Int}                # output row of each
    neighbors::Vector{Vector{Int}}       # nearest rows, by distance
    dist2::Vector{Vector{Float64}}       # their squared distances
    cond::Vector{Vector{Float64}}        # p(j | i) for each neighbor j
    iteration::Int
    remaining::Int                       # iterations before stopping
    tree::QuadTree                       # Barnes-Hut quadtree, reused
    pstart::Vector{Int}                  # symmetric affinities (CSR): row i's entries
    pcol::Vector{Int}                    # pstart[i]:pstart[i+1]-1, neighbors j with
    pval::Vector{Float64}                # p(j | i) and p(i | j) (both directions)
end

function init_state(::Type{TSNEModule}, ctx::StepContext)
    table = input_container(ctx, "table")
    table isa ProgressiveTable || error("TSNE: input 'table' must be a table")
    columns = numeric_columns(ctx, table)
    names = as_symbols(param(ctx, "output_columns", ["x", "y"]))
    out = set_output!(ctx, "result", ProgressiveTable((n => Float64 for n in names)...))
    d, m = length(columns), length(names)
    return TSNEState(table, input_subscription(ctx, "table"), columns, names, out,
                     Xoshiro(as_int(param(ctx, "seed", 0))), 0, zeros(d, 0), Float64[], zeros(m, 0), zeros(m, 0),
                     zeros(m, 0), Int[], Vector{Int}[], Vector{Float64}[], Vector{Float64}[], 0, 0, QuadTree(), Int[], Int[], Float64[])
end

function grow!(s::TSNEState, n::Int)
    cap = size(s.X, 2)
    n <= cap && return
    newcap = max(n, 2cap, 64)
    wider(A, fillvalue) = (B = fill(fillvalue, size(A, 1), newcap); B[:, 1:cap] = A; B)
    s.X, s.Y, s.update, s.gains = wider(s.X, 0.0), wider(s.Y, 0.0), wider(s.update, 0.0), wider(s.gains, 1.0)
end

# Insert rows `ids`: their features, neighbors, and the neighbor lists they enter
function insert_rows!(s::TSNEState, ids::RowIds, perplexity::Float64)
    F = reduce(hcat, [Float64.(s.table[ids, c]) for c in s.columns])'     # d × b
    keep = [all(isfinite, view(F, :, i)) for i in axes(F, 2)]
    F = F[:, keep]
    b = size(F, 2)
    b == 0 && return 0
    n0 = s.n
    n = n0 + b
    grow!(s, n)
    s.X[:, n0+1:n] = F
    append!(s.sqnorm, vec(sum(abs2, F; dims=1)))
    s.n = n
    k = min(round(Int, 3 * perplexity), n - 1)
    dirty = fill(false, n)           # (Bool, not bits: written from threads)
    # Distances from the new rows to all rows, in blocks of bounded memory
    block = max(1, 4_000_000 ÷ n)
    Xall = view(s.X, :, 1:n)
    for lo in n0+1:block:n
        hi = min(n, lo + block - 1)
        # Column t: squared distances from new row lo + t - 1 to all rows
        D = Xall' * view(s.X, :, lo:hi)
        b_ = hi - lo + 1
        lists = Vector{Vector{Int}}(undef, b_)
        dists = Vector{Vector{Float64}}(undef, b_)
        Threads.@threads for chunk in collect(Iterators.partition(1:b_, cld(b_, Threads.nthreads())))
            perm = Vector{Int}(undef, n)                 # reused within the chunk
            for t in chunk
                i = lo + t - 1
                col = view(D, :, t)
                @inbounds for j in 1:n
                    col[j] = max(s.sqnorm[i] + s.sqnorm[j] - 2 * col[j], 0.0)
                end
                col[i] = Inf
                order = partialsortperm!(perm, col, 1:k; initialized=false)
                lists[t] = collect(order)
                dists[t] = col[lists[t]]
            end
        end
        append!(s.neighbors, lists)
        append!(s.dist2, dists)
        dirty[lo:hi] .= true
        # Older rows whose neighbor lists the new rows enter
        Threads.@threads for j in 1:n0
            for t in 1:b_
                enter_neighbors!(s.neighbors[j], s.dist2[j], lo + t - 1, D[j, t], k) && (dirty[j] = true)
            end
        end
    end
    calibrate!(s, findall(dirty), perplexity)
    symmetrize!(s)
    # Positions: the mean of the nearest rows already embedded
    for i in n0+1:n
        near = [j for j in s.neighbors[i] if j <= n0][1:min(3, count(<=(n0), s.neighbors[i]))]
        for a in axes(s.Y, 1)
            base = isempty(near) ? 0.0 : sum(s.Y[a, j] for j in near) / length(near)
            s.Y[a, i] = base + 1e-4 * randn(s.rng)
        end
        s.update[:, i] .= 0.0
        s.gains[:, i] .= 1.0
    end
    rows::UnitRange{Int} = append!(s.out, NamedTuple{Tuple(s.names)}(Tuple(s.Y[a, n0+1:n] for a in axes(s.Y, 1))))
    append!(s.out_rows, rows)
    return b
end

# Insert neighbor i at squared distance d into a sorted list of at most k
function enter_neighbors!(list::Vector{Int}, d2::Vector{Float64}, i::Int, d::Float64, k::Int)
    length(list) < k || d < d2[end] || return false
    p = searchsortedlast(d2, d) + 1
    insert!(list, p, i); insert!(d2, p, d)
    if length(list) > k
        pop!(list); pop!(d2)
    end
    return true
end

# Each directed affinity p(j | i), in row i and in row j: the attractive
# force on a row then reads only its own entries (rows run on threads)
function symmetrize!(s::TSNEState)
    n = s.n
    counts = zeros(Int, n + 1)
    for i in 1:n
        counts[i] += length(s.neighbors[i])
        for j in s.neighbors[i]
            counts[j] += 1
        end
    end
    s.pstart = Vector{Int}(undef, n + 1)
    s.pstart[1] = 1
    for i in 1:n
        s.pstart[i + 1] = s.pstart[i] + counts[i]
    end
    total = s.pstart[n + 1] - 1
    s.pcol, s.pval = Vector{Int}(undef, total), Vector{Float64}(undef, total)
    next = s.pstart[1:n]
    @inbounds for i in 1:n
        list, p = s.neighbors[i], s.cond[i]
        for t in eachindex(list)
            j = list[t]
            s.pcol[next[i]], s.pval[next[i]] = j, p[t]; next[i] += 1
            s.pcol[next[j]], s.pval[next[j]] = i, p[t]; next[j] += 1
        end
    end
end

function calibrate!(s::TSNEState, rows::Vector{Int}, perplexity::Float64)
    length(s.cond) < s.n && append!(s.cond, [Float64[] for _ in length(s.cond)+1:s.n])
    Threads.@threads for i in rows
        s.cond[i] = cond_probabilities(s.dist2[i], perplexity)
    end
end

# p(j | i) over i's neighbors, with the entropy of the target perplexity
# (smaller when there are few neighbors), by bisection on the precision
function cond_probabilities(d2::Vector{Float64}, perplexity::Float64)
    isempty(d2) && return Float64[]
    target = log(clamp(length(d2) / 3, 1.0, perplexity))
    dmin = d2[1]
    shifted = d2 .- dmin
    mean_d = sum(shifted) / length(shifted)
    beta = mean_d > 0 ? 1 / mean_d : 1.0
    lo, hi = 0.0, Inf
    p = similar(d2)
    for _ in 1:200
        p .= exp.(-beta .* shifted)
        total = sum(p)
        H = log(total) + beta * sum(shifted .* p) / total
        abs(H - target) < 1e-5 && break
        if H > target
            lo = beta
            beta = isinf(hi) ? 2beta : (beta + hi) / 2
        else
            hi = beta
            beta = (beta + lo) / 2
        end
    end
    return p ./ sum(p)
end

# Gradient iterations

function iterate_tsne!(s::TSNEState, ctx)
    n, m = s.n, size(s.Y, 1)
    n < 2 && return
    early = s.iteration < as_int(param(ctx, "exaggeration_iterations", 250))
    exaggeration = early ? as_float(param(ctx, "early_exaggeration", 12.0)) : 1.0
    momentum = early ? 0.5 : 0.8
    rate = param(ctx, "learning_rate")
    eta = rate === nothing || rate == "auto" ? max(n / exaggeration / 4, 50.0) : as_float(rate)
    Y = view(s.Y, :, 1:n)
    attract = zeros(m, n)
    attractive_forces!(attract, Y, s.pstart, s.pcol, s.pval, n)
    repulse = zeros(m, n)
    sumq = zeros(n)
    if m == 2
        build!(s.tree, Y)
        theta = as_float(param(ctx, "theta", 0.5))
        # Points in Z-order: a chunk's points are close, so their traversals
        # read the same nodes (2.4x → better use of threads, measured)
        order = sortperm([zorder(Y[1, i], Y[2, i]) for i in 1:n])
        Threads.@threads for chunk in collect(Iterators.partition(order, cld(n, 4 * Threads.nthreads())))
            stack = Int[]                                 # reused within the chunk
            for i in chunk
                sumq[i] = repulsion!(repulse, s.tree, Y, i, theta, stack)
            end
        end
    else
        Threads.@threads for i in 1:n
            sumq[i] = exact_repulsion!(repulse, Y, i)
        end
    end
    Z = sum(sumq)
    @inbounds for i in 1:n, a in 1:m
        g = 4 * (exaggeration * attract[a, i] - repulse[a, i] / Z)
        u = s.update[a, i]
        s.gains[a, i] = g * u < 0 ? s.gains[a, i] + 0.2 : max(s.gains[a, i] * 0.8, 0.01)
        s.update[a, i] = momentum * u - eta * s.gains[a, i] * g
        s.Y[a, i] += s.update[a, i]
    end
    center = sum(Y; dims=2) ./ n
    Y .-= center
    s.iteration += 1
end

# Σ_j P_ij q_ij (y_i − y_j), P_ij = (p(j | i) + p(i | j)) / 2N, row by row
function attractive_forces!(F, Y, pstart, pcol, pval, n)
    m = size(Y, 1)
    Threads.@threads for i in 1:n
        @inbounds for e in pstart[i]:pstart[i + 1]-1
            j = pcol[e]
            d2 = 0.0
            for a in 1:m
                d2 += (Y[a, i] - Y[a, j])^2
            end
            w = pval[e] / (2n) / (1 + d2)
            for a in 1:m
                F[a, i] += w * (Y[a, i] - Y[a, j])
            end
        end
    end
end

# Σ_j q_ij² (y_i − y_j) into F[:, i]; returns Σ_j q_ij
function exact_repulsion!(F, Y, i)
    m, n = size(Y)
    total = 0.0
    @inbounds for j in 1:n
        j == i && continue
        d2 = 0.0
        for a in 1:m
            d2 += (Y[a, i] - Y[a, j])^2
        end
        q = 1 / (1 + d2)
        total += q
        for a in 1:m
            F[a, i] += q * q * (Y[a, i] - Y[a, j])
        end
    end
    return total
end

function step!(s::TSNEState, ctx::StepContext, budget::Int)
    counts = pending(s.sub)
    if counts.updated > 0 || counts.deleted > 0
        # Start over from all rows
        existing = row_ids(s.out)
        isempty(existing) || delete!(s.out, existing)
        reset!(s.sub)
        s.n = s.iteration = 0
        foreach(empty!, (s.sqnorm, s.out_rows, s.neighbors, s.dist2, s.cond, s.pstart, s.pcol, s.pval))
    end
    perplexity = as_float(param(ctx, "perplexity", 30.0))
    ids = next_created!(s.sub, budget)
    inserted = isempty(ids) ? 0 : insert_rows!(s, ids, perplexity)
    isempty(ids) || (s.remaining = as_int(param(ctx, "max_iter", 1000)))
    if s.remaining > 0 && s.n >= 2
        for _ in 1:as_int(param(ctx, "iterations", 1))
            iterate_tsne!(s, ctx)
            s.remaining -= 1
            s.remaining == 0 && break
        end
        update_rows!(s.out, s.out_rows, NamedTuple{Tuple(s.names)}(Tuple(s.Y[a, 1:s.n] for a in axes(s.Y, 1))))
    end
    more = has_changes(s.sub) || (s.remaining > 0 && s.n >= 2)
    return StepResult(more ? :ready : :blocked, length(ids))
end

consumed_rows(s::TSNEState) = lock(() -> setdiff(live_ids(s.table), s.sub.created), s.table.lock)
progress(s::TSNEState) = input_progress(s.table, s.sub)

function register_progressive_tsne!()
    register_module!(ModuleDescriptor(PROGRESSIVE_PACKAGE, "TSNE", TSNEModule,
        [InputPort("table", ProgressiveTable)], [OutputPort("result", ProgressiveTable)],
        Tuple{String, Type}[("columns", Vector{String}), ("output_columns", Vector{String}),
                            ("perplexity", Float64), ("max_iter", Int), ("iterations", Int), ("theta", Float64),
                            ("learning_rate", Any), ("early_exaggeration", Float64),
                            ("exaggeration_iterations", Int), ("seed", Int)]))
end
