"""
Test GCD workflow - version 100 (full implementation)
"""

using Pkg
Pkg.activate(@__DIR__)

using VisTrailsJL

println("=" ^ 60)
println("Testing GCD Workflow (Version 100)")
println("=" ^ 60)

vt_file = joinpath(@__DIR__, "..", "examples", "gcd.vt")

println("\nLoading $vt_file (version 100)...")

try
    # Load version 100 specifically
    vt = load_vistrail(vt_file, version=100)

    println("\n" * "=" ^ 60)
    println("Version Information")
    println("=" ^ 60)
    println("Total actions: ", length(vt.actions))
    println("Current version: ", vt.current_version)

    # Get the pipeline
    pipeline = get_pipeline(vt, 100)

    # Print pipeline information
    print_pipeline_info(pipeline)

    # Try to execute
    println("\n" * "=" ^ 60)
    println("Executing Pipeline")
    println("=" ^ 60)

    try
        results = execute_pipeline(pipeline)

        println("\n✓ Execution complete!")
        println("\nResults:")
        for (mod_id, outputs) in sort(collect(results), by=first)
            println("  Module $mod_id:")
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

catch e
    println("\nError: $e")
    println("\nStack trace:")
    showerror(stdout, e, catch_backtrace())
    println()
end
