"""
Debug terse graph generation
"""

using Pkg
Pkg.activate(@__DIR__)

using VisTrailsJL

vt_file = joinpath(@__DIR__, "..", "examples", "gcd.vt")
println("Loading $vt_file...")
vt = load_vistrail(vt_file)

println("\n" * "=" ^ 60)
println("Analyzing Version Tree Structure")
println("=" ^ 60)

# Load the terse_graph module
include("src/rendering/terse_graph.jl")

# Generate terse graph
terse = generate_terse_graph(vt)

println("\nVisible versions: ", sort(collect(terse.visible_versions)))
println("\nTerse edges:")
for (parent, children) in sort(collect(terse.edges))
    for (child, has_hidden) in children
        marker = has_hidden ? " (has hidden)" : ""
        println("  $parent -> $child$marker")
    end
end

# Check for the specific versions
println("\n" * "=" ^ 60)
println("Version Details")
println("=" ^ 60)

for v_id in sort(collect(terse.visible_versions))
    if v_id == 0
        println("\nVersion 0: ROOT")
    else
        action = vt.actions[v_id]
        parent = action.prev_id === nothing ? 0 : action.prev_id
        println("\nVersion $v_id:")
        println("  Parent: $parent")

        # Check if it's current
        if v_id == vt.current_version
            println("  ** CURRENT VERSION **")
        end

        # Check children in full graph
        full_graph = build_parent_child_graph(vt)
        children = get(full_graph, v_id, Int[])
        if !isempty(children)
            println("  Children: $children")
            if length(children) > 1
                println("  ** BRANCH POINT **")
            end
        else
            println("  ** LEAF VERSION **")
        end
    end
end
