"""
Module Registry

Central registry for all available module types.
Similar to Python VisTrails' module_registry.py
"""

# Global registry: (package, name) -> ModuleDescriptor
const MODULE_REGISTRY = Dict{Tuple{String, String}, ModuleDescriptor}()

"""
    register_module!(descriptor::ModuleDescriptor)

Register a module type in the global registry.
"""
function register_module!(descriptor::ModuleDescriptor)
    key = (descriptor.package, descriptor.name)

    if haskey(MODULE_REGISTRY, key)
        @warn "Module $(descriptor.package)::$(descriptor.name) already registered, overwriting"
    end

    MODULE_REGISTRY[key] = descriptor

    @info "Registered module: $(descriptor.package)::$(descriptor.name)"
end

"""
    get_module_descriptor(package::String, name::String) -> ModuleDescriptor

Look up a module descriptor in the registry.
"""
function get_module_descriptor(package::String, name::String)
    key = (package, name)

    if !haskey(MODULE_REGISTRY, key)
        error("Module not found in registry: $(package)::$(name)")
    end

    return MODULE_REGISTRY[key]
end

"""
    list_modules() -> Vector{Tuple{String, String}}

List all registered modules as (package, name) tuples.
"""
function list_modules()
    return collect(keys(MODULE_REGISTRY))
end

"""
    list_modules_by_package(package::String) -> Vector{String}

List all module names for a given package.
"""
function list_modules_by_package(package::String)
    modules = String[]

    for ((pkg, name), _) in MODULE_REGISTRY
        if pkg == package
            push!(modules, name)
        end
    end

    return modules
end

"""
    module_exists(package::String, name::String) -> Bool

Check if a module is registered.
"""
function module_exists(package::String, name::String)
    return haskey(MODULE_REGISTRY, (package, name))
end

"""
    describe_module(type_ref::String)
    describe_module(package::String, name::String)

Display information about a module including its input ports, output ports, and parameters.

# Examples
```julia
describe_module("datatools:CSVParser")
describe_module("org.vistrails.vistrails.datatools", "CSVParser")
```
"""
function describe_module(type_ref::String)
    # Parse "package:ModuleName" format
    if occursin(":", type_ref)
        parts = split(type_ref, ":")
        package_short = String(parts[1])
        name = String(parts[2])

        # Map short names to full package identifiers
        # Try common short names first
        short_name_map = Dict(
            "basic" => "org.vistrails.vistrails.basic",
            "julia" => "org.vistrails.vistrails.julia",
            "control_flow" => "org.vistrails.vistrails.control_flow",
            "pythoncalc" => "org.vistrails.vistrails.pythoncalc",
            "matplotlib" => "org.vistrails.vistrails.matplotlib",
            "datatools" => "org.vistrails.vistrails.datatools"
        )

        package = get(short_name_map, package_short, package_short)
    else
        error("Invalid module reference: $type_ref (expected format: package:ModuleName)")
    end

    describe_module(package, name)
end

function describe_module(package::String, name::String)
    if !module_exists(package, name)
        error("Module not found: $(package)::$(name)")
    end

    descriptor = get_module_descriptor(package, name)

    println("=" ^ 70)
    println("Module: $name")
    println("Package: $package")
    println("=" ^ 70)

    # Input ports
    if !isempty(descriptor.input_ports)
        println("\nInput Ports:")
        for port in descriptor.input_ports
            optional_str = port.optional ? " (optional)" : ""
            label_str = !isempty(port.label) ? " - $(port.label)" : ""
            println("  • $(port.name) :: $(port.type)$optional_str$label_str")
        end
    else
        println("\nInput Ports: (none)")
    end

    # Output ports
    if !isempty(descriptor.output_ports)
        println("\nOutput Ports:")
        for port in descriptor.output_ports
            label_str = !isempty(port.label) ? " - $(port.label)" : ""
            println("  • $(port.name) :: $(port.type)$label_str")
        end
    else
        println("\nOutput Ports: (none)")
    end

    # Parameters
    if !isempty(descriptor.parameters)
        println("\nParameters:")
        for (param_name, param_type) in descriptor.parameters
            println("  • $param_name :: $param_type")
        end
    else
        println("\nParameters: (none)")
    end

    println("=" ^ 70)
end

# Display registered modules
function print_registry()
    println("=" ^ 60)
    println("Module Registry")
    println("=" ^ 60)

    packages = Dict{String, Vector{String}}()

    for ((pkg, name), _) in MODULE_REGISTRY
        if !haskey(packages, pkg)
            packages[pkg] = String[]
        end
        push!(packages[pkg], name)
    end

    for (pkg, modules) in sort(collect(packages))
        println("\n", pkg, ":")
        for name in sort(modules)
            println("  - ", name)
        end
    end
end
