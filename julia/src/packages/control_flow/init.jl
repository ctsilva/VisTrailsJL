"""
Control Flow Package

Conditional and looping constructs: If, While, And, Or, Not
Vector operations: Sum, Cross, Dot, ElementwiseProduct
"""

include("conditionals.jl")
include("vector_ops.jl")

"""
    initialize_control_flow_package!()

Register all modules in the control flow package.
"""
function initialize_control_flow_package!()
    println("Initializing control_flow package...")

    register_conditionals!()
    register_vector_ops!()

    println("  ✓ Control flow package initialized")
end
