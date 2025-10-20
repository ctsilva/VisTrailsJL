"""
Default Interpreter

Executes workflows (pipelines) by running modules in topological order.
Similar to Python VisTrails' cached.py and default.py
"""

"""
Interpreter

Executes a pipeline, maintaining cache of computed results.
"""
mutable struct Interpreter
    pipeline::Pipeline
    cache::Dict{Int, Dict{String, Any}}
    execution_order::Vector{Int}
end

"""
    Interpreter(pipeline::Pipeline)

Create an interpreter for a pipeline.
"""
function Interpreter(pipeline::Pipeline)
    # Determine execution order
    execution_order = topological_sort(pipeline)

    return Interpreter(pipeline, Dict{Int, Dict{String, Any}}(), execution_order)
end

"""
    execute_pipeline(pipeline::Pipeline) -> Dict{Int, Dict{String, Any}}

Execute a complete pipeline and return all module outputs.
"""
function execute_pipeline(pipeline::Pipeline)
    interp = Interpreter(pipeline)

    println("Executing pipeline with $(length(pipeline.modules)) modules...")
    println("Execution order: ", interp.execution_order)

    # Execute each module in order
    for module_id in interp.execution_order
        execute_module!(interp, module_id)
    end

    println("Pipeline execution complete!")

    return interp.cache
end

"""
    execute_module!(interp::Interpreter, module_id::Int)

Execute a single module, using cached results if available.
"""
function execute_module!(interp::Interpreter, module_id::Int)
    # Check cache
    if haskey(interp.cache, module_id)
        println("  Module $module_id: using cached results")
        return interp.cache[module_id]
    end

    mod = get_module(interp.pipeline, module_id)

    println("  Module $module_id ($(mod.descriptor.name)): computing...")

    # Collect inputs from upstream modules
    collect_inputs!(interp, mod)

    # Execute the module
    try
        outputs = compute(mod, mod.descriptor.module_type)

        # Cache results
        interp.cache[module_id] = outputs

        # Debug: show what outputs were created
        if !isempty(outputs)
            output_str = join(["$k=$(repr(v)[1:min(50,length(repr(v)))])" for (k,v) in outputs], ", ")
            println("    Outputs: ", output_str)
        end

        println("    ✓ Complete")

        return outputs
    catch e
        println("    ✗ Error: ", e)
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
