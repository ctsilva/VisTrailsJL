"""
Test tag loading and display
"""

using Pkg
Pkg.activate(@__DIR__)

using VisTrailsJL

vt_file = joinpath(@__DIR__, "..", "examples", "terminator.vt")
println("Loading $vt_file...")
vt = load_vistrail(vt_file)

println("\nVistrail Info:")
println("  Total versions: ", length(vt.actions))
println("  Total tags: ", length(vt.tags))
println("  Current version: ", vt.current_version)

if !isempty(vt.tags)
    println("\nTags:")
    for tag in vt.tags
        println("  - \"$(tag.name)\" -> version $(tag.version_id)")
    end
else
    println("\n⚠️  No tags loaded!")
end

# Generate terse graph with stats
println("\n" * "=" ^ 60)
println("Generating Version Tree SVG with Tags")
println("=" ^ 60)

svg = render_version_tree_svg(vt,
                               width=1200,
                               height=800,
                               use_terse_graph=true,
                               show_stats=true)

# Save
output_file = joinpath(@__DIR__, "terminator_with_tags.svg")
write(output_file, svg)
println("\n✓ Saved to: $output_file")

# Check if tags appear in SVG
if !isempty(vt.tags)
    println("\nChecking SVG for tag names...")
    for tag in vt.tags
        if occursin(tag.name, svg)
            println("  ✓ Found tag \"$(tag.name)\" in SVG")
        else
            println("  ❌ Tag \"$(tag.name)\" NOT in SVG")
        end
    end
end
