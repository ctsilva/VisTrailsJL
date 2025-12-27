"""
Port types for VisTrails modules.

Ports define the inputs and outputs of modules.
"""

abstract type Port end

"""
InputPort

Defines an input port on a module.
"""
struct InputPort <: Port
    name::String
    type::Type
    optional::Bool
    default::Union{Nothing, Any}
    label::String

    InputPort(name::String, type::Type=Any; optional::Bool=false, default=nothing, label::String="") =
        new(name, type, optional, default, label)
end

"""
OutputPort

Defines an output port on a module.
"""
struct OutputPort <: Port
    name::String
    type::Type
    label::String

    OutputPort(name::String, type::Type=Any; label::String="") = new(name, type, label)
end

# Utility functions
function Base.show(io::IO, port::InputPort)
    print(io, "InputPort($(port.name)::$(port.type))")
end

function Base.show(io::IO, port::OutputPort)
    print(io, "OutputPort($(port.name)::$(port.type))")
end
