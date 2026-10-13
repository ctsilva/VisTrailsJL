"""
Tests for parallel progressive execution (Phase 4 of docs/PROGRESSIVE_EXECUTION_PLAN.md)

Run with several threads: julia --project=. --threads=4 test/progressive/test_parallel_progressive.jl
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Test
using Random
using Tables

const VT = VisTrailsJL
const P = "org.vistrails.progressive"
const TP = "org.vistrails.test.parallel_progressive"
const MULTI = Threads.nthreads() > 1

function node!(p, name, sources...; package=P, params...)
    m = add_module!(p, package, name)
    foreach(((k, v),) -> set_parameter!(m, String(k), v), params)
    foreach(s -> add_connection!(p, s, "result", m, "table"), sources)
    return m
end

result_of(run, m) = (c = run.outputs[m.id]["result"]; c isa ProgressiveValue ? current_value(c) :
                     c isa ProgressiveDict ? snapshot(c) : Tables.columntable(c))

# Step intervals per module, from on_module_step (start = end - duration)
struct Intervals <: ExecutionObserver
    spans::Dict{Int, Vector{Tuple{Float64, Float64}}}
    threads::Dict{Int, Set{Int}}
end
Intervals() = Intervals(Dict{Int, Vector{Tuple{Float64, Float64}}}(), Dict{Int, Set{Int}}())
function VT.on_module_step(o::Intervals, run, mod, result, seconds)
    t = time()
    push!(get!(Vector{Tuple{Float64, Float64}}, o.spans, mod.id), (t - seconds, t))
end
overlaps(a, b) = any(x[1] < y[2] && y[1] < x[2] for x in a for y in b)

# Test folds: one records the threads its blocks run on (with merge), one
# checks that no two steps of the same module run at once (without merge)
const BLOCK_THREADS = Set{Int}()
const BLOCK_LOCK = ReentrantLock()
const ACTIVE = Threads.Atomic{Int}(0)
const MAX_ACTIVE = Threads.Atomic{Int}(0)

function spin(seconds)
    stop = time() + seconds
    while time() < stop end
end

VT.define_fold_module!(TP, "ThreadRecorder";
    init=(ctx, cols) -> 0,
    update=function (n, chunk, ctx)
        lock(() -> push!(BLOCK_THREADS, Threads.threadid()), BLOCK_LOCK)
        spin(0.0005)
        n + length(first(chunk))
    end,
    merge=+,
    result=(n, ctx) -> n, output=:value, output_type=Int)

VT.define_fold_module!(TP, "Exclusive";
    init=(ctx, cols) -> 0,
    update=function (n, chunk, ctx)
        a = Threads.atomic_add!(ACTIVE, 1) + 1
        Threads.atomic_max!(MAX_ACTIVE, a)
        spin(0.001)
        Threads.atomic_sub!(ACTIVE, 1)
        n + length(first(chunk))
    end,
    result=(n, ctx) -> n, output=:value, output_type=Int)

# A one-shot module that must run on the main thread
struct MainOnly end
VT.thread_affinity(::Type{MainOnly}) = :main
function VT.compute(mod::VT.ModuleInstance, ::Type{MainOnly})
    mod.outputs["thread"] = Threads.threadid()
    return mod.outputs
end
VT.register_module!(VT.ModuleDescriptor(TP, "MainOnly", MainOnly,
    [VT.InputPort("value", Any)], [VT.OutputPort("thread", Int)], Tuple{String, Type}[]))

function wide_pipeline(rows)
    p = Pipeline()
    src = node!(p, "RandomTable"; rows=rows, seed=9)
    m = (src=src, min=node!(p, "Min", src), var=node!(p, "Var", src), count=node!(p, "Count", src),
         hist=node!(p, "Histogram2D", src; x_column="x", y_column="y", xbins=32, ybins=32,
                    xmin=0.0, xmax=1.0, ymin=0.0, ymax=1.0),
         filter=node!(p, "Filter", src; column="x", op=">", value=0.9))
    return p, merge(m, (fcount=node!(p, "Count", m.filter),))
end

@testset "Parallel progressive execution (threads: $(Threads.nthreads()))" begin
    @testset "Same results with any number of workers" begin
        p, m = wide_pipeline(60_000)
        exact = (:min, :count, :hist, :filter, :fcount)
        reference = run!(ProgressiveEngine(workers=1, step_size=id -> 5_000), p)
        for workers in (2, 4, 8)
            run = run!(ProgressiveEngine(workers=workers, step_size=id -> 5_000), p)
            for k in exact
                @test result_of(run, m[k]) == result_of(reference, m[k])
            end
            @test all(isapprox(result_of(run, m.var)[c], result_of(reference, m.var)[c]; rtol=1e-12) for c in (:x, :y))
            @test all(module_status(run, mod.id) == :done for mod in m)
        end
    end

    @testset "Prefix consistency while modules overlap" begin
        rng_lock = ReentrantLock()
        rng = MersenneTwister(4)
        failures = String[]
        checked = Ref(0)
        struct Prefix <: ExecutionObserver
            m::NamedTuple
            failures::Vector{String}
            checked::Base.RefValue{Int}
        end
        function VT.on_module_step(o::Prefix, run, mod, result, seconds)
            mod.id in (o.m.min.id, o.m.count.id, o.m.filter.id) || return
            state = run.engine_state.modules[mod.id].state
            consumed = consumed_rows(state)
            x = state.table[consumed, :x]
            r = result_of(run, mod)
            ok = mod.id == o.m.min.id ? (isempty(x) || r[:x] == minimum(x)) :
                 mod.id == o.m.count.id ? r == length(consumed) :
                 r.x == filter(>(0.9), x)
            o.checked[] += 1
            ok || push!(o.failures, "$(mod.descriptor.name) after $(length(consumed)) rows")
        end
        p, m = wide_pipeline(80_000)
        run!(ProgressiveEngine(workers=4, step_size=id -> lock(() -> rand(rng, 100:4_000), rng_lock)), p;
             observers=[Prefix(m, failures, checked)])
        @test isempty(failures)
        @test checked[] > 30
    end

    @testset "A producer and its consumers overlap" begin
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=3_000_000, seed=1)
        consumers = [node!(p, "Var", src), node!(p, "Histogram2D", src; x_column="x", y_column="y",
                                                xbins=128, ybins=128, xmin=0.0, xmax=1.0, ymin=0.0, ymax=1.0)]
        obs = Intervals()
        run = run!(ProgressiveEngine(workers=4, quantum=0.01), p; observers=[obs])
        @test all(module_status(run, c.id) == :done for c in consumers)
        if MULTI
            @test any(overlaps(obs.spans[src.id], obs.spans[c.id]) for c in consumers)
            @test overlaps(obs.spans[consumers[1].id], obs.spans[consumers[2].id])
        else
            @test_skip "needs several threads"
        end
    end

    @testset "Steps of one module never overlap" begin
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=200_000, seed=2)
        ex = node!(p, "Exclusive", src; package=TP)
        others = [node!(p, "Count", src) for _ in 1:3]
        ACTIVE[] = 0; MAX_ACTIVE[] = 0
        run = run!(ProgressiveEngine(workers=8, step_size=id -> 3_000), p)
        @test MAX_ACTIVE[] == 1
        @test result_of(run, ex) == 200_000
    end

    @testset "Data parallelism inside a step" begin
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=400_000, seed=3)
        rec = node!(p, "ThreadRecorder", src; package=TP)
        empty!(BLOCK_THREADS)
        run = run!(ProgressiveEngine(workers=2, step_size=id -> 200_000), p)
        @test result_of(run, rec) == 400_000
        if MULTI
            @test length(BLOCK_THREADS) > 1
        end
        blocks = VT.fold_block_list([(v=collect(1:40_000),)])
        @test [length(b.v) for b in blocks] == [16_384, 16_384, 7_232]
    end

    @testset "Results do not depend on the number of threads" begin
        script = """
        include(joinpath("$(escape_string(joinpath(@__DIR__, "..", "..")))", "src", "VisTrailsJL.jl")); using .VisTrailsJL
        const P = "org.vistrails.progressive"
        p = Pipeline()
        src = add_module!(p, P, "RandomTable"); set_parameter!(src, "rows", 300_000); set_parameter!(src, "seed", 5)
        ms = [add_module!(p, P, n) for n in ("Mean", "Var")]
        foreach(m -> add_connection!(p, src, "result", m, "table"), ms)
        run = run!(ProgressiveEngine(workers=1, step_size=id -> 70_000), p)
        r = [sort(collect(snapshot(run.outputs[m.id]["result"])), by=first) for m in ms]
        print("RESULT=", repr(r))
        """
        outputs = map((1, 4)) do threads
            out = read(pipeline(`$(Base.julia_cmd()) --project=$(joinpath(@__DIR__, "..", "..")) --threads=$threads -e $script`;
                                stderr=devnull), String)
            match(r"RESULT=(.*)$"s, out).captures[1]
        end
        @test outputs[1] == outputs[2]   # bit-identical floating-point results
    end

    @testset "Main-thread modules in a parallel run" begin
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=50_000)
        mn = node!(p, "Min", src)
        main_only = add_module!(p, TP, "MainOnly")
        add_connection!(p, mn, "result", main_only, "value")
        run = run!(ProgressiveEngine(workers=4, step_size=id -> 5_000), p)
        @test current_value(run.outputs[main_only.id]["thread"]) == 1
        @test module_status(run, main_only.id) == :done
    end

    @testset "Failures and stopping" begin
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=100_000)
        bad = node!(p, "Histogram1D", src; column="nope", bins=4, min=0.0, max=1.0)   # no such column
        after = node!(p, "Sink", bad)
        ok = node!(p, "Count", src)
        grabbed = Ref{Any}(nothing)
        struct Grab <: ExecutionObserver
            ref::Base.RefValue{Any}
        end
        VT.on_run_start(g::Grab, run) = (g.ref[] = run)
        @test_throws Exception run!(ProgressiveEngine(workers=4, step_size=id -> 10_000), p; observers=[Grab(grabbed)])
        run = grabbed[]
        @test module_status(run, bad.id) == :failed
        @test module_status(run, after.id) == :cancelled
        @test module_status(run, ok.id) == :done
        @test result_of(run, ok) == 100_000

        p2 = Pipeline()
        big = node!(p2, "RandomTable"; rows=100_000_000)
        cnt = node!(p2, "Count", big)
        pr = start!(ProgressiveEngine(workers=4, step_size=id -> 50_000), p2)
        while !(has_value(pr.run.outputs[cnt.id]["result"]) && current_value(pr.run.outputs[cnt.id]["result"]) > 0)
            sleep(0.01)
        end
        stop!(pr)
        run2 = wait(pr)
        @test module_status(run2, big.id) != :done
        @test 0 < current_value(run2.outputs[cnt.id]["result"]) < 100_000_000
    end
end
