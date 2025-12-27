"""
Default Interpreter

Executes workflows (pipelines) by running modules in topological order.
Similar to Python VisTrails' cached.py and default.py
"""

# Load logging system
include("../log/log.jl")

"""
Interpreter

Executes a pipeline, maintaining cache of computed results.
"""
mutable struct Interpreter
    pipeline::Pipeline
    cache::Dict{Int, Dict{String, Any}}
    execution_order::Vector{Int}

    # Execution logging
    workflow_exec::Union{WorkflowExec, Nothing}
    machine::Machine
    enable_logging::Bool
end

"""
    Interpreter(pipeline::Pipeline; enable_logging::Bool=true)

Create an interpreter for a pipeline.
"""
function Interpreter(pipeline::Pipeline; enable_logging::Bool=true)
    # Determine execution order
    execution_order = topological_sort(pipeline)

    # Create machine info
    machine = current_machine(1)

    return Interpreter(
        pipeline,
        Dict{Int, Dict{String, Any}}(),
        execution_order,
        nothing,  # workflow_exec (created when execution starts)
        machine,
        enable_logging
    )
end

"""
    execute_pipeline(pipeline::Pipeline; enable_logging::Bool=true) -> (Dict{Int, Dict{String, Any}}, Union{WorkflowExec, Nothing})

Execute a complete pipeline and return all module outputs and execution log.
"""
function execute_pipeline(pipeline::Pipeline; enable_logging::Bool=true)
    interp = Interpreter(pipeline, enable_logging=enable_logging)

    println("Executing pipeline with $(length(pipeline.modules)) modules...")
    println("Execution order: ", interp.execution_order)

    # Create workflow execution record
    if interp.enable_logging
        interp.workflow_exec = WorkflowExec(
            parent_version=-1  # Will be set if we have vistrail context
        )
        push!(interp.workflow_exec.machines, interp.machine)
    end

    # Execute each module in order
    try
        for module_id in interp.execution_order
            execute_module!(interp, module_id)
        end

        # Mark workflow as completed
        if interp.enable_logging
            mark_completed!(interp.workflow_exec)
        end

        println("Pipeline execution complete!")
    catch e
        # Mark workflow as failed
        if interp.enable_logging
            mark_failed!(interp.workflow_exec, string(e))
        end
        rethrow(e)
    end

    return interp.cache, interp.workflow_exec
end

"""
    execute_module!(interp::Interpreter, module_id::Int)

Execute a single module, using cached results if available.
"""
function execute_module!(interp::Interpreter, module_id::Int)
    mod = get_module(interp.pipeline, module_id)

    # Create module execution record
    mod_exec = if interp.enable_logging
        ModuleExec(
            module_id=module_id,
            module_name=mod.descriptor.name,
            machine_id=interp.machine.id
        )
    else
        nothing
    end

    # Check cache
    if haskey(interp.cache, module_id)
        println("  Module $module_id: using cached results")

        if interp.enable_logging
            mark_cached!(mod_exec)
            add_module_exec!(interp.workflow_exec, mod_exec)
        end

        return interp.cache[module_id]
    end

    println("  Module $module_id ($(mod.descriptor.name)): computing...")

    # Collect inputs from upstream modules
    collect_inputs!(interp, mod)

    # Execute the module
    try
        outputs = compute(mod, mod.descriptor.module_type)

        # Cache results
        interp.cache[module_id] = outputs

        # Mark as completed
        if interp.enable_logging
            mark_completed!(mod_exec)
            add_module_exec!(interp.workflow_exec, mod_exec)
        end

        # Debug: show what outputs were created
        if !isempty(outputs)
            output_str = join(["$k=$(repr(v)[1:min(50,length(repr(v)))])" for (k,v) in outputs], ", ")
            println("    Outputs: ", output_str)
        end

        println("    ✓ Complete")

        return outputs
    catch e
        println("    ✗ Error: ", e)

        if interp.enable_logging
            mark_failed!(mod_exec, string(e))
            add_module_exec!(interp.workflow_exec, mod_exec)
        end

        rethrow(e)
    end
end

"""
    collect_inputs!(interp::Interpreter, mod::ModuleInstance)

Collect input values from upstream modules and set them on the module.
"""
function collect_inputs!(interp::Interpreter, mod::ModuleInstance)
    # Find all connections where this module is the destination
    incoming = get_connections_to(interp.pipeline, mod.id)

    for conn in incoming
        # Get output from source module (executing it if necessary)
        source_outputs = execute_module!(interp, conn.source_module_id)

        # Get the specific output value
        if haskey(source_outputs, conn.source_port)
            value = source_outputs[conn.source_port]

            # Set as input on this module
            set_input!(mod, conn.dest_port, value)

            println("    Input '$(conn.dest_port)' from Module $(conn.source_module_id)")
        else
            @warn "Source module $(conn.source_module_id) does not have output port '$(conn.source_port)'"
        end
    end
end

"""
    compute(mod::ModuleInstance, module_type::Type)

Dispatch to the appropriate compute function for the module type.
This is the extension point for adding new module types.
"""
function compute(mod::ModuleInstance, module_type::Type)
    # This will be extended by each module implementation
    error("Compute not implemented for module type: $module_type")
end
