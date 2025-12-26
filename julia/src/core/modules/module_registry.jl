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
