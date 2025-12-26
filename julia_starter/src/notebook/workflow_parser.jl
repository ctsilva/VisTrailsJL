"""
Workflow Parser

Parses workflow notebooks and builds Pipeline objects.
Workflow notebooks define module instances and their connections.
"""

"""
    NotebookModuleDef

Module instance definition from a workflow notebook.
"""
struct NotebookModuleDef
    id::String                      # Unique identifier (e.g., "fetch_data")
    module_type::String             # Type reference (e.g., "basic:HTTPFile")
    params::Dict{String, Any}       # Parameter values
    inputs::Dict{String, String}    # Input connections (port_name => "source_id.output_port")
    code::String                    # Code for JuliaSource-style modules
end

"""
    NotebookWorkflow

Workflow definition from a notebook.
"""
struct NotebookWorkflow
    name::String
    modules::Vector{NotebookModuleDef}
    execute::Bool
end

"""
    parse_workflow_notebook(path::String) -> NotebookWorkflow

Parse a workflow notebook and return the workflow definition.

The notebook should contain:
- A cell with `#| workflow: name`
- Cells with `#| module-id: ...`, `#| module-type: ...`, and optionally `#| params:`, `#| inputs:`
- Optionally a cell with `#| execute` to indicate the workflow should run
"""
function parse_workflow_notebook(path::String)
    cells = parse_notebook(path)

    workflow_name = "unnamed"
    modules = NotebookModuleDef[]
    execute = false

    for cell in cells
        # Check for workflow metadata
        if has_directive(cell, "workflow")
            workflow_name = string(get_directive(cell, "workflow"))
        end

        # Check for module definition
        if has_directive(cell, "module-id")
            mod = parse_workflow_module_cell(cell)
            push!(modules, mod)
        end

        # Check for execute directive
        if has_directive(cell, "execute")
            execute = true
        end
    end

    return NotebookWorkflow(workflow_name, modules, execute)
end

"""
    parse_workflow_module_cell(cell::NotebookCell) -> NotebookModuleDef

Parse a module instance definition from a cell.
"""
function parse_workflow_module_cell(cell::NotebookCell)
    id = string(get_directive(cell, "module-id"))
    module_type = string(get_directive(cell, "module-type", "unknown:Unknown"))

    # Parse params
    params = Dict{String, Any}()
    params_raw = get_directive(cell, "params", nothing)
    if params_raw !== nothing
        if params_raw isa Dict
            for (k, v) in params_raw
                params[string(k)] = v
            end
        elseif params_raw isa Vector
            for item in params_raw
                if item isa Dict
                    for (k, v) in item
                        params[string(k)] = v
                    end
                end
            end
        end
    end

    # Parse inputs (connections)
    inputs = Dict{String, String}()
    inputs_raw = get_directive(cell, "inputs", nothing)
    if inputs_raw !== nothing
        if inputs_raw isa Dict
            for (k, v) in inputs_raw
                inputs[string(k)] = string(v)
            end
        elseif inputs_raw isa Vector
            for item in inputs_raw
                if item isa Dict
                    for (k, v) in item
                        inputs[string(k)] = string(v)
                    end
                end
            end
        end
    end

    return NotebookModuleDef(id, module_type, params, inputs, cell.code)
end

# Package short name to full identifier mapping
const PACKAGE_SHORT_NAMES = Dict(
    "basic" => "org.vistrails.vistrails.basic",
    "julia" => "org.vistrails.vistrails.julia",
    "control_flow" => "org.vistrails.vistrails.control_flow",
    "pythoncalc" => "org.vistrails.vistrails.pythoncalc",
)

"""
    parse_module_type_ref(type_str::AbstractString) -> (package, name)

Parse a module type reference like "basic:Integer" into (full_package, name).
"""
function parse_module_type_ref(type_str::AbstractString)
    type_str = String(type_str)

    if occursin(":", type_str)
        parts = split(type_str, ":")
        package_short = String(parts[1])
        name = String(parts[2])

        # Map short names to full package identifiers
        package = get(PACKAGE_SHORT_NAMES, package_short, package_short)
        return (package, name)
    end

    return ("unknown", type_str)
end

"""
    parse_connection_ref(ref::String) -> (source_id, source_port)

Parse a connection reference like "fetch_data.file" into (source_id, source_port).
"""
function parse_connection_ref(ref::AbstractString)
    ref = String(ref)
    parts = split(ref, ".")

    if length(parts) >= 2
        source_id = String(parts[1])
        source_port = String(join(parts[2:end], "."))
        return (source_id, source_port)
    end

    error("Invalid connection reference: $ref (expected format: module_id.port_name)")
end

"""
    build_pipeline_from_workflow(workflow::NotebookWorkflow) -> Pipeline

Build a Pipeline object from a workflow definition.
"""
function build_pipeline_from_workflow(workflow::NotebookWorkflow)
    pipeline = Pipeline()

    # Map from notebook module ID to pipeline module instance
    id_to_module = Dict{String, ModuleInstance}()

    # First pass: create all modules
    for nb_mod in workflow.modules
        package, name = parse_module_type_ref(nb_mod.module_type)

        # Create module instance
        mod = add_module!(pipeline, package, name)

        # Set parameters
        for (param_name, param_value) in nb_mod.params
            set_parameter!(mod, param_name, param_value)
        end

        id_to_module[nb_mod.id] = mod
    end

    # Second pass: create connections
    for nb_mod in workflow.modules
        dest_mod = id_to_module[nb_mod.id]

        for (dest_port, source_ref) in nb_mod.inputs
            source_id, source_port = parse_connection_ref(source_ref)

            if !haskey(id_to_module, source_id)
                error("Unknown source module: $source_id (referenced in $(nb_mod.id))")
            end

            source_mod = id_to_module[source_id]

            # Create connection
            add_connection!(pipeline, source_mod, source_port, dest_mod, dest_port)
        end
    end

    return pipeline
end

"""
    execute_notebook_pipeline(pipeline::Pipeline; enable_logging::Bool=false) -> Dict{Int, Dict{String, Any}}

Execute a pipeline that may contain notebook-defined modules.
Uses notebook compute functions for modules defined in notebooks,
falls back to standard compute for built-in modules.
"""
function execute_notebook_pipeline(pipeline::Pipeline; enable_logging::Bool=false)
    cache = Dict{Int, Dict{String, Any}}()

    # Get execution order
    execution_order = topological_sort(pipeline)

    println("Executing pipeline with $(length(pipeline.modules)) modules...")
    println("Execution order: ", execution_order)

    for module_id in execution_order
        mod = get_module(pipeline, module_id)

        println("  Module $module_id ($(mod.descriptor.name)): computing...")

        # Collect inputs from upstream
        incoming = get_connections_to(pipeline, module_id)
        for conn in incoming
            if haskey(cache, conn.source_module_id)
                source_outputs = cache[conn.source_module_id]
                if haskey(source_outputs, conn.source_port)
                    set_input!(mod, conn.dest_port, source_outputs[conn.source_port])
                end
            end
        end

        # Execute - check if it's a notebook module first
        key = (mod.descriptor.package, mod.descriptor.name)
        compute_fn = get_notebook_compute(key...)

        outputs = if compute_fn !== nothing
            # Notebook module - use stored function
            compute_fn(mod)
        else
            # Built-in module - use standard compute
            compute(mod, mod.descriptor.module_type)
        end

        cache[module_id] = outputs
        println("    Outputs: $outputs")
        println("    ✓ Complete")
    end

    return cache
end
