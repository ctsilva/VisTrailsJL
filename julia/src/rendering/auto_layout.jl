"""
Automatic graph layout using Graphviz for workflows without explicit positions
"""

using Graphviz_jll

"""
    auto_layout_pipeline!(pipeline::Pipeline; algorithm="dot")

Automatically compute layout positions for all modules in a pipeline using Graphviz.

Modifies the pipeline in-place by setting `layout_position` for each module.

# Arguments
- `pipeline`: The pipeline to layout
- `algorithm`: Graphviz layout algorithm ("dot", "neato", "fdp", "sfdp", "circo", "twopi")
  - "dot": Hierarchical/layered layout (best for DAGs/workflows)
  - "neato": Spring model layout
  - "fdp": Force-directed layout
  - "sfdp": Scalable force-directed layout
  - "circo": Circular layout
  - "twopi": Radial layout

Returns the pipeline (for chaining).
"""
function auto_layout_pipeline!(pipeline::Pipeline; algorithm="dot")
    # Create DOT graph description
    dot = generate_dot_string(pipeline)

    # Run Graphviz to compute layout
    # Use plain format which gives us node positions
    positions = run_graphviz_layout(dot, algorithm)

    # Apply positions to pipeline modules
    for (module_id, (x, y)) in positions
        if haskey(pipeline.modules, module_id)
            pipeline.modules[module_id].layout_position = (x, y)
        end
    end

    return pipeline
end

"""
    generate_dot_string(pipeline::Pipeline) -> String

Generate a Graphviz DOT format string from a pipeline.
"""
function generate_dot_string(pipeline::Pipeline)
    io = IOBuffer()

    println(io, "digraph workflow {")
    println(io, "  rankdir=TB;")  # Top to bottom layout
    println(io, "  node [shape=box];")

    # Add spacing controls to prevent overlap
    # nodesep: minimum space between nodes in same rank (in inches)
    # ranksep: minimum space between ranks (in inches)
    println(io, "  nodesep=1.0;")  # 1 inch = 72 points horizontal spacing
    println(io, "  ranksep=1.5;")  # 1.5 inches = 108 points vertical spacing

    # Add nodes
    for (id, mod) in pipeline.modules
        label = get(mod.annotations, "__desc__", mod.descriptor.name)
        # Escape quotes in label
        label = replace(label, "\"" => "\\\"")
        println(io, "  n$id [label=\"$label\"];")
    end

    # Add edges
    for conn in pipeline.connections
        println(io, "  n$(conn.source_module_id) -> n$(conn.dest_module_id);")
    end

    println(io, "}")

    return String(take!(io))
end

"""
    run_graphviz_layout(dot_string::String, algorithm::String) -> Dict{Int, Tuple{Float64, Float64}}

Run Graphviz layout algorithm and parse node positions.

Returns a dictionary mapping module IDs to (x, y) coordinates.
"""
function run_graphviz_layout(dot_string::String, algorithm::String)
    # Write DOT string to temp file
    dot_file = tempname() * ".dot"
    plain_file = tempname() * ".plain"

    try
        write(dot_file, dot_string)

        # Run Graphviz (using -Tplain for easy parsing)
        cmd = algorithm == "dot" ? Graphviz_jll.dot() :
              algorithm == "neato" ? Graphviz_jll.neato() :
              algorithm == "fdp" ? Graphviz_jll.fdp() :
              algorithm == "sfdp" ? Graphviz_jll.sfdp() :
              algorithm == "circo" ? Graphviz_jll.circo() :
              algorithm == "twopi" ? Graphviz_jll.twopi() :
              error("Unknown layout algorithm: $algorithm")

        run(pipeline(`$cmd -Tplain -o $plain_file $dot_file`))

        # Parse plain format output
        return parse_plain_format(plain_file)

    finally
        # Clean up temp files
        isfile(dot_file) && rm(dot_file)
        isfile(plain_file) && rm(plain_file)
    end
end

"""
    parse_plain_format(filename::String) -> Dict{Int, Tuple{Float64, Float64}}

Parse Graphviz plain format output to extract node positions.

Plain format has lines like:
  node n1 x y width height label style shape color fillcolor

Graphviz outputs positions in inches by default. We scale them to points
(1 inch = 72 points) to get a reasonable coordinate system similar to VisTrails.
"""
function parse_plain_format(filename::String)
    positions = Dict{Int, Tuple{Float64, Float64}}()

    # Graphviz uses inches; convert to points (72 DPI)
    # This gives us a coordinate system similar to VisTrails
    INCHES_TO_POINTS = 72.0

    for line in eachline(filename)
        parts = split(line)
        if length(parts) >= 4 && parts[1] == "node"
            # Extract node ID (e.g., "n1" -> 1)
            node_name = parts[2]
            if startswith(node_name, "n")
                node_id = parse(Int, node_name[2:end])
                x_inches = parse(Float64, parts[3])
                y_inches = parse(Float64, parts[4])

                # Convert inches to points for a more reasonable coordinate system
                x = x_inches * INCHES_TO_POINTS
                y = y_inches * INCHES_TO_POINTS

                positions[node_id] = (x, y)
            end
        end
    end

    return positions
end

"""
    has_layout_positions(pipeline::Pipeline) -> Bool

Check if any modules in the pipeline have layout positions.
"""
function has_layout_positions(pipeline::Pipeline)
    return any(m -> m.layout_position !== nothing, values(pipeline.modules))
end

"""
    ensure_layout!(pipeline::Pipeline; algorithm="dot", force=false)

Ensure the pipeline has layout positions, computing them automatically if needed.

# Arguments
- `pipeline`: The pipeline to layout
- `algorithm`: Graphviz layout algorithm (default: "dot" for hierarchical)
- `force`: If true, recompute layout even if positions exist

Returns the pipeline (for chaining).
"""
function ensure_layout!(pipeline::Pipeline; algorithm="dot", force=false)
    if force || !has_layout_positions(pipeline)
        auto_layout_pipeline!(pipeline; algorithm=algorithm)
    end
    return pipeline
end
