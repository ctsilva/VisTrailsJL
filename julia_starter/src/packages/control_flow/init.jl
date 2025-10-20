"""
Control Flow Package

Conditional and looping constructs: If, While, And, Or, Not
"""

include("conditionals.jl")

"""
    initialize_control_flow_package!()

Register all modules in the control flow package.
"""
function initialize_control_flow_package!()
    println("Initializing control_flow package...")

    register_conditionals!()

    println("  ✓ Control flow package initialized")
end
