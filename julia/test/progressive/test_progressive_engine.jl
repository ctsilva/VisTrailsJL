"""
Tests for the progressive engine and modules (Phase 3b of docs/PROGRESSIVE_EXECUTION_PLAN.md)

Guarantees checked (after progressivis-parallel/design/parallel_progressivis.md §8):
- prefix consistency: after every step, a fold's result equals the batch
  result on the rows it has consumed so far; a map's output equals the map
  applied to those rows;
- eventual exactness: final results equal the batch results;
- interleaving independence: final results do not depend on step sizes.
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Test
using Random
using Tables
using Logging
using CSV
using Arrow

const VT = VisTrailsJL
const P = "org.vistrails.progressive"
const TP = "org.vistrails.test.progressive"

function node!(p, name, sources...; package=P, port="table", params...)
    m = add_module!(p, package, name)
    for (k, v) in params
        set_parameter!(m, String(k), v)
    end
    for s in sources
        add_connection!(p, s, "result", m, port)
    end
    return m
end

result_of(run, m) = (c = run.outputs[m.id]["result"]; c isa ProgressiveValue ? current_value(c) :
                     c isa ProgressiveDict ? snapshot(c) : Tables.columntable(c))

quiet(f) = with_logger(NullLogger()) do; redirect_stdout(f, devnull); end

# Batch versions of the statistics
batch_mean(v) = sum(v) / length(v)
batch_var(v) = (m = batch_mean(v); sum(x -> (x - m)^2, v) / (length(v) - 1))
function batch_hist(v, lo, hi, bins)
    h = zeros(Int, bins)
    for x in v
        b = VT.histogram_bin(x, lo, hi, bins)
        b > 0 && (h[b] += 1)
    end
    return h
end

# A pipeline exercising every kind of module
function stats_pipeline(rows; seed=3)
    p = Pipeline()
    src = node!(p, "RandomTable"; rows=rows, seed=seed, columns=["x", "y"])
    m = (
        src = src,
        min = node!(p, "Min", src),
        max = node!(p, "Max", src),
        mean = node!(p, "Mean", src),
        var = node!(p, "Var", src),
        count = node!(p, "Count", src),
        hist = node!(p, "Histogram1D", src; column="x", bins=16, min=0.0, max=1.0),
        hist2 = node!(p, "Histogram2D", src; x_column="x", y_column="y", xbins=4, ybins=5,
                      xmin=0.0, xmax=1.0, ymin=0.0, ymax=1.0),
        filter = node!(p, "Filter", src; column="y", op="<", value=0.3),
    )
    m = merge(m, (fcount = node!(p, "Count", m.filter), sink = node!(p, "Sink", m.filter),
                  select = node!(p, "Select", m.filter; columns=["y"])))
    return p, m
end

# Checks the published result of a fold or map against its consumed rows
struct PrefixChecker <: ExecutionObserver
    m::NamedTuple
    checked::Dict{Symbol, Int}
    failures::Vector{String}
end
PrefixChecker(m) = PrefixChecker(m, Dict{Symbol, Int}(), String[])

function VT.on_module_step(c::PrefixChecker, run, mod, result, seconds)
    name = findfirst(x -> x.id == mod.id, c.m)
    name in (:src, :sink) && return
    state = run.engine_state.modules[mod.id].state
    consumed = consumed_rows(state)
    isempty(consumed) && return
    t = state.table
    x, y = t[consumed, :x], t[consumed, :y]
    r = result_of(run, mod)
    ok = if name == :min
        r == Dict(:x => minimum(x), :y => minimum(y))
    elseif name == :max
        r == Dict(:x => maximum(x), :y => maximum(y))
    elseif name == :mean
        isapprox(r[:x], batch_mean(x); rtol=1e-12) && isapprox(r[:y], batch_mean(y); rtol=1e-12)
    elseif name == :var
        length(x) < 2 || (isapprox(r[:x], batch_var(x); rtol=1e-9) && isapprox(r[:y], batch_var(y); rtol=1e-9))
    elseif name == :count
        r == length(consumed)
    elseif name == :hist
        r == batch_hist(x, 0.0, 1.0, 16)
    elseif name == :hist2
        sum(r) == count(i -> 0 <= x[i] <= 1 && 0 <= y[i] <= 1, eachindex(x)) && size(r) == (4, 5)
    elseif name == :filter
        keep = y .< 0.3
        r == (x=x[keep], y=y[keep])
    elseif name == :fcount
        r == length(consumed)
    elseif name == :select
        r == (y=y,)
    else
        true
    end
    c.checked[name] = get(c.checked, name, 0) + 1
    ok || push!(c.failures, "$name after $(length(consumed)) rows")
end

final_results(run, m) = Dict(k => result_of(run, v) for (k, v) in pairs(m) if k ∉ (:src, :sink))

@testset "Progressive engine" begin
    @testset "Prefix consistency under random step sizes" begin
        rng = MersenneTwister(11)
        p, m = stats_pipeline(30_000)
        checker = PrefixChecker(m)
        engine = ProgressiveEngine(step_size=id -> rand(rng, 1:3_000))
        run = run!(engine, p; observers=[checker])

        @test isempty(checker.failures)
        @test all(get(checker.checked, k, 0) >= 3 for k in keys(m) if k ∉ (:src, :sink))
        @test all(module_status(run, mod.id) == :done for mod in m)
    end

    @testset "Eventual exactness and interleaving independence" begin
        p, m = stats_pipeline(40_000)
        runs = [run!(ProgressiveEngine(step_size=id -> s), p) for s in (777, 10_000, 40_000)]
        push!(runs, run!(ProgressiveEngine(), p))       # time-predicted steps
        results = [final_results(r, m) for r in runs]

        table = Tables.columntable(runs[1].outputs[m.src.id]["result"])
        x, y = table.x, table.y
        @test length(x) == 40_000
        exact = results[1]
        @test exact[:min] == Dict(:x => minimum(x), :y => minimum(y))
        @test exact[:count] == 40_000
        @test exact[:hist] == batch_hist(x, 0.0, 1.0, 16)
        @test exact[:fcount] == count(<(0.3), y)
        @test isapprox(exact[:var][:x], batch_var(x); rtol=1e-9)

        for r in results[2:end]
            for k in (:min, :max, :count, :hist, :hist2, :filter, :fcount, :select)
                @test r[k] == exact[k]
            end
            @test all(isapprox(r[:mean][c], exact[:mean][c]; rtol=1e-12) for c in (:x, :y))
            @test all(isapprox(r[:var][c], exact[:var][c]; rtol=1e-12) for c in (:x, :y))
        end

        # The source produces the same rows whatever the step sizes
        @test all(Tables.columntable(r.outputs[m.src.id]["result"]) == table for r in runs)
    end

    @testset "Same results in the one-shot, parallel and cached engines" begin
        p, m = stats_pipeline(20_000)
        progressive = final_results(run!(ProgressiveEngine(), p), m)
        for engine in (OneShotEngine(), ParallelEngine(), ParallelEngine(CachedEngine()))
            r = final_results(run!(engine, p), m)
            for k in (:min, :max, :count, :hist, :hist2, :filter, :fcount, :select)
                @test r[k] == progressive[k]
            end
            @test all(isapprox(r[:var][c], progressive[:var][c]; rtol=1e-12) for c in (:x, :y))
        end
    end

    # A test source that appends, updates and deletes rows over its steps
    struct MutatorModule end
    VT.execution_style(::Type{MutatorModule}) = Progressive()
    mutable struct MutatorState
        table::ProgressiveTable
        phase::Int
    end
    VT.init_state(::Type{MutatorModule}, ctx) =
        MutatorState(set_output!(ctx, "result", ProgressiveTable(:x => Float64, :y => Float64)), 0)
    function VT.step!(s::MutatorState, ctx, budget)
        s.phase += 1
        t = s.table
        if s.phase == 1
            append!(t, (x=collect(1.0:100.0), y=collect(101.0:200.0)))
        elseif s.phase == 2
            t[1, :x] = 500.0           # new maximum
            t[50, :y] = 0.1            # now passes the filter
        elseif s.phase == 3
            delete!(t, 90:100)         # removes rows, including x = 100
            t[2, :y] = 1000.0
        else
            append!(t, (x=[-5.0], y=[0.2]))
            return StepResult(:done, 1)
        end
        return StepResult(:ready, 1)
    end
    VT.register_module!(VT.ModuleDescriptor(TP, "Mutator", MutatorModule, VT.InputPort[],
        [VT.OutputPort("result", ProgressiveTable)], Tuple{String, Type}[]))

    @testset "Updates and deletions reach consumers" begin
        p = Pipeline()
        src = node!(p, "Mutator"; package=TP)
        mn, mx = node!(p, "Min", src), node!(p, "Max", src)
        f = node!(p, "Filter", src; column="y", op="<", value=150.0)
        fc = node!(p, "Count", f)
        for step_size in (1, 7, 1_000)
            run = run!(ProgressiveEngine(step_size=id -> step_size), p)
            final = Tables.columntable(run.outputs[src.id]["result"])
            @test length(final.x) == 90
            @test result_of(run, mn) == Dict(:x => minimum(final.x), :y => minimum(final.y))
            @test result_of(run, mx) == Dict(:x => 500.0, :y => maximum(final.y))
            keep = final.y .< 150.0
            @test result_of(run, f) == (x=final.x[keep], y=final.y[keep])
            @test result_of(run, fc) == count(keep)
        end
    end

    @testset "Termination, logging and observer events" begin
        struct EventCounter <: ExecutionObserver
            events::Dict{Tuple{Symbol, Int}, Int}
            sweeps::Vector{Int}
        end
        bump!(c, k) = (c.events[k] = get(c.events, k, 0) + 1)
        VT.on_module_start(c::EventCounter, run, mod) = bump!(c, (:start, mod.id))
        VT.on_module_step(c::EventCounter, run, mod, result, seconds) = bump!(c, (:step, mod.id))
        VT.on_module_done(c::EventCounter, run, mod, outputs) = bump!(c, (:done, mod.id))
        VT.on_sweep(c::EventCounter, run, sweep) = push!(c.sweeps, sweep)

        p, m = stats_pipeline(10_000)
        counter = EventCounter(Dict{Tuple{Symbol, Int}, Int}(), Int[])
        run = run!(ProgressiveEngine(step_size=id -> 1_500), p; observers=[counter])

        for mod in m
            @test counter.events[(:start, mod.id)] == 1
            @test counter.events[(:done, mod.id)] == 1
            @test counter.events[(:step, mod.id)] == module_steps(run, mod.id).steps
        end
        @test counter.sweeps == 1:run.engine_state.sweeps
        @test module_steps(run, m.src.id) == (steps=7, items=10_000)   # ceil(10 000 / 1 500)
        @test VT.is_successful(run.workflow_exec)
        execs = Dict(e.module_id => e for e in run.workflow_exec.module_execs)
        @test execs[m.count.id].annotations["items"] == "10000"
        @test parse(Int, execs[m.count.id].annotations["steps"]) == module_steps(run, m.count.id).steps
    end

    # One-shot modules around progressive ones
    struct DescribeModule end      # one-shot: formats a dict
    function VT.compute(mod::VT.ModuleInstance, ::Type{DescribeModule})
        d = mod.inputs["value"]
        mod.outputs["text"] = join(("$k=$(round(v, digits=3))" for (k, v) in sort(collect(d), by=first)), ",")
        return mod.outputs
    end
    VT.register_module!(VT.ModuleDescriptor(TP, "Describe", DescribeModule,
        [VT.InputPort("value", Any)], [VT.OutputPort("text", String)], Tuple{String, Type}[]))

    @testset "One-shot modules in a progressive run" begin
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=20_000, seed=5)
        mn = node!(p, "Min", src)
        describe = add_module!(p, TP, "Describe")
        add_connection!(p, mn, "result", describe, "value")
        texts = String[]
        struct TextWatcher <: ExecutionObserver
            id::Int
            texts::Vector{String}
        end
        VT.on_module_step(w::TextWatcher, run, mod, result, seconds) =
            mod.id == w.id && push!(w.texts, current_value(run.outputs[w.id]["text"]))

        # Serially, the sweep order is deterministic: Describe sees intermediate minima
        run = run!(ProgressiveEngine(workers=1, step_size=id -> 2_000), p; observers=[TextWatcher(describe.id, texts)])
        @test length(texts) > 1                                  # recomputed as the minimum improved
        final_min = result_of(run, mn)
        expected = "x=$(round(final_min[:x], digits=3)),y=$(round(final_min[:y], digits=3))"
        @test last(texts) == expected
        @test module_status(run, describe.id) == :done

        # In parallel, how many intermediate results it sees depends on timing;
        # the final one is the same
        run = run!(ProgressiveEngine(step_size=id -> 2_000), p)
        @test current_value(run.outputs[describe.id]["text"]) == expected

        # A one-shot constant feeding a progressive module
        p2 = Pipeline()
        k = add_module!(p2, "org.vistrails.vistrails.basic", "Integer"); set_parameter!(k, "value", 3)
        sink = add_module!(p2, P, "Sink")
        add_connection!(p2, k, "value", sink, "table")
        run2 = run!(ProgressiveEngine(), p2)
        @test module_status(run2, k.id) == :done && module_status(run2, sink.id) == :done
    end

    @testset "Background runs: start!, live results, stop!" begin
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=50_000_000, seed=1)
        cnt = node!(p, "Count", src)
        pr = start!(ProgressiveEngine(step_size=id -> 20_000), p)
        seen = Int[]
        while length(seen) < 5
            sleep(0.01)
            c = pr.run.outputs[cnt.id]["result"]
            has_value(c) && push!(seen, current_value(c))
        end
        stop!(pr)
        run = wait(pr)
        @test run === pr.run && istaskdone(pr)
        @test issorted(seen) && last(seen) > 0
        @test module_status(run, src.id) != :done             # stopped early
        @test current_value(run.outputs[cnt.id]["result"]) < 50_000_000
    end

    # A module that fails on its second step
    struct FlakyModule end
    VT.execution_style(::Type{FlakyModule}) = Progressive()
    mutable struct FlakyState
        sub::Any
        steps::Int
    end
    VT.init_state(::Type{FlakyModule}, ctx) =
        (set_output!(ctx, "result", ProgressiveValue{Int}()); FlakyState(input_subscription(ctx, "table"), 0))
    function VT.step!(s::FlakyState, ctx, budget)
        s.steps += 1
        s.steps == 2 && error("flaky module failed")
        n = length(next_created!(s.sub, budget))
        return StepResult(has_changes(s.sub) ? :ready : :blocked, n)
    end
    VT.register_module!(VT.ModuleDescriptor(TP, "Flaky", FlakyModule,
        [VT.InputPort("table", ProgressiveTable)], [VT.OutputPort("result", ProgressiveValue)], Tuple{String, Type}[]))

    @testset "A failure stops its downstream only" begin
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=10_000)
        flaky = node!(p, "Flaky", src; package=TP)
        after = node!(p, "Sink", flaky)
        independent = node!(p, "Count", src)
        run_ref = Ref{Any}(nothing)
        struct Grab <: ExecutionObserver
            ref::Ref{Any}
        end
        VT.on_run_start(g::Grab, run) = (g.ref[] = run)

        @test_throws ErrorException run!(ProgressiveEngine(step_size=id -> 1_000), p; observers=[Grab(run_ref)])
        run = run_ref[]
        @test module_status(run, flaky.id) == :failed
        @test module_status(run, after.id) == :cancelled
        @test module_status(run, independent.id) == :done
        @test current_value(run.outputs[independent.id]["result"]) == 10_000
        @test !VT.is_successful(run.workflow_exec)
    end

    @testset "CSVLoader" begin
        dir = mktempdir()
        path = joinpath(dir, "points.csv")
        rng = MersenneTwister(2)
        n = 5_000
        xs, ks = round.(rand(rng, n), digits=4), rand(rng, 1:9, n)
        labels = rand(rng, ["a", "b", "c"], n)
        open(path, "w") do io
            println(io, "x,k,label")
            for i in 1:n
                println(io, "$(xs[i]),$(ks[i]),$(labels[i])")
            end
        end

        p = Pipeline()
        csv = node!(p, "CSVLoader"; path=path)
        mean = node!(p, "Mean", csv)
        sel = node!(p, "Select", csv; columns=["label"])
        run = run!(ProgressiveEngine(step_size=id -> 333), p)
        table = run.outputs[csv.id]["result"]
        @test eltype(column(table, :k)) == Float64                  # integers widened
        @test Tables.columntable(table) == (x=xs, k=Float64.(ks), label=labels)
        @test module_steps(run, csv.id).steps == cld(n, 333)
        @test isapprox(result_of(run, mean)[:x], batch_mean(xs); rtol=1e-12)
        @test result_of(run, sel) == (label=labels,)
    end

    @testset "ArrowLoader" begin
        path = joinpath(mktempdir(), "points.arrow")
        rng = MersenneTwister(3)
        n = 5_000
        data = (x=rand(rng, Float32, n), k=rand(rng, Int16(1):Int16(9), n), label=rand(rng, ["a", "b"], n))
        Arrow.write(path, data)

        p = Pipeline()
        arrow = node!(p, "ArrowLoader"; path=path)
        mean = node!(p, "Mean", arrow; columns=["x"])
        run = run!(ProgressiveEngine(step_size=id -> 333), p)
        table = run.outputs[arrow.id]["result"]
        @test eltype(column(table, :k)) == Int16                    # types kept
        @test Tables.columntable(table) == data
        @test module_steps(run, arrow.id).steps == cld(n, 333)
        @test isapprox(result_of(run, mean)[:x], batch_mean(Float64.(data.x)); rtol=1e-6)

        # A column subset; throttle caps the rows per step
        p = Pipeline()
        arrow = node!(p, "ArrowLoader"; path=path, columns=["label"], throttle=100)
        run = run!(ProgressiveEngine(step_size=id -> 1_000), p)
        @test Tables.columntable(run.outputs[arrow.id]["result"]) == (label=data.label,)
        @test module_steps(run, arrow.id).steps == cld(n, 100)

        # rate: rows per second, delivered in chunks of 50 ms worth of rows
        p = Pipeline()
        arrow = node!(p, "ArrowLoader"; path=path, rate=20_000.0)
        count = node!(p, "Count", arrow)
        t = @elapsed run = run!(ProgressiveEngine(step_size=id -> 100_000), p)
        @test result_of(run, count) == n
        @test 0.2 <= t < 2.0                                       # 5 000 rows at 20 000/s: 0.25 s
        @test module_steps(run, count.id).items == n
        @test module_steps(run, count.id).steps <= cld(n, 1_000) + 2   # chunks of >= 1 000 rows
    end

    @testset "Time predictor" begin
        pred = VT.StepPredictor()
        @test VT.predict(pred, 0.1, 500) == 500
        VT.record!(pred, 0, 2.0)                       # empty steps carry no information
        VT.record!(pred, 10, 100.0)                    # first step with items ignored (compilation)
        @test VT.predict(pred, 0.1, 500) == 500
        VT.record!(pred, 1_000, 0.01)
        VT.record!(pred, 3_000, 0.03)                  # 100 000 items/s
        @test VT.predict(pred, 0.1, 500) == 10_000
        VT.record!(pred, 0, 1.0)                       # empty steps carry no information
        @test VT.predict(pred, 0.1, 500) == 10_000
        for _ in 1:10
            VT.record!(pred, 1_000, 0.1)               # rate drops to 10 000 items/s
        end
        @test VT.predict(pred, 0.1, 500) == 1_000      # only the last 7 steps count

        # In a run, steps settle near the quantum
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=20_000_000, seed=1)
        node!(p, "Var", src)
        durations = Float64[]
        struct Durations <: ExecutionObserver
            d::Vector{Float64}
            id::Int
        end
        VT.on_module_step(o::Durations, run, mod, result, seconds) = mod.id == o.id && push!(o.d, seconds)
        quantum = 0.02
        pr = start!(ProgressiveEngine(quantum=quantum), p; observers=[Durations(durations, src.id)])
        while length(durations) < 15 && !istaskdone(pr)   # the run may end first (fast steps)
            sleep(0.01)
        end
        stop!(pr); wait(pr)
        @test length(durations) >= 8
        later = sort(durations[5:end])
        @test later[cld(length(later), 2)] < 3 * quantum      # median step within 3× the quantum
    end

    @testset "Workflow notebook" begin
        workflow = parse_workflow_notebook(joinpath(@__DIR__, "progressive_workflow.ipynb"))
        pipeline, id_to_module = build_pipeline_from_workflow(workflow)
        _, outputs = quiet(() -> execute_notebook_pipeline(pipeline, workflow; id_to_module=id_to_module,
                                                           engine=ProgressiveEngine()))
        points = run!(OneShotEngine(), pipeline).outputs[id_to_module["points"].id]["result"]
        xs = Tables.columntable(points).x
        @test current_value(outputs["count"]) == count(<(0.5), xs)
        @test isapprox(snapshot(outputs["mean"])[:x], batch_mean(filter(<(0.5), xs)); rtol=1e-12)
    end
end
