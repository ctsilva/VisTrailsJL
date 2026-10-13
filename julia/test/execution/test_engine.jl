"""
Tests for the execution engine (Phase 0 of docs/PROGRESSIVE_EXECUTION_PLAN.md)
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Test

const VT = VisTrailsJL
const PKG = "org.vistrails.test.engine"

# Test module types: a constant, a sum over every value connected to `in`,
# and a module that always fails. Each counts its computations.
struct TestConst end
struct TestSum end
struct TestFail end

const COMPUTE_COUNT = Dict{Int, Int}()
count_compute!(mod) = (COMPUTE_COUNT[mod.id] = get(COMPUTE_COUNT, mod.id, 0) + 1)

function VT.compute(mod::VT.ModuleInstance, ::Type{TestConst})
    count_compute!(mod)
    mod.outputs["value"] = mod.parameters["value"]
    return mod.outputs
end

function VT.compute(mod::VT.ModuleInstance, ::Type{TestSum})
    count_compute!(mod)
    mod.outputs["value"] = sum(get_input_list(mod, "in"); init=0)
    return mod.outputs
end

function VT.compute(mod::VT.ModuleInstance, ::Type{TestFail})
    count_compute!(mod)
    error("intentional failure")
end

for (name, type) in [("Const", TestConst), ("Sum", TestSum), ("Fail", TestFail)]
    VT.register_module!(VT.ModuleDescriptor(PKG, name, type,
        [VT.InputPort("in", Int; optional=true)], [VT.OutputPort("value", Int)],
        Tuple{String, Type}[]))
end

function constant!(pipeline, value)
    mod = add_module!(pipeline, PKG, "Const")
    set_parameter!(mod, "value", value)
    return mod
end

# Records every observer event as (event, module id or nothing)
struct RecordingObserver <: ExecutionObserver
    events::Vector{Tuple{Symbol, Union{Int, Nothing}}}
end
RecordingObserver() = RecordingObserver(Tuple{Symbol, Union{Int, Nothing}}[])

VT.on_run_start(o::RecordingObserver, run) = push!(o.events, (:run_start, nothing))
VT.on_module_start(o::RecordingObserver, run, mod) = push!(o.events, (:module_start, mod.id))
VT.on_module_done(o::RecordingObserver, run, mod, outputs) = push!(o.events, (:module_done, mod.id))
VT.on_module_error(o::RecordingObserver, run, mod, err) = push!(o.events, (:module_error, mod.id))
VT.on_run_done(o::RecordingObserver, run, err) =
    push!(o.events, (err === nothing ? :run_done : :run_failed, nothing))

@testset "Execution engine" begin
    @testset "Diamond: each module computed once" begin
        empty!(COMPUTE_COUNT)
        p = Pipeline()
        a = constant!(p, 2)
        left = add_module!(p, PKG, "Sum")
        right = add_module!(p, PKG, "Sum")
        join = add_module!(p, PKG, "Sum")
        add_connection!(p, a, "value", left, "in")
        add_connection!(p, a, "value", right, "in")
        add_connection!(p, left, "value", join, "in")
        add_connection!(p, right, "value", join, "in")

        run = run!(OneShotEngine(), p)

        @test run.outputs[join.id]["value"] == 4
        @test all(==(1), values(COMPUTE_COUNT))
        @test length(COMPUTE_COUNT) == 4
        @test run.order == [a.id, left.id, right.id, join.id]
    end

    @testset "Several connections into one port" begin
        p = Pipeline()
        consts = [constant!(p, v) for v in (1, 10, 100)]
        total = add_module!(p, PKG, "Sum")
        for c in consts
            add_connection!(p, c, "value", total, "in")
        end

        run = run!(OneShotEngine(), p)

        @test run.outputs[total.id]["value"] == 111
        @test get_input_list(run.instances[total.id], "in") == [1, 10, 100]
        # `inputs` keeps the last connected value, as before
        @test run.instances[total.id].inputs["in"] == 100
    end

    @testset "Execution does not mutate the pipeline" begin
        p = Pipeline()
        a = constant!(p, 5)
        s = add_module!(p, PKG, "Sum")
        add_connection!(p, a, "value", s, "in")

        run1 = run!(OneShotEngine(), p)
        run2 = run!(OneShotEngine(), p)

        @test isempty(a.outputs) && isempty(s.outputs)
        @test isempty(s.inputs) && isempty(s.input_lists)
        @test run1.outputs == run2.outputs
        @test run1.instances[s.id] !== run2.instances[s.id]
    end

    @testset "Observer events and logging" begin
        p = Pipeline()
        a = constant!(p, 1)
        s = add_module!(p, PKG, "Sum")
        add_connection!(p, a, "value", s, "in")

        obs = RecordingObserver()
        run = run!(OneShotEngine(), p; observers=[obs])

        @test obs.events == [(:run_start, nothing),
                             (:module_start, a.id), (:module_done, a.id),
                             (:module_start, s.id), (:module_done, s.id),
                             (:run_done, nothing)]
        @test run.workflow_exec !== nothing
        @test VT.is_successful(run.workflow_exec)
        @test length(run.workflow_exec.module_execs) == 2

        quiet = run!(OneShotEngine(), p; enable_logging=false)
        @test quiet.workflow_exec === nothing
    end

    @testset "Failure aborts the run" begin
        empty!(COMPUTE_COUNT)
        p = Pipeline()
        a = constant!(p, 1)
        bad = add_module!(p, PKG, "Fail")
        after = add_module!(p, PKG, "Sum")
        add_connection!(p, a, "value", bad, "in")
        add_connection!(p, bad, "value", after, "in")

        obs = RecordingObserver()
        @test_throws ErrorException run!(OneShotEngine(), p; observers=[obs])

        @test (:module_error, bad.id) in obs.events
        @test last(obs.events) == (:run_failed, nothing)
        @test !haskey(COMPUTE_COUNT, after.id)
    end

    @testset "execute_pipeline compatibility wrapper" begin
        p = Pipeline()
        a = constant!(p, 3)
        s = add_module!(p, PKG, "Sum")
        add_connection!(p, a, "value", s, "in")

        cache, workflow_exec = execute_pipeline(p; observers=ExecutionObserver[])
        @test cache[s.id]["value"] == 3
        @test VT.is_successful(workflow_exec)
    end

    @testset "Notebook modules run through the engine" begin
        nb_dir = joinpath(@__DIR__, "..", "notebooks")
        register_notebook_package!(load_package_from_notebook(joinpath(nb_dir, "math_package.ipynb")))
        workflow = parse_workflow_notebook(joinpath(nb_dir, "math_workflow.ipynb"))
        pipeline, _ = build_pipeline_from_workflow(workflow)

        # Notebook-defined modules used to run only in execute_notebook_pipeline
        cache, _ = execute_pipeline(pipeline; observers=ExecutionObserver[])
        @test 10.0 in [v for outputs in values(cache) for v in values(outputs)]
    end
end
