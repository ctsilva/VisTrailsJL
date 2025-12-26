using VisTrailsJL

println("Loading lung.vt...")
vt = load_vistrail("../examples/lung.vt")

println("Current version: ", vt.current_version)
pipeline = get(vt.pipelines, vt.current_version, nothing)

if pipeline !== nothing
    println("Modules: ", length(pipeline.modules))
    println("Connections: ", length(pipeline.connections))
    positioned = sum(1 for (id, m) in pipeline.modules if m.layout_position !== nothing)
    println("Positioned modules: ", positioned, " / ", length(pipeline.modules))

    if positioned > 0
        println("\nRendering to SVG...")
        svg = render_pipeline_svg(pipeline, width=1800, height=1400, module_width=120.0, module_height=60.0, port_size=6.0, margin=80.0)
        write("lung_workflow.svg", svg)
        println("✓ Saved to lung_workflow.svg")
    else
        println("ERROR: No modules have layout positions")
    end
else
    println("ERROR: No pipeline found for current version")
end
