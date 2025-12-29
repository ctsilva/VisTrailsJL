"""
High-Level API for VisTrailsJL

Provides a user-friendly API similar to Python VisTrails, making it easy to:
- Load and execute .vt files and notebook workflows
- Navigate version trees
- Parameterize workflows with inputs
- Extract outputs from executed workflows

Inspired by the Python VisTrails API shown in examples/api/ipython-notebook.ipynb
"""

# ============================================================================
# API Wrapper Types
# ============================================================================

"""
    ExecutionResult

Stores the results of a pipeline execution, providing convenient
access to module outputs.
"""
struct ExecutionResult
    cache::Dict{Int, Dict{String, Any}}
    workflow_exec::Union{WorkflowExec, Nothing}
    pipeline::Pipeline
    module_id_map::Dict{String, Int}  # Map module names to IDs
end

"""
    VistrailWrapper

High-level wrapper around the internal Vistrail type that provides
a convenient API for version navigation and execution.
"""
mutable struct VistrailWrapper
    vistrail::Vistrail
    file_path::Union{String, Nothing}
    current_pipeline::Union{Pipeline, Nothing}
    last_result::Union{ExecutionResult, Nothing}
end

"""
    PipelineWrapper

High-level wrapper around Pipeline that supports parameterized execution.
"""
mutable struct PipelineWrapper
    pipeline::Pipeline
    vistrail::Union{VistrailWrapper, Nothing}
    last_result::Union{ExecutionResult, Nothing}
end

# ============================================================================
# Loading Functions
# ============================================================================

"""
    load_vistrail(file_path::String) -> VistrailWrapper

Load a .vt file and return a high-level wrapper.

# Example
```julia
vt = load_vistrail("examples/gcd.vt")
vt.select_latest_version()
result = execute(vt)
```
"""
function load_vistrail(file_path::String)
    # Call the internal function that loads the raw Vistrail struct
    vistrail = load_vistrail_internal(file_path)

    wrapper = VistrailWrapper(vistrail, file_path, nothing, nothing)

    # Auto-select latest version if available
    if !isempty(vistrail.actions)
        latest = get_latest_version(vistrail)
        select_version!(wrapper, latest)
    end

    return wrapper
end

"""
    load_workflow(file_path::String) -> PipelineWrapper

Load a notebook workflow (.ipynb file) and return a pipeline wrapper.

# Example
```julia
workflow = load_workflow("examples/workflows/data_analysis.ipynb")
result = execute(workflow, save_outputs=true)
```
"""
function load_workflow(file_path::String)
    # Use existing notebook workflow parser
    notebook_workflow = parse_workflow_notebook(file_path)
    pipeline, id_to_module = build_pipeline_from_workflow(notebook_workflow)

    wrapper = PipelineWrapper(pipeline, nothing, nothing)
    return wrapper
end

"""
    load_package(identifier::String) -> NotebookPackage

Load a package by identifier or from a notebook file.

# Example
```julia
# Load from notebook
pkg = load_package("examples/packages/datatools.ipynb")

# Or use identifier if already registered
pkg = load_package("org.vistrails.vistrails.datatools")
```
"""
function load_package(path_or_id::String)
    if endswith(path_or_id, ".ipynb")
        # Load from notebook
        pkg = load_package_from_notebook(path_or_id)
        register_notebook_package!(pkg)
        return pkg
    else
        # Return package info (could be enhanced to return descriptor)
        error("Loading by identifier not yet implemented - use notebook path")
    end
end

# ============================================================================
# Version Navigation
# ============================================================================

"""
    select_version!(vt::VistrailWrapper, version_id::Int)

Select a specific version by ID.
"""
function select_version!(vt::VistrailWrapper, version_id::Int)
    pipeline = get_pipeline(vt.vistrail, version_id)
    vt.vistrail.current_version = version_id
    vt.current_pipeline = pipeline
    return vt
end

"""
    select_version!(vt::VistrailWrapper, tag_name::String)

Select a version by tag name.
"""
function select_version!(vt::VistrailWrapper, tag_name::String)
    version_id = get_tag(vt.vistrail, tag_name)
    if version_id === nothing
        error("Tag '$tag_name' not found")
    end
    return select_version!(vt, version_id)
end

"""
    select_latest_version!(vt::VistrailWrapper)

Select the most recent version.
"""
function select_latest_version!(vt::VistrailWrapper)
    latest = get_latest_version(vt.vistrail)
    return select_version!(vt, latest)
end

# ============================================================================
# Execution
# ============================================================================

"""
    execute(vt::VistrailWrapper; kwargs...) -> ExecutionResult

Execute the current pipeline in a vistrail.

# Keyword Arguments
- `enable_logging::Bool = true` - Enable provenance logging
- Input parameters can be passed as keyword arguments (e.g., `in_a=2, in_b=4`)

# Example
```julia
vt = load_vistrail("examples/gcd.vt")
result = execute(vt, in_a=2, in_b=4)
output = result.output_port("result")
```
"""
function execute(vt::VistrailWrapper; kwargs...)
    if vt.current_pipeline === nothing
        error("No version selected. Use select_version!() or select_latest_version!()")
    end

    result = execute(PipelineWrapper(vt.current_pipeline, vt, nothing); kwargs...)
    vt.last_result = result
    return result
end

"""
    execute(pw::PipelineWrapper; kwargs...) -> ExecutionResult

Execute a pipeline wrapper.

# Keyword Arguments
- `enable_logging::Bool = true` - Enable provenance logging
- `save_outputs::Bool = false` - Save outputs to notebook (for notebook workflows)
- Input parameters (e.g., `in_a=2, in_b=4`)
"""
function execute(pw::PipelineWrapper; enable_logging::Bool=true, save_outputs::Bool=false, kwargs...)
    pipeline = pw.pipeline

    # Set input parameters if provided
    if !isempty(kwargs)
        set_inputs!(pipeline, kwargs)
    end

    # Execute pipeline
    cache, workflow_exec = execute_pipeline(pipeline, enable_logging=enable_logging)

    # Build module ID map (name/function -> ID)
    module_id_map = build_module_id_map(pipeline)

    # Create result
    result = ExecutionResult(cache, workflow_exec, pipeline, module_id_map)
    pw.last_result = result

    return result
end

"""
    set_inputs!(pipeline::Pipeline, inputs::NamedTuple)

Set input port values on modules based on keyword arguments.
Looks for modules with matching names or input port names.
"""
function set_inputs!(pipeline::Pipeline, inputs)
    for (key, value) in pairs(inputs)
        key_str = String(key)

        # Try to find a module with a matching input port or name
        found = false

        for (mod_id, mod) in pipeline.modules
            # Check if module has an input port with this name
            for port in mod.descriptor.input_ports
                if port.name == key_str
                    set_input!(mod, key_str, value)
                    println("  Set input '$key_str' = $value on module $mod_id")
                    found = true
                    break
                end
            end

            # Also check module function/name
            if occursin(key_str, mod.descriptor.name)
                # For InputPort modules, set the value parameter
                if mod.descriptor.name == "InputPort"
                    set_parameter!(mod, "value", value)
                    println("  Set parameter on InputPort module $mod_id: $key_str = $value")
                    found = true
                end
            end
        end

        if !found
            @warn "Could not find input port or module for parameter: $key_str"
        end
    end
end

"""
    build_module_id_map(pipeline::Pipeline) -> Dict{String, Int}

Build a map from module names/functions to IDs for easier lookup.
"""
function build_module_id_map(pipeline::Pipeline)
    id_map = Dict{String, Int}()

    for (mod_id, mod) in pipeline.modules
        # Map by module name
        id_map[mod.descriptor.name] = mod_id

        # Map by function parameter (for modules like InputPort, OutputPort)
        if haskey(mod.parameters, "name")
            name = mod.parameters["name"]
            if name isa String
                id_map[name] = mod_id
            end
        end
    end

    return id_map
end

# ============================================================================
# Output Extraction
# ============================================================================

"""
    output_port(result::ExecutionResult, name::String) -> Any

Get the value from an OutputPort module by name.

# Example
```julia
result = execute(vt, in_a=2, in_b=4)
value = output_port(result, "out_times")
```
"""
function output_port(result::ExecutionResult, name::String)
    # Find OutputPort module with this name
    for (mod_id, mod) in result.pipeline.modules
        if mod.descriptor.name == "OutputPort"
            if haskey(mod.parameters, "name") && mod.parameters["name"] == name
                # Get the value from the module's inputs
                if haskey(result.cache, mod_id)
                    outputs = result.cache[mod_id]
                    # OutputPort modules typically pass through their input
                    if haskey(outputs, "value")
                        return outputs["value"]
                    end
                end
            end
        end
    end

    error("OutputPort '$name' not found or not executed")
end

"""
    module_output(result::ExecutionResult, module_id::Int, port_name::String="value") -> Any

Get an output port value from any module by ID.

# Example
```julia
result = execute(pipeline)
value = module_output(result, 5, "result")
```
"""
function module_output(result::ExecutionResult, module_id::Int, port_name::String="value")
    if !haskey(result.cache, module_id)
        error("Module $module_id was not executed or has no cached results")
    end

    outputs = result.cache[module_id]

    if !haskey(outputs, port_name)
        available = join(keys(outputs), ", ")
        error("Module $module_id does not have output port '$port_name'. Available: $available")
    end

    return outputs[port_name]
end

"""
    module_output(result::ExecutionResult, module_name::String, port_name::String="value") -> Any

Get an output port value from a module by name.

# Example
```julia
result = execute(pipeline)
value = module_output(result, "CSVParser", "rows")
```
"""
function module_output(result::ExecutionResult, module_name::String, port_name::String="value")
    if !haskey(result.module_id_map, module_name)
        error("Module '$module_name' not found in pipeline")
    end

    module_id = result.module_id_map[module_name]
    return module_output(result, module_id, port_name)
end

# ============================================================================
# Module Information
# ============================================================================

"""
    get_input(pipeline::Pipeline, name::String) -> Union{ModuleInstance, Nothing}

Get an InputPort module by name.
"""
function get_input(pipeline::Pipeline, name::String)
    for (mod_id, mod) in pipeline.modules
        if mod.descriptor.name == "InputPort"
            if haskey(mod.parameters, "name") && mod.parameters["name"] == name
                return mod
            end
        end
    end
    return nothing
end

"""
    get_module(pipeline::Pipeline, name::String) -> Union{ModuleInstance, Nothing}

Get a module by name or function parameter.
"""
function get_module(pipeline::Pipeline, name::String)
    for (mod_id, mod) in pipeline.modules
        # Check descriptor name
        if mod.descriptor.name == name
            return mod
        end

        # Check name parameter
        if haskey(mod.parameters, "name") && mod.parameters["name"] == name
            return mod
        end
    end
    return nothing
end

# ============================================================================
# Display Methods
# ============================================================================

function Base.show(io::IO, vt::VistrailWrapper)
    n_versions = length(vt.vistrail.actions)
    n_tags = length(vt.vistrail.tags)
    current = vt.vistrail.current_version

    print(io, "VistrailWrapper(")
    print(io, "\"$(vt.vistrail.name)\", ")
    print(io, "$n_versions versions, ")
    print(io, "$n_tags tags, ")
    print(io, "current=$current")
    print(io, ")")
end

function Base.show(io::IO, pw::PipelineWrapper)
    n_modules = length(pw.pipeline.modules)
    n_connections = length(pw.pipeline.connections)

    print(io, "PipelineWrapper(")
    print(io, "$n_modules modules, ")
    print(io, "$n_connections connections")
    print(io, ")")
end

function Base.show(io::IO, result::ExecutionResult)
    n_executed = length(result.cache)
    status = result.workflow_exec !== nothing ? result.workflow_exec.completed : "unknown"

    print(io, "ExecutionResult(")
    print(io, "$n_executed modules executed, ")
    print(io, "status=$status")
    print(io, ")")
end
