"""
Test terse graph on multiple VisTrails files
"""

using Pkg
Pkg.activate(@__DIR__)

using VisTrailsJL

# Test files
test_files = [
    "gcd.vt",
    "plot.vt",
    "terminator.vt",
    "vtk.vt"
]

examples_dir = joinpath(@__DIR__, "..", "examples")

for vt_filename in test_files
    vt_file = joinpath(examples_dir, vt_filename)

    if !isfile(vt_file)
        println("\n❌ File not found: $vt_filename")
        continue
    end

    println("\n" * "=" ^ 70)
    println("Testing: $vt_filename")
    println("=" ^ 70)

    try
        # Load vistrail
        vt = load_vistrail(vt_file)

        println("\nBasic Info:")
        println("  Total versions: ", length(vt.actions))
        println("  Tags: ", length(vt.tags))
        println("  Current version: ", vt.current_version)

        # Render with terse graph
        println("\nGenerating terse graph...")
        output_file = joinpath(@__DIR__, replace(vt_filename, ".vt" => "_terse.svg"))

        svg = render_version_tree_svg(vt,
                                       width=1200,
                                       height=800,
                                       node_width=100.0,
                                       node_height=50.0,
                                       min_horizontal_separation=30.0,
                                       min_vertical_separation=80.0,
                                       margin=50.0,
                                       use_terse_graph=true,
                                       show_stats=true)

        # Save SVG
        write(output_file, svg)
        println("\n✓ Saved to: ", basename(output_file))

        # Count SVG elements
        ellipse_count = length(collect(eachmatch(r"<ellipse", svg)))
        line_count = length(collect(eachmatch(r"<line", svg)))
        collapsed_count = length(collect(eachmatch(r"version-edge-collapsed", svg)))

        println("  SVG stats:")
        println("    Nodes: $ellipse_count")
        println("    Edges: $line_count")
        println("    Collapsed edges: $collapsed_count")

    catch e
        println("\n❌ Error processing $vt_filename:")
        println("  ", sprint(showerror, e))
    end
end

println("\n" * "=" ^ 70)
println("Testing Complete!")
println("=" ^ 70)
