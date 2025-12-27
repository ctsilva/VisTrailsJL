"""
Package Loader

Loads VisTrails packages from Jupyter notebooks.
Package notebooks define module types with `#|` directives.
"""

"""
    NotebookPackage

Package definition loaded from a notebook.
"""
struct NotebookPackage
    identifier::String
    version::String
    modules::Vector{Tuple{String, ModuleDescriptor, Function}}  # (name, descriptor, compute_fn)
end

"""
    load_package_from_notebook(path::String) -> NotebookPackage

Load a package from a Jupyter notebook.

The notebook should contain:
- A cell with `#| package-meta` and `#| identifier: ...`, `#| version: ...`
- Cells with `#| module: ModuleName` followed by port definitions and compute code
"""
function load_package_from_notebook(path::String)
    cells = parse_notebook(path)

    identifier = "unknown"
    version = "1.0.0"

    # Find package metadata
    for cell in cells
        if has_directive(cell, "package-meta")
            identifier = string(get_directive(cell, "identifier", identifier))
            version = string(get_directive(cell, "version", version))
            break
        end
    end

    modules = Tuple{String, ModuleDescriptor, Function}[]

    # Find module definitions
    for cell in cells
        if has_directive(cell, "module")
            module_name = string(get_directive(cell, "module"))

            input_ports = parse_input_port_specs(get_directive(cell, "input_ports", []))
            output_ports = parse_output_port_specs(get_directive(cell, "output_ports", []))

            # Create descriptor (use Nothing as placeholder type - we dispatch differently)
            descriptor = ModuleDescriptor(
                identifier,
                module_name,
                Nothing,
                input_ports,
                output_ports,
                Tuple{String, Type}[]
            )

            # Create compute function from code
            compute_fn = create_compute_function(cell.code)

            push!(modules, (module_name, descriptor, compute_fn))
        end
    end

    return NotebookPackage(identifier, version, modules)
end

"""
    parse_input_port_specs(specs) -> Vector{InputPort}

Parse input port specifications from directive data.
"""
function parse_input_port_specs(specs)
    ports = InputPort[]
    for spec in specs
        if spec isa Dict
            name = string(get(spec, "name", "unnamed"))
            sig = string(get(spec, "signature", "basic:Any"))
            optional = get(spec, "optional", false)
            label = string(get(spec, "label", ""))

            julia_type = signature_to_type(sig)
            push!(ports, InputPort(name, julia_type, optional=optional, label=label))
        end
    end
    return ports
end

"""
    parse_output_port_specs(specs) -> Vector{OutputPort}

Parse output port specifications from directive data.
"""
function parse_output_port_specs(specs)
    ports = OutputPort[]
    for spec in specs
        if spec isa Dict
            name = string(get(spec, "name", "unnamed"))
            sig = string(get(spec, "signature", "basic:Any"))
            label = string(get(spec, "label", ""))

            julia_type = signature_to_type(sig)
            push!(ports, OutputPort(name, julia_type, label=label))
        end
    end
    return ports
end

"""
    signature_to_type(sig::String) -> Type

Convert VisTrails type signature to Julia type.
"""
function signature_to_type(sig::AbstractString)
    sig = String(sig)
    # Handle package:Type format
    type_name = occursin(":", sig) ? String(split(sig, ":")[end]) : sig

    type_map = Dict(
        "Integer" => Int,
        "Int" => Int,
        "Float" => Float64,
        "String" => String,
        "Boolean" => Bool,
        "Bool" => Bool,
        "Any" => Any,
        "List" => Vector,
    )

    return get(type_map, type_name, Any)
end

"""
    create_compute_function(code::String) -> Function

Create a compute function from notebook cell code.
Returns a closure that takes a ModuleInstance and executes the code.
"""
function create_compute_function(code::String)
    code = strip(code)
    if isempty(code)
        return function(mod::ModuleInstance)
            return mod.outputs
        end
    end

    # Parse all expressions as a single block
    block_code = "begin\n$code\nend"
    block_expr = Meta.parse(block_code)

    # Return a closure that will be called during execution
    return function(mod::ModuleInstance)
        # Set up helper functions
        get_input = (name) -> mod.inputs[name]
        has_input = (name) -> haskey(mod.inputs, name)
        set_output = (name, value) -> (mod.outputs[name] = value)
        get_parameter = (name) -> mod.parameters[name]
        has_parameter = (name) -> haskey(mod.parameters, name)

        # Wrap the block in a let that provides the helpers
        wrapper = Expr(:let,
            Expr(:block,
                Expr(:(=), :get_input, get_input),
                Expr(:(=), :has_input, has_input),
                Expr(:(=), :set_output, set_output),
                Expr(:(=), :get_parameter, get_parameter),
                Expr(:(=), :has_parameter, has_parameter),
            ),
            block_expr
        )
        eval(wrapper)

        return mod.outputs
    end
end

# Global storage for notebook compute functions
const NOTEBOOK_COMPUTE_FUNCTIONS = Dict{Tuple{String, String}, Function}()

"""
    register_notebook_package!(pkg::NotebookPackage)

Register all modules from a notebook package in the global registry.
"""
function register_notebook_package!(pkg::NotebookPackage)
    println("Registering notebook package: $(pkg.identifier) v$(pkg.version)")

    # Auto-register package short name (last component of identifier)
    # e.g., "org.vistrails.vistrails.branching" → "branching"
    parts = split(pkg.identifier, ".")
    if length(parts) > 0
        short_name = String(parts[end])
        register_package_short_name!(short_name, pkg.identifier)
    end

    for (name, descriptor, compute_fn) in pkg.modules
        # Store the compute function for lookup during execution
        NOTEBOOK_COMPUTE_FUNCTIONS[(pkg.identifier, name)] = compute_fn

        # Register the module descriptor
        register_module!(descriptor)

        println("  ✓ Registered module: $name")
    end

    println("Package $(pkg.identifier) registered with $(length(pkg.modules)) modules")
end

"""
    get_notebook_compute(package::String, name::String) -> Union{Function, Nothing}

Get the compute function for a notebook-defined module.
"""
function get_notebook_compute(package::String, name::String)
    return get(NOTEBOOK_COMPUTE_FUNCTIONS, (package, name), nothing)
end

"""
    is_notebook_module(package::String, name::String) -> Bool

Check if a module was defined in a notebook.
"""
function is_notebook_module(package::String, name::String)
    return haskey(NOTEBOOK_COMPUTE_FUNCTIONS, (package, name))
end
