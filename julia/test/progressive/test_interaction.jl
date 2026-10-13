"""
Tests for live inputs and interactive priority (Phase 5a of docs/PROGRESSIVE_EXECUTION_PLAN.md)

Run with several threads: julia --project=. --threads=4 test/progressive/test_interaction.jl
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Test
using Tables

const VT = VisTrailsJL
const P = "org.vistrails.progressive"

function node!(p, name, sources...; port="table", params...)
    m = add_module!(p, P, name)
    foreach(((k, v),) -> set_parameter!(m, String(k), v), params)
    foreach(s -> add_connection!(p, s, "result", m, port), sources)
    return m
end

result_of(run, m) = (c = run.outputs[m.id]["result"]; c isa ProgressiveValue ? current_value(c) :
                     c isa ProgressiveDict ? snapshot(c) : Tables.columntable(c))

function wait_until(f; timeout=30.0)
    t0 = time()
    while !f()
        time() - t0 > timeout && error("timed out")
        sleep(0.005)
    end
end

# source → Filter(x < threshold) → Count, with the threshold from a Variable
function live_filter(rows; threshold=0.5, seed=1)
    p = Pipeline()
    src = node!(p, "RandomTable"; rows=rows, seed=seed)
    var = node!(p, "Variable"; value=threshold)
    filt = node!(p, "Filter", src; column="x", op="<", value=0.99)   # parameter overridden by the input
    add_connection!(p, var, "result", filt, "value")
    count = node!(p, "Count", filt)
    return p, (; src, var, filt, count)
end

xs(run, src) = Tables.columntable(run.outputs[src.id]["result"]).x

struct Log <: ExecutionObserver
    events::Vector{Any}
end
VT.on_module_step(o::Log, run, mod, result, seconds) = push!(o.events, (:step, mod.id, time() - seconds))  # start time
VT.on_interaction(o::Log, run, id, value) = push!(o.events, (:interaction, id, time()))
VT.on_interaction_done(o::Log, run, seconds) = push!(o.events, (:caught_up, seconds, time()))

@testset "Live inputs and interactive priority (threads: $(Threads.nthreads()))" begin
    @testset "A Variable drives a parameter" begin
        p, m = live_filter(50_000; threshold=0.3)
        for engine in (ProgressiveEngine(workers=1), ProgressiveEngine(), OneShotEngine(), CachedEngine())
            run = run!(engine, p)     # run!: inputs closed, the Variable acts as a constant
            x = xs(run, m.src)
            @test result_of(run, m.count) == count(<(0.3), x)
            @test result_of(run, m.filt).x == filter(<(0.3), x)
        end
        @test is_input_module(VT.VariableModule)
        @test any(port.name == "value" && port.optional for port in get_module_descriptor(P, "Filter").input_ports)
    end

    @testset "A driven parameter waits for its first value" begin
        # Histogram1D's bounds come from an input that has no value at first
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=20_000, seed=3)
        lo = node!(p, "Variable")                       # no initial value
        h = node!(p, "Histogram1D", src; column="x", bins=10, max=1.0)
        add_connection!(p, lo, "result", h, "min")
        pr = start!(ProgressiveEngine(step_size=id -> 1_000), p)
        sleep(0.2)
        @test !has_value(pr.run.outputs[h.id]["result"])   # waited, did not fail
        set_variable!(pr, lo, 0.0)
        close_inputs!(pr)
        run = wait(pr)
        @test module_status(run, h.id) == :done
        @test sum(result_of(run, h)) == 20_000
    end

    @testset "Changing a value during a run" begin
        for workers in (1, 4)
            p, m = live_filter(2_000_000; threshold=0.5)
            pr = start!(ProgressiveEngine(workers=workers, step_size=id -> 50_000), p)
            wait_until(() -> has_value(pr.run.outputs[m.count.id]["result"]) &&
                             current_value(pr.run.outputs[m.count.id]["result"]) > 0)
            set_variable!(pr, m.var, 0.1)
            close_inputs!(pr)
            run = wait(pr)
            x = xs(run, m.src)
            @test length(x) == 2_000_000
            @test result_of(run, m.count) == count(<(0.1), x)
            @test result_of(run, m.filt).x == filter(<(0.1), x)
            @test all(module_status(run, mod.id) == :done for mod in m)
        end
    end

    @testset "A fold restarts when a parameter changes" begin
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=500_000, seed=2)
        bins = node!(p, "Variable"; value=8)
        hist = node!(p, "Histogram1D", src; column="x", min=0.0, max=1.0)
        add_connection!(p, bins, "result", hist, "bins")
        pr = start!(ProgressiveEngine(workers=1, step_size=id -> 25_000), p)
        wait_until(() -> has_value(pr.run.outputs[hist.id]["result"]) &&
                         sum(current_value(pr.run.outputs[hist.id]["result"])) > 0)
        @test length(current_value(pr.run.outputs[hist.id]["result"])) == 8
        set_variable!(pr, bins, 20)
        close_inputs!(pr)
        run = wait(pr)
        h = result_of(run, hist)
        @test length(h) == 20 && sum(h) == 500_000
        x = xs(run, src)
        @test h == [count(v -> VT.histogram_bin(v, 0.0, 1.0, 20) == b, x) for b in 1:20]
    end

    @testset "Modules downstream of an input change go first" begin
        for workers in (1, 4)
            p = Pipeline()
            # A long-running branch, and a small branch with a live threshold
            big = node!(p, "RandomTable"; rows=500_000_000, seed=3)
            heavy = node!(p, "Var", big)
            small = node!(p, "RandomTable"; rows=300_000, seed=4)
            var = node!(p, "Variable"; value=0.5)
            filt = node!(p, "Filter", small; column="x", op="<", value=0.0)
            add_connection!(p, var, "result", filt, "value")
            cnt = node!(p, "Count", filt)

            log = Log(Any[])
            pr = start!(ProgressiveEngine(workers=workers, quantum=0.05), p; observers=[log])
            wait_until(() -> module_status(pr.run, small.id) == :done && module_status(pr.run, filt.id) == :blocked &&
                             module_status(pr.run, cnt.id) == :blocked)
            x = xs(pr.run, small)
            t0 = time()
            set_variable!(pr, var, 0.2)
            wait_until(() -> any(e -> e[1] == :caught_up, log.events))
            latency = time() - t0
            stop!(pr); wait(pr)

            @test result_of(pr.run, cnt) == count(<(0.2), x)
            @test latency < 1.0
            i0 = findfirst(e -> e[1] == :interaction, log.events)
            i1 = findfirst(e -> e[1] == :caught_up, log.events)
            during = log.events[i0:i1]
            @test any(e -> e[1] == :step && e[2] == filt.id, during)
            if workers == 1
                # Serially, only the selected modules start steps until they caught up
                # (a step already running when the input changed finishes first)
                t_input = log.events[i0][3]
                @test !any(e -> e[1] == :step && e[2] in (big.id, heavy.id) && e[3] > t_input, during)
            end
            @test log.events[i1][2] < 1.0      # reported latency
        end
    end

    @testset "An idle run sleeps until input" begin
        for workers in (1, 4)
            p, m = live_filter(10_000; threshold=0.5)
            pr = start!(ProgressiveEngine(workers=workers), p)
            wait_until(() -> module_status(pr.run, m.count.id) == :blocked &&
                             module_status(pr.run, m.src.id) == :done &&
                             !isready(pr.run.engine_state.events))
            sleep(0.05)
            sweeps = pr.run.engine_state.sweeps
            sleep(0.3)
            @test pr.run.engine_state.sweeps - sweeps <= 1     # no busy loop
            @test !istaskdone(pr)                               # inputs open: still running

            set_variable!(pr, m.var, 0.25)
            wait_until(() -> current_value(pr.run.outputs[m.count.id]["result"]) == count(<(0.25), xs(pr.run, m.src)))
            @test pr.run.engine_state.sweeps > sweeps

            t0 = time()
            stop!(pr)                                           # wakes the idle scheduler
            wait(pr)
            @test time() - t0 < 0.5
        end
    end

    @testset "Errors" begin
        p, m = live_filter(1_000)
        pr = start!(ProgressiveEngine(), p)
        @test_throws ErrorException set_variable!(pr, m.filt, 1)       # not an input module
        close_inputs!(pr)
        @test_throws ErrorException set_variable!(pr, m.var, 0.2)      # inputs closed
        run = wait(pr)
        @test module_status(run, m.var.id) == :done
    end
end
