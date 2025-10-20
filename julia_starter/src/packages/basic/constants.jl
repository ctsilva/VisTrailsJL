"""
Constant Value Modules

Basic constant types: Integer, Float, String, Boolean
"""

# Module types
struct IntegerModule end
struct FloatModule end
struct StringModule end
struct BooleanModule end

"""
Register all constant modules.
"""
function register_constants!()
    # Integer
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",
        "Integer",
        IntegerModule,
        InputPort[],
        [OutputPort("value", Int)],
        [("value", Int)]
    )
    register_module!(descriptor)

    # Float
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",
        "Float",
        FloatModule,
        InputPort[],
        [OutputPort("value", Float64)],
        [("value", Float64)]
    )
    register_module!(descriptor)

    # String
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",
        "String",
        StringModule,
        InputPort[],
        [OutputPort("value", String)],
        [("value", String)]
    )
    register_module!(descriptor)

    # Boolean
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",
        "Boolean",
        BooleanModule,
        InputPort[],
        [OutputPort("value", Bool)],
        [("value", Bool)]
    )
    register_module!(descriptor)

    @info "Registered constant modules: Integer, Float, String, Boolean"
end

"""
Compute function for Integer - returns value from parameter OR input.
"""
function compute(mod::ModuleInstance, ::Type{IntegerModule})
    # Check if there's an input connection (pass-through mode)
    if !isempty(mod.inputs)
        # Get the first non-nothing input
        value = nothing
        for (k, v) in mod.inputs
            if v !== nothing
                value = v
                break
            end
        end

        if value !== nothing && value isa String
            value = parse(Int, value)
        end
    # Otherwise use parameter
    elseif haskey(mod.parameters, "value")
        value = mod.parameters["value"]
        # Convert string to Int if needed (from XML parsing)
        if value isa String
            value = parse(Int, value)
        end
    else
        # No input and no parameter - default to 0
        value = 0
    end

    mod.outputs["value"] = value
    return mod.outputs
end

"""
Compute function for Float - just returns the value parameter.
"""
function compute(mod::ModuleInstance, ::Type{FloatModule})
    value = mod.parameters["value"]
    # Convert string to Float64 if needed (from XML parsing)
    if value isa String
        value = parse(Float64, value)
    end
    mod.outputs["value"] = value
    return mod.outputs
end

"""
Compute function for String - just returns the value parameter.
"""
function compute(mod::ModuleInstance, ::Type{StringModule})
    mod.outputs["value"] = String(mod.parameters["value"])
    return mod.outputs
end

"""
Compute function for Boolean - just returns the value parameter.
"""
function compute(mod::ModuleInstance, ::Type{BooleanModule})
    value = mod.parameters["value"]
    # Convert string to Bool if needed (from XML parsing)
    if value isa String
        value = lowercase(value) in ["true", "1", "yes"]
    end
    mod.outputs["value"] = Bool(value)
    return mod.outputs
end
