"""
Execution engines

A `Pipeline` is a specification; an `Engine` runs it. Each run gets its own
`PipelineRun`, which holds per-run copies of the module instances and their
outputs, so executing never mutates the pipeline.

See docs/PROGRESSIVE_EXECUTION_PLAN.md for the engines planned on top of this.
"""

abstract type Engine end

"""
OneShotEngine

Runs each module's `compute` once, in topological order.
"""
struct OneShotEngine <: Engine end

"""
CachedEngine

Like `OneShotEngine`, but keeps module outputs keyed by subpipeline
signature across runs, and reuses them whenever a module and everything
upstream of it are unchanged, including after switching to another version.
A module is reused only if it and all its upstream modules are cacheable.

Cached outputs are shared between runs: modules must not mutate their inputs.
"""
mutable struct CachedEngine <: Engine
    entries::Dict{String, Dict{String, Any}}  # subpipeline signature → outputs
end

CachedEngine() = CachedEngine(Dict{String, Dict{String, Any}}())

"""
    clear_cache!(engine::CachedEngine)

Drop every cached result.
"""
clear_cache!(engine::CachedEngine) = (empty!(engine.entries); engine)

"""
PipelineRun

State of one execution of a pipeline.

- `instances`: per-run copies of the pipeline's modules (inputs, outputs)
- `outputs`: module id → output dict, for every module that completed
- `signatures`: module id → subpipeline signature
- `reusable`: module id → whether its results may be cached and reused:
  its type is cacheable and so is everything upstream of it
- `reused`: ids of modules whose outputs came from a cache
"""
mutable struct PipelineRun
    pipeline::Pipeline
    order::Vector{Int}
    instances::Dict{Int, ModuleInstance}
    outputs::Dict{Int, Dict{String, Any}}
    signatures::Dict{Int, String}
    reusable::Dict{Int, Bool}
    reused::Set{Int}
    observers::Vector{ExecutionObserver}
    workflow_exec::Union{WorkflowExec, Nothing}
    machine::Machine
end

function PipelineRun(pipeline::Pipeline;
                     observers=ExecutionObserver[], enable_logging::Bool=true)
    machine = current_machine(1)
    workflow_exec = nothing
    if enable_logging
        workflow_exec = WorkflowExec(parent_version=-1)
        push!(workflow_exec.machines, machine)
    end

    order = topological_sort(pipeline)
    instances = Dict(id => instance_for_run(mod) for (id, mod) in pipeline.modules)

    return PipelineRun(pipeline, order, instances,
                       Dict{Int, Dict{String, Any}}(),
                       subpipeline_signatures(pipeline, order),
                       reusable_modules(pipeline, order), Set{Int}(),
                       collect(ExecutionObserver, observers),
                       workflow_exec, machine)
end

"""
    reusable_modules(pipeline::Pipeline, order::Vector{Int}) -> Dict{Int, Bool}

A module's results may be reused if its type is cacheable and so is every
module upstream of it (a non-deterministic producer invalidates its consumers).
"""
function reusable_modules(pipeline::Pipeline, order::Vector{Int})
    reusable = Dict{Int, Bool}()
    for module_id in order
        reusable[module_id] =
            is_cacheable(pipeline.modules[module_id].descriptor.module_type) &&
            all(reusable[c.source_module_id] for c in get_connections_to(pipeline, module_id))
    end
    return reusable
end

notify_observers(f, run::PipelineRun, args...) =
    foreach(obs -> f(obs, run, args...), run.observers)

"""
    run!(engine::Engine, pipeline::Pipeline; observers=[], enable_logging=true) -> PipelineRun

Execute a pipeline. On a module failure the run is aborted, the failure is
logged and reported to the observers, and the exception is rethrown.
"""
function run!(engine::Engine, pipeline::Pipeline;
              observers=ExecutionObserver[], enable_logging::Bool=true)
    run = PipelineRun(pipeline; observers=observers, enable_logging=enable_logging)
    notify_observers(on_run_start, run)

    try
        for module_id in run.order
            execute_module!(engine, run, module_id)
        end
    catch e
        run.workflow_exec !== nothing && mark_failed!(run.workflow_exec, string(e))
        notify_observers(on_run_done, run, e)
        rethrow()
    end

    run.workflow_exec !== nothing && mark_completed!(run.workflow_exec)
    notify_observers(on_run_done, run, nothing)
    return run
end

"""
    execute_module!(engine::Engine, run::PipelineRun, module_id::Int) -> Dict{String, Any}

Produce a module's outputs. Engines decide how; the default computes it.
"""
execute_module!(::Engine, run::PipelineRun, module_id::Int) = compute_module!(run, module_id)

function execute_module!(engine::CachedEngine, run::PipelineRun, module_id::Int)
    signature = run.signatures[module_id]
    cacheable = run.reusable[module_id]

    if cacheable && haskey(engine.entries, signature)
        return reuse_module!(run, module_id, engine.entries[signature])
    end

    outputs = compute_module!(run, module_id)
    cacheable && (engine.entries[signature] = outputs)
    return outputs
end

function new_module_exec(run::PipelineRun, mod::ModuleInstance)
    run.workflow_exec === nothing && return nothing
    mod_exec = ModuleExec(module_id=mod.id, module_name=mod.descriptor.name,
                          machine_id=run.machine.id)
    mod_exec.annotations["signature"] = run.signatures[mod.id]
    return mod_exec
end

"""
    reuse_module!(run::PipelineRun, module_id::Int, outputs) -> Dict{String, Any}

Record outputs taken from a cache as the module's result for this run.
"""
function reuse_module!(run::PipelineRun, module_id::Int, outputs::Dict{String, Any})
    mod = run.instances[module_id]
    run.outputs[module_id] = outputs
    push!(run.reused, module_id)

    mod_exec = new_module_exec(run, mod)
    if mod_exec !== nothing
        mark_cached!(mod_exec)
        add_module_exec!(run.workflow_exec, mod_exec)
    end
    notify_observers(on_module_cached, run, mod, outputs)

    return outputs
end

"""
    compute_module!(run::PipelineRun, module_id::Int) -> Dict{String, Any}

Gather a module's inputs from its (already executed) producers and compute it.
"""
function compute_module!(run::PipelineRun, module_id::Int)
    mod = run.instances[module_id]
    gather_inputs!(run, mod)

    mod_exec = new_module_exec(run, mod)
    notify_observers(on_module_start, run, mod)
    outputs = try
        compute_module(mod)
    catch e
        if mod_exec !== nothing
            mark_failed!(mod_exec, string(e))
            add_module_exec!(run.workflow_exec, mod_exec)
        end
        notify_observers(on_module_error, run, mod, e)
        rethrow()
    end

    run.outputs[module_id] = outputs

    if mod_exec !== nothing
        mark_completed!(mod_exec)
        add_module_exec!(run.workflow_exec, mod_exec)
    end
    notify_observers(on_module_done, run, mod, outputs)

    return outputs
end

"""
    gather_inputs!(run::PipelineRun, mod::ModuleInstance)

Copy producer outputs into the module's inputs. Connections are applied in
id order: `inputs[port]` holds the last value, `input_lists[port]` all of them.
"""
function gather_inputs!(run::PipelineRun, mod::ModuleInstance)
    incoming = sort(get_connections_to(run.pipeline, mod.id), by=c -> c.id)

    for conn in incoming
        source_outputs = run.outputs[conn.source_module_id]

        if haskey(source_outputs, conn.source_port)
            value = source_outputs[conn.source_port]
            mod.inputs[conn.dest_port] = value
            push!(get!(Vector{Any}, mod.input_lists, conn.dest_port), value)
        else
            @warn "Source module $(conn.source_module_id) does not have output port '$(conn.source_port)'"
        end
    end
end

"""
    compute_module(mod::ModuleInstance) -> Dict{String, Any}

Run a module's implementation: a notebook-defined compute function if one is
registered for its type, otherwise the `compute` method for its Julia type.
"""
function compute_module(mod::ModuleInstance)
    notebook_compute = get_notebook_compute(mod.descriptor.package, mod.descriptor.name)
    if notebook_compute !== nothing
        return notebook_compute(mod)
    end
    return compute(mod, mod.descriptor.module_type)
end

"""
    compute(mod::ModuleInstance, module_type::Type)

Dispatch to the appropriate compute function for the module type.
This is the extension point for adding new module types.
"""
function compute(mod::ModuleInstance, module_type::Type)
    error("Compute not implemented for module type: $module_type")
end

"""
    execute_pipeline(pipeline::Pipeline; enable_logging=true, observers=[ConsoleObserver()],
                     engine=OneShotEngine())
        -> (Dict{Int, Dict{String, Any}}, Union{WorkflowExec, Nothing})

Execute a pipeline with `engine` (one-shot by default) and return all module
outputs and the execution log.
"""
function execute_pipeline(pipeline::Pipeline; enable_logging::Bool=true,
                          observers=ExecutionObserver[ConsoleObserver()],
                          engine::Engine=OneShotEngine())
    run = run!(engine, pipeline; observers=observers, enable_logging=enable_logging)
    return run.outputs, run.workflow_exec
end
