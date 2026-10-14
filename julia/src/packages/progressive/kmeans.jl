"""
Mini-batch k-means, after ProgressiVis' `MBKMeans` and `MBKMeansFilter`

- `MBKMeans`: clusters the rows of `table` (`columns`, default numeric)
  into `n_clusters` with mini-batch k-means (Sculley 2010, as sklearn's
  `MiniBatchKMeans`): each iteration draws `batch_size` rows (default 1024)
  uniformly from the rows read so far and moves each center towards the
  mean of its rows, weighted by the rows it has seen. Centers start with
  greedy k-means++ on `batch_size` random rows (as sklearn's first
  `partial_fit`) once `max(n_clusters, batch_size)` rows are there. On data
  with scattered outliers (taxi coordinates), the iterations to converge
  depend much on the seed (in both systems).
  A step runs up to its budget of iterations, until no center moves more
  than `tol` (default 1e-5, in data units: converged); new rows resume the
  iterations. Outputs:
  - `result`: the centers, one row per cluster, updated in place;
  - `labels`: the cluster (1-based) of every row read (column `row`: the
    input row id; `label`), computed in passes over the rows as the
    centers move, `batch_size` rows per iteration of budget;
  - `converged`: whether the centers have converged.
  The input `moved_center` (optional; a `Dict` cluster → coordinates, e.g.
  from a `Variable`) moves centers by hand, as ProgressiVis' `set_centroid`.
  Input updates and deletions restart the counts (centers are kept).
- `MBKMeansFilter`: the rows of `table` whose label (from `labels`) is
  `cluster`, as a selection view, following the labels as they change.

Draws come from one generator seeded by `seed`: results are reproducible
for given step sizes.
"""

struct MBKMeansModule end
execution_style(::Type{MBKMeansModule}) = Progressive()
default_step_size(::Type{MBKMeansModule}) = 100        # iterations

mutable struct MBKMeansState
    table::ProgressiveTable
    sub::TableSubscription
    columns::Vector{Symbol}
    k::Int
    batch_size::Int
    tol::Float64
    rng::Xoshiro
    ids::Vector{Int}                 # input rows read, in order
    centers::Matrix{Float64}         # d × k (empty: not initialized)
    counts::Vector{Float64}          # rows seen per center
    converged::Bool
    iterations::Int
    result::ProgressiveTable
    labels::ProgressiveTable
    label_row::Vector{Int}           # input row id → labels row (0: none)
    cursor::Int                      # labelling pass: ids[1:cursor] labelled with `pass_centers`
    pass_centers::Matrix{Float64}
    converged_out::ProgressiveValue{Bool}
    moved::Union{ValueSubscription, Nothing}
end

function init_state(::Type{MBKMeansModule}, ctx::StepContext)
    table = input_container(ctx, "table")
    table isa ProgressiveTable || error("MBKMeans: input 'table' must be a table")
    columns = numeric_columns(ctx, table)
    k = as_int(required_param(ctx, "n_clusters"))
    k >= 1 || error("MBKMeans: n_clusters must be positive")
    result = set_output!(ctx, "result", ProgressiveTable((c => Float64 for c in columns)...))
    labels = set_output!(ctx, "labels", ProgressiveTable(:row => Int, :label => Int))
    conv = set_output!(ctx, "converged", ProgressiveValue{Bool}(false))
    moved = has_input(ctx, "moved_center") ? input_subscription(ctx, "moved_center") : nothing
    return MBKMeansState(table, input_subscription(ctx, "table"), columns, k,
                         as_int(param(ctx, "batch_size", 1024)), as_float(param(ctx, "tol", 1e-5)),
                         Xoshiro(as_int(param(ctx, "seed", 0))), Int[], zeros(length(columns), 0), zeros(k),
                         false, 0, result, labels, Int[], 0, zeros(length(columns), 0), conv, moved)
end

# Rows `ids` of the clustered columns, as a d × n matrix
function row_matrix(t::ProgressiveTable, columns::Vector{Symbol}, ids::Vector{Int})
    X = Matrix{Float64}(undef, length(columns), length(ids))
    for (j, c) in enumerate(columns)
        fill_row!(X, j, gather(column(t, c), ids))
    end
    return X
end
fill_row!(X::Matrix{Float64}, j::Int, v::AbstractVector) = (@inbounds for i in eachindex(v); X[j, i] = v[i]; end)

function nearest_center(C::Matrix{Float64}, X::Matrix{Float64}, i::Int)
    best, dbest = 1, Inf
    @inbounds for c in axes(C, 2)
        d = 0.0
        for j in axes(X, 1)
            d += (X[j, i] - C[j, c])^2
        end
        d < dbest && ((best, dbest) = (c, d))
    end
    return best, dbest
end

# Greedy k-means++ seeding on rows X (d × n), as sklearn's: each center is
# the best of 2 + log(k) candidates drawn ∝ D² (the one leaving the least
# potential). Outliers get centers of their own, which then stay put (plain
# k-means++ can leave a center among scattered outliers, moving forever).
function kmeanspp(X::Matrix{Float64}, k::Int, rng)
    n = size(X, 2)
    trials = 2 + floor(Int, log(k))
    C = Matrix{Float64}(undef, size(X, 1), k)
    C[:, 1] = X[:, rand(rng, 1:n)]
    d2 = [sum(abs2, view(X, :, i) .- view(C, :, 1)) for i in 1:n]
    candidate_d2 = similar(d2)
    best_d2 = similar(d2)
    for c in 2:k
        total = sum(d2)
        best, best_potential = 0, Inf
        for _ in 1:trials
            i = total > 0 ? draw_weighted(d2, rand(rng) * total) : rand(rng, 1:n)
            for m in 1:n
                candidate_d2[m] = min(d2[m], sum(abs2, view(X, :, m) .- view(X, :, i)))
            end
            potential = sum(candidate_d2)
            if potential < best_potential
                best, best_potential = i, potential
                best_d2 .= candidate_d2
            end
        end
        C[:, c] = X[:, best]
        d2 .= best_d2
    end
    return C
end

# The index where the cumulative sum of `w` reaches r
function draw_weighted(w::Vector{Float64}, r::Float64)
    acc = 0.0
    for j in eachindex(w)
        acc += w[j]
        acc >= r && return j
    end
    return lastindex(w)
end

# One mini-batch update; returns the largest center move
function minibatch_update!(s::MBKMeansState, X::Matrix{Float64})
    old = copy(s.centers)
    sums = zeros(size(X, 1), s.k)
    seen = zeros(s.k)
    for i in axes(X, 2)
        c, _ = nearest_center(s.centers, X, i)
        seen[c] += 1
        @views sums[:, c] .+= X[:, i]
    end
    for c in 1:s.k
        seen[c] == 0 && continue
        total = s.counts[c] + seen[c]
        @views s.centers[:, c] .= (s.centers[:, c] .* s.counts[c] .+ sums[:, c]) ./ total
        s.counts[c] = total
    end
    return maximum(c -> sqrt(sum(abs2, view(s.centers, :, c) .- view(old, :, c))), 1:s.k)
end

function apply_moved_centers!(s::MBKMeansState)
    s.moved === nothing && return false
    has_changes(s.moved) || return false
    moves = take_value!(s.moved)
    (moves === nothing || isempty(s.centers)) && return false
    for (c, coords) in moves
        c = as_int(c)
        1 <= c <= s.k || error("MBKMeans: no cluster $c to move")
        length(coords) == length(s.columns) || error("MBKMeans: cluster $c moved to $(length(coords)) coordinates, expected $(length(s.columns))")
        s.centers[:, c] = as_float_vector(coords)
        s.counts[c] = 1          # as ProgressiVis: the next rows pull it freely
    end
    return true
end

function step!(s::MBKMeansState, ctx::StepContext, budget::Int)
    counts = pending(s.sub)
    if counts.updated > 0 || counts.deleted > 0
        # Rows changed: read them again, forget the counts, keep the centers
        reset!(s.sub)
        empty!(s.ids)
        fill!(s.counts, 0)
        # Labels of deleted rows go too
        live = row_ids(s.table)
        gone = [r for (id, r) in enumerate(s.label_row) if r != 0 && !(id in live)]
        isempty(gone) || delete!(s.labels, RowIds(gone))
        foreach(id -> id in live || (s.label_row[id] = 0), eachindex(s.label_row))
        s.converged = false
        s.cursor = 0
    end
    created = next_created!(s.sub)
    if !isempty(created)
        append!(s.ids, created)
        s.converged = false
    end
    moved = apply_moved_centers!(s)
    moved && (s.converged = false)
    n = length(s.ids)
    n < max(s.k, s.batch_size) && return StepResult(:blocked, 0)

    if isempty(s.centers)
        sample = s.ids[rand(s.rng, 1:n, min(n, s.batch_size))]
        s.centers = kmeanspp(row_matrix(s.table, s.columns, sample), s.k, s.rng)
    end
    iterations = 0
    while !s.converged && iterations < budget
        batch = s.ids[rand(s.rng, 1:n, s.batch_size)]
        move = minibatch_update!(s, row_matrix(s.table, s.columns, batch))
        iterations += 1
        s.iterations += 1
        move < s.tol && (s.converged = true)
    end
    write_centers!(s, moved || iterations > 0)
    labelled = label_rows!(s, budget * s.batch_size)
    current_value(s.converged_out) == s.converged || set!(s.converged_out, s.converged)
    work = iterations + cld(labelled, s.batch_size)
    more = !s.converged || s.cursor < n || has_changes(s.sub)
    return StepResult(more ? :ready : :blocked, work)
end

function write_centers!(s::MBKMeansState, changed::Bool)
    if isempty(s.result)
        append!(s.result, NamedTuple{Tuple(s.columns)}(Tuple(s.centers[j, :] for j in eachindex(s.columns))))
    elseif changed
        update_rows!(s.result, collect(1:s.k), NamedTuple{Tuple(s.columns)}(Tuple(s.centers[j, :] for j in eachindex(s.columns))))
    end
end

# Label up to `limit` rows, continuing the current pass; a pass whose
# centers have moved since it started starts over once it reaches the end
function label_rows!(s::MBKMeansState, limit::Int)
    n = length(s.ids)
    if s.cursor >= n && s.pass_centers != s.centers && s.cursor > 0
        s.cursor = 0
    end
    s.cursor == 0 && (s.pass_centers = copy(s.centers))
    lo, hi = s.cursor + 1, min(n, s.cursor + limit)
    hi < lo && return 0
    ids = s.ids[lo:hi]
    X = row_matrix(s.table, s.columns, ids)
    labels = [nearest_center(s.pass_centers, X, i)[1] for i in axes(X, 2)]
    maximum(ids) > length(s.label_row) && append!(s.label_row, zeros(Int, maximum(ids) - length(s.label_row)))
    old = [s.label_row[id] for id in ids]
    known = findall(!=(0), old)
    if !isempty(known)
        known_rows, values = old[known], labels[known]
        changed = findall(i -> s.labels[known_rows[i], :label] != values[i], eachindex(known_rows))
        isempty(changed) || update_rows!(s.labels, known_rows[changed], (label=values[changed],))
    end
    fresh = findall(==(0), old)
    if !isempty(fresh)
        rows::UnitRange{Int} = append!(s.labels, (row=ids[fresh], label=labels[fresh]))
        for (i, r) in zip(fresh, rows)
            s.label_row[ids[i]] = r
        end
    end
    s.cursor = hi
    # The pass reached the end with centers that have moved since: start over
    s.cursor >= n && s.pass_centers != s.centers && (s.cursor = 0)
    return length(ids)
end

consumed_rows(s::MBKMeansState) = lock(() -> setdiff(live_ids(s.table), s.sub.created), s.table.lock)
progress(s::MBKMeansState) = (s.cursor, length(s.ids))

# MBKMeansFilter

struct MBKMeansFilterModule end
execution_style(::Type{MBKMeansFilterModule}) = Progressive()
default_step_size(::Type{MBKMeansFilterModule}) = 1_000_000

mutable struct MBKMeansFilterState
    labels::ProgressiveTable
    sub::TableSubscription
    view::ProgressiveTable
    input_of::Vector{Int}            # labels row → input row id
end

function init_state(::Type{MBKMeansFilterModule}, ctx::StepContext)
    table = input_container(ctx, "table")
    labels = input_container(ctx, "labels")
    table isa ProgressiveTable && labels isa ProgressiveTable || error("MBKMeansFilter: inputs must be tables")
    view = set_output!(ctx, "result", selection_view(table))
    return MBKMeansFilterState(labels, input_subscription(ctx, "labels"), view, Int[])
end

function step!(s::MBKMeansFilterState, ctx::StepContext, budget::Int)
    cluster = as_int(required_param(ctx, "cluster"))
    # The data table's rows reach the view through the labels: its changes
    # only wake this module
    foreach(consume_all!, get(ctx.subscriptions, "table", AbstractSubscription[]))
    cluster_subs = get(ctx.subscriptions, "cluster", AbstractSubscription[])
    if any(has_changes, cluster_subs)
        # Another cluster: select again from all labels
        foreach(consume_all!, cluster_subs)
        reset!(s.sub)
        set_selection!(s.view, RowIds())
    end
    deleted = next_deleted!(s.sub)
    gone = Int[s.input_of[r] for r in deleted if r <= length(s.input_of)]
    changed = union(next_updated!(s.sub, budget), next_created!(s.sub, budget))
    rows = collect(changed)
    inputs = isempty(rows) ? Int[] : s.labels[changed, :row]
    labels = isempty(rows) ? Int[] : s.labels[changed, :label]
    isempty(rows) || (maximum(rows) > length(s.input_of) && append!(s.input_of, zeros(Int, maximum(rows) - length(s.input_of))))
    for (r, id) in zip(rows, inputs)
        s.input_of[r] = id
    end
    deselect!(s.view, RowIds(vcat(gone, inputs[labels .!= cluster])))
    select!(s.view, RowIds(inputs[labels .== cluster]))
    items = length(deleted) + length(rows)
    items == 0 && return StepResult(:blocked, 0)
    return StepResult(has_changes(s.sub) ? :ready : :blocked, items)
end

function register_progressive_kmeans!()
    P = PROGRESSIVE_PACKAGE
    register_module!(ModuleDescriptor(P, "MBKMeans", MBKMeansModule,
        [InputPort("table", ProgressiveTable), InputPort("moved_center", Any; optional=true)],
        [OutputPort("result", ProgressiveTable), OutputPort("labels", ProgressiveTable),
         OutputPort("converged", ProgressiveValue)],
        Tuple{String, Type}[("n_clusters", Int), ("columns", Vector{String}), ("batch_size", Int),
                            ("tol", Float64), ("seed", Int)]))
    register_module!(ModuleDescriptor(P, "MBKMeansFilter", MBKMeansFilterModule,
        vcat([InputPort("table", ProgressiveTable), InputPort("labels", ProgressiveTable)],
             control_ports([("cluster", Int)])),
        [OutputPort("result", ProgressiveTable)],
        Tuple{String, Type}[("cluster", Int)]))
end
