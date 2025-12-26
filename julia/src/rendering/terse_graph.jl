###############################################################################
##
## Copyright (C) 2014-2016, New York University.
## Copyright (C) 2011-2014, NYU-Poly.
## Copyright (C) 2006-2011, University of Utah.
## All rights reserved.
## Contact: contact@vistrails.org
##
## This file implements terse graph generation for version trees.
##
###############################################################################
"""
Terse Graph Generation

Generates a simplified version tree that hides linear chain versions,
showing only:
- Root version (0)
- Tagged versions
- Branch points (versions with multiple children)
- Merge points (versions with multiple parents - rare)
- Leaf versions (no children)
- Current version

This dramatically improves readability of long linear histories.
"""

"""
    TerseGraph

Simplified graph showing only key versions.

Fields:
- `visible_versions::Set{Int}` - Version IDs to show
- `edges::Dict{Int, Vector{Tuple{Int, Bool}}}` - parent -> [(child, has_hidden_versions)]
"""
struct TerseGraph
    visible_versions::Set{Int}
    edges::Dict{Int, Vector{Tuple{Int, Bool}}}
end

"""
    build_parent_child_graph(vistrail)

Build full parent-child graph from vistrail actions.
Returns Dict{Int, Vector{Int}} mapping parent_id -> [child_ids]
"""
function build_parent_child_graph(vistrail)
    graph = Dict{Int, Vector{Int}}()

    for (id, action) in vistrail.actions
        parent = action.prev_id === nothing ? 0 : action.prev_id

        if !haskey(graph, parent)
            graph[parent] = Int[]
        end
        push!(graph[parent], id)
    end

    return graph
end

"""
    find_next_visible_descendants(start_id, full_graph, visible_versions)

Follow the graph from start_id until finding visible version(s).
Returns Vector{Tuple{Int, Bool}} of (visible_descendant_id, has_hidden_between)
"""
function find_next_visible_descendants(start_id::Int,
                                       full_graph::Dict{Int, Vector{Int}},
                                       visible_versions::Set{Int})
    results = Tuple{Int, Bool}[]
    visited = Set{Int}()

    # BFS to find next visible descendants
    queue = [(start_id, false)]  # (current_id, has_hidden)

    while !isempty(queue)
        (current_id, has_hidden) = popfirst!(queue)

        if current_id in visited
            continue
        end
        push!(visited, current_id)

        children = get(full_graph, current_id, Int[])

        for child in children
            if child in visible_versions
                # Found a visible descendant
                push!(results, (child, has_hidden || current_id != start_id))
            else
                # Keep searching through hidden version
                push!(queue, (child, true))
            end
        end
    end

    return results
end

"""
    generate_terse_graph(vistrail)

Generate a terse (simplified) version tree graph.

Includes only:
- Root (version 0)
- Current version
- All tagged versions
- Branch points (>1 child)
- Merge points (>1 parent - rare in VisTrails)
- Leaf versions (no children)

Returns TerseGraph with visible versions and edges.
"""
function generate_terse_graph(vistrail)
    visible_versions = Set{Int}()

    # Build full parent-child graph
    full_graph = build_parent_child_graph(vistrail)

    # Always include root
    push!(visible_versions, 0)

    # Always include current version
    if vistrail.current_version != 0
        push!(visible_versions, vistrail.current_version)
    end

    # Collect tagged version IDs for quick lookup
    tagged_ids = Set{Int}()
    for tag in vistrail.tags
        push!(tagged_ids, tag.version_id)
        push!(visible_versions, tag.version_id)
    end

    # Collect all children across the graph
    all_children = Set{Int}()
    for (parent, children) in full_graph
        for child in children
            push!(all_children, child)
        end
    end

    # Include branch points (versions with multiple children)
    # But only include immediate children if they are tagged or themselves branch points
    for (parent, children) in full_graph
        if length(children) > 1
            push!(visible_versions, parent)
            # Only include immediate children if they meet special criteria
            for child in children
                # Include child if it's:
                # 1. Tagged
                # 2. Current version
                # 3. A leaf (no children)
                # 4. Itself a branch point
                if (child in tagged_ids) ||
                   (child == vistrail.current_version) ||
                   (!(child in keys(full_graph)) || isempty(full_graph[child])) ||
                   (haskey(full_graph, child) && length(full_graph[child]) > 1)
                    push!(visible_versions, child)
                end
            end
        end
    end

    # Count parents for each version (for merge points)
    parent_counts = Dict{Int, Int}()
    for (parent, children) in full_graph
        for child in children
            parent_counts[child] = get(parent_counts, child, 0) + 1
        end
    end

    # Include merge points (versions with multiple parents)
    for (child, parent_count) in parent_counts
        if parent_count > 1
            push!(visible_versions, child)
        end
    end

    # Include leaf versions (no children)
    for (id, action) in vistrail.actions
        if !(id in all_children)
            push!(visible_versions, id)
        end
    end

    # Build terse graph edges
    terse_edges = Dict{Int, Vector{Tuple{Int, Bool}}}()

    for v in visible_versions
        terse_edges[v] = []

        # Get immediate children from full graph
        children = get(full_graph, v, Int[])

        for child in children
            if child in visible_versions
                # Direct edge to visible child
                push!(terse_edges[v], (child, false))
            else
                # Skip hidden versions to find next visible descendant(s)
                descendants = find_next_visible_descendants(child, full_graph, visible_versions)
                for (desc_id, has_hidden) in descendants
                    push!(terse_edges[v], (desc_id, true))  # Mark as having hidden versions
                end
            end
        end
    end

    return TerseGraph(visible_versions, terse_edges)
end

"""
    print_terse_graph_stats(vistrail, terse_graph)

Print statistics about the terse graph.
"""
function print_terse_graph_stats(vistrail, terse_graph)
    total_versions = length(vistrail.actions) + 1  # +1 for root
    visible_count = length(terse_graph.visible_versions)
    hidden_count = total_versions - visible_count

    # Count edges with hidden versions
    edges_with_hidden = 0
    total_edges = 0
    for (parent, children) in terse_graph.edges
        for (child, has_hidden) in children
            total_edges += 1
            if has_hidden
                edges_with_hidden += 1
            end
        end
    end

    println("Terse Graph Statistics:")
    println("  Total versions: $total_versions")
    println("  Visible versions: $visible_count ($hidden_count hidden)")
    println("  Reduction: $(round((1 - visible_count/total_versions) * 100, digits=1))%")
    println("  Total edges: $total_edges")
    println("  Edges with hidden versions: $edges_with_hidden")

    # Show what's included
    tagged_count = length(vistrail.tags)
    println("\nVisible versions include:")
    println("  - Root version (0)")
    println("  - Current version ($(vistrail.current_version))")
    println("  - Tagged versions: $tagged_count")

    # Count branch points
    branch_count = 0
    for (parent, children) in terse_graph.edges
        if length(children) > 1
            branch_count += 1
        end
    end
    println("  - Branch points: $branch_count")

    # Count leaves
    all_children = Set{Int}()
    for (parent, children) in terse_graph.edges
        for (child, _) in children
            push!(all_children, child)
        end
    end
    leaf_count = 0
    for v in terse_graph.visible_versions
        if !(v in all_children) && v != 0
            leaf_count += 1
        end
    end
    println("  - Leaf versions: $leaf_count")
end
