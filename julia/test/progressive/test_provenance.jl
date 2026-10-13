"""
Tests for state across edits and provenance (Phase 5b of docs/PROGRESSIVE_EXECUTION_PLAN.md)

Run with several threads: julia --project=. --threads=4 test/progressive/test_provenance.jl
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Test
using Tables
using JSON3

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

function wait_until(f; timeout=60.0)
    t0 = time()
    while !f()
        time() - t0 > timeout && error("timed out")
        sleep(0.005)
    end
end

struct StepCounter <: ExecutionObserver
    steps::Dict{Int, Int}
end
StepCounter() = StepCounter(Dict{Int, Int}())
VT.on_module_step(c::StepCounter, run, mod, result, seconds) = (c.steps[mod.id] = get(c.steps, mod.id, 0) + 1)

const ROWS = 2_000_000

function version_a()
    p = Pipeline()
    src = node!(p, "RandomTable"; rows=ROWS, seed=6)
    mn = node!(p, "Min", src)
    filt = node!(p, "Filter", src; column="x", op="<", value=0.5)
    cnt = node!(p, "Count", filt)
    return p, (; src, mn, filt, cnt)
end

@testset "State across edits and provenance (threads: $(Threads.nthreads()))" begin
    @testset "Unchanged modules continue after an edit" begin
        for workers in (1, 4)
            cache = ProgressiveStateCache()
            engine = ProgressiveEngine(workers=workers, step_size=id -> 50_000, state_cache=cache)
            a, m = version_a()

            pr = start!(engine, a)
            wait_until(() -> module_steps(pr.run, m.src.id).items >= 300_000)
            stop!(pr); wait(pr)
            produced = module_steps(pr.run, m.src.id).items
            @test produced < ROWS
            @test module_progress(pr.run, m.src.id) == (produced, ROWS)
            table_a = pr.run.outputs[m.src.id]["result"]
            execs = Dict(e.module_id => e for e in pr.run.workflow_exec.module_execs)
            @test execs[m.src.id].annotations["partial"] == "true"
            @test execs[m.src.id].annotations["progress"] == "$produced/$ROWS"
            @test execs[m.src.id].completed == 0
            @test length(cache) == 4

            # Version B: another threshold, and a new module
            b = deepcopy(a)
            set_parameter!(b.modules[m.filt.id], "value", 0.2)
            mx = node!(b, "Max", b.modules[m.src.id])
            counter = StepCounter()
            pr2 = restart!(pr, b; observers=[counter])
            close_inputs!(pr2)
            run_b = wait(pr2)

            @test run_b.reused == Set([m.src.id, m.mn.id])                     # same signatures
            @test run_b.outputs[m.src.id]["result"] === table_a                  # same table, continued
            @test counter.steps[m.src.id] == cld(ROWS - produced, 50_000)        # only the rest produced
            @test module_steps(run_b, m.src.id).items == ROWS                    # counters are cumulative
            x = column(table_a, :x)
            @test length(x) == ROWS
            @test result_of(run_b, m.mn)[:x] == minimum(x)
            @test result_of(run_b, mx)[:x] == maximum(x)
            @test result_of(run_b, m.cnt) == count(<(0.2), x)                    # edited: from all rows
            execs_b = Dict(e.module_id => e for e in run_b.workflow_exec.module_execs)
            @test execs_b[m.src.id].annotations["resumed"] == "true"
            @test !haskey(execs_b[m.filt.id].annotations, "resumed")

            # Running version B again: everything is reused, nothing steps
            counter2 = StepCounter()
            run_b2 = run!(engine, b; observers=[counter2])
            @test isempty(counter2.steps)
            @test run_b2.reused == Set(keys(b.modules))
            @test result_of(run_b2, m.cnt) == count(<(0.2), x)
            @test all(e -> e.cached && e.annotations["resumed"] == "true", run_b2.workflow_exec.module_execs)

            # Back to version A: its Filter resumes where run A stopped it
            run_a2 = run!(engine, a)
            @test m.filt.id in run_a2.reused
            @test result_of(run_a2, m.cnt) == count(<(0.5), x)
        end
    end

    @testset "Eviction and non-cacheable inputs" begin
        cache = ProgressiveStateCache(max_entries=1)
        engine = ProgressiveEngine(state_cache=cache)
        a, m = version_a()
        run!(engine, a)
        @test length(cache) == 1                        # only the most recent kept
        run2 = run!(engine, a)
        @test length(run2.reused) <= 1                  # a consumer needs its producer resumed too
        @test result_of(run2, m.cnt) == count(<(0.5), column(run2.outputs[m.src.id]["result"], :x))

        # A consumer kept while its producer was evicted must start over: resumed,
        # it would keep reading the stopped run's partial table
        p_stop = Pipeline()
        big = node!(p_stop, "RandomTable"; rows=1_000_000, seed=2)
        cnt = node!(p_stop, "Count", big)
        engine3 = ProgressiveEngine(workers=1, step_size=id -> 50_000,
                                    state_cache=ProgressiveStateCache(max_entries=1))
        pr = start!(engine3, p_stop)
        wait_until(() -> module_steps(pr.run, cnt.id).items >= 100_000)
        stop!(pr); wait(pr)
        @test length(engine3.state_cache) == 1             # Count kept, RandomTable evicted
        run4 = run!(engine3, p_stop)
        @test isempty(run4.reused)
        @test result_of(run4, cnt) == 1_000_000

        # A Variable's value is not in its signature: never resumed, nor its downstream
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=10_000)
        var = node!(p, "Variable"; value=0.3)
        filt = node!(p, "Filter", src; column="x", op="<", value=0.0)
        add_connection!(p, var, "result", filt, "value")
        engine2 = ProgressiveEngine(state_cache=ProgressiveStateCache())
        run!(engine2, p)
        run3 = run!(engine2, p)
        @test run3.reused == Set([src.id])
        empty!(engine2.state_cache)
        @test length(engine2.state_cache) == 0
    end

    @testset "Progress of partial results" begin
        # Stopped part way: a source large enough to outlast the stop
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=20_000_000)
        mn = node!(p, "Min", src)
        pr = start!(ProgressiveEngine(workers=1, step_size=id -> 100_000), p)
        wait_until(() -> module_steps(pr.run, mn.id).items >= 200_000)
        stop!(pr); run = wait(pr)
        done, total = module_progress(run, mn.id)
        @test done == module_steps(run, mn.id).items
        @test total == last_id(run.outputs[src.id]["result"])
        @test 0 < done <= total < 20_000_000

        p = Pipeline()
        src = node!(p, "RandomTable"; rows=1_000_000)
        mn = node!(p, "Min", src)
        run_full = run!(ProgressiveEngine(), p)
        @test module_progress(run_full, src.id) == (1_000_000, 1_000_000)
        @test module_progress(run_full, mn.id) == (1_000_000, 1_000_000)
        e = only(filter(e -> e.module_id == mn.id, run_full.workflow_exec.module_execs))
        @test e.annotations["progress"] == "1000000/1000000" && e.completed == 1
    end

    @testset "Execution history for ProgressiVis' viewer" begin
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=500_000)
        mods = [node!(p, n, src) for n in ("Min", "Var", "Count")]
        history = ExecutionHistory()
        run = run!(ProgressiveEngine(step_size=id -> 40_000), p; observers=[history])
        path = export_execution_history(history, joinpath(mktempdir(), "capture.json"))
        capture = JSON3.read(read(path, String))
        @test capture.schema_version == 1 && capture.status == "completed" && capture.complete
        @test length(capture.graph.modules) == 4 && length(capture.graph.connections) == 3
        for mod in (src, mods...)
            records = capture.histories[Symbol(string(mod.id))]
            @test sum(r.steps_run for r in records) == module_steps(run, mod.id).items
            @test all(records[i].start >= records[i - 1].end for i in 2:length(records))
            @test last(records).state == 5     # done
        end

        viewer_model = joinpath(homedir(), "src", "progressivis-parallel", "tools", "execution-viewer", "model.js")
        if Sys.which("node") !== nothing && isfile(viewer_model)
            script = "const m = require($(repr(viewer_model))); const c = m.parse(JSON.parse(require('fs').readFileSync($(repr(path)), 'utf8'))); console.log('OK', c.steps, c.nodes.length);"
            out = read(`node -e $script`, String)
            @test startswith(out, "OK")
        else
            @test_skip "ProgressiVis viewer model not found"
        end

        # A stopped run is exported as paused
        p2 = Pipeline()
        big = node!(p2, "RandomTable"; rows=100_000_000)
        node!(p2, "Count", big)
        h2 = ExecutionHistory()
        pr = start!(ProgressiveEngine(), p2; observers=[h2])
        wait_until(() -> module_steps(pr.run, big.id).steps >= 3)
        stop!(pr); wait(pr)
        @test execution_history_json(h2)["status"] == "paused"
    end

    @testset "Interactions recorded as versions" begin
        vt = Vistrail("exploration")
        p = Pipeline()
        src = node!(p, "RandomTable"; rows=200_000, seed=8)
        var = node!(p, "Variable"; value=0.5)
        filt = node!(p, "Filter", src; column="x", op="<", value=0.0)
        add_connection!(p, var, "result", filt, "value")
        cnt = node!(p, "Count", filt)
        base = add_version!(vt, p, 0; notes="initial")

        recorder = VersionRecorder(vt, base)
        pr = start!(ProgressiveEngine(), vt.pipelines[base]; observers=[recorder])
        for v in (0.1, 0.3, 0.25)
            set_variable!(pr, var, v)
            sleep(0.02)
        end
        close_inputs!(pr)
        run = wait(pr)

        @test length(recorder.versions) == 3
        chain = [base; recorder.versions]
        @test all(vt.actions[chain[i]].prev_id == chain[i - 1] for i in 2:length(chain))
        @test [vt.pipelines[v].modules[var.id].parameters["value"] for v in recorder.versions] == [0.1, 0.3, 0.25]
        @test vt.actions[recorder.versions[1]].operations[1].parameter == "value"
        @test vt.pipelines[base].modules[var.id].parameters["value"] == 0.5    # earlier versions unchanged

        # The last version reproduces the final state of the session
        final = run!(ProgressiveEngine(), vt.pipelines[last(recorder.versions)])
        @test result_of(final, cnt) == result_of(run, cnt)
        @test occursin("<svg", render_version_tree_svg(vt))
    end
end
