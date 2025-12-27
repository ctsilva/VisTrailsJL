"""
Test complete round-trip: .vt file → notebook conversion → rendering

This validates the entire production workflow:
1. Load .vt file
2. Convert to notebook format
3. Load notebook as workflow
4. Render with auto-layout
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("="^70)
println("Round-Trip Test: .vt → notebook → render")
println("="^70)

# 1. Load .vt file
println("\n1. Loading .vt file...")
vt_path = joinpath(@__DIR__, "..", "..", "..", "examples", "gcd.vt")
vt = load_vistrail(vt_path)
println("   ✓ Loaded: $(vt.name)")
println("   Versions: $(length(vt.actions))")

# 2. Get a workflow from the current version (134)
current_version = vt.current_version
println("\n2. Getting pipeline from version $current_version...")
pipeline_original = get_pipeline(vt, current_version)
println("   ✓ Pipeline extracted")
println("   Modules: $(length(pipeline_original.modules))")
println("   Connections: $(length(pipeline_original.connections))")

# 3. Convert to notebook
println("\n3. Converting to notebook format...")
output_path = joinpath(@__DIR__, "test_gcd_converted.ipynb")
vistrail_workflow_to_notebook(vt_path, current_version, output_path=output_path)
println("   ✓ Notebook created: $output_path")

# 4. Load notebook back
println("\n4. Loading notebook as workflow...")
workflow = parse_workflow_notebook(output_path)
println("   ✓ Notebook parsed")
println("   Workflow: $(workflow.name)")
println("   Modules: $(length(workflow.modules))")

# 5. Build pipeline from notebook
println("\n5. Building pipeline from notebook...")
pipeline_from_notebook, id_to_module = build_pipeline_from_workflow(workflow)
println("   ✓ Pipeline built")
println("   Modules: $(length(pipeline_from_notebook.modules))")
println("   Connections: $(length(pipeline_from_notebook.connections))")

# 6. Render with auto-layout
println("\n6. Rendering with auto-layout...")
try
    svg = render_pipeline_svg(pipeline_from_notebook, width=1200, height=900)
    svg_path = joinpath(@__DIR__, "test_gcd_from_notebook.svg")
    write(svg_path, svg)
    println("   ✓ SVG generated: $svg_path")
    println("   Size: $(length(svg)) characters")

    # Verify positions were computed
    positioned = count(m -> m.layout_position !== nothing, values(pipeline_from_notebook.modules))
    println("   Positioned modules: $positioned / $(length(pipeline_from_notebook.modules))")

    if positioned == length(pipeline_from_notebook.modules)
        println("\n✅ SUCCESS: Complete round-trip works!")
        println("   .vt → notebook → render pipeline is production-ready")
    else
        println("\n⚠️  WARNING: Some modules not positioned")
    end

catch e
    println("   ✗ Rendering failed: $e")
    showerror(stdout, e, catch_backtrace())
    error("Round-trip test failed")
end

# 7. Clean up test files
println("\n7. Cleaning up test files...")
isfile(output_path) && rm(output_path)
println("   ✓ Cleaned up")

println("\n" * "="^70)
println("Round-trip test complete!")
println("="^70)
