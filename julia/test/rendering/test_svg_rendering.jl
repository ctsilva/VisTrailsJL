"""
Test SVG rendering of workflows with existing layout positions
"""

# Load VisTrailsJL module
include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("=" ^ 60)
println("Testing SVG Rendering with Existing Positions")
println("=" ^ 60)

vt_file = joinpath(@__DIR__, "..", "..", "..", "examples", "gcd.vt")

println("\nLoading $vt_file...")

# Load the vistrail (uses workflow element fallback for version 134)
vt = load_vistrail(vt_file)

pipeline = get_pipeline(vt, vt.current_version)

println("\nPipeline info:")
println("  Modules: ", length(pipeline.modules))
println("  Connections: ", length(pipeline.connections))

# Check how many modules have positions
positioned = count(m -> m.layout_position !== nothing, values(pipeline.modules))
println("  Modules with positions: $positioned / $(length(pipeline.modules))")

if positioned > 0
    # Show sample positions
    println("\nSample positions:")
    for (i, (id, mod)) in enumerate(pipeline.modules)
        if mod.layout_position !== nothing
            x, y = mod.layout_position
            println("  Module $id ($(mod.descriptor.name)): ($x, $y)")
            if i >= 5
                break
            end
        end
    end

    # Render to SVG
    println("\n" * "=" ^ 60)
    println("Rendering to SVG")
    println("=" ^ 60)

    output_file = "gcd_workflow.svg"

    try
        save_pipeline_svg(pipeline, output_file,
                         width=1000,
                         height=800,
                         module_width=140.0,
                         module_height=70.0)

        println("\n✓ SVG rendering complete!")
        println("  Open $output_file in a web browser to view")

        # Also print the SVG to see it
        svg = render_pipeline_svg(pipeline, width=1000, height=800)
        println("\nGenerated SVG length: ", length(svg), " characters")

    catch e
        println("\n✗ SVG rendering failed: $e")
        showerror(stdout, e, catch_backtrace())
    end
else
    println("\n⚠ No layout positions found - cannot render")
    println("  This can happen if modules were deleted in version history")
end
