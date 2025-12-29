"""
Test: describe_module() function

Test module introspection functionality.
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("="^70)
println("Module Introspection Test")
println("="^70)

# First, load the datatools package
println("\n1. Loading datatools package...")
pkg_path = joinpath(@__DIR__, "..", "..", "examples", "packages", "datatools.ipynb")
pkg = load_package_from_notebook(pkg_path)
register_notebook_package!(pkg)
println("   ✓ Package registered")

# Test describe_module with different modules
println("\n2. Testing describe_module()...\n")

# Test custom package module
describe_module("datatools:CSVParser")

println()

# Test built-in module
describe_module("basic:HTTPFile")

println()

# Test matplotlib module
describe_module("matplotlib:MplLinePlot")

println("\n" * "="^70)
println("✅ Module introspection working!")
println("="^70)
