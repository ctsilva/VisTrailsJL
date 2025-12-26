###############################################################################
##
## Copyright (C) 2014-2016, New York University.
## Copyright (C) 2011-2014, NYU-Poly.
## Copyright (C) 2006-2011, University of Utah.
## All rights reserved.
## Contact: contact@vistrails.org
##
## This file is a Julia translation of the VisTrails tree layout code.
##
###############################################################################
"""
This file has the implementation of an algorithm to layout general
rooted trees in a nice way. The "LW" stands for (L)inear (W)alker.
This code is based on the paper:

    Christoph Buchheim, Michael Junger, and Sebastian Leipert.
    Improving walker's algorithm to run in linear time.
    In Stephen G. Kobourov and Michael T. Goodrich, editors, Graph
    Drawing, volume 2528 of Lecture Notes in Computer Science, pages
    344-353. Springer, 2002.

which is a faster (linear time!) way to compute the tree layout
proposed by Walker than the algorithm described by him.
The original paper is:

    John Q. Walker II.
    A node-positioning algorithm for general trees.
    Softw., Pract. Exper., 20(7):685-705, 1990.
"""

mutable struct NodeLW
    """
    Node of the tree with all the auxiliary
    variables needed to the LW algorithm.
    The fields width, height and object
    are given as input. The first two are
    used to layout while the last one might
    be used by the user of this class.
    """
    width::Float64
    height::Float64
    object::Any

    children::Vector{NodeLW}
    parent::Union{NodeLW, Nothing}
    index::Int
    level::Int

    # intermediate variables for layout algorithm
    mod::Float64
    prelim::Float64
    ancestor::Union{NodeLW, Nothing}
    thread::Union{NodeLW, Nothing}
    change::Float64
    shift::Float64

    # final center position
    x::Float64
    y::Float64

    function NodeLW(width::Float64, height::Float64, object=nothing)
        node = new(width, height, object,
                   NodeLW[], nothing, 0, 0,
                   0.0, 0.0, nothing, nothing, 0.0, 0.0,
                   0.0, 0.0)
        node.ancestor = node  # self-reference
        return node
    end
end

function get_num_children(node::NodeLW)::Int
    return length(node.children)
end

function has_child(node::NodeLW)::Bool
    return !isempty(node.children)
end

function add_child!(node::NodeLW, child::NodeLW)
    push!(node.children, child)
    child.index = length(node.children) - 1  # 0-indexed like Python
    child.parent = node
    child.level = node.level + 1
end

function is_leaf(node::NodeLW)::Bool
    return isempty(node.children)
end

function left_child(node::NodeLW)::NodeLW
    return node.children[1]
end

function right_child(node::NodeLW)::NodeLW
    return node.children[end]
end

function left_sibling(node::NodeLW)::Union{NodeLW, Nothing}
    if node.index > 0 && node.parent !== nothing
        return node.parent.children[node.index]  # index is 0-based, but we want previous
    else
        return nothing
    end
end

function left_most_sibling(node::NodeLW)::NodeLW
    if node.parent !== nothing
        return node.parent.children[1]
    else
        return node
    end
end

function is_sibling_of(node::NodeLW, v::NodeLW)::Bool
    return node.parent === v.parent && node.parent !== nothing
end

# Tree structure
mutable struct TreeLW
    nodes::Vector{NodeLW}
    max_level::Int

    TreeLW() = new(NodeLW[], 0)
end

function root(tree::TreeLW)::NodeLW
    return tree.nodes[1]
end

function add_node!(tree::TreeLW, parent_node::Union{NodeLW, Nothing},
                  width::Float64, height::Float64, object=nothing)::NodeLW
    new_node = NodeLW(width, height, object)
    push!(tree.nodes, new_node)

    if parent_node !== nothing
        add_child!(parent_node, new_node)
    end

    tree.max_level = max(tree.max_level, new_node.level)
    return new_node
end

function change_parent_of_node_with_no_parent!(tree::TreeLW, parent_node::NodeLW,
                                               child_node::NodeLW)
    if child_node.parent !== nothing
        error("Node already has a parent")
    end

    add_child!(parent_node, child_node)
    max_level = dfs_update_level!(child_node)

    tree.max_level = max(tree.max_level, max_level)
end

function dfs_update_level!(node::NodeLW)::Int
    if node.parent === nothing
        node.level = 0
    else
        node.level = node.parent.level + 1
    end
    max_level = node.level
    for child in node.children
        max_level = max(max_level, dfs_update_level!(child))
    end
    return max_level
end

function bounding_box(tree::TreeLW)::Tuple{Float64, Float64, Float64, Float64}
    minx = miny = maxx = maxy = nothing

    for w in tree.nodes
        x1, y1 = w.x - w.width/2.0, w.y - w.height/2.0
        x2, y2 = w.x + w.width/2.0, w.y + w.height/2.0

        minx = minx === nothing ? x1 : min(minx, x1)
        miny = miny === nothing ? y1 : min(miny, y1)
        maxx = maxx === nothing ? x2 : max(maxx, x2)
        maxy = maxy === nothing ? y2 : max(maxy, y2)
    end

    return (minx, miny, maxx - minx, maxy - miny)
end

function get_max_node_height_per_level(tree::TreeLW)::Vector{Float64}
    result = zeros(Float64, tree.max_level + 1)
    for w in tree.nodes
        level = w.level + 1  # Julia is 1-indexed
        result[level] = max(result[level], w.height)
    end
    return result
end

# Tree Layout Algorithm
@enum VerticalAlignment TOP_ALIGN=0 MIDDLE_ALIGN=1 BOTTOM_ALIGN=2

mutable struct TreeLayoutLW
    xdistance::Float64
    ydistance::Float64
    tree::TreeLW
    vertical_alignment::VerticalAlignment

    function TreeLayoutLW(tree::TreeLW;
                         vertical_alignment::VerticalAlignment=MIDDLE_ALIGN,
                         xdistance::Float64=10.0,
                         ydistance::Float64=10.0)
        layout = new(xdistance, ydistance, tree, vertical_alignment)
        tree_layout!(layout)
        return layout
    end
end

function tree_layout!(layout::TreeLayoutLW)
    for v in layout.tree.nodes
        v.mod = 0.0
        v.thread = nothing
        v.ancestor = v
    end

    r = root(layout.tree)
    first_walk!(layout, r)
    second_walk!(layout, r, -r.prelim)
    set_vertical_positions!(layout)
end

function set_vertical_positions!(layout::TreeLayoutLW)
    # set y position
    max_node_height_per_level = get_max_node_height_per_level(layout.tree)
    info_level = Tuple{Float64, Float64}[]
    position_level = 0.0

    for height_level in max_node_height_per_level
        push!(info_level, (position_level, height_level))
        position_level += layout.ydistance + height_level
    end

    for w in layout.tree.nodes
        level = w.level + 1  # Julia is 1-indexed
        position_level, height_level = info_level[level]

        if layout.vertical_alignment == TOP_ALIGN
            w.y = position_level + w.height/2.0
        elseif layout.vertical_alignment == MIDDLE_ALIGN
            w.y = position_level + height_level/2.0
        else  # BOTTOM_ALIGN
            w.y = position_level + height_level - w.height/2.0
        end
    end
end

function gap(layout::TreeLayoutLW, v1::NodeLW, v2::NodeLW)::Float64
    return layout.xdistance + (v1.width + v2.width)/2.0
end

function first_walk!(layout::TreeLayoutLW, v::NodeLW)
    if is_leaf(v)
        v.prelim = 0.0
        w = left_sibling(v)
        if w !== nothing
            v.prelim = w.prelim + gap(layout, w, v)
        end
    else
        default_ancestor = left_child(v)
        for w in v.children
            first_walk!(layout, w)
            default_ancestor = apportion!(layout, w, default_ancestor)
        end
        execute_shifts!(layout, v)

        midpoint = (left_child(v).prelim + right_child(v).prelim) / 2.0

        w = left_sibling(v)
        if w !== nothing
            v.prelim = w.prelim + gap(layout, w, v)
            v.mod = v.prelim - midpoint
        else
            v.prelim = midpoint
        end
    end
end

function apportion!(layout::TreeLayoutLW, v::NodeLW, default_ancestor::NodeLW)::NodeLW
    """
    Apportion: to divide and assign proportionally.

    Suppose the left siblings of "v" are all aligned.
    Now align the subtree with root "v".
    """
    w = left_sibling(v)
    if w !== nothing
        # p stands for + or plus (right subtree)
        # m stands for - or minus (left subtree)
        # i stands for inside
        # o stands for outside
        # v stands for vertex
        # s stands for shift
        vip = vop = v
        vim = w
        vom = left_most_sibling(vip)
        sip = vip.mod
        sop = vop.mod
        sim = vim.mod
        som = vom.mod

        while next_right(layout, vim) !== nothing && next_left(layout, vip) !== nothing
            vim = next_right(layout, vim)
            vip = next_left(layout, vip)
            vom = next_left(layout, vom)
            vop = next_right(layout, vop)

            vop.ancestor = v

            shift = (vim.prelim + sim) - (vip.prelim + sip) + gap(layout, vim, vip)

            if shift > 0
                move_subtree!(layout, ancestor(layout, vim, v, default_ancestor), v, shift)
                sip += shift
                sop += shift
            end

            sim += vim.mod
            sip += vip.mod
            som += vom.mod
            sop += vop.mod
        end

        if next_right(layout, vim) !== nothing && next_right(layout, vop) === nothing
            vop.thread = next_right(layout, vim)
            vop.mod += sim - sop
        end

        if next_left(layout, vip) !== nothing && next_left(layout, vom) === nothing
            vom.thread = next_left(layout, vip)
            vom.mod += sip - som
            default_ancestor = v
        end
    end

    return default_ancestor
end

function next_left(layout::TreeLayoutLW, v::NodeLW)::Union{NodeLW, Nothing}
    if has_child(v)
        return left_child(v)
    else
        return v.thread
    end
end

function next_right(layout::TreeLayoutLW, v::NodeLW)::Union{NodeLW, Nothing}
    if has_child(v)
        return right_child(v)
    else
        return v.thread
    end
end

function move_subtree!(layout::TreeLayoutLW, wm::NodeLW, wp::NodeLW, shift::Float64)
    subtrees = Float64(wp.index - wm.index)
    wp.change += -shift/subtrees
    wp.shift += shift
    wm.change += shift/subtrees
    wp.prelim += shift
    wp.mod += shift
end

function execute_shifts!(layout::TreeLayoutLW, v::NodeLW)
    shift = 0.0
    change = 0.0
    # Iterate in reverse (Python: range(n-1, -1, -1))
    for i in length(v.children):-1:1
        w = v.children[i]
        w.prelim += shift
        w.mod += shift
        change += w.change
        shift += w.shift + change
    end
end

function ancestor(layout::TreeLayoutLW, vim::NodeLW, v::NodeLW,
                 default_ancestor::NodeLW)::NodeLW
    if is_sibling_of(vim.ancestor, v)
        return vim.ancestor
    else
        return default_ancestor
    end
end

function second_walk!(layout::TreeLayoutLW, v::NodeLW, m::Float64)
    v.x = v.prelim + m
    for w in v.children
        second_walk!(layout, w, m + v.mod)
    end
end
