"""
Progressive PCA, after ProgressiVis' `PPCA` and `PPCATransformer`

- `PPCA`: incremental PCA (Ross et al. 2008, as sklearn's
  `IncrementalPCA`) of the rows of `table` (`columns`, default numeric),
  each step's rows folded in with one SVD. Outputs `transformer`, the model
  (a `PCAModel`, a new one after each step), and `result`, a selection
  view of the rows fitted so far. Input updates and deletions refit.
- `PPCATransformer`: projects the rows of `table` on the `n_components`
  principal components of the model on `transformer`, into columns `_pc1`
  ... (`result`, row i for input row i). Rows are projected with the
  model of the last reset; when the model changes, the module measures its
  drift on `samples` random projected rows (default 100): the mean over
  the rows of √Σ (old − new)² / explained variance. Above `rtol` (default
  0.001) it resets: every row is projected again with the new model, in
  place. After `threshold` rows (default: never) it stops resetting.

`transform(model, X)` and `inverse_transform(model, Y)` apply a model to
a matrix of rows.
"""

"""
    PCAModel

A fitted PCA: `components` (k × d), the `mean` of the rows and the
`explained_variance` of each component, from `n_samples` rows of `columns`.
"""
struct PCAModel
    columns::Vector{Symbol}
    mean::Vector{Float64}
    components::Matrix{Float64}
    singular_values::Vector{Float64}
    explained_variance::Vector{Float64}
    n_samples::Int
end

transform(m::PCAModel, X::AbstractMatrix) = (X .- m.mean') * m.components'
inverse_transform(m::PCAModel, Y::AbstractMatrix) = Y * m.components .+ m.mean'

# Incremental fit (sklearn's IncrementalPCA.partial_fit)
mutable struct IncrementalPCA
    k::Int
    n::Int
    mean::Vector{Float64}
    var::Vector{Float64}
    components::Matrix{Float64}
    singular_values::Vector{Float64}
end

IncrementalPCA(k::Int, d::Int) = IncrementalPCA(k, 0, zeros(d), zeros(d), zeros(0, d), Float64[])

function partial_fit!(p::IncrementalPCA, X::Matrix{Float64})
    m = size(X, 1)
    m == 0 && return p
    total = p.n + m
    batch_mean = vec(sum(X; dims=1)) ./ m
    batch_ss = vec(sum(abs2, X .- batch_mean'; dims=1))
    # Running mean and variance (Chan et al.)
    delta = batch_mean .- p.mean
    new_mean = p.mean .+ delta .* (m / total)
    p.var = (p.var .* p.n .+ batch_ss .+ delta .^ 2 .* (p.n * m / total)) ./ total
    A = if p.n == 0
        X .- new_mean'
    else
        correction = sqrt(p.n / total * m) .* (p.mean .- batch_mean)
        vcat(p.singular_values .* p.components, X .- batch_mean', correction')
    end
    F = LinearAlgebra.svd(A)
    Vt = F.Vt
    # Signs: the largest coefficient of each component is positive (sklearn's svd_flip on V)
    for i in axes(Vt, 1)
        j = argmax(abs.(view(Vt, i, :)))
        Vt[i, j] < 0 && (Vt[i, :] .*= -1)
    end
    k = min(p.k, size(Vt, 1))
    p.components = Vt[1:k, :]
    p.singular_values = F.S[1:k]
    p.mean = new_mean
    p.n = total
    return p
end

model(p::IncrementalPCA, columns) =
    PCAModel(columns, copy(p.mean), copy(p.components), copy(p.singular_values),
             p.singular_values .^ 2 ./ max(p.n - 1, 1), p.n)

struct PPCAModule end
execution_style(::Type{PPCAModule}) = Progressive()
default_step_size(::Type{PPCAModule}) = 10_000

mutable struct PPCAState
    table::ProgressiveTable
    sub::TableSubscription
    columns::Vector{Symbol}
    pca::IncrementalPCA
    view::ProgressiveTable
    transformer::ProgressiveValue{PCAModel}
end

function init_state(::Type{PPCAModule}, ctx::StepContext)
    table = input_container(ctx, "table")
    table isa ProgressiveTable || error("PPCA: input 'table' must be a table")
    columns = numeric_columns(ctx, table)
    k = as_int(param(ctx, "n_components", 2))
    1 <= k <= length(columns) || error("PPCA: n_components must be between 1 and $(length(columns)) (the columns)")
    view = set_output!(ctx, "result", selection_view(table))
    transformer = set_output!(ctx, "transformer", ProgressiveValue{PCAModel}())
    return PPCAState(table, input_subscription(ctx, "table"), columns, IncrementalPCA(k, length(columns)), view, transformer)
end

# The first fit needs at least n_components rows
ready_to_step(s::PPCAState, ctx::StepContext) =
    s.pca.n > 0 || pending(s.sub).created >= s.pca.k || producers_done(ctx)

table_matrix(t::ProgressiveTable, columns::Vector{Symbol}, ids::RowIds) =
    reduce(hcat, [Float64.(t[ids, c]) for c in columns])

function step!(s::PPCAState, ctx::StepContext, budget::Int)
    counts = pending(s.sub)
    if counts.updated > 0 || counts.deleted > 0
        reset!(s.sub)
        s.pca = IncrementalPCA(s.pca.k, length(s.columns))
        set_selection!(s.view, RowIds())
    end
    ids = next_created!(s.sub, max(budget, s.pca.k))
    isempty(ids) && return StepResult(:blocked, 0)
    partial_fit!(s.pca, table_matrix(s.table, s.columns, ids))
    set!(s.transformer, model(s.pca, s.columns))
    select!(s.view, ids)
    return StepResult(has_changes(s.sub) ? :ready : :blocked, length(ids))
end

consumed_rows(s::PPCAState) = lock(() -> setdiff(live_ids(s.table), s.sub.created), s.table.lock)
progress(s::PPCAState) = input_progress(s.table, s.sub)

# PPCATransformer

struct PPCATransformerModule end
execution_style(::Type{PPCATransformerModule}) = Progressive()
default_step_size(::Type{PPCATransformerModule}) = 100_000

mutable struct PPCATransformerState
    table::ProgressiveTable
    sub::TableSubscription
    transformer::ProgressiveValue
    tsub::ValueSubscription
    names::Vector{Symbol}
    out::ProgressiveTable
    out_id::Vector{Int}              # input row → output row (0: none)
    projected::Vector{Int}           # input rows projected, for samples
    model::Union{PCAModel, Nothing}  # the model rows are projected with
    rng::Xoshiro
    resets::Int
end

function init_state(::Type{PPCATransformerModule}, ctx::StepContext)
    table = input_container(ctx, "table")
    table isa ProgressiveTable || error("PPCATransformer: input 'table' must be a table")
    k = as_int(param(ctx, "n_components", 2))
    names = [Symbol("_pc$i") for i in 1:k]
    out = set_output!(ctx, "result", ProgressiveTable((n => Float64 for n in names)...))
    return PPCATransformerState(table, input_subscription(ctx, "table"), input_container(ctx, "transformer"),
                                input_subscription(ctx, "transformer"), names, out, Int[], Int[], nothing,
                                Xoshiro(as_int(param(ctx, "seed", 0))), 0)
end

ready_to_step(s::PPCATransformerState, ctx::StepContext) = has_value(s.transformer)

project(m::PCAModel, t::ProgressiveTable, ids::RowIds) = transform(m, table_matrix(t, m.columns, ids))

# Mean drift of projections between two models, on sample rows
function drift(old::PCAModel, new::PCAModel, t::ProgressiveTable, ids::RowIds)
    a, b = project(old, t, ids), project(new, t, ids)
    k = min(size(a, 2), size(b, 2))
    ev = new.explained_variance[1:k]
    return sum(i -> sqrt(sum(j -> (a[i, j] - b[i, j])^2 / ev[j], 1:k)), axes(a, 1)) / size(a, 1)
end

function needs_reset(s::PPCATransformerState, ctx, new::PCAModel)
    old = s.model
    (old === nothing || old === new || isempty(s.projected)) && return false
    threshold = param(ctx, "threshold")
    threshold !== nothing && length(s.projected) >= as_int(threshold) && return false
    n = min(length(s.projected), as_int(param(ctx, "samples", 100)))
    sample = RowIds(s.projected[rand(s.rng, eachindex(s.projected), n)])
    return drift(old, new, s.table, sample) > as_float(param(ctx, "rtol", 0.001))
end

function step!(s::PPCATransformerState, ctx::StepContext, budget::Int)
    m = current_value(s.transformer)::PCAModel
    take_value!(s.tsub)
    size(m.components, 1) == length(s.names) ||
        error("PPCATransformer: the model has $(size(m.components, 1)) components, n_components is $(length(s.names))")
    counts = pending(s.sub)
    if s.model === nothing
        s.model = m
    elseif counts.updated > 0 || counts.deleted > 0 || needs_reset(s, ctx, m)
        # Project every row again, with the current model
        s.model = m
        s.resets += 1
        deleted = next_deleted!(s.sub)
        for id in deleted
            id <= length(s.out_id) && s.out_id[id] != 0 && (delete!(s.out, s.out_id[id]); s.out_id[id] = 0)
        end
        filter!(id -> s.out_id[id] != 0, s.projected)
        reset!(s.sub)
    end
    next_updated!(s.sub)
    ids = next_created!(s.sub, budget)
    isempty(ids) && return StepResult(:blocked, 0)
    Y = project(s.model, s.table, ids)
    list = collect(ids)
    last(list) > length(s.out_id) && append!(s.out_id, zeros(Int, last(list) - length(s.out_id)))
    again = findall(id -> s.out_id[id] != 0, list)
    fresh = findall(id -> s.out_id[id] == 0, list)
    isempty(again) || update_rows!(s.out, s.out_id[list[again]],
                                   NamedTuple{Tuple(s.names)}(Tuple(Y[again, j] for j in eachindex(s.names))))
    if !isempty(fresh)
        rows::UnitRange{Int} = append!(s.out, NamedTuple{Tuple(s.names)}(Tuple(Y[fresh, j] for j in eachindex(s.names))))
        for (i, r) in zip(fresh, rows)
            s.out_id[list[i]] = r
        end
        append!(s.projected, list[fresh])
    end
    return StepResult(has_changes(s.sub) ? :ready : :blocked, length(list))
end

consumed_rows(s::PPCATransformerState) = lock(() -> setdiff(live_ids(s.table), s.sub.created), s.table.lock)
progress(s::PPCATransformerState) = input_progress(s.table, s.sub)

function register_progressive_pca!()
    P = PROGRESSIVE_PACKAGE
    register_module!(ModuleDescriptor(P, "PPCA", PPCAModule,
        [InputPort("table", ProgressiveTable)],
        [OutputPort("result", ProgressiveTable), OutputPort("transformer", ProgressiveValue)],
        Tuple{String, Type}[("n_components", Int), ("columns", Vector{String})]))
    register_module!(ModuleDescriptor(P, "PPCATransformer", PPCATransformerModule,
        [InputPort("table", ProgressiveTable), InputPort("transformer", ProgressiveValue)],
        [OutputPort("result", ProgressiveTable)],
        Tuple{String, Type}[("n_components", Int), ("rtol", Float64), ("threshold", Int), ("samples", Int),
                            ("seed", Int)]))
end
