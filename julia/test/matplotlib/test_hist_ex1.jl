"""
Test matplotlib histogram example: hist_ex1.vt

This should work immediately with our current implementation.
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("="^70)
println("Testing hist_ex1.vt")
println("="^70)

# Load the .vt file
vt_path = joinpath(@__DIR__, "..", "..", "..", "examples", "matplotlib", "hist_ex1.vt")
println("\nLoading: $vt_path")

vt = load_vistrail(vt_path)
println("✓ Loaded vistrail")
println("  Current version: $(vt.current_version)")

# Get the pipeline
pipeline = get_pipeline(vt, vt.current_version)
println("\n✓ Got pipeline")
println("  Modules: $(length(pipeline.modules))")
println("  Connections: $(length(pipeline.connections))")

# Show module details
println("\nModule details:")
for (id, mod) in pipeline.modules
    mod_type = mod.descriptor.module_type
    println("  - ID $id: $mod_type")

    # Show parameters
    if !isempty(mod.parameters)
        println("    Parameters:")
        for (param_name, param_val) in mod.parameters
            println("      $param_name = $param_val")
        end
    end
end

# Execute the pipeline
println("\nExecuting pipeline...")
try
    results, workflow_exec = execute_pipeline(pipeline)

    println("\n✓ Execution completed!")

    # Check for output file
    if isfile("matplotlib_output.png")
        filesize = stat("matplotlib_output.png").size
        println("\n✅ SUCCESS!")
        println("  Generated: matplotlib_output.png")
        println("  File size: $filesize bytes")
    else
        println("\n⚠️  Execution completed but no output file found")
    end

catch e
    println("\n❌ FAILED!")
    println("Error: $e")
    showerror(stdout, e, catch_backtrace())
    rethrow(e)
end

println("\n" * "="^70)
