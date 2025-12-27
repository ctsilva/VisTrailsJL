"""
Test loading and executing lineplot_ex3.vt from matplotlib examples

This is the simplest matplotlib example workflow.
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("="^70)
println("Testing lineplot_ex3.vt from matplotlib examples")
println("="^70)

# Load the .vt file
println("\n1. Loading lineplot_ex3.vt...")
vt_path = joinpath(@__DIR__, "..", "..", "..", "examples", "matplotlib", "lineplot_ex3.vt")
vt = load_vistrail(vt_path)

println("   ✓ Loaded workflow: $(vt.name)")
println("   Current version: $(vt.current_version)")
println("   Total versions: $(length(vt.actions))")

# Get the current pipeline
println("\n2. Extracting pipeline from version $(vt.current_version)...")
try
    pipeline = get_pipeline(vt, vt.current_version)

    println("   ✓ Pipeline extracted")
    println("   Modules: $(length(pipeline.modules))")
    println("   Connections: $(length(pipeline.connections))")

    # Show what modules are in the pipeline
    println("\n3. Pipeline modules:")
    for (id, mod) in sort(collect(pipeline.modules), by=x->x[1])
        pkg = mod.descriptor.package
        name = mod.descriptor.name
        println("      [$id] $pkg::$name")
    end

    # Show connections
    println("\n4. Pipeline connections:")
    for conn in pipeline.connections
        src = pipeline.modules[conn.source_module_id]
        dst = pipeline.modules[conn.dest_module_id]
        println("      $(src.descriptor.name).$(conn.source_port) → $(dst.descriptor.name).$(conn.dest_port)")
    end

    # Try to execute
    println("\n5. Attempting to execute pipeline...")
    results, workflow_exec = execute_pipeline(pipeline)

    println("   ✓ Pipeline executed!")

    # Check for output
    if isfile("matplotlib_output.png")
        println("\n✅ SUCCESS: Matplotlib figure generated!")
        println("   Output: matplotlib_output.png")
        println("   Size: $(filesize("matplotlib_output.png")) bytes")
    else
        println("\n⚠️  No output file found, but execution completed")
    end

catch e
    println("\n❌ ERROR during pipeline extraction or execution:")
    println("   $(typeof(e)): $e")

    if isa(e, ErrorException) && occursin("Module not found", string(e))
        println("\n   This is expected - matplotlib modules need data to work properly.")
        println("   The .vt file likely has parameters/data embedded that we need to extract.")
    else
        println("\n   Stack trace:")
        showerror(stdout, e, catch_backtrace())
    end
end

println("\n" * "="^70)
println("Test complete!")
println("="^70)
