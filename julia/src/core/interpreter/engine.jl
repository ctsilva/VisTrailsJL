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
PipelineRun

State of one execution of a pipeline.

- `instances`: per-run copies of the pipeline's modules (inputs, outputs)
- `outputs`: module id → output dict, for every module that completed
"""
mutable struct PipelineRun
    pipeline::Pipeline
    order::Vector{Int}
    instances::Dict{Int, ModuleInstance}
    outputs::Dict{Int, Dict{String, Any}}
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

    instances = Dict(id => instance_for_run(mod) for (id, mod) in pipeline.modules)

    return PipelineRun(pipeline, topological_sort(pipeline), instances,
                       Dict{Int, Dict{String, Any}}(),
                       collect(ExecutionObserver, observers),
                       workflow_exec, machine)
end

notify_observers(f, run::PipelineRun, args...) =
    foreach(obs -> f(obs, run, args...), run.observers)

"""
    run!(engine::Engine, pipeline::Pipeline; observers=[], enable_logging=true) -> PipelineRun

Execute a pipeline. On a module failure the run is aborted, the failure is
logged and reported to the observers, and the exception is rethrown.
"""
function run!(::OneShotEngine, pipeline::Pipeline;
              observers=ExecutionObserver[], enable_logging::Bool=true)
    run = PipelineRun(pipeline; observers=observers, enable_logging=enable_logging)
    notify_observers(on_run_start, run)

    try
        for module_id in run.order
            execute_module!(run, module_id)
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
    execute_module!(run::PipelineRun, module_id::Int) -> Dict{String, Any}

Gather a module's inputs from its (already executed) producers and compute it.
"""
function execute_module!(run::PipelineRun, module_id::Int)
    mod = run.instances[module_id]
    gather_inputs!(run, mod)

    mod_exec = if run.workflow_exec !== nothing
        ModuleExec(module_id=module_id, module_name=mod.descriptor.name,
                   machine_id=run.machine.id)
    else
        nothing
    end

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
    execute_pipeline(pipeline::Pipeline; enable_logging=true, observers=[ConsoleObserver()])
        -> (Dict{Int, Dict{String, Any}}, Union{WorkflowExec, Nothing})

Execute a pipeline with the one-shot engine and return all module outputs and
the execution log.
"""
function execute_pipeline(pipeline::Pipeline; enable_logging::Bool=true,
                          observers=ExecutionObserver[ConsoleObserver()])
    run = run!(OneShotEngine(), pipeline; observers=observers, enable_logging=enable_logging)
    return run.outputs, run.workflow_exec
end
