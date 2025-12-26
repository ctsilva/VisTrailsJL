"""
Conversion Tools

Convert between notebook-based and code-based package/workflow definitions.

Supports:
- Package code → Notebook
- Notebook → Package code
- .vt file → Workflow notebook
"""

using JSON

# ============================================================================
# Package Code → Notebook
# ============================================================================

"""
    package_to_notebook(package_id::String, modules::Vector; version::String="1.0.0") -> Dict

Convert a package definition to notebook JSON structure.

# Arguments
- `package_id`: Package identifier (e.g., "org.vistrails.vistrails.basic")
- `modules`: Vector of module definitions, each a Dict with:
  - `name`: Module name
  - `input_ports`: Vector of (name, signature) tuples
  - `output_ports`: Vector of (name, signature) tuples
  - `parameters`: Vector of (name, signature) tuples (optional)
  - `code`: Julia code for the compute function
- `version`: Package version string

# Returns
Dict representing the notebook JSON structure
"""
function package_to_notebook(package_id::String, modules::Vector; version::String="1.0.0")
    cells = []

    # Title cell
    push!(cells, Dict(
        "cell_type" => "markdown",
        "metadata" => Dict(),
        "source" => ["# Package: $package_id\n", "\n", "Version: $version"]
    ))

    # Package metadata cell
    push!(cells, Dict(
        "cell_type" => "code",
        "metadata" => Dict(),
        "source" => [
            "#| package-meta\n",
            "#| identifier: $package_id\n",
            "#| version: $version"
        ],
        "outputs" => [],
        "execution_count" => nothing
    ))

    # Module cells
    for mod in modules
        source_lines = String[]

        push!(source_lines, "#| module: $(mod["name"])\n")

        # Input ports
        if haskey(mod, "input_ports") && !isempty(mod["input_ports"])
            push!(source_lines, "#| input_ports:\n")
            for (name, sig) in mod["input_ports"]
                push!(source_lines, "#|   - name: $name\n")
                push!(source_lines, "#|     signature: $sig\n")
            end
        end

        # Output ports
        if haskey(mod, "output_ports") && !isempty(mod["output_ports"])
            push!(source_lines, "#| output_ports:\n")
            for (name, sig) in mod["output_ports"]
                push!(source_lines, "#|   - name: $name\n")
                push!(source_lines, "#|     signature: $sig\n")
            end
        end

        # Parameters
        if haskey(mod, "parameters") && !isempty(mod["parameters"])
            push!(source_lines, "#| parameters:\n")
            for (name, sig) in mod["parameters"]
                push!(source_lines, "#|   - name: $name\n")
                push!(source_lines, "#|     signature: $sig\n")
            end
        end

        # Add blank line before code
        push!(source_lines, "\n")

        # Code
        if haskey(mod, "code")
            for line in split(mod["code"], '\n')
                push!(source_lines, line * "\n")
            end
        end

        push!(cells, Dict(
            "cell_type" => "code",
            "metadata" => Dict(),
            "source" => source_lines,
            "outputs" => [],
            "execution_count" => nothing
        ))
    end

    return Dict(
        "cells" => cells,
        "metadata" => Dict(
            "kernelspec" => Dict(
                "display_name" => "Julia",
                "language" => "julia",
                "name" => "julia"
            ),
            "language_info" => Dict(
                "name" => "julia"
            )
        ),
        "nbformat" => 4,
        "nbformat_minor" => 4
    )
end

"""
    save_package_notebook(notebook::Dict, path::String)

Save a notebook Dict to a .ipynb file.
"""
function save_package_notebook(notebook::Dict, path::String)
    open(path, "w") do f
        JSON.print(f, notebook, 1)
    end
    println("Saved package notebook to: $path")
end

"""
    registered_package_to_notebook(package_id::String, path::String; version::String="1.0.0")

Export a registered package to a notebook file.

Note: This exports the structure but cannot recover the original compute code.
The code cells will contain placeholder comments.
"""
function registered_package_to_notebook(package_id::String, path::String; version::String="1.0.0")
    # Find all modules in this package
    all_modules = list_modules()
    package_modules = filter(m -> m[1] == package_id, all_modules)

    if isempty(package_modules)
        error("No modules found for package: $package_id")
    end

    modules = []
    for (pkg, name) in package_modules
        descriptor = get_module_descriptor(pkg, name)

        mod = Dict{String, Any}(
            "name" => name,
            "input_ports" => [(p.name, type_to_signature(p.type)) for p in descriptor.input_ports],
            "output_ports" => [(p.name, type_to_signature(p.type)) for p in descriptor.output_ports],
            "parameters" => [(p[1], type_to_signature(p[2])) for p in descriptor.parameters],
            "code" => "# TODO: Implement compute logic\n# Use get_input(\"name\"), set_output(\"name\", value)"
        )

        push!(modules, mod)
    end

    notebook = package_to_notebook(package_id, modules; version=version)
    save_package_notebook(notebook, path)
end

"""
    type_to_signature(t::Type) -> String

Convert a Julia type to a VisTrails signature string.
"""
function type_to_signature(t::Type)
    type_map = Dict(
        Int => "basic:Integer",
        Float64 => "basic:Float",
        String => "basic:String",
        Bool => "basic:Boolean",
        Any => "basic:Any",
        Vector => "basic:List",
    )
    return get(type_map, t, "basic:Any")
end

# ============================================================================
# Notebook → Package Code
# ============================================================================

"""
    notebook_to_package_code(notebook_path::String) -> String

Convert a package notebook to Julia package code.

Returns a string containing the complete Julia code for the package.
"""
function notebook_to_package_code(notebook_path::String)
    pkg = load_package_from_notebook(notebook_path)

    lines = String[]

    # Header
    push!(lines, "\"\"\"")
    push!(lines, "Package: $(pkg.identifier)")
    push!(lines, "Version: $(pkg.version)")
    push!(lines, "")
    push!(lines, "Auto-generated from notebook: $(basename(notebook_path))")
    push!(lines, "\"\"\"")
    push!(lines, "")

    # Module structs and compute functions
    for (name, descriptor, _) in pkg.modules
        # Generate struct
        push!(lines, "struct $(name)Module <: Module")
        push!(lines, "end")
        push!(lines, "")

        # Generate compute function signature
        push!(lines, "function compute(mod::ModuleInstance, ::Type{$(name)Module})")

        # Add helper definitions
        push!(lines, "    # Input accessors")
        push!(lines, "    get_input(name) = mod.inputs[name]")
        push!(lines, "    has_input(name) = haskey(mod.inputs, name)")
        push!(lines, "    set_output(name, value) = (mod.outputs[name] = value)")
        push!(lines, "    get_parameter(name) = mod.parameters[name]")
        push!(lines, "    has_parameter(name) = haskey(mod.parameters, name)")
        push!(lines, "")

        # Find the original code from notebook
        cells = parse_notebook(notebook_path)
        for cell in cells
            if has_directive(cell, "module") && get_directive(cell, "module") == name
                code = strip(cell.code)
                if !isempty(code)
                    push!(lines, "    # User code")
                    for code_line in split(code, '\n')
                        push!(lines, "    " * code_line)
                    end
                end
                break
            end
        end

        push!(lines, "")
        push!(lines, "    return mod.outputs")
        push!(lines, "end")
        push!(lines, "")
    end

    # Registration function
    push!(lines, "function register_$(replace(pkg.identifier, "." => "_"))!()")
    for (name, descriptor, _) in pkg.modules
        push!(lines, "    # Register $name")
        push!(lines, "    descriptor = ModuleDescriptor(")
        push!(lines, "        \"$(descriptor.package)\",")
        push!(lines, "        \"$name\",")
        push!(lines, "        $(name)Module,")

        # Input ports
        if isempty(descriptor.input_ports)
            push!(lines, "        InputPort[],")
        else
            port_strs = ["InputPort(\"$(p.name)\", $(p.type))" for p in descriptor.input_ports]
            push!(lines, "        [$(join(port_strs, ", "))],")
        end

        # Output ports
        if isempty(descriptor.output_ports)
            push!(lines, "        OutputPort[],")
        else
            port_strs = ["OutputPort(\"$(p.name)\", $(p.type))" for p in descriptor.output_ports]
            push!(lines, "        [$(join(port_strs, ", "))],")
        end

        # Parameters
        if isempty(descriptor.parameters)
            push!(lines, "        Tuple{String, Type}[]")
        else
            param_strs = ["(\"$(p[1])\", $(p[2]))" for p in descriptor.parameters]
            push!(lines, "        [$(join(param_strs, ", "))]")
        end

        push!(lines, "    )")
        push!(lines, "    register_module!(descriptor)")
        push!(lines, "")
    end
    push!(lines, "end")

    return join(lines, "\n")
end

"""
    save_package_code(notebook_path::String, output_path::String)

Convert a package notebook to Julia code and save to file.
"""
function save_package_code(notebook_path::String, output_path::String)
    code = notebook_to_package_code(notebook_path)
    open(output_path, "w") do f
        write(f, code)
    end
    println("Saved package code to: $output_path")
end

# ============================================================================
# .vt Workflow → Notebook
# ============================================================================

"""
    vistrail_workflow_to_notebook(vt_path::String, version::Int; output_path::String="") -> Dict

Convert a workflow from a .vt file to a notebook.

# Arguments
- `vt_path`: Path to the .vt file
- `version`: Version number to extract
- `output_path`: Optional path to save the notebook

# Returns
Dict representing the notebook JSON structure
"""
function vistrail_workflow_to_notebook(vt_path::String, version::Int; output_path::String="")
    # Load the vistrail
    vistrail = load_vistrail(vt_path)

    # Get the pipeline for this version
    pipeline = get_pipeline(vistrail, version)

    # Convert to notebook
    notebook = pipeline_to_notebook(pipeline, basename(vt_path), version)

    if !isempty(output_path)
        open(output_path, "w") do f
            JSON.print(f, notebook, 1)
        end
        println("Saved workflow notebook to: $output_path")
    end

    return notebook
end

"""
    pipeline_to_notebook(pipeline::Pipeline, name::String, version::Int) -> Dict

Convert a Pipeline to a notebook structure.
"""
function pipeline_to_notebook(pipeline::Pipeline, name::String, version::Int)
    cells = []

    # Title cell
    push!(cells, Dict(
        "cell_type" => "markdown",
        "metadata" => Dict(),
        "source" => ["# Workflow: $name\n", "\n", "Converted from version $version"]
    ))

    # Workflow metadata cell
    workflow_name = replace(name, r"\.vt$" => "")
    push!(cells, Dict(
        "cell_type" => "code",
        "metadata" => Dict(),
        "source" => ["#| workflow: $workflow_name"],
        "outputs" => [],
        "execution_count" => nothing
    ))

    # Create a mapping from module ID to a readable name
    id_to_name = Dict{Int, String}()
    name_counts = Dict{String, Int}()

    for (id, mod) in pipeline.modules
        base_name = lowercase(mod.descriptor.name)
        count = get(name_counts, base_name, 0) + 1
        name_counts[base_name] = count

        if count == 1
            id_to_name[id] = base_name
        else
            id_to_name[id] = "$(base_name)_$count"
        end
    end

    # Build connection map: dest_id -> [(dest_port, source_id, source_port)]
    connections_to = Dict{Int, Vector{Tuple{String, Int, String}}}()
    for conn in pipeline.connections
        if !haskey(connections_to, conn.dest_module_id)
            connections_to[conn.dest_module_id] = []
        end
        push!(connections_to[conn.dest_module_id],
              (conn.dest_port, conn.source_module_id, conn.source_port))
    end

    # Module cells (in topological order)
    execution_order = topological_sort(pipeline)

    for mod_id in execution_order
        mod = pipeline.modules[mod_id]
        mod_name = id_to_name[mod_id]

        source_lines = String[]

        # Module ID and type
        push!(source_lines, "#| module-id: $mod_name\n")

        # Determine short type reference
        type_ref = module_type_to_short_ref(mod.descriptor.package, mod.descriptor.name)
        push!(source_lines, "#| module-type: $type_ref\n")

        # Parameters
        if !isempty(mod.parameters)
            push!(source_lines, "#| params:\n")
            for (param_name, param_value) in mod.parameters
                value_str = format_param_value(param_value)
                push!(source_lines, "#|   - $param_name: $value_str\n")
            end
        end

        # Input connections
        if haskey(connections_to, mod_id) && !isempty(connections_to[mod_id])
            push!(source_lines, "#| inputs:\n")
            for (dest_port, source_id, source_port) in connections_to[mod_id]
                source_name = id_to_name[source_id]
                push!(source_lines, "#|   - $dest_port: $source_name.$source_port\n")
            end
        end

        push!(cells, Dict(
            "cell_type" => "code",
            "metadata" => Dict(),
            "source" => source_lines,
            "outputs" => [],
            "execution_count" => nothing
        ))
    end

    # Execute cell
    push!(cells, Dict(
        "cell_type" => "code",
        "metadata" => Dict(),
        "source" => ["#| execute"],
        "outputs" => [],
        "execution_count" => nothing
    ))

    return Dict(
        "cells" => cells,
        "metadata" => Dict(
            "kernelspec" => Dict(
                "display_name" => "Julia",
                "language" => "julia",
                "name" => "julia"
            )
        ),
        "nbformat" => 4,
        "nbformat_minor" => 4
    )
end

"""
    module_type_to_short_ref(package::String, name::String) -> String

Convert full package identifier to short reference.
"""
function module_type_to_short_ref(package::String, name::String)
    short_map = Dict(
        "org.vistrails.vistrails.basic" => "basic",
        "org.vistrails.vistrails.julia" => "julia",
        "org.vistrails.vistrails.control_flow" => "control_flow",
        "org.vistrails.vistrails.pythoncalc" => "pythoncalc",
    )

    short_pkg = get(short_map, package, package)
    return "$short_pkg:$name"
end

"""
    format_param_value(value) -> String

Format a parameter value for notebook output.
"""
function format_param_value(value)
    if value isa String
        # Check if it needs quoting
        if occursin(' ', value) || occursin(':', value)
            return "\"$value\""
        end
        return value
    elseif value isa Number
        return string(value)
    elseif value isa Bool
        return value ? "true" : "false"
    else
        return repr(value)
    end
end
