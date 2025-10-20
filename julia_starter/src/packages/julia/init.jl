"""
Julia Package Initialization

Registers Julia-specific modules (JuliaSource, etc.)
"""

include("JuliaSource.jl")

"""
    initialize_julia_package!()

Register all modules in the julia package.
"""
function initialize_julia_package!()
    println("Initializing julia package...")

    register_juliasource!()

    println("  ✓ Julia package initialized")
end
