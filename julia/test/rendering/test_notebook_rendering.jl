"""
Test: Can we render a notebook-defined workflow to SVG?

This tests the critical workflow: notebook → pipeline → SVG
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("="^70)
println("Testing Notebook Workflow Rendering")
println("="^70)

# Use the data_analysis example which uses only built-in modules
notebook_path = joinpath(@__DIR__, "..", "..", "examples", "data_analysis_workflow.ipynb")
println("\n1. Loading workflow from: $notebook_path")
workflow = parse_workflow_notebook(notebook_path)
println("   ✓ Workflow loaded: $(workflow.name)")
println("   Modules: $(length(workflow.modules))")

# Build pipeline
println("\n2. Building pipeline...")
pipeline, id_to_module = build_pipeline_from_workflow(workflow)
println("   ✓ Pipeline built")
println("   Modules: $(length(pipeline.modules))")
println("   Connections: $(length(pipeline.connections))")

# Check if modules have positions
println("\n3. Checking module positions...")
positioned = count(m -> m.layout_position !== nothing, values(pipeline.modules))
println("   Positioned modules: $positioned / $(length(pipeline.modules))")

if positioned == 0
    println("   ⚠ No layout positions - using automatic layout")

    # Use Graphviz to compute layout
    println("\n4. Computing automatic layout with Graphviz...")
    try
        auto_layout_pipeline!(pipeline, algorithm="dot")
        positioned_after = count(m -> m.layout_position !== nothing, values(pipeline.modules))
        println("   ✓ Auto-layout complete!")
        println("   Positioned modules: $positioned_after / $(length(pipeline.modules))")
    catch e
        println("   ✗ Auto-layout failed: $e")
        rethrow(e)
    end
end

# Render to SVG
println("\n5. Rendering to SVG...")
try
    svg = render_pipeline_svg(pipeline, width=1200, height=900)
    println("   ✓ SVG generated!")
    println("   Length: $(length(svg)) characters")

    # Save it
    output_file = joinpath(@__DIR__, "notebook_workflow_auto_layout.svg")
    write(output_file, svg)
    println("   ✓ Saved to: $output_file")

    println("\n✅ SUCCESS: Notebook workflow can be rendered with auto-layout!")

catch e
    println("   ✗ Rendering failed: $e")
    showerror(stdout, e, catch_backtrace())
    error("Rendering failed")
end

println("\n" * "="^70)
println("Test complete!")
println("="^70)
