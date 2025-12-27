"""
Test pipeline rendering improvements on gcd.vt workflow
"""

# Load VisTrailsJL module
include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL


println("=" ^ 70)
println("Testing Pipeline Rendering")
println("=" ^ 70)

# Load gcd.vt (current version has full workflow with positions)
vt_file = joinpath(@__DIR__, "..", "..", "..", "examples", "gcd.vt")
println("\nLoading $vt_file...")
vt = load_vistrail(vt_file)

println("\nVistrail Info:")
println("  Current version: ", vt.current_version)

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
        println("\n" * "=" ^ 70)
        println("Rendering Pipeline to SVG")
        println("=" ^ 70)

        svg = render_pipeline_svg(pipeline,
                                   width=1800,
                                   height=1400,
                                   module_width=120.0,
                                   module_height=60.0,
                                   port_size=6.0,
                                   margin=80.0)

        output_file = joinpath(@__DIR__, "gcd_workflow.svg")
        write(output_file, svg)
        println("\n✓ Saved to: $output_file")

        # Stats
        println("\nSVG Stats:")
        println("  Size: ", length(svg), " bytes")
        println("  Modules rendered: ", count(r"<rect class=\"module\"", svg))
        println("  Connections rendered: ", count(r"<path class=\"connection\"", svg))

        # Sample module for debugging port positions
        println("\n" * "=" ^ 70)
        println("Sample Module Details (for debugging):")
        println("=" ^ 70)
        for (id, mod) in pipeline.modules
            if length(mod.descriptor.input_ports) > 0 && length(mod.descriptor.output_ports) > 0
                println("\nModule $id: $(mod.descriptor.name)")
                println("  Position: $(mod.layout_position)")
                println("  Input ports: ", length(mod.descriptor.input_ports))
                for (i, port) in enumerate(mod.descriptor.input_ports)
                    println("    $i: $(port.name) ($(port.type))")
                end
                println("  Output ports: ", length(mod.descriptor.output_ports))
                for (i, port) in enumerate(mod.descriptor.output_ports)
                    println("    $i: $(port.name) ($(port.type))")
                end
                break  # Just show one example
            end
        end

        # Sample connection for debugging
        println("\n" * "=" ^ 70)
        println("Sample Connection Details (for debugging):")
        println("=" ^ 70)
        if length(pipeline.connections) > 0
            conn = first(pipeline.connections)
            println("\nConnection:")
            println("  Source: module $(conn.source_module_id), port '$(conn.source_port)'")
            println("  Dest: module $(conn.dest_module_id), port '$(conn.dest_port)'")

            if haskey(pipeline.modules, conn.source_module_id)
                src_mod = pipeline.modules[conn.source_module_id]
                println("  Source module: $(src_mod.descriptor.name)")
                println("    Output ports: ", [p.name for p in src_mod.descriptor.output_ports])
            end

            if haskey(pipeline.modules, conn.dest_module_id)
                dst_mod = pipeline.modules[conn.dest_module_id]
                println("  Dest module: $(dst_mod.descriptor.name)")
                println("    Input ports: ", [p.name for p in dst_mod.descriptor.input_ports])
            end
        end

    else
        println("\n⚠️  No layout positions found in pipeline")
    end
else
    println("\n⚠️  Pipeline not loaded")
end
