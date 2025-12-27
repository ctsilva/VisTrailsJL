"""
Module base types and functionality.

Modules are the computational units in a VisTrails workflow.
"""

"""
ModuleError

Error type for module execution failures.
Compatible with Python VisTrails' ModuleError.
"""
struct ModuleError <: Exception
    module_instance::Union{Any, Nothing}  # Will be ModuleInstance after it's defined
    message::String

    ModuleError(mod, msg::String) = new(mod, msg)
    ModuleError(msg::String) = new(nothing, msg)
end

function Base.showerror(io::IO, e::ModuleError)
    if e.module_instance !== nothing
        print(io, "ModuleError in $(e.module_instance.descriptor.name): $(e.message)")
    else
        print(io, "ModuleError: $(e.message)")
    end
end

"""
PortSpec

Port specification from workflow XML.
Defines a port for a specific module instance (not the generic module type).
"""
struct PortSpec
    name::String            # Port name (e.g., "a", "b", "value")
    port_type::Symbol       # :input or :output
    sort_key::Int          # Order for rendering (important!)
    optional::Bool
    signature::String      # Type signature (e.g., "Integer", "Float")
end

"""
ModuleDescriptor

Describes a module type (like a class definition).
Registered in the module registry.
"""
struct ModuleDescriptor
    package::String          # e.g., "org.vistrails.vistrails.basic"
    name::String            # e.g., "HTTPFile"
    module_type::Type       # Julia type
    input_ports::Vector{InputPort}
    output_ports::Vector{OutputPort}
    parameters::Vector{Tuple{String, Type}}  # (name, type) pairs
end

"""
Module (abstract)

Base type for all executable modules.
Subtype this to create new module types.
"""
abstract type Module end

"""
ModuleInstance

Runtime instance of a module in a workflow.
"""
mutable struct ModuleInstance
    id::Int
    descriptor::ModuleDescriptor
    inputs::Dict{String, Any}
    outputs::Dict{String, Any}
    parameters::Dict{String, Any}
    annotations::Dict{String, String}  # key-value pairs like "__desc__" => "a (integer)"
    port_specs::Vector{PortSpec}  # Instance-specific port definitions from workflow XML
    cache_state::Symbol  # :invalid, :valid, :computing
    uptodate::Bool
    layout_position::Union{Tuple{Float64, Float64}, Nothing}  # (x, y) from .vt file

    function ModuleInstance(id::Int, descriptor::ModuleDescriptor)
        new(id, descriptor,
            Dict{String, Any}(),
            Dict{String, Any}(),
            Dict{String, Any}(),
            Dict{String, String}(),
            PortSpec[],  # No port specs initially
            :invalid,
            false,
            nothing)  # layout_position starts as nothing
    end
end

# Module operations

"""
    set_input!(mod::ModuleInstance, port_name::String, value::Any)

Set an input value on a module.
"""
function set_input!(mod::ModuleInstance, port_name::String, value::Any)
    mod.inputs[port_name] = value
    mod.cache_state = :invalid
    mod.uptodate = false
end

"""
    set_parameter!(mod::ModuleInstance, param_name::String, value::Any)

Set a parameter value on a module.
"""
function set_parameter!(mod::ModuleInstance, param_name::String, value::Any)
    mod.parameters[param_name] = value
    mod.cache_state = :invalid
    mod.uptodate = false
end

"""
    get_output(mod::ModuleInstance, port_name::String)

Get an output value from a module.
"""
function get_output(mod::ModuleInstance, port_name::String)
    return mod.outputs[port_name]
end

# Display
function Base.show(io::IO, mod::ModuleInstance)
    print(io, "ModuleInstance(id=$(mod.id), type=$(mod.descriptor.name))")
end
