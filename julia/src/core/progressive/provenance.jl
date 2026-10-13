"""
Provenance of progressive runs

- `ExecutionHistory`: an observer recording every step of every module, as
  intervals with their work, exported in the JSON format of ProgressiVis'
  execution history (schema version 1), so its offline viewer
  (`progressivis-parallel/tools/execution-viewer`) can replay a run.
- `VersionRecorder`: an observer recording each live input change
  (`set_variable!`) as a new version of a vistrail, so an exploration session
  becomes a branch of the version tree.
"""

using JSON3

# ProgressiVis module states: created=0, ready=1, running=2, blocked=3,
# suspended=4, zombie=5, terminated=6, invalid=7
const HISTORY_STATE = Dict(:ready => 1, :blocked => 3, :done => 5)

"""
    ExecutionHistory()

Observer recording the steps of a run. Pass it to `run!`/`start!`, then
`export_execution_history(history, path)`.
"""
mutable struct ExecutionHistory <: ExecutionObserver
    origin::Float64
    run::Any
    histories::Dict{Int, Vector{Dict{String, Any}}}
    steps::Int
    status::String
end

ExecutionHistory() = ExecutionHistory(0.0, nothing, Dict{Int, Vector{Dict{String, Any}}}(), 0, "paused")

function on_run_start(h::ExecutionHistory, run)
    h.origin = time()
    h.run = run
    h.histories = Dict(id => Dict{String, Any}[] for id in run.order)
    h.steps = 0
    h.status = "paused"
end

function record_step!(h::ExecutionHistory, id::Int, start::Float64, stop::Float64, work::Int, state::Int, failed::Bool)
    records = h.histories[id]
    previous_end = isempty(records) ? 0.0 : records[end]["end"]
    start = max(start, previous_end)   # intervals of a module never overlap
    h.steps += 1
    push!(records, Dict{String, Any}("execution" => 1, "run" => h.steps, "start" => start,
                                     "end" => max(stop, start), "steps_run" => work,
                                     "state" => state, "failed" => failed))
end

function on_module_step(h::ExecutionHistory, run, mod, result, seconds)
    t = time() - h.origin
    record_step!(h, mod.id, t - seconds, t, result.items, HISTORY_STATE[result.status], false)
end

# A module that finished without a final :done step (e.g. a fold whose inputs
# ended) gets a zero-work terminating record, as ProgressiVis records zombie
function on_module_done(h::ExecutionHistory, run, mod, outputs)
    records = h.histories[mod.id]
    (isempty(records) || records[end]["state"] != HISTORY_STATE[:done]) || return
    t = time() - h.origin
    record_step!(h, mod.id, t, t, 0, HISTORY_STATE[:done], false)
end

function on_module_error(h::ExecutionHistory, run, mod, err)
    t = time() - h.origin
    record_step!(h, mod.id, t, t, 0, 7, true)   # invalid, failed
end

function on_run_done(h::ExecutionHistory, run, err)
    state = run.engine_state
    h.status = err !== nothing ? "failed" :
               (state isa ProgressiveState && !all_finished(state)) ? "paused" : "completed"
end

"""
    execution_history_json(history) -> Dict

The capture in ProgressiVis' execution-history format (schema version 1).
"""
function execution_history_json(h::ExecutionHistory)
    h.run === nothing && error("no run recorded")
    run = h.run
    modules = [Dict("id" => string(id),
                    "name" => "$(run.instances[id].descriptor.name) $id",
                    "type" => "$(run.instances[id].descriptor.package).$(run.instances[id].descriptor.name)")
               for id in run.order]
    connections = [Dict("source" => string(c.source_module_id), "output" => c.source_port,
                        "target" => string(c.dest_module_id), "input" => c.dest_port)
                   for c in run.pipeline.connections]
    return Dict("schema_version" => 1,
                "clock" => "monotonic_seconds_since_capture_start",
                "status" => h.status,
                "complete" => h.status == "completed",
                "executions" => 1,
                "graph" => Dict("modules" => modules, "connections" => connections),
                "histories" => Dict(string(id) => records for (id, records) in h.histories))
end

"""
    export_execution_history(history, path) -> path

Write the capture as JSON, for ProgressiVis' execution viewer.
"""
function export_execution_history(h::ExecutionHistory, path::AbstractString)
    open(io -> JSON3.write(io, execution_history_json(h)), path, "w")
    return path
end

"""
    VersionRecorder(vistrail, version)

Observer recording each `set_variable!` of a progressive run as a new
version of `vistrail`: a child of the previous one, starting from `version`
(the version whose pipeline is being run), whose pipeline has the input's
new value as its `value` parameter. `recorder.versions` lists them.
"""
mutable struct VersionRecorder <: ExecutionObserver
    vistrail::Vistrail
    version::Int
    versions::Vector{Int}
end

VersionRecorder(vt::Vistrail, version::Int) = VersionRecorder(vt, version, Int[])

function on_interaction(r::VersionRecorder, run, module_id, value)
    pipeline = deepcopy(r.vistrail.pipelines[r.version])
    haskey(pipeline.modules, module_id) ||
        error("module $module_id is not in version $(r.version) of the vistrail")
    set_parameter!(pipeline.modules[module_id], "value", value)
    name = pipeline.modules[module_id].descriptor.name
    v = add_version!(r.vistrail, pipeline, r.version;
                     notes="live: $name $module_id value = $(repr(value))",
                     operations=Any[(type=:change_parameter, module_id=module_id,
                                     parameter="value", value=value)])
    r.version = v
    push!(r.versions, v)
end
