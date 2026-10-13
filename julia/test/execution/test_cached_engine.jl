"""
Tests for signatures and the cached engine (Phase 1 of docs/PROGRESSIVE_EXECUTION_PLAN.md)
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Test
using Logging

const VT = VisTrailsJL
const PKG = "org.vistrails.test.cache"

# A constant, a sum over every value connected to `in`, a non-cacheable
# "random" source, and a module that always fails. Each counts its computations.
struct CConst end
struct CSum end
struct CRandom end
struct CFail end

const COMPUTED = Int[]

function VT.compute(mod::VT.ModuleInstance, ::Type{CConst})
    push!(COMPUTED, mod.id)
    mod.outputs["value"] = mod.parameters["value"]
    return mod.outputs
end

function VT.compute(mod::VT.ModuleInstance, ::Type{CSum})
    push!(COMPUTED, mod.id)
    mod.outputs["value"] = sum(get_input_list(mod, "in"); init=0)
    return mod.outputs
end

function VT.compute(mod::VT.ModuleInstance, ::Type{CRandom})
    push!(COMPUTED, mod.id)
    mod.outputs["value"] = rand(1:1_000_000)
    return mod.outputs
end
VT.is_cacheable(::Type{CRandom}) = false

function VT.compute(mod::VT.ModuleInstance, ::Type{CFail})
    push!(COMPUTED, mod.id)
    error("intentional failure")
end

for (name, type) in [("Const", CConst), ("Sum", CSum), ("Random", CRandom), ("Fail", CFail)]
    VT.register_module!(VT.ModuleDescriptor(PKG, name, type,
        [VT.InputPort("in", Int; optional=true)], [VT.OutputPort("value", Int)],
        Tuple{String, Type}[]))
end

function constant!(pipeline, value)
    mod = add_module!(pipeline, PKG, "Const")
    set_parameter!(mod, "value", value)
    return mod
end

function sum!(pipeline, sources...)
    mod = add_module!(pipeline, PKG, "Sum")
    for s in sources
        add_connection!(pipeline, s, "value", mod, "in")
    end
    return mod
end

quiet_run(engine, pipeline) = run!(engine, pipeline; enable_logging=true)

# a(1) ─┐
#       ├─ s1 ── s2
# b(2) ─┘
#  c(3) ──────── s3
function chain_pipeline()
    p = Pipeline()
    a = constant!(p, 1); b = constant!(p, 2); c = constant!(p, 3)
    s1 = sum!(p, a, b); s2 = sum!(p, s1); s3 = sum!(p, c)
    return p, (; a, b, c, s1, s2, s3)
end

@testset "Cached engine" begin
    @testset "Signatures" begin
        p1, m1 = chain_pipeline()

        # Same computation built in another order: different ids, same signatures
        p2 = Pipeline()
        c = constant!(p2, 3); s3 = sum!(p2, c)
        b = constant!(p2, 2); a = constant!(p2, 1)
        s1 = sum!(p2, a, b); s2 = sum!(p2, s1)
        @test m1.s2.id != s2.id
        sig1 = subpipeline_signatures(p1)
        sig2 = subpipeline_signatures(p2)
        @test sig1[m1.s2.id] == sig2[s2.id]
        @test sig1[m1.s3.id] == sig2[s3.id]

        # A parameter change affects the module and its downstream only
        set_parameter!(m1.a, "value", 10)
        sig3 = subpipeline_signatures(p1)
        @test sig3[m1.a.id] != sig1[m1.a.id]
        @test sig3[m1.s1.id] != sig1[m1.s1.id]
        @test sig3[m1.s2.id] != sig1[m1.s2.id]
        @test sig3[m1.b.id] == sig1[m1.b.id]
        @test sig3[m1.s3.id] == sig1[m1.s3.id]

        # Values are typed: 5 and "5" differ
        q1 = Pipeline(); x1 = constant!(q1, 5)
        q2 = Pipeline(); x2 = constant!(q2, "5")
        @test module_signature(x1) != module_signature(x2)

        # Connection order determines list inputs, so it is part of the signature
        r1 = Pipeline(); u = constant!(r1, 1); v = constant!(r1, 2); t1 = sum!(r1, u, v)
        r2 = Pipeline(); u = constant!(r2, 1); v = constant!(r2, 2); t2 = sum!(r2, v, u)
        @test subpipeline_signatures(r1)[t1.id] != subpipeline_signatures(r2)[t2.id]
    end

    @testset "Re-running reuses everything" begin
        p, m = chain_pipeline()
        engine = CachedEngine()

        empty!(COMPUTED)
        run1 = quiet_run(engine, p)
        @test sort(COMPUTED) == sort(collect(keys(p.modules)))
        @test isempty(run1.reused)

        empty!(COMPUTED)
        run2 = quiet_run(engine, p)
        @test isempty(COMPUTED)
        @test run2.reused == Set(keys(p.modules))
        @test run2.outputs[m.s2.id]["value"] == 3

        # Reuse is recorded in the provenance log, with the signature
        execs = run2.workflow_exec.module_execs
        @test all(e -> e.cached, execs)
        @test all(e -> e.annotations["signature"] == run2.signatures[e.module_id], execs)
    end

    @testset "An edit recomputes the module and its downstream only" begin
        p, m = chain_pipeline()
        engine = CachedEngine()
        quiet_run(engine, p)

        set_parameter!(m.b, "value", 20)
        empty!(COMPUTED)
        run = quiet_run(engine, p)
        @test sort(COMPUTED) == sort([m.b.id, m.s1.id, m.s2.id])
        @test run.reused == Set([m.a.id, m.c.id, m.s3.id])
        @test run.outputs[m.s2.id]["value"] == 21

        # Undoing the edit finds the earlier results again
        set_parameter!(m.b, "value", 2)
        empty!(COMPUTED)
        run = quiet_run(engine, p)
        @test isempty(COMPUTED)
        @test run.outputs[m.s2.id]["value"] == 3
    end

    @testset "Switching versions reuses shared subpipelines" begin
        # Version A: a, b → s1 → s2. Version B adds a branch: s1 + d → s4
        vA, mA = chain_pipeline()
        vB, mB = chain_pipeline()
        d = constant!(vB, 100)
        s4 = sum!(vB, mB.s1, d)

        engine = CachedEngine()
        quiet_run(engine, vA)

        empty!(COMPUTED)
        runB = quiet_run(engine, vB)
        @test sort(COMPUTED) == sort([d.id, s4.id])
        @test runB.outputs[s4.id]["value"] == 103

        empty!(COMPUTED)
        quiet_run(engine, vA)
        @test isempty(COMPUTED)
    end

    @testset "Non-cacheable modules and their downstream always run" begin
        p, m = chain_pipeline()
        r = add_module!(p, PKG, "Random")
        after = sum!(p, r)
        engine = CachedEngine()
        run1 = quiet_run(engine, p)

        empty!(COMPUTED)
        run2 = quiet_run(engine, p)
        @test sort(COMPUTED) == sort([r.id, after.id])
        @test run2.outputs[after.id]["value"] == run2.outputs[r.id]["value"]
        @test !run2.reusable[after.id]
    end

    @testset "Failures are not cached; completed modules are" begin
        p = Pipeline()
        a = constant!(p, 1)
        bad = add_module!(p, PKG, "Fail")
        add_connection!(p, a, "value", bad, "in")
        engine = CachedEngine()

        @test_throws ErrorException quiet_run(engine, p)
        empty!(COMPUTED)
        @test_throws ErrorException quiet_run(engine, p)
        @test COMPUTED == [bad.id]

        clear_cache!(engine)
        @test isempty(engine.entries)
    end

    @testset "Re-registering a notebook package invalidates its modules" begin
        nb_dir = joinpath(@__DIR__, "..", "notebooks")
        load_math() = with_logger(NullLogger()) do
            redirect_stdout(devnull) do
                register_notebook_package!(load_package_from_notebook(joinpath(nb_dir, "math_package.ipynb")))
            end
        end

        load_math()
        workflow = parse_workflow_notebook(joinpath(nb_dir, "math_workflow.ipynb"))
        pipeline, id_to_module = build_pipeline_from_workflow(workflow)
        notebook_ids = Set(m.id for m in values(pipeline.modules) if VT.is_notebook_module(m.descriptor.package, m.descriptor.name))
        @test !isempty(notebook_ids)

        engine = CachedEngine()
        quiet_run(engine, pipeline)
        @test quiet_run(engine, pipeline).reused == Set(keys(pipeline.modules))

        load_math()
        run = quiet_run(engine, pipeline)
        @test isempty(intersect(run.reused, notebook_ids))
        @test !isempty(run.reused)  # constants are unaffected
    end

    @testset "gcd.vt through the API" begin
        gcd = joinpath(@__DIR__, "..", "..", "..", "examples", "gcd.vt")
        vistrail = with_logger(NullLogger()) do
            redirect_stdout(devnull) do
                load_vistrail_internal(gcd; version=122)
            end
        end
        vt = VT.VistrailWrapper(vistrail, gcd, nothing, nothing)
        select_version!(vt, 122)
        pipeline = vt.current_pipeline

        cached_ids(result) = Set(e.module_id for e in result.workflow_exec.module_execs if e.cached)
        quiet_execute() = redirect_stdout(devnull) do; execute(vt); end

        # Even the first run reuses: modules computing exactly the same thing as
        # an earlier module of the same pipeline (same subpipeline signature)
        first_result = quiet_execute()
        signatures = subpipeline_signatures(pipeline)
        computed_signatures = Set(signatures[e.module_id] for e in first_result.workflow_exec.module_execs if !e.cached)
        @test !isempty(cached_ids(first_result))
        @test all(signatures[id] in computed_signatures for id in cached_ids(first_result))

        second = quiet_execute()
        @test cached_ids(second) == Set(id for (id, ok) in VT.reusable_modules(pipeline, VT.topological_sort(pipeline)) if ok)
        @test second.cache == first_result.cache

        # Edit one Integer constant: it and its downstream are recomputed
        int_id = first(id for (id, m) in sort(collect(pipeline.modules), by=first)
                       if m.descriptor.name == "Integer")
        downstream = Set([int_id])
        for id in VT.topological_sort(pipeline)
            if any(c.source_module_id in downstream for c in VT.get_connections_to(pipeline, id))
                push!(downstream, id)
            end
        end
        set_parameter!(pipeline.modules[int_id], "value", "7")
        third = quiet_execute()
        @test isempty(intersect(cached_ids(third), downstream))
        @test length(cached_ids(third)) == length(pipeline.modules) - length(downstream)
    end
end
