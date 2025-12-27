"""
Test pipeline rendering on lung.vt "Texture with Shading" workflow
"""

using Pkg
Pkg.activate(@__DIR__)

using VisTrailsJL

println("=" ^ 70)
println("Testing Lung.vt Workflow Rendering")
println("=" ^ 70)

# Load lung.vt
vt_file = joinpath(@__DIR__, "..", "examples", "lung.vt")
println("\nLoading $vt_file...")
vt = load_vistrail(vt_file)

println("\nVistrail Info:")
println("  Total versions: ", length(vt.actions))
println("  Tags: ", length(vt.tags))

# Find "First" tag (simpler workflow without VTK dependencies)
global target_tag = nothing
for tag in vt.tags
    if tag.name == "First"
        global target_tag = tag
        break
    end
end

if target_tag === nothing
    println("\n❌ Tag 'First' not found!")
    println("\nAvailable tags:")
    for tag in vt.tags
        println("  - \"$(tag.name)\" (version $(tag.version_id))")
    end
    exit(1)
end

println("\n✓ Found tag: \"$(target_tag.name)\" -> version $(target_tag.version_id)")

# Load that specific version
println("\nLoading version $(target_tag.version_id)...")
vt_tagged = load_vistrail(vt_file, version=target_tag.version_id)

# Check if pipeline was loaded
if haskey(vt_tagged.pipelines, target_tag.version_id)
    pipeline = vt_tagged.pipelines[target_tag.version_id]

    println("\nPipeline Info:")
    println("  Modules: ", length(pipeline.modules))
    println("  Connections: ", length(pipeline.connections))

    # Check for layout positions
    positioned_count = count(m -> m.layout_position !== nothing, values(pipeline.modules))
    println("  Modules with positions: $positioned_count / $(length(pipeline.modules))")

    if positioned_count > 0
        println("\nModule details:")
        for (id, mod) in pipeline.modules
            if mod.layout_position !== nothing
                println("  Module $id: $(mod.descriptor.name) at $(mod.layout_position)")
            end
        end

        # Render pipeline
        println("\n" * "=" ^ 70)
        println("Rendering Pipeline to SVG")
        println("=" ^ 70)

        svg = render_pipeline_svg(pipeline,
                                   width=1400,
                                   height=1000,
                                   module_width=150.0,
                                   module_height=80.0,
                                   port_size=7.0,
                                   margin=50.0)

        output_file = joinpath(@__DIR__, "lung_texture_shading_workflow.svg")
        write(output_file, svg)
        println("\n✓ Saved to: $output_file")

        # Stats
        println("\nSVG Stats:")
        println("  Size: ", length(svg), " bytes")
        println("  Modules rendered: ", count(r"<rect class=\"module\"", svg))
        println("  Connections rendered: ", count(r"<path class=\"connection\"", svg))

    else
        println("\n⚠️  No layout positions found in pipeline")
    end
else
    println("\n⚠️  Pipeline not loaded for version $(target_tag.version_id)")
    println("     This version might not have a <workflow> element in the XML")
end
