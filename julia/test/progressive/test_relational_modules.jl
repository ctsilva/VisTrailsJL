"""
Tests for the relational modules ported from ProgressiVis (tier 3):
Unary, ColsBinary, Reduce, LinearMap, GroupBy, Aggregate, Join, JoinById,
Switch

Results are checked against batch computations on all rows, under several
step sizes, with inputs arriving in different orders, input updates and
deletions, live parameters, and in the one-shot engine.
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Test
using Random
using Statistics
using Tables

const VT = VisTrailsJL
const P = "org.vistrails.progressive"
const T = "org.vistrails.test.relational"

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

result_of(run, m, port="result") = (c = run.outputs[m.id][port]; c isa ProgressiveValue ? current_value(c) :
                                    c isa ProgressiveDict ? snapshot(c) : Tables.columntable(c))

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

# Appends, then updates and deletes rows, then appends more
struct MutatorModule end
VT.execution_style(::Type{MutatorModule}) = VT.Progressive()
mutable struct MutatorState
    table::ProgressiveTable
    phase::Int
end
VT.init_state(::Type{MutatorModule}, ctx) =
    MutatorState(VT.set_output!(ctx, "result", ProgressiveTable(:k => Int, :v => Float64)), 0)
function VT.step!(s::MutatorState, ctx, budget)
    s.phase += 1
    t = s.table
    if s.phase == 1
        append!(t, (k=[i % 5 for i in 1:100], v=collect(1.0:100.0)))
    elseif s.phase == 2
        t[3, :v] = 1000.0
        t[4, :k] = 7                  # a new key
    elseif s.phase == 3
        delete!(t, VT.RowIds(50:60))
    else
        append!(t, (k=[1, 9], v=[0.5, 0.25]))
        return VT.StepResult(:done, 1)
    end
    return VT.StepResult(:ready, 1)
end

for (name, type) in (("FixedTable", FixedTableModule), ("Mutator", MutatorModule))
    VT.register_module!(VT.ModuleDescriptor(T, name, type, VT.InputPort[],
        [VT.OutputPort("result", ProgressiveTable)], Tuple{String, Type}[("key", String), ("chunk", Int)]))
end

source!(p, key; chunk=typemax(Int)) = node!(p, "FixedTable"; package=T, key=key, chunk=chunk)

function data_table(n; seed=4)
    rng = Xoshiro(seed)
    return (x=randn(rng, n), y=randn(rng, n), k=rand(rng, -3:3, n), g=rand(rng, ["a", "b", "c"], n),
            w=rand(rng, 1:5, n))
end

# Batch aggregation: Dict key → (count, sum, mean, var, std, min, max) of `v`
function batch_groups(keys, v)
    out = Dict{Any, NTuple{7, Float64}}()
    for k in unique(keys)
        x = Float64.(v[keys .== Ref(k)])
        n = length(x)
        out[k] = (n, sum(x), mean(x), n > 1 ? var(x) : NaN, n > 1 ? std(x) : NaN, minimum(x), maximum(x))
    end
    return out
end

@testset "Relational modules (tier 3)" begin
    TABLES["data"] = data_table(20_000)
    data = TABLES["data"]

    @testset "Unary, ColsBinary, Reduce" begin
        for step in (333, 20_000)
            p = Pipeline()
            src = source!(p, "data")
            u = node!(p, "Unary", src; var"function"="abs", columns=["x", "k"])
            e = node!(p, "Unary", src; var"function"="exp", columns=["y"])
            b = node!(p, "ColsBinary", src; var"function"="hypot", first=["x"], second=["y"], cols_out=["r"])
            d = node!(p, "ColsBinary", src; var"function"="-", first=["x", "k"], second=["y", "w"])
            sum_ = node!(p, "Reduce", src; var"function"="+", columns=["k", "w"])
            max_ = node!(p, "Reduce", src; var"function"="max", columns=["x"])
            run = run!(ProgressiveEngine(step_size=id -> step), p)
            @test result_of(run, u) == (x=abs.(data.x), k=abs.(data.k))
            @test eltype(column(run.outputs[u.id]["result"], :k)) == Int              # types follow the function
            @test result_of(run, e) == (y=exp.(data.y),)
            @test result_of(run, b) == (r=hypot.(data.x, data.y),)
            @test result_of(run, d) == (x=data.x .- data.y, k=data.k .- data.w)
            @test result_of(run, sum_) == Dict(:k => sum(data.k), :w => sum(data.w))
            @test result_of(run, max_) == Dict(:x => maximum(data.x))
        end
        p = Pipeline()
        node!(p, "Reduce", source!(p, "data"); var"function"="-")
        @test_throws ErrorException run!(ProgressiveEngine(), p)                   # not associative
    end

    @testset "LinearMap: rows wait for the whole matrix" begin
        TABLES["matrix"] = (a=[1.0, 0.0, 2.0], b=[0.5, -1.0, 0.0])                 # 3 × 2
        TABLES["vectors"] = (x=data.x, y=data.y, w=Float64.(data.w))
        X = hcat(data.x, data.y, Float64.(data.w))
        M = [1.0 0.5; 0.0 -1.0; 2.0 0.0]
        for matrix_chunk in (1, 3)      # matrix rows one per step (late) or at once
            p = Pipeline()
            vec = source!(p, "vectors")
            mat = source!(p, "matrix"; chunk=matrix_chunk)
            lm = node!(p, "LinearMap", vec; port="vectors")
            connect!(p, mat, lm, "transformation")
            run = run!(ProgressiveEngine(step_size=id -> 2_500), p)
            Y = X * M
            r = result_of(run, lm)
            @test keys(r) == (:a, :b)
            @test r.a ≈ Y[:, 1] && r.b ≈ Y[:, 2]
        end
    end

    @testset "GroupBy and Aggregate" begin
        computations = ["x:count", "x:sum", "x:mean", "x:var", "x:std", "x:min", "x:max"]
        for (step, by) in ((997, ["k"]), (20_000, ["g", "w"]))
            p = Pipeline()
            src = source!(p, "data")
            gb = node!(p, "GroupBy", src; by=by)
            agg = node!(p, "Aggregate", gb; compute=[computations; ":count"])
            agg2 = node!(p, "Aggregate", src; by=by, compute=["y:mean"])             # without GroupBy
            run = run!(ProgressiveEngine(step_size=id -> step), p)
            keys_ = length(by) == 1 ? data.k : [(data.g[i], data.w[i]) for i in eachindex(data.g)]
            groups = run.outputs[gb.id]["result"].meta[:groups].rows
            @test Dict(k => sort(v) for (k, v) in groups) == Dict(k => findall(==(k), keys_) for k in unique(keys_))
            r = result_of(run, agg)
            expected = batch_groups(keys_, data.x)
            out_keys = length(by) == 1 ? r.k : collect(zip(r.g, r.w))
            @test Set(out_keys) == Set(keys(expected)) && allunique(out_keys)
            @test out_keys == unique(keys_)                                           # order of appearance
            for (i, k) in enumerate(out_keys)
                e = expected[k]
                @test r.x_count[i] == e[1] && r.count[i] == e[1]
                @test r.x_sum[i] ≈ e[2] && r.x_mean[i] ≈ e[3] && r.x_var[i] ≈ e[4] && r.x_std[i] ≈ e[5]
                @test r.x_min[i] == e[6] && r.x_max[i] == e[7]
            end
            r2 = result_of(run, agg2)
            ey = batch_groups(keys_, data.y)
            @test all(r2.y_mean[i] ≈ ey[k][3] for (i, k) in enumerate(length(by) == 1 ? r2.k : collect(zip(r2.g, r2.w))))
        end

        # Input updates and deletions: groups and aggregates recomputed
        p = Pipeline()
        src = node!(p, "Mutator"; package=T)
        gb = node!(p, "GroupBy", src; by=["k"])
        agg = node!(p, "Aggregate", gb; compute=["v:sum", ":count"])
        run = run!(ProgressiveEngine(step_size=id -> 30), p)
        t = Tables.columntable(run.outputs[src.id]["result"])
        expected = batch_groups(t.k, t.v)
        r = result_of(run, agg)
        @test Dict(k => (c, s) for (k, c, s) in zip(r.k, r.count, r.v_sum)) == Dict(k => (Int(e[1]), e[2]) for (k, e) in expected)
        groups = run.outputs[gb.id]["result"].meta[:groups].rows
        live = collect(row_ids(run.outputs[src.id]["result"]))
        @test Dict(k => sort(v) for (k, v) in groups) == Dict(k => live[findall(==(k), t.k)] for k in unique(t.k))
    end

    # Primary: one row per key 0..39 (keys 40.. never come); related: keys 0..49
    TABLES["primary"] = (key=collect(0:39), name=["n$i" for i in 0:39], score=collect(0.0:39.0) ./ 2)
    rng = Xoshiro(8)
    TABLES["related"] = (key=rand(rng, 0:49, 5_000), amount=rand(rng, 5_000))
    prim, rel = TABLES["primary"], TABLES["related"]

    @testset "Join: inner and outer, keys arriving after their rows" begin
        for (how, primary_chunk) in (("inner", 3), ("outer", 3), ("inner", 1000), ("outer", 1000))
            p = Pipeline()
            pr = source!(p, "primary"; chunk=primary_chunk)       # 3: keys arrive slowly
            re = source!(p, "related")
            j = node!(p, "Join"; on=["key"], how=how)
            connect!(p, pr, j, "primary"); connect!(p, re, j, "related")
            run = run!(ProgressiveEngine(step_size=id -> 400), p)
            r = result_of(run, j)
            @test keys(r) == (:key, :amount, :name, :score)
            matched = [i for i in eachindex(rel.key) if rel.key[i] < 40]
            rows = how == "inner" ? matched : collect(eachindex(rel.key))
            @test sort(collect(zip(r.key, r.amount))) == sort(collect(zip(rel.key[rows], rel.amount[rows])))
            for i in eachindex(r.key)
                if r.key[i] < 40
                    @test r.name[i] == "n$(r.key[i])" && r.score[i] == r.key[i] / 2
                else
                    @test how == "outer" && ismissing(r.name[i]) && ismissing(r.score[i])
                end
            end
        end
        # Duplicate primary keys
        TABLES["dup"] = (key=[1, 2, 1], name=["a", "b", "c"])
        p = Pipeline()
        j = node!(p, "Join"; on=["key"])
        connect!(p, source!(p, "dup"), j, "primary"); connect!(p, source!(p, "related"), j, "related")
        @test_throws ErrorException run!(ProgressiveEngine(), p)

        # Related updates and deletions are re-joined row by row
        TABLES["lookup"] = (k=collect(0:9), label=["L$i" for i in 0:9])
        p = Pipeline()
        j = node!(p, "Join"; on=["k"])
        mut = node!(p, "Mutator"; package=T)
        connect!(p, source!(p, "lookup"), j, "primary"); connect!(p, mut, j, "related")
        run = run!(ProgressiveEngine(step_size=id -> 30), p)
        rel_t = Tables.columntable(run.outputs[j.id]["result"])
        src_t = Tables.columntable(run.outputs[mut.id]["result"])
        @test sort(collect(zip(rel_t.k, rel_t.v, rel_t.label))) == sort([(k, v, "L$k") for (k, v) in zip(src_t.k, src_t.v)])
    end

    @testset "JoinById over views of one table; Switch" begin
        p = Pipeline()
        src = source!(p, "data")
        ix = node!(p, "BinningIndex", src; column="x", init_threshold=1_000)
        q = node!(p, "SimpleFilter", ix; port="index", column="x", op="<", value=0.5)
        cat = node!(p, "CategoricalQuery", src; column="g", choice=["a", "b"])
        jb = node!(p, "JoinById", q, cat)
        cond = node!(p, "Variable")
        sw = node!(p, "Switch", src)
        connect!(p, cond, sw, "condition")
        n_true, n_else = node!(p, "Count", sw), add_module!(p, P, "Count")
        connect!(p, sw, n_else, "table"; from="result_else")
        pr = start!(ProgressiveEngine(step_size=id -> 1_500), p)
        sleep(0.05)
        set_variable!(pr, cond, false)       # rows go to result_else...
        sleep(0.05)
        set_variable!(pr, cond, true)        # ...then all move to result
        close_inputs!(pr)
        run = wait(pr)
        both = [i for i in eachindex(data.x) if data.x[i] < 0.5 && data.g[i] in ("a", "b")]
        r = result_of(run, jb)
        @test r.x_1 == data.x[both] && r.g_2 == data.g[both] && r.k_1 == r.k_2
        @test sort(collect(row_ids(run.outputs[sw.id]["result"]))) == collect(eachindex(data.x))
        @test isempty(row_ids(run.outputs[sw.id]["result_else"]))
        @test result_of(run, n_true) == length(data.x) && result_of(run, n_else) == 0
    end

    @testset "One-shot engine" begin
        p = Pipeline()
        src = source!(p, "data")
        u = node!(p, "Unary", src; var"function"="abs", columns=["x"])
        agg = node!(p, "Aggregate", src; by=["k"], compute=["x:sum"])
        j = node!(p, "Join"; on=["key"])
        connect!(p, source!(p, "primary"), j, "primary"); connect!(p, source!(p, "related"), j, "related")
        progressive, oneshot = run!(ProgressiveEngine(), p), run!(OneShotEngine(), p)
        for m in (u, j)
            @test result_of(oneshot, m) == result_of(progressive, m)
        end
        a, b = result_of(oneshot, agg), result_of(progressive, agg)
        @test a.k == b.k && a.x_sum ≈ b.x_sum
    end
end
