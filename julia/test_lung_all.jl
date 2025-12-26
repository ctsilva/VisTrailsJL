using VisTrailsJL

println("Loading lung.vt...")
vt = load_vistrail("../examples/lung.vt")

println("\nTotal versions in vistrail: ", length(vt.pipelines))
println("Current version: ", vt.current_version)

# Find the largest pipeline
largest_version = nothing
largest_size = 0
largest_positioned = 0

for (version, pipeline) in vt.pipelines
    num_modules = length(pipeline.modules)
    positioned = sum(1 for (id, m) in pipeline.modules if m.layout_position !== nothing)
    
    if num_modules > largest_size
        largest_size = num_modules
        largest_version = version
        largest_positioned = positioned
    end
    
    if num_modules > 0
        println("  Version $version: $num_modules modules, $positioned positioned")
    end
end

println("\n" * "="^70)
println("Largest pipeline:")
println("  Version: $largest_version")
println("  Modules: $largest_size")
println("  Positioned: $largest_positioned")
println("="^70)

if largest_version !== nothing && largest_positioned > 0
    pipeline = vt.pipelines[largest_version]
    println("\nRendering version $largest_version to SVG...")
    svg = render_pipeline_svg(pipeline, width=1800, height=1400, module_width=120.0, module_height=60.0, port_size=6.0, margin=80.0)
    write("lung_workflow.svg", svg)
    println("✓ Saved to lung_workflow.svg")
else
    println("\nERROR: No positioned modules found in any pipeline")
end
