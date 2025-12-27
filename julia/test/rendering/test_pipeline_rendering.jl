"""
Test pipeline rendering
"""

# Load VisTrailsJL module
include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL


println("=" ^ 70)
println("Testing Pipeline Rendering")
println("=" ^ 70)

# Load a workflow with layout positions
vt_file = joinpath(@__DIR__, "..", "..", "..", "examples", "gcd.vt")
println("\nLoading $vt_file...")
vt = load_vistrail(vt_file)

println("\nVistrail Info:")
println("  Total versions: ", length(vt.actions))
println("  Current version: ", vt.current_version)

# Get pipeline for current version
if haskey(vt.pipelines, vt.current_version)
    pipeline = vt.pipelines[vt.current_version]

    println("\nPipeline Info:")
    println("  Modules: ", length(pipeline.modules))
    println("  Connections: ", length(pipeline.connections))

    # Check for layout positions
    positioned_count = count(m -> m.layout_position !== nothing, values(pipeline.modules))
    println("  Modules with positions: $positioned_count / $(length(pipeline.modules))")

    if positioned_count > 0
        # Render pipeline
        println("\nRendering pipeline to SVG...")
        svg = render_pipeline_svg(pipeline,
                                   width=1200,
                                   height=900,
                                   module_width=140.0,
                                   module_height=70.0,
                                   port_size=6.0,
                                   margin=40.0)

        output_file = joinpath(@__DIR__, "gcd_workflow_new.svg")
        write(output_file, svg)
        println("✓ Saved to: $output_file")

        # Stats
        println("\nSVG Stats:")
        println("  Size: ", length(svg), " bytes")
        println("  Modules rendered: ", count(r"<rect class=\"module\"", svg))
        println("  Connections rendered: ", count(r"<path class=\"connection\"", svg))
    else
        println("\n⚠️  No layout positions found in pipeline")
    end
else
    println("\n⚠️  No pipeline loaded for current version")
end
