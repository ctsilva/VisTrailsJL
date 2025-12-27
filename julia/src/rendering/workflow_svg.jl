"""
SVG Renderer for VisTrails Workflows

Renders pipeline DAGs to SVG format matching the VisTrails visual style:
- Rounded rectangle modules
- Small square ports on module edges
- Bezier curve connections
"""

"""
Escape XML special characters in text content.
"""
function escape_xml(s::String)
    s = replace(s, "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    s = replace(s, "\"" => "&quot;")
    s = replace(s, "'" => "&apos;")
    return s
end

"""
Estimate text width in pixels for SVG rendering.
Uses approximate character widths for Arial 14px bold font.
"""
function estimate_text_width(text::String, font_size::Float64=14.0)
    # Approximate average character width in pixels for Arial bold
    # This is a rough estimate: ~0.6 * font_size per character
    char_width = font_size * 0.6
    return length(text) * char_width
end

"""
Calculate module box dimensions based on text label.
Returns (width, height) with padding for ports and margins.
"""
function calculate_module_size(label::String, min_width::Float64=80.0, min_height::Float64=60.0)
    text_width = estimate_text_width(label)
    # Add padding: 20px on each side for margins, plus space for ports
    width = max(min_width, text_width + 40.0)
    height = min_height
    return (width, height)
end

"""
Helper function to compute port position inside a module box.

Returns (x, y) coordinates for the CENTER of a port box given:
- module_center: (x, y) center position of module
- module_size: (width, height) of module
- port_type: :input or :output
- port_index: 1-based index of port among ports of that type
- num_ports: total number of ports of that type
- port_size: size of port square
- scale: scaling factor

Input ports are positioned inside top-left, going left to right.
Output ports are positioned inside bottom-right, going right to left.
"""
function compute_port_position(module_center, module_size, port_type, port_index, num_ports, port_size, scale)
    cx, cy = module_center
    w, h = module_size .* scale
    ps = port_size * scale

    # Padding from module edge
    edge_padding = 8.0 * scale  # Distance from edge (inside box)
    port_spacing = ps + 4.0 * scale  # Space between ports (closely packed)

    if port_type == :input
        # Input ports: top-left, going left to right
        # Start from left edge + padding
        start_x = cx - w/2 + edge_padding + ps/2
        port_x = start_x + (port_index - 1) * port_spacing
        port_y = cy - h/2 + edge_padding + ps/2  # Just below top edge
    else  # :output
        # Output ports: bottom-right, going right to left
        # Start from right edge - padding (first port is rightmost)
        start_x = cx + w/2 - edge_padding - ps/2
        port_x = start_x - (port_index - 1) * port_spacing
        port_y = cy + h/2 - edge_padding - ps/2  # Just above bottom edge
    end

    return (port_x, port_y)
end

"""
Get input port specs for a module, preferring instance-specific portSpecs over descriptor ports.

Returns a vector of (name, sort_key) tuples, sorted by sort_key.
"""
function get_input_port_specs(mod::ModuleInstance)
    # Use port_specs from workflow XML if available
    if !isempty(mod.port_specs)
        input_specs = filter(ps -> ps.port_type == :input, mod.port_specs)
        # Sort by sort_key (important for correct order!)
        sort!(input_specs, by = ps -> ps.sort_key)
        return [(ps.name, ps.sort_key) for ps in input_specs]
    end

    # Fallback to descriptor ports
    return [(p.name, i) for (i, p) in enumerate(mod.descriptor.input_ports)]
end

"""
Get output port specs for a module, preferring instance-specific portSpecs over descriptor ports.

Returns a vector of (name, sort_key) tuples, sorted by sort_key.
"""
function get_output_port_specs(mod::ModuleInstance)
    # Use port_specs from workflow XML if available
    if !isempty(mod.port_specs)
        output_specs = filter(ps -> ps.port_type == :output, mod.port_specs)
        # Sort by sort_key (important for correct order!)
        sort!(output_specs, by = ps -> ps.sort_key)
        return [(ps.name, ps.sort_key) for ps in output_specs]
    end

    # Fallback to descriptor ports
    return [(p.name, i) for (i, p) in enumerate(mod.descriptor.output_ports)]
end

"""
    render_pipeline_svg(pipeline::Pipeline; kwargs...)

Render a pipeline to SVG. Automatically computes layout positions if not present.

# Arguments
- `pipeline::Pipeline`: The pipeline to render
- `width::Int=800`: SVG canvas width
- `height::Int=600`: SVG canvas height
- `module_width::Float64=120.0`: Default module width
- `module_height::Float64=60.0`: Default module height
- `port_size::Float64=8.0`: Port square size
- `margin::Float64=50.0`: Canvas margin
- `auto_layout::Bool=true`: Automatically compute layout if positions missing

# Returns
- `String`: SVG XML content
"""

function render_pipeline_svg(pipeline::Pipeline;
                             width::Int=800,
                             height::Int=600,
                             module_width::Float64=120.0,
                             module_height::Float64=60.0,
                             port_size::Float64=8.0,
                             margin::Float64=50.0,
                             auto_layout::Bool=true)

    io = IOBuffer()

    # Collect modules with positions
    positioned_modules = [(id, mod) for (id, mod) in pipeline.modules
                          if mod.layout_position !== nothing]

    if isempty(positioned_modules)
        if auto_layout
            # Compute automatic layout using Graphviz
            auto_layout_pipeline!(pipeline, algorithm="dot")
            # Recompute positioned modules
            positioned_modules = [(id, mod) for (id, mod) in pipeline.modules
                                  if mod.layout_position !== nothing]
        end

        if isempty(positioned_modules)
            @warn "No layout positions found and auto-layout disabled - rendering empty SVG"
            println(io, """<?xml version="1.0" encoding="UTF-8"?>""")
            println(io, """<svg width="$width" height="$height" xmlns="http://www.w3.org/2000/svg">""")
            println(io, """  <text x="$(width/2)" y="$(height/2)" text-anchor="middle" fill="#999">""")
            println(io, """    No layout positions available""")
            println(io, """  </text>""")
            println(io, """</svg>""")
            return String(take!(io))
        end
    end

    # Find bounding box from module positions
    positions = [mod.layout_position for (_, mod) in positioned_modules]
    min_x = minimum(p[1] for p in positions) - module_width/2
    max_x = maximum(p[1] for p in positions) + module_width/2
    min_y = minimum(p[2] for p in positions) - module_height/2
    max_y = maximum(p[2] for p in positions) + module_height/2

    # Calculate scale to fit in canvas
    bbox_width = max_x - min_x
    bbox_height = max_y - min_y
    available_width = width - 2*margin
    available_height = height - 2*margin

    scale_x = available_width / bbox_width
    scale_y = available_height / bbox_height
    scale = min(scale_x, scale_y, 1.0)  # Don't scale up, only down

    # Transform function: workflow coords -> SVG coords
    # VisTrails uses negative Y for top, so we flip the Y-axis
    function to_svg(x, y)
        svg_x = margin + (x - min_x) * scale
        svg_y = margin + (max_y - y) * scale  # Flip Y-axis
        return (svg_x, svg_y)
    end

    # SVG header
    println(io, """<?xml version="1.0" encoding="UTF-8"?>""")
    println(io, """<svg width="$width" height="$height" xmlns="http://www.w3.org/2000/svg">""")

    # Add CSS styles
    println(io, """  <defs>""")
    println(io, """    <style>""")
    println(io, """      .module {""")
    println(io, """        fill: #f5f5f5;""")
    println(io, """        stroke: #333;""")
    println(io, """        stroke-width: 2;""")
    println(io, """      }""")
    println(io, """      .module-text {""")
    println(io, """        font-family: Arial, sans-serif;""")
    println(io, """        font-size: 14px;""")
    println(io, """        font-weight: bold;""")
    println(io, """        fill: #333;""")
    println(io, """        text-anchor: middle;""")
    println(io, """        dominant-baseline: middle;""")
    println(io, """      }""")
    println(io, """      .port {""")
    println(io, """        fill: #666;""")
    println(io, """        stroke: #333;""")
    println(io, """        stroke-width: 1;""")
    println(io, """      }""")
    println(io, """      .connection {""")
    println(io, """        stroke: #000;""")
    println(io, """        stroke-width: 2;""")
    println(io, """        fill: none;""")
    println(io, """        stroke-opacity: 1.0;""")
    println(io, """      }""")
    println(io, """    </style>""")
    println(io, """  </defs>""")
    println(io)

    # Calculate sizes for each module based on label
    # IMPORTANT: Calculate size AFTER scaling to ensure text fits in scaled boxes
    module_sizes = Dict{Int, Tuple{Float64, Float64}}()
    for (id, mod) in positioned_modules
        module_label = get(mod.annotations, "__desc__", mod.descriptor.name)
        # Calculate text width in final scaled coordinates
        text_width = estimate_text_width(module_label) / scale
        # Add padding and enforce minimum
        width = max(module_width, text_width + 40.0)
        height = module_height
        module_sizes[id] = (width, height)
    end

    # Render modules first (below connections)
    println(io, """  <!-- Modules -->""")
    for (id, mod) in positioned_modules
        x, y = to_svg(mod.layout_position...)

        # Get module-specific dimensions
        mod_width, mod_height = module_sizes[id]

        # Module dimensions (scaled)
        w = mod_width * scale
        h = mod_height * scale
        rx = x - w/2  # Top-left corner
        ry = y - h/2

        println(io, """  <g class="module-group" id="module-$id">""")

        # Module rectangle
        println(io, """    <rect class="module" x="$rx" y="$ry" width="$w" height="$h" rx="5"/>""")

        # Module label: use __desc__ annotation if present, otherwise module name
        module_label = get(mod.annotations, "__desc__", mod.descriptor.name)
        module_label_escaped = escape_xml(module_label)
        println(io, """    <text class="module-text" x="$x" y="$y">$module_label_escaped</text>""")

        # Input ports (top-left, inside box) - use instance-specific port specs
        input_port_specs = get_input_port_specs(mod)
        num_inputs = length(input_port_specs)
        if num_inputs > 0
            for (i, (_port_name, _sort_key)) in enumerate(input_port_specs)
                # compute_port_position returns the CENTER of the port
                port_x, port_y = compute_port_position((x, y), (mod_width, mod_height),
                                                        :input, i, num_inputs, port_size, scale)
                ps = port_size * scale
                println(io, """    <rect class="port" x="$(port_x - ps/2)" y="$(port_y - ps/2)" width="$ps" height="$ps"/>""")
            end
        end

        # Output ports (bottom-right, inside box) - use instance-specific port specs
        output_port_specs = get_output_port_specs(mod)
        num_outputs = length(output_port_specs)
        if num_outputs > 0
            for (i, (_port_name, _sort_key)) in enumerate(output_port_specs)
                # compute_port_position returns the CENTER of the port
                port_x, port_y = compute_port_position((x, y), (mod_width, mod_height),
                                                        :output, i, num_outputs, port_size, scale)
                ps = port_size * scale
                println(io, """    <rect class="port" x="$(port_x - ps/2)" y="$(port_y - ps/2)" width="$ps" height="$ps"/>""")
            end
        end

        println(io, """  </g>""")
    end
    println(io)

    # Render connections - draw lines from output ports to input ports
    println(io, """  <!-- Connections -->""")
    for conn in pipeline.connections
        # Verify both modules exist and have positions
        src_mod = get(pipeline.modules, conn.source_module_id, nothing)
        dst_mod = get(pipeline.modules, conn.dest_module_id, nothing)

        if src_mod === nothing || dst_mod === nothing
            continue
        end

        if src_mod.layout_position === nothing || dst_mod.layout_position === nothing
            continue
        end

        # Get the transformed center positions in SVG coordinates
        src_center_x, src_center_y = to_svg(src_mod.layout_position...)
        dst_center_x, dst_center_y = to_svg(dst_mod.layout_position...)

        # Get port information for both modules
        src_outputs = get_output_port_specs(src_mod)
        dst_inputs = get_input_port_specs(dst_mod)

        # Find which port index this connection uses (1-based)
        src_idx = findfirst(p -> p[1] == conn.source_port, src_outputs)
        dst_idx = findfirst(p -> p[1] == conn.dest_port, dst_inputs)

        if src_idx === nothing || dst_idx === nothing
            continue
        end

        # Get module-specific sizes
        src_mod_width, src_mod_height = module_sizes[conn.source_module_id]
        dst_mod_width, dst_mod_height = module_sizes[conn.dest_module_id]

        # Calculate the exact port positions (centers of port squares)
        src_port_x, src_port_y = compute_port_position(
            (src_center_x, src_center_y),
            (src_mod_width, src_mod_height),
            :output,
            src_idx,
            length(src_outputs),
            port_size,
            scale
        )

        dst_port_x, dst_port_y = compute_port_position(
            (dst_center_x, dst_center_y),
            (dst_mod_width, dst_mod_height),
            :input,
            dst_idx,
            length(dst_inputs),
            port_size,
            scale
        )

        # Draw a cubic Bezier curve from source port to destination port
        # Control points create a smooth vertical curve
        vertical_distance = abs(dst_port_y - src_port_y)
        control_offset = vertical_distance * 0.4

        control1_x = src_port_x
        control1_y = src_port_y + control_offset
        control2_x = dst_port_x
        control2_y = dst_port_y - control_offset

        # Output the path
        println(io, """  <path class="connection" d="M $src_port_x,$src_port_y C $control1_x,$control1_y $control2_x,$control2_y $dst_port_x,$dst_port_y"/>""")
    end
    println(io)

    # SVG footer
    println(io, """</svg>""")

    return String(take!(io))
end

"""
    save_pipeline_svg(pipeline::Pipeline, filename::String; kwargs...)

Render pipeline to SVG and save to file.
"""
function save_pipeline_svg(pipeline::Pipeline, filename::String; kwargs...)
    svg = render_pipeline_svg(pipeline; kwargs...)
    write(filename, svg)
    println("✓ Saved SVG to: $filename")
end
