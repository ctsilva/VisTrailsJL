"""
PythonCalc Package

Python-based calculations and expressions.
"""

include("PythonCalc.jl")

"""
    initialize_pythoncalc_package!()

Register all modules in the pythoncalc package.
"""
function initialize_pythoncalc_package!()
    println("Initializing pythoncalc package...")

    register_pythoncalc!()

    println("  ✓ PythonCalc package initialized")
end
