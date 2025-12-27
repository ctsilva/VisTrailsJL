"""
Vector Operations for Control Flow Package

Implements list/vector operations: Sum, Cross, Dot, ElementwiseProduct
"""

# Module types
struct SumModule end
struct CrossModule end
struct DotModule end
struct ElementwiseProductModule end

"""
Register all vector operation modules.
"""
function register_vector_ops!()
    # Sum - sum all elements in a list
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.control_flow",
        "Sum",
        SumModule,
        [InputPort("InputList", Vector)],
        [OutputPort("Result", Float64)],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)

    # Cross - cross product of two 3-element vectors
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.control_flow",
        "Cross",
        CrossModule,
        [
            InputPort("v1", Vector),
            InputPort("v2", Vector)
        ],
        [OutputPort("Result", Vector)],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)

    # Dot - dot product of two vectors
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.control_flow",
        "Dot",
        DotModule,
        [
            InputPort("v1", Vector),
            InputPort("v2", Vector)
        ],
        [OutputPort("Result", Float64)],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)

    # ElementwiseProduct - element-wise product of two lists
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.control_flow",
        "ElementwiseProduct",
        ElementwiseProductModule,
        [
            InputPort("v1", Vector),
            InputPort("v2", Vector)
        ],
        [OutputPort("Result", Vector)],
        [("NumericalProduct", Bool)]
    )
    register_module!(descriptor)

    @info "Registered vector operation modules: Sum, Cross, Dot, ElementwiseProduct"
end

"""
Compute function for Sum - sum all elements in a list.

Example: Sum([1, 2, 3]) = 6
"""
function compute(mod::ModuleInstance, ::Type{SumModule})
    input_list = mod.inputs["InputList"]

    if isempty(input_list)
        mod.outputs["Result"] = 0.0
    else
        # Convert to numbers and sum
        result = sum(Float64(x) for x in input_list)
        mod.outputs["Result"] = result
    end

    return mod.outputs
end

"""
Compute function for Cross - cross product of two 3-element vectors.

Example: Cross([1, 2, -1], [0, 2, 5]) = [12, -5, 2]

The cross product formula for vectors u = [u1, u2, u3] and v = [v1, v2, v3] is:
u × v = [u2*v3 - u3*v2, u3*v1 - u1*v3, u1*v2 - u2*v1]
"""
function compute(mod::ModuleInstance, ::Type{CrossModule})
    v1 = mod.inputs["v1"]
    v2 = mod.inputs["v2"]

    # Validate inputs are 3-element vectors
    if length(v1) != 3
        throw(ModuleError(mod, "v1 must be a 3-element vector, got length $(length(v1))"))
    end
    if length(v2) != 3
        throw(ModuleError(mod, "v2 must be a 3-element vector, got length $(length(v2))"))
    end

    # Convert to Float64 for computation
    u1, u2, u3 = Float64(v1[1]), Float64(v1[2]), Float64(v1[3])
    w1, w2, w3 = Float64(v2[1]), Float64(v2[2]), Float64(v2[3])

    # Cross product: u × v = [u2*v3 - u3*v2, u3*v1 - u1*v3, u1*v2 - u2*v1]
    result = [
        u2 * w3 - u3 * w2,
        u3 * w1 - u1 * w3,
        u1 * w2 - u2 * w1
    ]

    mod.outputs["Result"] = result
    return mod.outputs
end

"""
Compute function for Dot - dot product of two vectors.

Example: Dot([2, 0, -1], [4, 2, 3]) = 2*4 + 0*2 + (-1)*3 = 8 + 0 - 3 = 5

The dot product is the sum of element-wise products.
"""
function compute(mod::ModuleInstance, ::Type{DotModule})
    v1 = mod.inputs["v1"]
    v2 = mod.inputs["v2"]

    # Validate same length
    if length(v1) != length(v2)
        throw(ModuleError(mod, "Vectors must have the same length: v1 has $(length(v1)), v2 has $(length(v2))"))
    end

    # Compute dot product: sum of element-wise products
    result = 0.0
    for i in 1:length(v1)
        result += Float64(v1[i]) * Float64(v2[i])
    end

    mod.outputs["Result"] = result
    return mod.outputs
end

"""
Compute function for ElementwiseProduct - element-wise product of two lists.

If NumericalProduct is true (default), outputs element-wise multiplication:
Example: ElementwiseProduct([1, 2, 3], [2, 0, -1]) = [2, 0, -3]

If NumericalProduct is false, outputs element-wise tuples:
Example: ElementwiseProduct([1, 2, 3], [2, 0, -1]) = [(1, 2), (2, 0), (3, -1)]
"""
function compute(mod::ModuleInstance, ::Type{ElementwiseProductModule})
    v1 = mod.inputs["v1"]
    v2 = mod.inputs["v2"]
    numerical = get(mod.parameters, "NumericalProduct", true)

    # Validate same length
    if length(v1) != length(v2)
        throw(ModuleError(mod, "Vectors must have the same length: v1 has $(length(v1)), v2 has $(length(v2))"))
    end

    if numerical
        # Numerical product: element-wise multiplication
        result = [Float64(v1[i]) * Float64(v2[i]) for i in 1:length(v1)]
    else
        # Tuple product: element-wise pairing
        result = [(v1[i], v2[i]) for i in 1:length(v1)]
    end

    mod.outputs["Result"] = result
    return mod.outputs
end
