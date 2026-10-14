"""
Tests for the modules ported from ProgressiVis (tier 1): ParquetLoader,
Quantiles, KLLSketch, Histogram1DCategorical, Distinct, Corr, IdxMin, IdxMax,
Sample

As for the other modules: after every step, a fold's result is the batch
result on the rows it consumed (approximately, within the sketch's rank
error, for the quantiles); final results do not depend on step sizes.
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Test
using Random
using Statistics
using Tables
using Parquet2

const VT = VisTrailsJL
const P = "org.vistrails.progressive"

function node!(p, name, sources...; port="table", params...)
    m = add_module!(p, P, name)
    for (k, v) in params
        set_parameter!(m, String(k), v)
    end
    for s in sources
        add_connection!(p, s, "result", m, port)
    end
    return m
end

result_of(run, m, port="result") = (c = run.outputs[m.id][port]; c isa ProgressiveValue ? current_value(c) :
                                    c isa ProgressiveDict ? snapshot(c) : Tables.columntable(c))

# Rank of v among xs, as a fraction: within [lo, hi] (ties)
rank_interval(xs_sorted, v) = (searchsortedfirst(xs_sorted, v) - 1, searchsortedlast(xs_sorted, v)) ./ length(xs_sorted)
rank_error(xs_sorted, v, q) = (r = rank_interval(xs_sorted, v); r[1] <= q <= r[2] ? 0.0 : min(abs(q - r[1]), abs(q - r[2])))

# A table with numeric, categorical and integer columns, from a constant source
function data_table(n; seed=5)
    rng = Xoshiro(seed)
    x = randn(rng, n)
    y = 2 .* x .+ randn(rng, n)
    t = (x=x, y=y, z=rand(rng, n), cat=rand(rng, ["red", "green", "blue", "cyan"], n), k=rand(rng, 1:7, n))
    return t
end

const TABLES = Dict{String, Any}()

# A source that serves a fixed table in steps
struct FixedTableModule end
VT.execution_style(::Type{FixedTableModule}) = VT.Progressive()
VT.default_step_size(::Type{FixedTableModule}) = 10_000
mutable struct FixedTableState
    data::Any
    table::ProgressiveTable
    position::Int
end
function VT.init_state(::Type{FixedTableModule}, ctx::VT.StepContext)
    data = TABLES[VT.param(ctx, "key")]
    table = VT.set_output!(ctx, "result",
                           ProgressiveTable((n => eltype(v) for (n, v) in pairs(data))...; segment_size=4_096))
    return FixedTableState(data, table, 0)
end
function VT.step!(s::FixedTableState, ctx::VT.StepContext, budget::Int)
    n = min(budget, length(first(s.data)) - s.position)
    append!(s.table, map(v -> v[s.position+1:s.position+n], s.data))
    s.position += n
    return VT.StepResult(s.position == length(first(s.data)) ? :done : :ready, n)
end
VT.register_module!(VT.ModuleDescriptor("org.vistrails.test.modules", "FixedTable", FixedTableModule,
    VT.InputPort[], [VT.OutputPort("result", ProgressiveTable)], Tuple{String, Type}[("key", String)]))

# A source that appends, then updates, then deletes rows
struct MutatorModule end
VT.execution_style(::Type{MutatorModule}) = VT.Progressive()
mutable struct MutatorState
    table::ProgressiveTable
    phase::Int
end
VT.init_state(::Type{MutatorModule}, ctx) =
    MutatorState(VT.set_output!(ctx, "result", ProgressiveTable(:x => Float64, :y => Float64)), 0)
function VT.step!(s::MutatorState, ctx, budget)
    s.phase += 1
    t = s.table
    if s.phase == 1
        append!(t, (x=collect(1.0:100.0), y=collect(101.0:200.0)))
    elseif s.phase == 2
        t[1, :x] = 500.0
    elseif s.phase == 3
        delete!(t, VT.RowIds(90:100))
        t[2, :y] = 1000.0
    else
        append!(t, (x=[-5.0], y=[0.2]))
        return VT.StepResult(:done, 1)
    end
    return VT.StepResult(:ready, 1)
end
VT.register_module!(VT.ModuleDescriptor("org.vistrails.test.modules", "Mutator", MutatorModule, VT.InputPort[],
    [VT.OutputPort("result", ProgressiveTable)], Tuple{String, Type}[]))

function fixed_source!(p, key)
    m = add_module!(p, "org.vistrails.test.modules", "FixedTable")
    set_parameter!(m, "key", key)
    return m
end

function modules_pipeline(key)
    p = Pipeline()
    src = fixed_source!(p, key)
    m = (
        src = src,
        quantiles = node!(p, "Quantiles", src; columns=["x", "y"], quantiles=[0.0, 0.1, 0.5, 0.9, 1.0]),
        kll = node!(p, "KLLSketch", src; column="z", binning=4, quantiles=[0.5]),
        cat = node!(p, "Histogram1DCategorical", src; column="cat"),
        distinct = node!(p, "Distinct", src; columns=["cat", "k", "x"], threshold=10),
        corr = node!(p, "Corr", src; columns=["x", "y", "z"]),
        cov = node!(p, "Corr", src; columns=["x", "y"], mode="CovarianceOnly"),
        idxmin = node!(p, "IdxMin", src; columns=["x", "k"]),
        idxmax = node!(p, "IdxMax", src; columns=["x", "k"]),
    )
    return p, m
end

# The batch result of each module on rows `t` (a column table)
function check_module(name, r, t)
    n = length(t.x)
    if name == :quantiles
        return all(begin
            xs = sort(t[c])
            r[c][1] == xs[1] && r[c][end] == xs[end] &&
                all(rank_error(xs, v, q) <= 0.02 for (v, q) in zip(r[c], [0.0, 0.1, 0.5, 0.9, 1.0]))
        end for c in (:x, :y))
    elseif name == :kll
        zs = sort(t.z)
        return r[:n] == n && r[:min] == zs[1] && r[:max] == zs[end] && rank_error(zs, r[:quantiles][1], 0.5) <= 0.02 &&
               length(r[:pmf]) == 4 && isapprox(sum(r[:pmf]), 1.0; atol=1e-9) &&
               all(abs(m - count(r[:splits][i] .<= t.z .< r[:splits][i+1]) / n) <= 0.03 for (i, m) in enumerate(r[:pmf][1:3]))
    elseif name == :cat
        return r == Dict{Any, Any}(v => count(==(v), t.cat) for v in unique(t.cat))
    elseif name == :distinct
        return r[:cat] == Set{Any}(t.cat) && r[:k] == Set{Any}(t.k) && (length(unique(t.x)) > 10 ? r[:x] === nothing : r[:x] == Set{Any}(t.x))
    elseif name == :corr
        n < 2 && return isempty(r)
        return all(isapprox(r[(a, b)], cor(t[a], t[b]); atol=1e-9) for a in (:x, :y, :z), b in (:x, :y, :z))
    elseif name == :cov
        n < 2 && return isempty(r)
        return all(isapprox(r[(a, b)], cov(t[a], t[b]); rtol=1e-9) for a in (:x, :y), b in (:x, :y))
    elseif name in (:idxmin, :idxmax)
        f = name == :idxmin ? argmin : argmax
        return all(r[c].id == f(t[c]) && r[c].value == t[c][f(t[c])] for c in (:x, :k))
    end
    return true
end

struct PrefixChecker <: ExecutionObserver
    m::NamedTuple
    data::Any
    checked::Dict{Symbol, Int}
    failures::Vector{String}
end

function VT.on_module_step(c::PrefixChecker, run, mod, result, seconds)
    name = findfirst(x -> x.id == mod.id, c.m)
    name == :src && return
    consumed = collect(consumed_rows(run.engine_state.modules[mod.id].state))
    isempty(consumed) && return
    consumed == 1:length(consumed) || push!(c.failures, "$name consumed rows out of order")
    t = map(v -> v[consumed], c.data)
    c.checked[name] = get(c.checked, name, 0) + 1
    check_module(name, result_of(run, mod), t) || push!(c.failures, "$name after $(length(consumed)) rows")
end

@testset "ProgressiVis modules (tier 1)" begin
    @testset "KLL sketch" begin
        # Exact while nothing was compacted
        sk = VT.kll_update!(VT.KLL(200), [5.0, 1.0, NaN, 3.0, 2.0, 4.0])
        @test sk.n == 5
        @test VT.kll_quantiles(sk, [0.0, 0.2, 0.5, 0.6, 1.0]) == [1.0, 1.0, 3.0, 3.0, 5.0]
        @test isnan(VT.kll_quantiles(VT.KLL(), [0.5])[1])

        # Rank error and size on 2 M values, in pieces of various sizes, and merged
        rng = Xoshiro(1)
        xs = randn(rng, 2_000_000)
        sk = VT.KLL(200)
        i = 0
        while i < length(xs)
            m = min(length(xs) - i, rand(rng, 1:50_000))
            VT.kll_update!(sk, view(xs, i+1:i+m))
            i += m
        end
        parts = [VT.kll_update!(VT.KLL(200), view(xs, r)) for r in (1:700_000, 700_001:1_500_000, 1_500_001:2_000_000)]
        merged = foldl(VT.kll_merge!, parts[2:end]; init=parts[1])
        sorted = sort(xs)
        qs = 0.01:0.01:0.99
        for s in (sk, merged)
            @test s.n == length(xs)
            @test sum(length, s.levels) <= 3 * 200
            @test maximum(rank_error(sorted, v, q) for (v, q) in zip(VT.kll_quantiles(s, qs), qs)) <= 0.015
            @test VT.kll_quantiles(s, [0.0, 1.0]) == [sorted[1], sorted[end]]
        end
        edges = collect(range(-2, 2; length=9))
        pmf = VT.kll_pmf(sk, edges)
        exact = [count(edges[i] .<= xs .< edges[i+1]) for i in 1:8] ./ length(xs)
        @test maximum(abs.(pmf .- exact)) <= 0.015
    end

    TABLES["data"] = data_table(60_000)
    data = TABLES["data"]

    @testset "Prefix consistency under random step sizes" begin
        rng = MersenneTwister(4)
        p, m = modules_pipeline("data")
        checker = PrefixChecker(m, data, Dict{Symbol, Int}(), String[])
        run = run!(ProgressiveEngine(step_size=id -> rand(rng, 1:7_000)), p; observers=[checker])
        @test isempty(checker.failures)
        @test all(get(checker.checked, k, 0) >= 3 for k in keys(m) if k != :src)
        @test all(module_status(run, mod.id) == :done for mod in m)
    end

    @testset "Final results: exact (quantiles: within the rank error), whatever the step sizes" begin
        p, m = modules_pipeline("data")
        runs = [run!(ProgressiveEngine(step_size=id -> s), p) for s in (999, 60_000)]
        push!(runs, run!(ProgressiveEngine(), p))
        for r in runs, (name, mod) in pairs(m)
            name == :src && continue
            @test check_module(name, result_of(r, mod), data)
        end
        # Exact results agree (sketches are merged along step boundaries, so
        # theirs vary within the rank error)
        for r in runs[2:end], name in (:cat, :distinct, :idxmin, :idxmax)
            @test result_of(r, m[name]) == result_of(runs[1], m[name])
        end
    end

    @testset "Same results in the one-shot and parallel engines" begin
        p, m = modules_pipeline("data")
        sample = node!(p, "Sample", m.src; samples=500, seed=3)
        progressive = run!(ProgressiveEngine(), p)
        for engine in (OneShotEngine(), ParallelEngine())
            r = run!(engine, p)
            for name in (:cat, :distinct, :idxmin, :idxmax)
                @test result_of(r, m[name]) == result_of(progressive, m[name])
            end
            for name in (:quantiles, :kll, :corr, :cov)
                @test check_module(name, result_of(r, m[name]), data)
            end
            @test result_of(r, sample, "select") == result_of(progressive, sample, "select")
        end
    end

    @testset "Input updates and deletions" begin
        p = Pipeline()
        src = add_module!(p, "org.vistrails.test.modules", "Mutator")
        hi = node!(p, "IdxMax", src)
        cat = node!(p, "Histogram1DCategorical", src; column="x")
        s = node!(p, "Sample", src; samples=20, seed=1)
        run = run!(ProgressiveEngine(step_size=id -> 10), p)
        live = setdiff(1:100, 90:100)
        x = [i == 1 ? 500.0 : Float64(i) for i in live]
        @test result_of(run, hi)[:x] == (id=1, value=500.0)       # updated row
        @test result_of(run, hi)[:y] == (id=2, value=1000.0)
        @test result_of(run, cat) == Dict{Any, Any}(v => 1 for v in [x; -5.0])
        sampled = result_of(run, s)
        @test length(sampled.x) == 20 && isempty(intersect(result_of(run, s, "select"), 90:100))
        t = run.outputs[src.id]["result"]
        @test all(sampled.x[i] == t[id, :x] && sampled.y[i] == t[id, :y]
                  for (i, id) in enumerate(result_of(run, s, "select")))
    end

    @testset "IdxMin, IdxMax: ties to the first row, NaN skipped" begin
        TABLES["ties"] = (v=[NaN, 3.0, 1.0, 5.0, 1.0, 5.0, NaN],)
        p = Pipeline()
        src = fixed_source!(p, "ties")
        lo, hi = node!(p, "IdxMin", src), node!(p, "IdxMax", src)
        run = run!(ProgressiveEngine(step_size=id -> 2), p)
        @test result_of(run, lo)[:v] == (id=3, value=1.0)
        @test result_of(run, hi)[:v] == (id=4, value=5.0)
    end

    @testset "Sample" begin
        TABLES["ids"] = (id=collect(1:200_000), v=collect(1.0:200_000.0))
        sample(rows_key, samples, step) = begin
            p = Pipeline()
            src = fixed_source!(p, rows_key)
            s = node!(p, "Sample", src; samples=samples, seed=7)
            run = run!(ProgressiveEngine(step_size=id -> step), p)
            result_of(run, s), result_of(run, s, "select")
        end

        rows, select = sample("ids", 2_000, 10_000)
        @test length(rows.id) == 2_000 && allunique(rows.id)
        @test rows.id == select
        @test rows.v == Float64.(rows.id)                        # whole rows
        # Uniform: about 200 sampled rows in each tenth of the input
        counts = [count(i -> (d - 1) * 20_000 < i <= d * 20_000, rows.id) for d in 1:10]
        @test sum((counts .- 200) .^ 2 ./ 200) < 27.9           # chi² (9 dof), p = 0.001
        # The same sample whatever the step sizes
        @test sample("ids", 2_000, 777)[2] == select
        @test sample("ids", 2_000, 200_000)[2] == select

        # Fewer rows than samples: all rows
        TABLES["few"] = (id=collect(1:30), v=collect(1.0:30.0))
        @test sort(sample("few", 50, 7)[1].id) == 1:30

        # Consumers see replacements as updates, and their results follow
        p = Pipeline()
        src = fixed_source!(p, "ids")
        s = node!(p, "Sample", src; samples=100, seed=7)
        mean = node!(p, "Mean", s; columns=["v"])
        run = run!(ProgressiveEngine(step_size=id -> 5_000), p)
        @test result_of(run, mean)[:v] ≈ sum(result_of(run, s).v) / 100
    end

    @testset "ParquetLoader" begin
        path = joinpath(mktempdir(), "points.parquet")
        rng = Xoshiro(9)
        n = 10_000
        x = Union{Missing, Float32}[rand(rng) < 0.05 ? missing : rand(rng, Float32) for _ in 1:n]
        data = (x=x, k=rand(rng, Int16(1):Int16(9), n), label=rand(rng, ["a", "b", "c"], n))
        parts = [map(c -> c[r], data) for r in (1:3_000, 3_001:7_500, 7_501:n)]   # three row groups
        Parquet2.writefile(path, Tables.partitioner(parts))

        p = Pipeline()
        pq = node!(p, "ParquetLoader"; path=path)
        counter = node!(p, "Count", pq)
        cat = node!(p, "Histogram1DCategorical", pq; column="label")
        run = run!(ProgressiveEngine(step_size=id -> 1_000), p)
        table = run.outputs[pq.id]["result"]
        @test eltype(column(table, :x)) == Float32                 # nullable floats: NaN for null
        @test eltype(column(table, :k)) == Int16
        t = Tables.columntable(table)
        @test isequal(t.x, Float32[ismissing(v) ? NaN32 : v for v in x])
        @test t.k == data.k && t.label == data.label
        @test result_of(run, counter) == n
        @test module_steps(run, pq.id).steps == 10                # steps cross row groups
        @test result_of(run, cat) == Dict{Any, Any}(l => count(==(l), data.label) for l in ("a", "b", "c"))

        # A column subset
        p = Pipeline()
        pq = node!(p, "ParquetLoader"; path=path, columns=["label"])
        run = run!(ProgressiveEngine(), p)
        @test Tables.columntable(run.outputs[pq.id]["result"]) == (label=data.label,)
    end
end
