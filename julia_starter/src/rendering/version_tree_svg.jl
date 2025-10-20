###############################################################################
##
## Copyright (C) 2014-2016, New York University.
## Copyright (C) 2011-2014, NYU-Poly.
## Copyright (C) 2006-2011, University of Utah.
## All rights reserved.
## Contact: contact@vistrails.org
##
## This file renders VisTrails version trees as SVG.
##
###############################################################################
"""
SVG Renderer for VisTrails Version Trees

Renders version history as a tree visualization using the TreeLayoutLW algorithm.
"""

include("version_tree_layout.jl")
include("terse_graph.jl")

"""
Simple graph structure for version tree layout.
"""
struct SimpleGraph
    vertices::Set{Int}
    edges::Dict{Int, Vector{Tuple{Int,Int}}}  # parent -> [(child, child)]
end

function edges_from(graph::SimpleGraph, id::Int)
    return get(graph.edges, id, Tuple{Int,Int}[])
end

"""
Build graph from vistrail actions.
"""
function build_version_graph(vistrail)::SimpleGraph
    vertices = Set{Int}()
    edges = Dict{Int, Vector{Tuple{Int,Int}}}()

    # Add root
    push!(vertices, 0)

    # Build parent-child relationships
    for (id, action) in vistrail.actions
        push!(vertices, id)

        parent_id = action.prev_id === nothing ? 0 : action.prev_id

        if !haskey(edges, parent_id)
            edges[parent_id] = Tuple{Int,Int}[]
        end
        push!(edges[parent_id], (id, id))  # Format: (to_id, to_id)

        if parent_id != 0
            push!(vertices, parent_id)
        end
    end

    return SimpleGraph(vertices, edges)
end

"""
    render_version_tree_svg(vistrail::Vistrail; kwargs...)

Render version history tree to SVG using proper VisTrails layout algorithm.

# Arguments
- `vistrail::Vistrail`: The vistrail to render
- `width::Int=1200`: SVG canvas width
- `height::Int=800`: SVG canvas height
- `node_width::Float64=100.0`: Approximate node width (will be adjusted by text)
- `node_height::Float64=50.0`: Node height
- `min_horizontal_separation::Float64=20.0`: Minimum horizontal spacing
- `min_vertical_separation::Float64=50.0`: Minimum vertical spacing
- `margin::Float64=50.0`: Canvas margin

# Returns
- `String`: SVG XML content
"""
function render_version_tree_svg(vistrail::Vistrail;
                                 width::Int=1200,
                                 height::Int=800,
                                 node_width::Float64=100.0,
                                 node_height::Float64=50.0,
                                 min_horizontal_separation::Float64=20.0,
                                 min_vertical_separation::Float64=50.0,
                                 margin::Float64=50.0,
                                 use_terse_graph::Bool=true,
                                 show_stats::Bool=false)

    if isempty(vistrail.actions)
        return render_empty_tree_svg(width, height)
    end

    # Generate terse graph if requested
    terse_edges_info = Dict{Tuple{Int,Int}, Bool}()  # (parent, child) -> has_hidden

    if use_terse_graph
        terse = generate_terse_graph(vistrail)

        if show_stats
            print_terse_graph_stats(vistrail, terse)
        end

        # Store which edges have hidden versions
        for (parent, children) in terse.edges
            for (child, has_hidden) in children
                terse_edges_info[(parent, child)] = has_hidden
            end
        end

        # Create filtered vistrail with only visible versions
        filtered_actions = Dict{Int, Any}()
        for id in terse.visible_versions
            if id != 0 && haskey(vistrail.actions, id)
                filtered_actions[id] = vistrail.actions[id]
            end
        end

        filtered_vistrail = (actions=filtered_actions,
                           tags=vistrail.tags,
                           current_version=vistrail.current_version)

        # Convert terse edges to SimpleGraph format
        simple_edges = Dict{Int, Vector{Tuple{Int,Int}}}()
        for (parent, children) in terse.edges
            simple_edges[parent] = [(child, child) for (child, has_hidden) in children]
        end

        graph = SimpleGraph(terse.visible_versions, simple_edges)
    else
        # Use full graph
        filtered_vistrail = vistrail
        graph = build_version_graph(vistrail)
    end

    # Text measurement function (approximate)
    # For 12px Arial: average character width ~8px, but we add padding
    function text_width(text::String)::Float64
        if isempty(text)
            return node_width
        end
        # 9 pixels per character is a safer estimate for 12px Arial
        estimated_width = length(text) * 9.0
        return max(estimated_width, node_width * 0.8)
    end

    # Compute layout using VisTrails algorithm
    layout_result = layout_from(filtered_vistrail, graph,
                               text_width_f=text_width,
                               text_height=node_height * 0.6,
                               text_horizontal_margin=20.0,  # Increased for better spacing
                               text_vertical_margin=5.0,
                               min_horizontal_separation=min_horizontal_separation,
                               min_vertical_separation=min_vertical_separation,
                               vertical_alignment=TOP_ALIGN)

    nodes = layout_result.nodes
    tree_width = layout_result.width
    tree_height = layout_result.height

    # Compute bounding box
    if isempty(nodes)
        return render_empty_tree_svg(width, height)
    end

    # Find bounds
    min_x = min_y = Inf
    max_x = max_y = -Inf

    for (id, node) in nodes
        min_x = min(min_x, node.x - node.width/2)
        max_x = max(max_x, node.x + node.width/2)
        min_y = min(min_y, node.y)
        max_y = max(max_y, node.y + node.height)
    end

    # Transform to fit canvas
    bbox_width = max_x - min_x
    bbox_height = max_y - min_y

    scale_x = (width - 2*margin) / bbox_width
    scale_y = (height - 2*margin) / bbox_height
    scale = min(scale_x, scale_y, 1.0)  # Don't scale up

    function to_svg(x, y)
        svg_x = margin + (x - min_x) * scale
        svg_y = margin + (y - min_y) * scale
        return (svg_x, svg_y)
    end

    # Build SVG
    io = IOBuffer()
    println(io, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    println(io, "<svg width=\"$width\" height=\"$height\" xmlns=\"http://www.w3.org/2000/svg\">")

    # CSS styles
    println(io, "  <defs>")
    println(io, "    <style>")
    println(io, "      .version-node {")
    println(io, "        fill: #f0e68c;")  # khaki
    println(io, "        stroke: #333;")
    println(io, "        stroke-width: 2;")
    println(io, "      }")
    println(io, "      .version-node-tagged {")
    println(io, "        fill: #daa520;")  # goldenrod
    println(io, "        stroke: #333;")
    println(io, "        stroke-width: 2;")
    println(io, "      }")
    println(io, "      .version-node-current {")
    println(io, "        fill: #ff8c00;")  # darkorange
    println(io, "        stroke: #333;")
    println(io, "        stroke-width: 3;")
    println(io, "      }")
    println(io, "      .version-text {")
    println(io, "        font-family: Arial, sans-serif;")
    println(io, "        font-size: 12px;")
    println(io, "        fill: #333;")
    println(io, "        text-anchor: middle;")
    println(io, "        dominant-baseline: middle;")
    println(io, "      }")
    println(io, "      .version-edge {")
    println(io, "        stroke: #333;")
    println(io, "        stroke-width: 2;")
    println(io, "        fill: none;")
    println(io, "      }")
    println(io, "      .version-edge-collapsed {")
    println(io, "        stroke: #666;")
    println(io, "        stroke-width: 2;")
    println(io, "        stroke-dasharray: 5, 5;")
    println(io, "        fill: none;")
    println(io, "      }")
    println(io, "    </style>")
    println(io, "  </defs>")
    println(io)

    # Draw edges first
    println(io, "  <!-- Edges -->")
    for (parent_id, children) in graph.edges
        for (child_id, _) in children
            if parent_id in keys(nodes) && child_id in keys(nodes)
                parent_node = nodes[parent_id]
                child_node = nodes[child_id]

                px, py = to_svg(parent_node.x, parent_node.y + parent_node.height)
                cx, cy = to_svg(child_node.x, child_node.y)

                # Check if this edge has hidden versions
                has_hidden = get(terse_edges_info, (parent_id, child_id), false)
                edge_class = has_hidden ? "version-edge-collapsed" : "version-edge"

                println(io, "  <line class=\"$edge_class\" x1=\"$px\" y1=\"$py\" x2=\"$cx\" y2=\"$cy\"/>")
            end
        end
    end
    println(io)

    # Draw nodes
    println(io, "  <!-- Nodes -->")
    for (id, node) in nodes
        cx, cy = to_svg(node.x, node.y + node.height/2)
        # Use minimum of scaled and unscaled width to prevent text overflow
        # The layout computed proper widths for text, so we preserve them
        rx = max(node.width / 2, node.width * scale / 2)
        ry = node.height * scale / 2

        # Determine node class
        is_current = (id == vistrail.current_version)
        is_tagged = any(tag -> tag.version_id == id, vistrail.tags)

        node_class = if is_current
            "version-node-current"
        elseif is_tagged
            "version-node-tagged"
        else
            "version-node"
        end

        # Get label
        label = string(id)
        for tag in vistrail.tags
            if tag.version_id == id
                label = tag.name
                break
            end
        end

        println(io, "  <g class=\"version-group\" id=\"version-$id\">")
        println(io, "    <ellipse class=\"$node_class\" cx=\"$cx\" cy=\"$cy\" rx=\"$rx\" ry=\"$ry\"/>")
        println(io, "    <text class=\"version-text\" x=\"$cx\" y=\"$cy\">$label</text>")
        println(io, "  </g>")
    end

    println(io, "</svg>")

    return String(take!(io))
end

"""
Render an empty tree SVG.
"""
function render_empty_tree_svg(width::Int, height::Int)::String
    io = IOBuffer()
    println(io, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    println(io, "<svg width=\"$width\" height=\"$height\" xmlns=\"http://www.w3.org/2000/svg\">")
    println(io, "  <text x=\"$(width/2)\" y=\"$(height/2)\" text-anchor=\"middle\" font-size=\"16\">")
    println(io, "    No version history")
    println(io, "  </text>")
    println(io, "</svg>")
    return String(take!(io))
end

"""
Save version tree SVG to file.
"""
function save_version_tree_svg(filename::String, vistrail::Vistrail; kwargs...)
    svg = render_version_tree_svg(vistrail; kwargs...)
    write(filename, svg)
    println("Saved version tree to: $filename")
end
