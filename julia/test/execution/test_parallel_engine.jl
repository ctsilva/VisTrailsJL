"""
Tests for the parallel engine (Phase 2 of docs/PROGRESSIVE_EXECUTION_PLAN.md)

Run with several threads: julia --project=. --threads=4 test/execution/test_parallel_engine.jl
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Test
using Logging
using Random

const VT = VisTrailsJL
const PKG = "org.vistrails.test.parallel"

# Test modules record when and where they ran
struct PConst end
struct PSum end
struct PWork end    # spins for `ms` milliseconds (no yield), then sums its inputs
struct PFail end    # spins for `ms` milliseconds, then throws
struct PMain end    # must run on the main thread

const TRACE = Tuple{Int, Symbol, UInt64, Int}[]  # (module id, :start/:end, time, thread)
const TRACE_LOCK = ReentrantLock()
trace!(mod, what) = lock(() -> push!(TRACE, (mod.id, what, time_ns(), Threads.threadid())), TRACE_LOCK)

function spin(ms)
    stop = time_ns() + round(UInt64, ms * 1e6)
    x = 0.0
    while time_ns() < stop
        x += sin(x)
    end
    return x
end

total_inputs(mod) = sum(get_input_list(mod, "in"); init=0)

function VT.compute(mod::VT.ModuleInstance, ::Type{PConst})
    trace!(mod, :start); trace!(mod, :end)
    mod.outputs["value"] = mod.parameters["value"]
    return mod.outputs
end

function VT.compute(mod::VT.ModuleInstance, ::Type{PSum})
    trace!(mod, :start)
    mod.outputs["value"] = total_inputs(mod) + get(mod.parameters, "add", 0)
    trace!(mod, :end)
    return mod.outputs
end

function VT.compute(mod::VT.ModuleInstance, ::Type{PWork})
    trace!(mod, :start)
    spin(get(mod.parameters, "ms", 50))
    mod.outputs["value"] = total_inputs(mod) + 1
    trace!(mod, :end)
    return mod.outputs
end

function VT.compute(mod::VT.ModuleInstance, ::Type{PFail})
    trace!(mod, :start)
    spin(get(mod.parameters, "ms", 0))
    trace!(mod, :end)
    error("intentional failure in module $(mod.id)")
end

function VT.compute(mod::VT.ModuleInstance, ::Type{PMain})
    trace!(mod, :start)
    mod.outputs["value"] = Threads.threadid()
    trace!(mod, :end)
    return mod.outputs
end
VT.thread_affinity(::Type{PMain}) = :main

for (name, type) in [("Const", PConst), ("Sum", PSum), ("Work", PWork), ("Fail", PFail), ("Main", PMain)]
    VT.register_module!(VT.ModuleDescriptor(PKG, name, type,
        [VT.InputPort("in", Int; optional=true)], [VT.OutputPort("value", Int)],
        Tuple{String, Type}[]))
end

function node!(pipeline, name, sources...; params...)
    mod = add_module!(pipeline, PKG, name)
    for (k, v) in params
        set_parameter!(mod, String(k), v)
    end
    for s in sources
        add_connection!(pipeline, s, "value", mod, "in")
    end
    return mod
end

events(id) = filter(e -> e[1] == id, TRACE)
start_time(id) = first(e[3] for e in TRACE if e[1] == id && e[2] == :start)
end_time(id) = first(e[3] for e in TRACE if e[1] == id && e[2] == :end)

# Largest number of modules running at the same time, from the trace
function max_concurrency()
    level, best = 0, 0
    for (_, what, _, _) in sort(TRACE, by=e -> (e[3], e[2] == :start))
        level += what == :start ? 1 : -1
        best = max(best, level)
    end
    return best
end

# Random DAG of sums; each module adds its id so results depend on the structure
function random_pipeline(rng, n)
    p = Pipeline()
    mods = [node!(p, "Const"; value=rand(rng, 1:10))]
    for i in 2:n
        k = rand(rng, 0:min(3, length(mods)))
        sources = unique(rand(rng, mods, k))
        push!(mods, node!(p, rand(rng) < 0.3 ? "Const" : "Sum", (isempty(sources) ? () : sources)...;
                          value=i, add=i))
    end
    return p
end

const MULTI = Threads.nthreads() > 1

@testset "Parallel engine (threads: $(Threads.nthreads()))" begin
    @testset "Same results as the one-shot engine" begin
        rng = MersenneTwister(42)
        for trial in 1:20
            p = random_pipeline(rng, 40)
            expected = run!(OneShotEngine(), p; enable_logging=false).outputs
            for max_tasks in (1, 2, 8)
                got = run!(ParallelEngine(; max_tasks=max_tasks), p; enable_logging=false).outputs
                @test got == expected
            end
        end
    end

    @testset "Producers finish before consumers start" begin
        empty!(TRACE)
        p = Pipeline()
        roots = [node!(p, "Work"; ms=20) for _ in 1:4]
        mids = [node!(p, "Work", roots[i], roots[mod1(i + 1, 4)]; ms=20) for i in 1:4]
        last_mod = node!(p, "Work", mids...; ms=10)
        run = run!(ParallelEngine(), p)

        for c in p.connections
            @test end_time(c.source_module_id) <= start_time(c.dest_module_id)
        end
        @test run.outputs[last_mod.id]["value"] == 4 * 3 + 1
        @test VT.is_successful(run.workflow_exec)
        @test length(run.workflow_exec.module_execs) == 9
    end

    @testset "Independent modules overlap" begin
        empty!(TRACE)
        p = Pipeline()
        works = [node!(p, "Work"; ms=100) for _ in 1:4]
        node!(p, "Sum", works...)
        t = @elapsed run!(ParallelEngine(), p; enable_logging=false)

        if MULTI
            @test max_concurrency() >= 2
            @test length(unique(e[4] for e in TRACE if e[1] in [w.id for w in works])) >= 2
            @test t < 0.8 * 0.4  # four 100 ms modules
        else
            @test_skip max_concurrency() >= 2
        end

        empty!(TRACE)
        run!(ParallelEngine(; max_tasks=1), p; enable_logging=false)
        @test max_concurrency() == 1
    end

    @testset "Main-thread modules run on thread 1" begin
        empty!(TRACE)
        p = Pipeline()
        works = [node!(p, "Work"; ms=30) for _ in 1:3]
        mains = [node!(p, "Main", w) for w in works]
        run = run!(ParallelEngine(), p; enable_logging=false)
        @test all(run.outputs[m.id]["value"] == 1 for m in mains)

        # Called from another task, main-thread modules are refused
        if MULTI
            err = fetch(Threads.@spawn try
                run!(ParallelEngine(), p; enable_logging=false); nothing
            catch e
                e
            end)
            if Threads.threadid() == 1 && err === nothing
                @test_skip "spawned task landed on thread 1"
            else
                @test err isa ErrorException && occursin("main thread", err.msg)
            end
        end
    end

    @testset "A failure stops new work and joins running modules" begin
        empty!(TRACE)
        p = Pipeline()
        bad = node!(p, "Fail"; ms=10)
        after_bad = node!(p, "Sum", bad)
        slow = node!(p, "Work"; ms=200)   # independent, already running when `bad` fails
        after_slow = node!(p, "Work", slow; ms=10)

        engine = ParallelEngine(; max_tasks=2)
        @test_throws ErrorException run!(engine, p)

        @test isempty(events(after_bad.id))             # downstream of the failure never ran
        @test !isempty(events(slow.id))
        @test any(e -> e[2] == :end, events(slow.id))   # running module finished before run! returned
        # Nothing new starts after the failure: `after_slow` may only have run if
        # `slow` finished before `bad` failed (both tasks can share a thread)
        if !isempty(events(after_slow.id))
            @test end_time(slow.id) < end_time(bad.id)
        end
    end

    @testset "Several failures are all reported" begin
        p = Pipeline()
        fails = [node!(p, "Fail"; ms=50) for _ in 1:2]
        err = try
            run!(ParallelEngine(; max_tasks=2), p; enable_logging=false); nothing
        catch e
            e
        end
        if MULTI
            @test err isa CompositeException
            @test length(err.exceptions) == 2
        else
            @test err isa Union{ErrorException, CompositeException}
        end
    end

    @testset "Observers see every event" begin
        struct Counter <: ExecutionObserver
            counts::Dict{Symbol, Int}
        end
        bump!(c, k) = (c.counts[k] = get(c.counts, k, 0) + 1)
        VT.on_module_start(c::Counter, run, mod) = bump!(c, :start)
        VT.on_module_done(c::Counter, run, mod, outputs) = bump!(c, :done)
        VT.on_module_cached(c::Counter, run, mod, outputs) = bump!(c, :cached)

        p = random_pipeline(MersenneTwister(7), 60)
        counter = Counter(Dict{Symbol, Int}())
        engine = ParallelEngine(CachedEngine())
        run!(engine, p; observers=[counter])
        n = length(p.modules)
        @test get(counter.counts, :start, 0) == get(counter.counts, :done, 0)
        @test counter.counts[:done] + get(counter.counts, :cached, 0) == n

        counter2 = Counter(Dict{Symbol, Int}())
        run!(engine, p; observers=[counter2])
        @test counter2.counts == Dict(:cached => n)
    end

    @testset "Parallel and cached" begin
        p = Pipeline()
        a = node!(p, "Work"; ms=20)
        b = node!(p, "Work"; ms=20)
        s = node!(p, "Sum", a, b)
        engine = ParallelEngine(CachedEngine())

        run!(engine, p)
        run2 = run!(engine, p)
        @test run2.reused == Set(keys(p.modules))

        set_parameter!(a, "ms", 21)
        run3 = run!(engine, p)
        @test run3.reused == Set([b.id])
        @test run3.outputs[s.id]["value"] == 2

        clear_cache!(engine)
        @test isempty(engine.base.entries)
    end

    @testset "gcd.vt and a notebook workflow" begin
        gcd = joinpath(@__DIR__, "..", "..", "..", "examples", "gcd.vt")
        vistrail = with_logger(NullLogger()) do
            redirect_stdout(devnull) do
                load_vistrail_internal(gcd; version=122)
            end
        end
        pipeline = vistrail.pipelines[122]
        quiet(f) = with_logger(NullLogger()) do; redirect_stdout(f, devnull); end
        expected = quiet(() -> run!(OneShotEngine(), pipeline).outputs)
        got = quiet(() -> run!(ParallelEngine(CachedEngine()), pipeline).outputs)
        @test got == expected

        nb_dir = joinpath(@__DIR__, "..", "notebooks")
        quiet(() -> register_notebook_package!(load_package_from_notebook(joinpath(nb_dir, "math_package.ipynb"))))
        workflow = parse_workflow_notebook(joinpath(nb_dir, "math_workflow.ipynb"))
        nb_pipeline, id_to_module = build_pipeline_from_workflow(workflow)
        _, outputs = quiet(() -> execute_notebook_pipeline(nb_pipeline, workflow;
                                                           id_to_module=id_to_module,
                                                           engine=ParallelEngine()))
        @test outputs["final_result"] == 10.0
    end
end
