"""
Example: Loading Original .vt Files

This demonstrates loading and inspecting a VisTrails .vt file using Julia.
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using VisTrailsJL

println("=" ^ 60)
println("Example: Loading .vt File")
println("=" ^ 60)

# Path to a .vt file
# Update this path to point to an actual .vt file
vt_file = joinpath(@__DIR__, "..", "..", "examples", "gcd.vt")

if !isfile(vt_file)
    println("\nError: File not found: $vt_file")
    println("\nPlease update the vt_file path in this script to point to a valid .vt file.")
    exit(1)
end

println("\nLoading $vt_file...")

try
    # Load the vistrail
    vt = load_vistrail(vt_file)

    # Print vistrail information
    print_vistrail_info(vt)

    # Get the latest pipeline
    if !isempty(vt.pipelines)
        latest_version = vt.current_version
        pipeline = get_pipeline(vt, latest_version)

        # Print pipeline information
        print_pipeline_info(pipeline)

        # Try to execute if possible
        if !isempty(pipeline.modules)
            println("\n" * "=" ^ 60)
            println("Attempting to Execute Pipeline")
            println("=" ^ 60)

            try
                results = execute_pipeline(pipeline)

                println("\n✓ Execution complete!")
                println("\nResults:")
                for (mod_id, outputs) in results
                    println("  Module $mod_id:")
                    for (port, value) in outputs
                        println("    $port = ", repr(value)[1:min(100, length(repr(value)))])
                    end
                end
            catch e
                println("\n✗ Execution failed: $e")
                println("\nThis is expected if the required modules are not yet implemented.")
            end
        end
    else
        println("\nNo pipelines found in vistrail.")
    end

    println("\n✓ Example complete!")

catch e
    println("\nError loading vistrail: $e")
    println("\nStack trace:")
    showerror(stdout, e, catch_backtrace())
    println()
end
