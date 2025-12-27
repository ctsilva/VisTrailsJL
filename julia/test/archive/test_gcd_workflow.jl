"""
Test GCD workflow using workflow element (fallback from action replay)
"""

using Pkg
Pkg.activate(@__DIR__)

using VisTrailsJL

println("=" ^ 60)
println("Testing GCD Workflow from Workflow Element")
println("=" ^ 60)

vt_file = joinpath(@__DIR__, "..", "examples", "gcd.vt")

println("\nLoading $vt_file...")

# Temporarily disable action replay by requesting a non-existent version
# This will force fallback to workflow element
vt = load_vistrail(vt_file)

pipeline = vt.pipelines[vt.current_version]

print_pipeline_info(pipeline)

println("\n" * "=" ^ 60)
println("Executing Pipeline")
println("=" ^ 60)

try
    results = execute_pipeline(pipeline)

    println("\n✓ Execution complete!")
    println("\nResults:")
    for (mod_id, outputs) in sort(collect(results), by=first)
        mod_name = pipeline.modules[mod_id].descriptor.name
        println("  Module $mod_id ($mod_name):")
        for (port, value) in outputs
            val_str = repr(value)
            println("    $port = ", val_str[1:min(100, length(val_str))])
        end
    end
catch e
    println("\n✗ Execution failed: $e")
    println("\nStack trace:")
    showerror(stdout, e, catch_backtrace())
    println()
end
