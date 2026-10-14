"""
Tests for the analytics modules ported from ProgressiVis (tier 4): Blobs,
MVBlobs, MinMaxScaler, MBKMeans, MBKMeansFilter, PPCA, PPCATransformer,
KernelDensity, TSNE; and `update_rows!`

Results are checked against batch computations (exact where the method is:
full-rank PCA, densities, neighbor lists; within tolerances for k-means and
generated data; by neighborhood preservation for t-SNE), under several step
sizes, with live parameters, input updates and deletions, and in the
one-shot engine.
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Test
using Random
using Statistics
using Tables
using LinearAlgebra

const VT = VisTrailsJL
const P = "org.vistrails.progressive"
const T = "org.vistrails.test.analytics"

function node!(p, name, sources...; port="table", package=P, params...)
    m = add_module!(p, package, name)
    for (k, v) in params
        set_parameter!(m, String(k), v)
    end
    for s in sources
        add_connection!(p, s, "result", m, port)
    end
    return m
end
connect!(p, a, b, port; from="result") = add_connection!(p, a, from, b, port)

output(run, m, port="result") = run.outputs[m.id][port]
result_of(run, m, port="result") = (c = output(run, m, port); c isa ProgressiveValue ? current_value(c) :
                                    c isa ProgressiveDict ? snapshot(c) : Tables.columntable(c))
state_of(run, m) = run.engine_state.modules[m.id].state

function wait_until(f; timeout=60.0)
    t0 = time()
    while !f()
        time() - t0 > timeout && error("timed out")
        sleep(0.005)
    end
end

# A source serving a fixed table in steps of `chunk` rows (default: the step size)
const TABLES = Dict{String, Any}()
struct FixedTableModule end
VT.execution_style(::Type{FixedTableModule}) = VT.Progressive()
mutable struct FixedTableState
    data::Any
    table::ProgressiveTable
    position::Int
    chunk::Int
end
function VT.init_state(::Type{FixedTableModule}, ctx::VT.StepContext)
    data = TABLES[VT.param(ctx, "key")]
    t = VT.set_output!(ctx, "result", ProgressiveTable((n => eltype(v) for (n, v) in pairs(data))...; segment_size=1_024))
    return FixedTableState(data, t, 0, Int(VT.param(ctx, "chunk", typemax(Int))))
end
function VT.step!(s::FixedTableState, ctx::VT.StepContext, budget::Int)
    n = min(budget, s.chunk, length(first(s.data)) - s.position)
    append!(s.table, map(v -> v[s.position+1:s.position+n], s.data))
    s.position += n
    return VT.StepResult(s.position == length(first(s.data)) ? :done : :ready, n)
end

# Serves a table, then updates some rows and deletes others
struct MutatorModule end
VT.execution_style(::Type{MutatorModule}) = VT.Progressive()
mutable struct MutatorState
    data::Any
    table::ProgressiveTable
    phase::Int
end
function VT.init_state(::Type{MutatorModule}, ctx)
    data = TABLES[VT.param(ctx, "key")]
    MutatorState(data, VT.set_output!(ctx, "result", ProgressiveTable((n => eltype(v) for (n, v) in pairs(data))...)), 0)
end
function VT.step!(s::MutatorState, ctx, budget)
    s.phase += 1
    t = s.table
    if s.phase == 1
        append!(t, s.data)
    elseif s.phase == 2
        for c in column_names(t)
            t[3, c] = s.data[c][3] + 5           # moves row 3
        end
    else
        delete!(t, VT.RowIds(50:60))
        return VT.StepResult(:done, 1)
    end
    return VT.StepResult(:ready, 1)
end
# The table a Mutator ends with
function mutated(data)
    cols = Dict(c => copy(v) for (c, v) in pairs(data))
    foreach(c -> cols[c][3] += 5, keys(cols))
    keep = setdiff(1:length(first(data)), 50:60)
    return NamedTuple{keys(data)}(Tuple(cols[c][keep] for c in keys(data)))
end

for (name, type) in (("FixedTable", FixedTableModule), ("Mutator", MutatorModule))
    VT.register_module!(VT.ModuleDescriptor(T, name, type, VT.InputPort[],
        [VT.OutputPort("result", ProgressiveTable)], Tuple{String, Type}[("key", String), ("chunk", Int)]))
end

source!(p, key; chunk=typemax(Int)) = node!(p, "FixedTable"; package=T, key=key, chunk=chunk)
mutator!(p, key) = node!(p, "Mutator"; package=T, key=key)

matrix(data, cols) = reduce(hcat, [Float64.(data[c]) for c in cols])

# Batch PCA with sklearn's signs (largest coefficient of each component positive)
function batch_pca(X)
    mu = vec(mean(X; dims=1))
    F = svd(X .- mu')
    Vt = copy(F.Vt)
    for i in axes(Vt, 1)
        j = argmax(abs.(Vt[i, :]))
        Vt[i, j] < 0 && (Vt[i, :] .*= -1)
    end
    return mu, Vt, F.S .^ 2 ./ (size(X, 1) - 1)
end

brute_density(xs, ys, qx, qy, k, bw) =
    sum(d -> exp(-0.5 * d / bw^2), partialsort((xs .- qx) .^ 2 .+ (ys .- qy) .^ 2, 1:min(k, length(xs)))) /
    (bw * sqrt(2π)) / k

@testset "Analytics modules (tier 4)" begin
    @testset "update_rows!" begin
        t = ProgressiveTable(:a => Int, :b => Float64)
        append!(t, (a=collect(1:10), b=zeros(10)))
        sub = subscribe!(t)
        next_created!(sub, 5)                                 # rows 1-5 read
        update_rows!(t, [2, 7, 4], (b=[2.0, 7.0, 4.0],))
        @test t[RowIds(1:10), :b] == [0, 2, 0, 4, 0, 0, 7, 0, 0, 0]
        @test collect(next_updated!(sub)) == [2, 4]           # row 7 is still pending as created
        delete!(t, 9)
        @test_throws ArgumentError update_rows!(t, [9], (a=[0],))
        @test_throws ArgumentError update_rows!(t, [11], (a=[0],))
        @test_throws DimensionMismatch update_rows!(t, [1, 2], (a=[0],))
    end

    @testset "Blobs, MVBlobs" begin
        centers = [[0.0, 0.0], [5.0, 5.0], [-5.0, 5.0]]
        stds = [0.5, 1.0, 1.5]
        results = map((777, 1_000_000)) do step
            p = Pipeline()
            b = node!(p, "Blobs"; rows=30_000, centers=centers, cluster_std=stds, seed=7)
            run = run!(ProgressiveEngine(step_size=id -> step), p)
            (result_of(run, b), result_of(run, b, "labels").label)
        end
        @test results[1] == results[2]                        # rows do not depend on step sizes
        (data, labels) = results[1]
        @test length(data.x) == 30_000 && keys(data) == (:x, :y)
        for (b, (c, s)) in enumerate(zip(centers, stds))
            rows = labels .== b
            @test abs(count(rows) - 10_000) < 400             # blobs drawn uniformly
            @test mean(data.x[rows]) ≈ c[1] atol=0.05
            @test mean(data.y[rows]) ≈ c[2] atol=0.05
            @test std(data.x[rows]) ≈ s rtol=0.04
        end

        p = Pipeline()
        b = node!(p, "Blobs"; rows=1000, centers=4, columns=3, seed=1)
        run = run!(ProgressiveEngine(), p)
        data = result_of(run, b)
        @test keys(data) == (:_1, :_2, :_3)
        @test sort(unique(result_of(run, b, "labels").label)) == 1:4

        covs = [[[1.0, 0.8], [0.8, 1.0]], [[2.0, 0.0], [0.0, 0.5]]]
        p = Pipeline()
        mv = node!(p, "MVBlobs"; rows=40_000, means=[[0.0, 0.0], [3.0, 3.0]], covs=covs, columns=["u", "v"], seed=2)
        run = run!(OneShotEngine(), p)                        # also in the one-shot engine
        data, labels = result_of(run, mv), result_of(run, mv, "labels").label
        for b in 1:2
            X = hcat(data.u[labels .== b], data.v[labels .== b])
            @test cov(X) ≈ reduce(vcat, permutedims.(covs[b])) atol=0.05
        end
    end

    rng = Xoshiro(11)
    n = 20_000
    TABLES["scale"] = (id=collect(1:n), x=randn(rng, n), y=10 .* rand(rng, n))

    @testset "MinMaxScaler" begin
        data = TABLES["scale"]
        lo, hi = Dict(:x => minimum(data.x), :y => minimum(data.y)), Dict(:x => maximum(data.x), :y => maximum(data.y))
        function scaler(engine; params...)
            p = Pipeline()
            src = source!(p, "scale"; chunk=700)
            mn = node!(p, "Min", src; columns=["x", "y"])
            mx = node!(p, "Max", src; columns=["x", "y"])
            sc = node!(p, "MinMaxScaler", src; columns=["x", "y"], params...)
            connect!(p, mn, sc, "min"); connect!(p, mx, sc, "max")
            run = run!(engine, p)
            return run, sc
        end
        # All rows at once: the exact bounds
        run, sc = scaler(OneShotEngine())
        out = result_of(run, sc)
        @test out.id == data.id                               # other columns pass through
        @test out.x ≈ (data.x .- lo[:x]) ./ (hi[:x] - lo[:x])
        @test out.y ≈ (data.y .- lo[:y]) ./ (hi[:y] - lo[:y])

        # Progressively: each output row is its input row scaled with the
        # bounds the scaler ended with, clipped; dropped rows are counted
        for (step, params) in ((500, (;)), (1_000, (ignore_max=50,)), (2_000, (delta=0.0, reset_threshold=0)))
            run, sc = scaler(ProgressiveEngine(step_size=id -> step); params...)
            out = result_of(run, sc)
            info = result_of(run, sc, "info")
            s = state_of(run, sc)
            @test length(out.id) + info[:ignored] == n
            @test info[:ignored] <= get(params, :ignore_max, 0)
            @test allunique(out.id)
            @test all(0 .<= out.x .<= 1) && all(0 .<= out.y .<= 1)
            for (j, c) in enumerate((:x, :y))
                @test out[c] ≈ clamp.((data[c][out.id] .- s.lo[j]) ./ (s.hi[j] - s.lo[j]), 0, 1)
            end
        end

        # Rows far out of the bounds: dropped up to ignore_max, else a reset
        TABLES["outliers"] = (id=collect(1:n), x=[i > n - 10 ? 100.0 + i : rand(rng) for i in 1:n])
        for ignore_max in (0, 10)
            p = Pipeline()
            src = source!(p, "outliers"; chunk=1_000)
            mn = node!(p, "Min", src; columns=["x"]); mx = node!(p, "Max", src; columns=["x"])
            sc = node!(p, "MinMaxScaler", src; columns=["x"], ignore_max=ignore_max, reset_threshold=0)
            connect!(p, mn, sc, "min"); connect!(p, mx, sc, "max")
            run = run!(ProgressiveEngine(workers=1, step_size=id -> 1_000), p)
            out, info = result_of(run, sc), result_of(run, sc, "info")
            @test length(out.x) + info[:ignored] == n && info[:ignored] <= ignore_max
            ignore_max == 0 && @test length(out.x) == n && maximum(out.x) == 1.0
            @test all(0 .<= out.x .<= 1)
        end

        # Input updates and deletions: the scaler starts over
        TABLES["small"] = (x=collect(1.0:100.0), y=collect(100.0:-1:1))
        p = Pipeline()
        src = mutator!(p, "small")
        mn = node!(p, "Min", src); mx = node!(p, "Max", src)
        sc = node!(p, "MinMaxScaler", src; ignore_max=1_000)
        connect!(p, mn, sc, "min"); connect!(p, mx, sc, "max")
        run = run!(ProgressiveEngine(workers=1), p)
        final = mutated(TABLES["small"])
        @test result_of(run, sc).x ≈ (final.x .- minimum(final.x)) ./ (maximum(final.x) - minimum(final.x))
        @test result_of(run, sc, "info")[:resets] >= 1
    end

    # Three well separated blobs
    TABLES["blobs"] = let rng = Xoshiro(5), n = 40_000
        c = [(0.0, 0.0), (6.0, 6.0), (-6.0, 6.0)]
        lab = rand(rng, 1:3, n)
        (x=[c[l][1] + 0.5 * randn(rng) for l in lab], y=[c[l][2] + 0.5 * randn(rng) for l in lab], truth=lab)
    end
    true_centers = [(0.0, 0.0), (6.0, 6.0), (-6.0, 6.0)]

    @testset "MBKMeans, MBKMeansFilter" begin
        data = TABLES["blobs"]
        function kmeans_run(engine; chunk=2_500)
            p = Pipeline()
            src = source!(p, "blobs"; chunk=chunk)
            km = node!(p, "MBKMeans", src; n_clusters=3, columns=["x", "y"], seed=3)
            filters = [node!(p, "MBKMeansFilter", src; cluster=c) for c in 1:3]
            foreach(f -> connect!(p, km, f, "labels"; from="labels"), filters)
            return run!(engine, p), km, filters
        end
        for engine in (ProgressiveEngine(), ProgressiveEngine(workers=4), OneShotEngine())
            run, km, filters = kmeans_run(engine)
            C = result_of(run, km)
            found = collect(zip(C.x, C.y))
            # Each true center has a found center close by
            match = [argmin([hypot(f[1] - t[1], f[2] - t[2]) for f in found]) for t in true_centers]
            @test sort(match) == 1:3
            @test all(hypot(found[m][1] - t[1], found[m][2] - t[2]) < 0.05 for (m, t) in zip(match, true_centers))
            @test result_of(run, km, "converged") === true
            # Every row labelled with its nearest final center
            L = result_of(run, km, "labels")
            @test sort(L.row) == 1:length(data.x)
            nearest(i) = argmin([(data.x[i] - f[1])^2 + (data.y[i] - f[2])^2 for f in found])
            @test all(L.label[r] == nearest(L.row[r]) for r in eachindex(L.row))
            @test mean(match[data.truth[L.row]] .== L.label) > 0.999
            # Filters: the rows of each cluster
            for (c, f) in enumerate(filters)
                @test sort(collect(row_ids(output(run, f)))) == sort(L.row[L.label .== c])
            end
        end
        # Reproducible for given step sizes
        runs = [kmeans_run(ProgressiveEngine(workers=1, step_size=id -> 300)) for _ in 1:2]
        @test result_of(runs[1][1], runs[1][2]) == result_of(runs[2][1], runs[2][2])

        # Live: change the filtered cluster; move a center by hand
        p = Pipeline()
        src = source!(p, "blobs"; chunk=1_000)
        km = node!(p, "MBKMeans", src; n_clusters=3, columns=["x", "y"], seed=3)
        cluster = node!(p, "Variable"; value=1)
        moved = node!(p, "Variable")
        connect!(p, moved, km, "moved_center")
        f = node!(p, "MBKMeansFilter", src)
        connect!(p, km, f, "labels"; from="labels"); connect!(p, cluster, f, "cluster")
        pr = start!(ProgressiveEngine(), p)
        wait_until(() -> current_value(output(pr.run, km, "converged")) && length(output(pr.run, km, "labels")) == 40_000 &&
                         module_status(pr.run, km.id) == :blocked)
        set_variable!(pr, cluster, 2)
        set_variable!(pr, moved, Dict(1 => [50.0, 50.0]))
        close_inputs!(pr)
        run = wait(pr)
        C, L = result_of(run, km), result_of(run, km, "labels")
        @test (C.x[1], C.y[1]) == (50.0, 50.0)                 # no rows pull it back
        @test !any(==(1), L.label)                             # its rows went to the other centers
        @test sort(collect(row_ids(output(run, f)))) == sort(L.row[L.label .== 2])

        # Input updates and deletions: rows read again, labels of deleted rows removed
        TABLES["kmut"] = (x=data.x[1:5_000], y=data.y[1:5_000])
        p = Pipeline()
        km = node!(p, "MBKMeans", mutator!(p, "kmut"); n_clusters=3, seed=1)
        run = run!(ProgressiveEngine(workers=1), p)
        L = result_of(run, km, "labels")
        @test sort(L.row) == setdiff(1:5_000, 50:60)
    end

    rng = Xoshiro(21)
    m = 4_000
    A = randn(rng, 6, 6) .* [5.0, 3.0, 2.0, 1.0, 0.5, 0.1]
    Xp = randn(rng, m, 6) * A .+ [1.0 2.0 3.0 4.0 5.0 6.0]
    TABLES["pca"] = NamedTuple{Tuple(Symbol("c$i") for i in 1:6)}(Tuple(Xp[:, i] for i in 1:6))
    cols = [Symbol("c$i") for i in 1:6]

    @testset "PPCA, PPCATransformer" begin
        mu, Vt, ev = batch_pca(Xp)
        # Full rank: the incremental PCA is exact, whatever the steps
        for (engine, chunk) in ((ProgressiveEngine(step_size=id -> 97), 1_000), (ProgressiveEngine(), 333), (OneShotEngine(), 4_000))
            p = Pipeline()
            pca = node!(p, "PPCA", source!(p, "pca"; chunk=chunk); n_components=6)
            run = run!(engine, p)
            model = result_of(run, pca, "transformer")
            @test model isa VT.PCAModel && model.n_samples == m
            @test model.mean ≈ mu rtol=1e-10
            @test model.components ≈ Vt atol=1e-8
            @test model.explained_variance ≈ ev rtol=1e-8
            @test length(output(run, pca)) == m                # the rows fitted
        end
        # Fewer components: close to the batch PCA's leading ones
        p = Pipeline()
        pca = node!(p, "PPCA", source!(p, "pca"; chunk=500); n_components=2)
        run = run!(ProgressiveEngine(), p)
        model = result_of(run, pca, "transformer")
        @test svdvals(model.components * Vt[1:2, :]') ≈ [1.0, 1.0] atol=1e-3   # same subspace
        @test model.explained_variance ≈ ev[1:2] rtol=1e-2
        X2 = VT.inverse_transform(model, VT.transform(model, Xp))
        batch2 = (Xp .- mu') * Vt[1:2, :]' * Vt[1:2, :] .+ mu'
        @test norm(X2 .- Xp) <= 1.001 * norm(batch2 .- Xp)          # as good as the batch reconstruction

        # Transformer: rtol 0 resets on every model change (ending with every
        # row projected by the final model); a huge rtol never resets
        for (rtol, threshold) in ((0.0, nothing), (1e9, nothing), (0.0, 1))
            p = Pipeline()
            src = source!(p, "pca"; chunk=400)
            pca = node!(p, "PPCA", src; n_components=3)
            tr = node!(p, "PPCATransformer", src; n_components=3, rtol=rtol)
            threshold === nothing || set_parameter!(tr, "threshold", threshold)
            connect!(p, pca, tr, "transformer"; from="transformer")
            run = run!(ProgressiveEngine(workers=1, step_size=id -> 400), p)
            out = result_of(run, tr)
            @test keys(out) == (:_pc1, :_pc2, :_pc3) && length(out._pc1) == m
            final = result_of(run, pca, "transformer")
            s = state_of(run, tr)
            if rtol == 0.0 && threshold === nothing
                @test s.resets > 0
                @test hcat(out...) ≈ VT.transform(final, Xp) atol=1e-9
            else
                @test s.resets == 0
                @test !(hcat(out...) ≈ VT.transform(final, Xp))
            end
        end
        p = Pipeline()
        src = source!(p, "pca")
        pca = node!(p, "PPCA", src; n_components=2)
        tr = node!(p, "PPCATransformer", src; n_components=3)
        connect!(p, pca, tr, "transformer"; from="transformer")
        @test_throws Exception run!(ProgressiveEngine(), p)

        # Input updates and deletions: refit from the rows left
        TABLES["pmut"] = (a=Xp[1:500, 1], b=Xp[1:500, 2])
        p = Pipeline()
        pca = node!(p, "PPCA", mutator!(p, "pmut"); n_components=2)
        run = run!(ProgressiveEngine(workers=1), p)
        final = mutated(TABLES["pmut"])
        mu2, Vt2, ev2 = batch_pca(hcat(final.a, final.b))
        model = result_of(run, pca, "transformer")
        @test model.components ≈ Vt2 atol=1e-8
        @test model.n_samples == 489
    end

    @testset "KernelDensity" begin
        # The index: exact neighbors, also for clustered and duplicate
        # points and for queries far away
        rng = Xoshiro(3)
        g = VT.PointIndex()
        xs, ys = Float64[], Float64[]
        for batch in 1:6
            bx = vcat(randn(rng, 3_000), fill(2.0, 50), fill(-3.0, 500), 100 .+ 0.01 .* randn(rng, 20), [-680.0 * batch])
            by = vcat(randn(rng, 3_000), fill(2.0, 50), fill(-3.0, 500), 0.01 .* randn(rng, 20), [45.0])
            VT.insert_points!(g, bx, by)
            append!(xs, bx); append!(ys, by)
            for (qx, qy) in [(0.0, 0.0), (2.0, 2.0), (-3.0, -3.0), (100.0, 0.0), (500.0, -300.0), (randn(rng), randn(rng))]
                @test VT.knn_distances(g, qx, qy, 60) == sort((xs .- qx) .^ 2 .+ (ys .- qy) .^ 2)[1:60]
            end
        end
        @test VT.knn_distances(VT.PointIndex(), 0.0, 0.0, 5) == Float64[]

        rng = Xoshiro(8)
        n = 20_000
        TABLES["kde"] = (x=vcat(randn(rng, n ÷ 2), 4 .+ 0.5 .* randn(rng, n ÷ 2)), y=randn(rng, n))
        data = TABLES["kde"]
        samples = [[0.0, 0.0], [4.0, 0.0], [2.0, 1.0], [-3.0, 3.0], [10.0, 10.0]]
        for (engine, params) in ((ProgressiveEngine(step_size=id -> 1_500), (samples=samples, knn=50, bandwidth=0.3)),
                                 (ProgressiveEngine(), (bins=8, threshold=5_000)),
                                 (OneShotEngine(), (bins=4,)))
            p = Pipeline()
            kde = node!(p, "KernelDensity", source!(p, "kde"; chunk=3_000); params...)
            run = run!(engine, p)
            out = result_of(run, kde)
            k, bw = get(params, :knn, 100), get(params, :bandwidth, 0.2)
            if haskey(params, :samples)
                @test collect(zip(out.x, out.y)) == [(s[1], s[2]) for s in samples]
            else
                bins = params.bins
                @test length(out.x) == bins^2
                @test minimum(out.x) ≈ minimum(data.x) + (maximum(data.x) - minimum(data.x)) / 2bins
            end
            @test out.density ≈ [brute_density(data.x, data.y, qx, qy, k, bw) for (qx, qy) in zip(out.x, out.y)] rtol=1e-12
        end
        # Input updates and deletions rebuild the index
        TABLES["kmut2"] = (u=data.x[1:2_000], v=data.y[1:2_000])
        p = Pipeline()
        kde = node!(p, "KernelDensity", mutator!(p, "kmut2"); x_column="u", y_column="v", samples=samples[1:3], knn=20)
        run = run!(ProgressiveEngine(workers=1), p)
        final = mutated(TABLES["kmut2"])
        @test result_of(run, kde).density ≈ [brute_density(final.u, final.v, s[1], s[2], 20, 0.2) for s in samples[1:3]]
    end

    @testset "TSNE" begin
        # Perplexity calibration
        d2 = sort(rand(Xoshiro(1), 90) .* 10)
        p_ = VT.cond_probabilities(d2, 30.0)
        @test sum(p_) ≈ 1
        @test -sum(p_ .* log.(p_)) ≈ log(30) atol=1e-4

        # Barnes-Hut against exact repulsion
        Y = randn(Xoshiro(2), 2, 500) .* 5
        exact, bh0, bh = zeros(2, 500), zeros(2, 500), zeros(2, 500)
        tree = VT.build!(VT.QuadTree(), Y)
        zs = [VT.exact_repulsion!(exact, Y, i) for i in 1:500]
        @test [VT.repulsion!(bh0, tree, Y, i, 0.0) for i in 1:500] ≈ zs
        @test bh0 ≈ exact
        z5 = [VT.repulsion!(bh, tree, Y, i, 0.5) for i in 1:500]
        @test norm(bh .- exact) / norm(exact) < 0.05
        @test sum(z5) ≈ sum(zs) rtol=0.01

        # Six blobs in 10-D: neighbor lists exact after incremental insertion;
        # blobs separated in the embedding
        rng = Xoshiro(4)
        n = 1_500
        C = 8 .* randn(rng, 6, 10)
        lab = rand(rng, 1:6, n)
        X = C[lab, :] .+ randn(rng, n, 10)
        TABLES["tsne"] = merge(NamedTuple{Tuple(Symbol("f$i") for i in 1:10)}(Tuple(X[:, i] for i in 1:10)), (label=lab,))
        fcols = ["f$i" for i in 1:10]
        p = Pipeline()
        ts = node!(p, "TSNE", source!(p, "tsne"; chunk=211); columns=fcols, max_iter=750, seed=1)
        run = run!(ProgressiveEngine(), p)
        s = state_of(run, ts)
        D = [sum(abs2, X[i, :] .- X[j, :]) for i in 1:n, j in 1:n]
        foreach(i -> D[i, i] = Inf, 1:n)
        @test all(Set(s.neighbors[i]) == Set(partialsortperm(D[i, :], 1:90)) for i in 1:n)
        @test all(issorted, s.dist2)
        E = result_of(run, ts)
        @test length(E.x) == n
        agreement = mean(1:n) do i
            d = (E.x .- E.x[i]) .^ 2 .+ (E.y .- E.y[i]) .^ 2
            d[i] = Inf
            mean(lab[partialsortperm(d, 1:10)] .== lab[i])
        end
        @test agreement > 0.98
        @test s.iteration >= 750

        # 3-D output (exact repulsion), one-shot engine, restarts
        p = Pipeline()
        ts = node!(p, "TSNE", source!(p, "tsne"); columns=fcols, output_columns=["a", "b", "c"], max_iter=100)
        run = run!(OneShotEngine(), p)
        @test keys(result_of(run, ts)) == (:a, :b, :c) && length(result_of(run, ts).a) == n
        TABLES["tmut"] = (u=X[1:300, 1], v=X[1:300, 2], w=X[1:300, 3])
        p = Pipeline()
        ts = node!(p, "TSNE", mutator!(p, "tmut"); max_iter=50, perplexity=10.0)
        run = run!(ProgressiveEngine(workers=1), p)
        @test length(result_of(run, ts).x) == 289 && state_of(run, ts).n == 289
    end
end
