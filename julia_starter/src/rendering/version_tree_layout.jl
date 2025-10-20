###############################################################################
##
## Copyright (C) 2014-2016, New York University.
## Copyright (C) 2011-2014, NYU-Poly.
## Copyright (C) 2006-2011, University of Utah.
## All rights reserved.
## Contact: contact@vistrails.org
##
## This file is a Julia translation of the VisTrails version tree layout code.
##
###############################################################################
"""
Interface Vistrails - TreeLayoutLW to align version trees.
Originally written by Lauro D. Lins.

Translated to Julia from vistrails/core/layout/version_tree_layout.py
"""

# tree_layout.jl is already included by main module

"""
    text_width_function(text::String)::Float64

Default text width function (placeholder).
Override with actual text measurement in GUI context.
"""
function default_text_width(text::String)::Float64
    return length(text) * 7.0  # Approximate character width
end

"""
    VistrailsTreeLayoutLW

Adapter to generate tree layout for VisTrails version histories.
"""
struct VistrailsTreeLayoutLW
    text_width_f::Function
    text_height::Float64
    text_horizontal_margin::Float64
    text_vertical_margin::Float64
    nodes::Dict{Int, Any}  # Map from version ID to node info
    width::Float64
    height::Float64
    scale::Float64

    function VistrailsTreeLayoutLW(text_width_f::Function,
                                   text_height::Float64,
                                   text_horizontal_margin::Float64,
                                   text_vertical_margin::Float64)
        new(text_width_f, text_height, text_horizontal_margin,
            text_vertical_margin, Dict{Int, Any}(), 0.0, 0.0, 0.0)
    end
end

"""
    generate_tree_lw(layout::VistrailsTreeLayoutLW, vistrail, graph)

Generate TreeLW from vistrail and graph structure.
"""
function generate_tree_lw(layout::VistrailsTreeLayoutLW, vistrail, graph)::TreeLW
    # Create list of nodes
    nodes_to_add = Tuple{Int, String}[]
    X = Set{Int}()

    # Include root manually
    push!(nodes_to_add, (0, ""))
    push!(X, 0)

    # Include tagged nodes
    tag_map = vistrail.tags  # Assuming vistrail.tags is a collection
    for tag in tag_map
        id = tag.version_id
        tag_name = tag.name
        # Check if in graph (simplified - assuming all are in graph)
        push!(nodes_to_add, (id, tag_name))
        push!(X, id)
    end

    # Mount list of edges (parent, child) from the graph
    edges = Tuple{Int, Int}[]
    for (parent_id, children) in graph.edges
        for (child_id, _) in children  # children is Vector{Tuple{Int,Int}}
            push!(edges, (parent_id, child_id))

            if !(parent_id in X)
                # Use empty description for non-tagged nodes
                push!(nodes_to_add, (parent_id, ""))
                push!(X, parent_id)
            end
            if !(child_id in X)
                # Use empty description for non-tagged nodes
                push!(nodes_to_add, (child_id, ""))
                push!(X, child_id)
            end
        end
    end

    # Get widths and heights for nodes
    empty_width = layout.text_horizontal_margin + layout.text_width_f(" " ^ 5)
    height = layout.text_height + layout.text_vertical_margin

    # Create tree
    tree = TreeLW()
    map_tree_nodes = Dict{Int, NodeLW}()

    # Add nodes to tree
    for (id, tag) in nodes_to_add
        width = layout.text_horizontal_margin + layout.text_width_f(tag)
        width = max(width, empty_width)
        map_tree_nodes[id] = add_node!(tree, nothing, width, height, (id, tag))
    end

    # Preserve edge order to add children to parents
    for (parent_id, child_id) in edges
        parent = map_tree_nodes[parent_id]
        child = map_tree_nodes[child_id]
        change_parent_of_node_with_no_parent!(tree, parent, child)
    end

    return tree
end

"""
    layout_from(vistrail, graph; kwargs...)

Take vistrail and graph, compute tree layout, return node positions.
"""
function layout_from(vistrail, graph;
                     text_width_f::Function=default_text_width,
                     text_height::Float64=20.0,
                     text_horizontal_margin::Float64=10.0,
                     text_vertical_margin::Float64=5.0,
                     min_horizontal_separation::Float64=20.0,
                     min_vertical_separation::Float64=50.0,
                     vertical_alignment::VerticalAlignment=TOP_ALIGN)

    # Create layout helper
    layout_helper = VistrailsTreeLayoutLW(text_width_f, text_height,
                                         text_horizontal_margin,
                                         text_vertical_margin)

    # Generate tree
    tree = generate_tree_lw(layout_helper, vistrail, graph)

    # Compute layout
    layout = TreeLayoutLW(tree,
                         vertical_alignment=vertical_alignment,
                         xdistance=min_horizontal_separation,
                         ydistance=min_vertical_separation)

    # Extract node positions
    nodes = Dict{Int, Any}()
    for v in tree.nodes
        id, tag = v.object
        nodes[id] = (x=v.x, y=v.y, width=v.width, height=v.height, id=id)
    end

    # Compute bounding box
    (minx, miny, width, height) = bounding_box(tree)

    return (nodes=nodes, width=width, height=height, scale=0.0)
end
