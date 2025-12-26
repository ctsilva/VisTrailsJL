"""
Data Structure Modules

Tuple, Untuple, List modules for handling collections.
"""

# Module types
struct TupleModule end
struct UntupleModule end
struct ListModule end
struct RoundModule end

"""
Register all data structure modules.
"""
function register_datastructures!()
    # Tuple - creates a tuple from inputs
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",
        "Tuple",
        TupleModule,
        InputPort[],  # Dynamic inputs
        [OutputPort("value", Tuple)],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)

    # Untuple - extracts elements from a tuple
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",
        "Untuple",
        UntupleModule,
        InputPort[],  # Dynamic inputs
        OutputPort[],  # Dynamic outputs
        Tuple{String, Type}[]
    )
    register_module!(descriptor)

    # List - creates a list from inputs
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",
        "List",
        ListModule,
        InputPort[],  # Dynamic inputs
        [OutputPort("value", Vector)],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)

    # Round - rounds a number
    # Python source: vistrails/core/modules/basic_modules.py
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",
        "Round",
        RoundModule,
        [
            InputPort("in_value", Float64),
            InputPort("floor", Bool, optional=true, default=true)
        ],
        [OutputPort("out_value", Int)],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)

    @info "Registered data structure modules: Tuple, Untuple, List, Round"
end

"""
Compute function for Tuple - creates a tuple from all inputs.
"""
function compute(mod::ModuleInstance, ::Type{TupleModule})
    # Collect all inputs in order
    inputs = []

    # Check numbered inputs (in0, in1, in2, ...)
    i = 0
    while haskey(mod.inputs, "in$i")
        push!(inputs, mod.inputs["in$i"])
        i += 1
    end

    # If no numbered inputs, collect all inputs
    if isempty(inputs)
        inputs = collect(values(mod.inputs))
    end

    mod.outputs["value"] = tuple(inputs...)
    return mod.outputs
end

"""
Compute function for Untuple - extracts tuple elements to outputs.
"""
function compute(mod::ModuleInstance, ::Type{UntupleModule})
    # Get the first (and should be only) input
    if isempty(mod.inputs)
        @warn "Untuple: No input provided"
        return mod.outputs
    end

    input_tuple = first(values(mod.inputs))

    # Convert to tuple if it's a vector
    if input_tuple isa Vector
        input_tuple = tuple(input_tuple...)
    end

    # Set named outputs based on tuple size (a, b, c, ... or numbered)
    # Try to match the expected output names
    if length(input_tuple) == 2
        # Common case: tuple of 2 elements -> a, b
        mod.outputs["a"] = input_tuple[1]
        mod.outputs["b"] = input_tuple[2]
    else
        # General case: numbered outputs
        for (i, val) in enumerate(input_tuple)
            mod.outputs["out$(i-1)"] = val
        end
    end

    return mod.outputs
end

"""
Compute function for List - creates a vector from all inputs.
"""
function compute(mod::ModuleInstance, ::Type{ListModule})
    # Collect all inputs
    inputs = []

    # Check numbered inputs (in0, in1, in2, ...)
    i = 0
    while haskey(mod.inputs, "in$i")
        push!(inputs, mod.inputs["in$i"])
        i += 1
    end

    # If no numbered inputs, collect all inputs
    if isempty(inputs)
        inputs = collect(values(mod.inputs))
    end

    mod.outputs["value"] = inputs
    return mod.outputs
end

"""
Compute function for Round - rounds a number to nearest integer.
"""
function compute(mod::ModuleInstance, ::Type{RoundModule})
    # Get the first input (should be a number)
    if isempty(mod.inputs)
        @warn "Round: No input provided"
        return mod.outputs
    end

    input_val = first(values(mod.inputs))
    result = round(Int, input_val)

    # Set output with the same name as the first output port in connections
    # Default to "out_value" which is common in VisTrails
    mod.outputs["out_value"] = result

    return mod.outputs
end
