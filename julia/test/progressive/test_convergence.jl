"""
Tests for convergence-driven loading: sources step only while a module
downstream wants data (`converged`), and resume when one no longer has.

Run with several threads: julia --project=. --threads=4 test/progressive/test_convergence.jl
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Test
using Tables

const VT = VisTrailsJL
const P = "org.vistrails.progressive"
const TP = "org.vistrails.test.convergence"

# Enough: counts rows, converged once it saw `need` of them (`need` may come
# from a Variable); `opinion=false` makes it express no opinion
struct EnoughModule end
VT.execution_style(::Type{EnoughModule}) = Progressive()

mutable struct EnoughState
    sub::TableSubscription
    rows::Int
    need::Int
    opinion::Bool
    out::ProgressiveValue{Int}
end

function VT.init_state(::Type{EnoughModule}, ctx::StepContext)
    out = VT.set_output!(ctx, "result", ProgressiveValue{Int}())
    set!(out, 0)
    return EnoughState(input_subscription(ctx, "table"), 0, Int(VT.param(ctx, "need", 0)),
                       Bool(VT.param(ctx, "opinion", true)), out)
end

function VT.step!(s::EnoughState, ctx::StepContext, budget::Int)
    s.need = Int(VT.param(ctx, "need", s.need))
    has_input(ctx, "need") && has_changes(input_subscription(ctx, "need")) && take_value!(input_subscription(ctx, "need"))
    ids = next_created!(s.sub, budget)
    s.rows += length(ids)
    set!(s.out, s.rows)
    return StepResult(has_changes(s.sub) ? :ready : :blocked, length(ids))
end

VT.converged(s::EnoughState) = s.opinion ? s.rows >= s.need : nothing

VT.register_module!(VT.ModuleDescriptor(TP, "Enough", EnoughModule,
    [VT.InputPort("table", ProgressiveTable), VT.InputPort("need", Any; optional=true)],
    [VT.OutputPort("result", ProgressiveValue)],
    Tuple{String, Type}[("need", Int), ("opinion", Bool)]))

function node!(p, package, name, sources...; port="table", params...)
    m = add_module!(p, package, name)
    foreach(((k, v),) -> set_parameter!(m, String(k), v), params)
    foreach(s -> add_connection!(p, s, "result", m, port), sources)
    return m
end

loaded(run, src) = length(run.outputs[src.id]["result"])
value(run, m) = current_value(run.outputs[m.id]["result"])

function wait_until(f; timeout=30.0)
    t0 = time()
    while !f()
        time() - t0 > timeout && error("timed out")
        sleep(0.005)
    end
end

const ROWS = 1_000_000
const STEP = 1_000

@testset "Convergence (threads: $(Threads.nthreads()))" begin
    for workers in (1, 4)
        engine() = ProgressiveEngine(workers=workers, step_size=id -> STEP)

        @testset "Loading stops once the consumer converged ($workers workers)" begin
            p = Pipeline()
            src = node!(p, P, "RandomTable"; rows=ROWS)
            enough = node!(p, TP, "Enough", src; need=10_000)
            run = run!(engine(), p)
            @test 10_000 <= loaded(run, src) <= 10_000 + 4 * STEP   # a few steps may be in flight
            @test value(run, enough) == loaded(run, src)            # consumers read what was loaded
            @test module_status(run, src.id) == :done                # completed as converged
            @test module_status(run, enough.id) == :done
            @test module_converged(run, enough.id) === true
            @test module_converged(run, src.id) === nothing
            src_exec = only(e for e in run.workflow_exec.module_execs if e.module_id == src.id)
            @test src_exec.annotations["converged"] == "true"
        end

        @testset "The most demanding consumer decides ($workers workers)" begin
            p = Pipeline()
            src = node!(p, P, "RandomTable"; rows=ROWS)
            node!(p, TP, "Enough", src; need=10_000)
            node!(p, TP, "Enough", src; need=50_000)
            run = run!(engine(), p)
            @test 50_000 <= loaded(run, src) <= 50_000 + 4 * STEP
        end

        @testset "Consumers without an opinion want everything ($workers workers)" begin
            p = Pipeline()
            src = node!(p, P, "RandomTable"; rows=200_000)
            node!(p, TP, "Enough", src; need=10_000)
            count = node!(p, P, "Count", src)                    # a leaf with no opinion
            run = run!(engine(), p)
            @test loaded(run, src) == 200_000
            @test value(run, count) == 200_000

            p = Pipeline()
            src = node!(p, P, "RandomTable"; rows=200_000)
            node!(p, TP, "Enough", src; need=10_000, opinion=false)
            @test loaded(run!(engine(), p), src) == 200_000
        end

        @testset "Through a module without an opinion ($workers workers)" begin
            # source → Filter (no opinion) → Enough: the filter steps for its consumer
            p = Pipeline()
            src = node!(p, P, "RandomTable"; rows=ROWS)
            filt = node!(p, P, "Filter", src; column="x", op="<", value=0.5)
            enough = node!(p, TP, "Enough", filt; need=10_000)
            run = run!(engine(), p)
            # In parallel, the source and the filter step while Enough catches up:
            # the overshoot is the pipeline in flight, not the whole table
            @test 10_000 <= value(run, enough) <= 10_000 + (workers == 1 ? 1 : 10) * STEP
            @test loaded(run, src) < 60_000
            @test all(module_status(run, m.id) == :done for m in (src, filt, enough))
        end

        @testset "A live input resumes loading ($workers workers)" begin
            p = Pipeline()
            src = node!(p, P, "RandomTable"; rows=ROWS)
            need = node!(p, P, "Variable"; value=10_000)
            enough = node!(p, TP, "Enough", src; need=0)
            add_connection!(p, need, "result", enough, "need")
            pr = start!(engine(), p)
            wait_until(() -> is_paused(pr.run, src.id))
            first = loaded(pr.run, src)
            @test 10_000 <= first <= 10_000 + 4 * STEP
            # Paused: no steps while idle
            steps = module_steps(pr.run, src.id).steps
            sleep(0.2)
            @test module_steps(pr.run, src.id).steps == steps
            @test loaded(pr.run, src) == first

            set_variable!(pr, need, 30_000)
            wait_until(() -> loaded(pr.run, src) >= 30_000 && is_paused(pr.run, src.id))
            @test loaded(pr.run, src) <= 30_000 + 4 * STEP
            close_inputs!(pr)
            run = wait(pr)
            @test module_status(run, src.id) == :done
            @test value(run, enough) == loaded(run, src)
        end
    end

    @testset "No converged modules: unchanged behavior" begin
        p = Pipeline()
        src = node!(p, P, "RandomTable"; rows=100_000)
        count = node!(p, P, "Count", src)
        run = run!(ProgressiveEngine(step_size=id -> STEP), p)
        @test loaded(run, src) == 100_000
        @test value(run, count) == 100_000
        @test !is_paused(run, src.id)
    end
end
