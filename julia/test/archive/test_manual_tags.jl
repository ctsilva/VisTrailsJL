"""
Test tag rendering with manually created tags
"""

using Pkg
Pkg.activate(@__DIR__)

using VisTrailsJL

# Load a vistrail
vt_file = joinpath(@__DIR__, "..", "examples", "gcd.vt")
println("Loading $vt_file...")
vt = load_vistrail(vt_file)

println("\nOriginal vistrail:")
println("  Versions: ", length(vt.actions))
println("  Tags: ", length(vt.tags))

# Manually add some tags for testing
println("\nAdding test tags...")
push!(vt.tags, VisTrailsJL.Tag("Initial", 1))
push!(vt.tags, VisTrailsJL.Tag("Branch Point", 71))
push!(vt.tags, VisTrailsJL.Tag("Final", 134))

println("  Tags: ", length(vt.tags))
for tag in vt.tags
    println("    - \"$(tag.name)\" -> version $(tag.version_id)")
end

# Generate SVG
println("\nGenerating version tree with tags...")
svg = render_version_tree_svg(vt,
                               width=1200,
                               height=800,
                               use_terse_graph=true,
                               show_stats=true)

# Save
output_file = joinpath(@__DIR__, "gcd_with_manual_tags.svg")
write(output_file, svg)
println("\n✓ Saved to: $output_file")

# Check if tags appear in SVG
println("\nChecking SVG for tag labels...")
for tag in vt.tags
    if occursin(tag.name, svg)
        println("  ✓ Found tag \"$(tag.name)\" in SVG")
    else
        println("  ❌ Tag \"$(tag.name)\" NOT in SVG (version $(tag.version_id) might be hidden)")
    end
end
