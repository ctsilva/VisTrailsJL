"""
Debug PythonCalc parameters
"""

# Load VisTrailsJL module
include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

vt_file = joinpath(@__DIR__, "..", "..", "..", "examples", "gcd.vt")

println("Loading version 100...")
vt = load_vistrail(vt_file, version=100)

pipeline = get_pipeline(vt, 100)

println("\nPythonCalc modules and their parameters:")
for (mid, mod) in pipeline.modules
    if mod.descriptor.name == "PythonCalc"
        println("Module $mid (PythonCalc):")
        println("  Parameters: ", mod.parameters)
        println("  Descriptor params: ", [p[1] for p in mod.descriptor.parameters])
    end
end
