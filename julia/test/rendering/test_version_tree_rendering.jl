"""
Test version tree SVG rendering
"""

# Load VisTrailsJL module
include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL


println("=" ^ 60)
println("Testing Version Tree SVG Rendering")
println("=" ^ 60)

vt_file = joinpath(@__DIR__, "..", "..", "..", "examples", "gcd.vt")

println("\nLoading $vt_file...")
vt = load_vistrail(vt_file)

println("\nVistrail info:")
println("  Total versions: ", length(vt.actions))
println("  Tags: ", length(vt.tags))
println("  Current version: ", vt.current_version)

# Render version tree to SVG with terse graph
println("\nRendering version tree to SVG (with terse graph)...")
println()

output_file = joinpath(@__DIR__, "gcd_version_tree.svg")

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

println()

println("  SVG size: ", length(svg), " bytes")

# Save to file
write(output_file, svg)

println("✓ Saved version tree SVG to: $output_file")

# Report some stats
line_count = count(c -> c == '\n', svg)
println("  Lines: $line_count")

# Count SVG elements
ellipse_count = length(collect(eachmatch(r"<ellipse", svg)))
line_elem_count = length(collect(eachmatch(r"<line", svg)))

println("  Ellipses (versions): $ellipse_count")
println("  Lines (edges): $line_elem_count")

println("\n✓ Test completed successfully!")
