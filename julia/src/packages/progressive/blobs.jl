"""
Gaussian blobs, after ProgressiVis' `BlobsPTable` and `MVBlobsPTable`

Sources of `rows` rows of points around centers, with the center of each
row (1-based) in the output `labels` (row i of `labels` is row i of
`result`):

- `Blobs`: isotropic blobs (sklearn's `make_blobs`): `centers` is a number
  of centers (drawn uniformly in `center_box`, default `[-10, 10]` per
  coordinate) or a list of center coordinates; `cluster_std` is one
  standard deviation, or one per center;
- `MVBlobs`: multivariate normal blobs: `means` (one vector per blob) and
  `covs` (one covariance matrix per blob, as a list of rows).

Columns are named by `columns` (a list of names, or a number n: `_1` ...
`_n`; default from the centers' dimension). Each row draws its blob
uniformly, then its coordinates, from one generator seeded by `seed`, so
the rows do not depend on step sizes (ProgressiVis keeps that property
with reservoirs of 10,000 rows of balanced blobs).
"""

import LinearAlgebra

struct BlobsModule end
struct MVBlobsModule end
for M in (BlobsModule, MVBlobsModule)
    @eval execution_style(::Type{$M}) = Progressive()
    @eval default_step_size(::Type{$M}) = 100_000
end

mutable struct BlobsState
    table::ProgressiveTable
    labels::ProgressiveTable
    rng::Xoshiro
    columns::Vector{Symbol}
    means::Vector{Vector{Float64}}
    factors::Vector{Matrix{Float64}}     # x = mean + factor * z, z ~ N(0, I)
    remaining::Int
end

as_float_vector(v) = Float64[as_float(x) for x in v]

# A matrix given as a list of rows (or a matrix)
as_float_matrix(m::AbstractMatrix) = Float64.(m)
as_float_matrix(rows::AbstractVector) = permutedims(reduce(hcat, as_float_vector.(rows)))

function blob_columns(ctx, d::Int)
    c = param(ctx, "columns")
    names = c === nothing ? (d == 2 ? [:x, :y] : [Symbol("_$i") for i in 1:d]) :
            c isa Integer || (c isa AbstractString && all(isdigit, c)) ? [Symbol("_$i") for i in 1:as_int(c)] :
            as_symbols(c)
    length(names) == d || error("$(ctx.mod.descriptor.name): $(length(names)) columns for $d-dimensional blobs")
    return names
end

function blobs_state(ctx, means, factors, rng)
    columns = blob_columns(ctx, length(first(means)))
    table = set_output!(ctx, "result", ProgressiveTable((c => Float64 for c in columns)...))
    labels = set_output!(ctx, "labels", ProgressiveTable(:label => Int))
    return BlobsState(table, labels, rng, columns, means, factors, as_int(param(ctx, "rows", 100_000)))
end

function init_state(::Type{BlobsModule}, ctx::StepContext)
    rng = Xoshiro(as_int(param(ctx, "seed", 0)))
    centers = param(ctx, "centers", 3)
    means = if centers isa AbstractVector
        as_float_vector.(centers)
    else
        box = as_float_vector(param(ctx, "center_box", [-10.0, 10.0]))
        c = param(ctx, "columns")
        d = c === nothing ? 2 : c isa AbstractVector ? length(c) : as_int(c)
        [box[1] .+ (box[2] - box[1]) .* rand(rng, d) for _ in 1:as_int(centers)]
    end
    isempty(means) && error("Blobs: no centers")
    std = param(ctx, "cluster_std", 1.0)
    stds = std isa AbstractVector ? as_float_vector(std) : fill(as_float(std), length(means))
    length(stds) == length(means) || error("Blobs: cluster_std needs one value per center")
    d = length(first(means))
    factors = [Matrix{Float64}(s * LinearAlgebra.I, d, d) for s in stds]
    return blobs_state(ctx, means, factors, rng)
end

function init_state(::Type{MVBlobsModule}, ctx::StepContext)
    means = as_float_vector.(required_param(ctx, "means"))
    covs = as_float_matrix.(required_param(ctx, "covs"))
    length(means) == length(covs) || error("MVBlobs: one covariance matrix per mean is needed")
    isempty(means) && error("MVBlobs: no means")
    d = length(first(means))
    all(m -> length(m) == d, means) && all(c -> size(c) == (d, d), covs) ||
        error("MVBlobs: means and covariance matrices must all have dimension $d")
    factors = [Matrix(LinearAlgebra.cholesky(LinearAlgebra.Symmetric(c)).L) for c in covs]
    return blobs_state(ctx, means, factors, Xoshiro(as_int(param(ctx, "seed", 0))))
end

function step!(s::BlobsState, ctx::StepContext, budget::Int)
    n = min(budget, s.remaining)
    d = length(s.columns)
    columns = [Vector{Float64}(undef, n) for _ in 1:d]
    labels = Vector{Int}(undef, n)
    draw_blobs!(columns, labels, s.rng, s.means, s.factors)
    append!(s.table, NamedTuple{Tuple(s.columns)}(Tuple(columns)))
    append!(s.labels, (label=labels,))
    s.remaining -= n
    return StepResult(s.remaining == 0 ? :done : :ready, n)
end

# Row by row: the blob, then the d coordinates
function draw_blobs!(columns::Vector{Vector{Float64}}, labels::Vector{Int}, rng, means, factors)
    d = length(columns)
    z = Vector{Float64}(undef, d)
    @inbounds for i in eachindex(labels)
        b = rand(rng, eachindex(means))
        labels[i] = b
        for j in 1:d
            z[j] = randn(rng)
        end
        L, m = factors[b], means[b]
        for j in 1:d
            v = m[j]
            for k in 1:j
                v += L[j, k] * z[k]       # factors are lower triangular
            end
            columns[j][i] = v
        end
    end
end

progress(s::BlobsState) = (last_id(s.table), last_id(s.table) + s.remaining)

function register_progressive_blobs!()
    P = PROGRESSIVE_PACKAGE
    outputs = [OutputPort("result", ProgressiveTable), OutputPort("labels", ProgressiveTable)]
    register_module!(ModuleDescriptor(P, "Blobs", BlobsModule, InputPort[], outputs,
        Tuple{String, Type}[("columns", Any), ("rows", Int), ("seed", Int), ("centers", Any),
                            ("cluster_std", Any), ("center_box", Vector{Float64})]))
    register_module!(ModuleDescriptor(P, "MVBlobs", MVBlobsModule, InputPort[], outputs,
        Tuple{String, Type}[("columns", Any), ("rows", Int), ("seed", Int), ("means", Any), ("covs", Any)]))
end
