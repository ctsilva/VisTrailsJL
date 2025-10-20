"""
Analyze version tree structure in gcd.vt
"""

using Pkg
Pkg.activate(@__DIR__)

using VisTrailsJL

println("=" ^ 60)
println("Analyzing Version Tree Structure")
println("=" ^ 60)

vt_file = joinpath(@__DIR__, "..", "examples", "gcd.vt")

println("\nLoading $vt_file...")

vt = load_vistrail(vt_file)

println("\nVistrail info:")
println("  Total versions (actions): ", length(vt.actions))
println("  Tags: ", length(vt.tags))
println("  Current version: ", vt.current_version)

# Analyze parent-child relationships
println("\n" * "=" ^ 60)
println("Version Tree Structure")
println("=" ^ 60)

# Build parent -> children map
children = Dict{Int, Vector{Int}}()
parents = Dict{Int, Int}()

for (id, action) in vt.actions
    parent_id = action.prev_id

    if parent_id > 0
        if !haskey(children, parent_id)
            children[parent_id] = Int[]
        end
        push!(children[parent_id], id)
        parents[id] = parent_id
    end
end

# Find root (version with no parent)
roots = [id for id in keys(vt.actions) if !haskey(parents, id)]
println("Root versions: ", roots)

# Count tree properties
total_nodes = length(vt.actions)
max_depth = 0
max_children = 0

function compute_depth(id, current_depth=0)
    global max_depth
    max_depth = max(max_depth, current_depth)

    if haskey(children, id)
        for child_id in children[id]
            compute_depth(child_id, current_depth + 1)
        end
    end
end

for root in roots
    compute_depth(root)
end

for (parent_id, child_list) in children
    global max_children; max_children = max(max_children, length(child_list))
end

println("\nTree statistics:")
println("  Total nodes: ", total_nodes)
println("  Max depth: ", max_depth)
println("  Max children per node: ", max_children)

# Show first few levels
println("\n" * "=" ^ 60)
println("Tree Structure (first 3 levels)")
println("=" ^ 60)

function print_tree(id, indent=0, max_level=3)
    if indent > max_level
        return
    end

    action = vt.actions[id]
    tag_str = ""
    for tag in vt.tags
        if tag.version_id == id
            tag_str = " [$(tag.name)]"
        end
    end

    println("  " ^ indent, "Version $id", tag_str, " ($(action.timestamp))")

    if haskey(children, id)
        for child_id in sort(children[id])
            print_tree(child_id, indent + 1, max_level)
        end
    end
end

for root in roots
    print_tree(root)
end

# Check for tags
println("\n" * "=" ^ 60)
println("Tagged Versions")
println("=" ^ 60)

if isempty(vt.tags)
    println("No tags found")
else
    for tag in vt.tags
        println("  $(tag.name): version $(tag.version_id)")
    end
end

# Analyze branching
println("\n" * "=" ^ 60)
println("Branching Points")
println("=" ^ 60)

branch_points = filter(p -> length(p.second) > 1, collect(children))
sort!(branch_points, by=p -> p.first)

if isempty(branch_points)
    println("No branching (linear history)")
else
    println("Found $(length(branch_points)) branching points:")
    for (parent_id, child_ids) in branch_points[1:min(5, length(branch_points))]
        println("  Version $parent_id -> $(length(child_ids)) children: $child_ids")
    end
end
