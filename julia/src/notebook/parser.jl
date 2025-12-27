"""
Notebook Parser - Spike Implementation

Parses Jupyter notebooks (.ipynb) and extracts VisTrails directives.
Directives are comments starting with `#|` that define packages, modules, and workflows.
"""

using JSON

"""
    NotebookCell

Represents a single cell from a Jupyter notebook.
"""
struct NotebookCell
    cell_type::String          # "code" or "markdown"
    source::String             # Combined source lines
    directives::Dict{String, Any}  # Parsed directives
    code::String               # Code after directives
end

"""
    parse_notebook(path::String) -> Vector{NotebookCell}

Parse a Jupyter notebook file and return cells with extracted directives.
"""
function parse_notebook(path::String)
    # Read and parse JSON
    content = read(path, String)
    nb = JSON.parse(content)

    cells = NotebookCell[]

    for cell in nb["cells"]
        cell_type = cell["cell_type"]

        # Combine source lines into single string
        source = if cell["source"] isa Vector
            join(cell["source"], "")
        else
            cell["source"]
        end

        # Parse directives from source
        directives, code = parse_directives(source)

        push!(cells, NotebookCell(cell_type, source, directives, code))
    end

    return cells
end

"""
    parse_directives(source::String) -> (Dict{String, Any}, String)

Extract `#|` directives from source code.
Returns (directives_dict, remaining_code).

Handles simple key-value pairs and YAML-style nested structures.
"""
function parse_directives(source::String)
    lines = split(source, '\n')
    directives = Dict{String, Any}()
    code_lines = String[]

    i = 1
    while i <= length(lines)
        line = lines[i]
        stripped = strip(line)

        if startswith(stripped, "#|")
            # Extract directive content after "#|"
            directive_content = strip(stripped[3:end])

            if isempty(directive_content)
                # Empty directive line, skip
                i += 1
                continue
            end

            # Check if it's a key: value pair
            if occursin(":", directive_content)
                colon_pos = findfirst(':', directive_content)
                key = strip(directive_content[1:colon_pos-1])
                value_str = strip(directive_content[colon_pos+1:end])

                # Check if value is empty (nested structure follows)
                if isempty(value_str)
                    # Parse nested YAML-style structure
                    nested, i = parse_nested_directives(lines, i + 1)
                    directives[key] = nested
                else
                    # Simple key: value
                    directives[key] = parse_value(value_str)
                end
            else
                # Flag-style directive (just a name)
                directives[directive_content] = true
            end
        else
            # Not a directive, it's code
            push!(code_lines, line)
        end

        i += 1
    end

    return directives, join(code_lines, '\n')
end

"""
    parse_nested_directives(lines, start_index) -> (result, end_index)

Parse YAML-style nested directives (lists and dicts).
"""
function parse_nested_directives(lines, start_index)
    # Check if this is a list or dict by looking at first line
    is_list = false
    result_dict = Dict{String, Any}()
    result_list = []
    current_item = nothing
    i = start_index

    # Peek at first line to determine structure
    if i <= length(lines)
        first_line = lines[i]
        first_stripped = strip(first_line)
        if startswith(first_stripped, "#|")
            first_content = strip(first_stripped[3:end])
            if startswith(first_content, "- ")
                is_list = true
            end
        end
    end

    while i <= length(lines)
        line = lines[i]
        stripped = strip(line)

        if !startswith(stripped, "#|")
            # End of directives
            break
        end

        # Get content AFTER "#|" (preserving indentation)
        directive_prefix_end = findfirst("#|", stripped)[end] + 1
        if directive_prefix_end > length(stripped)
            content = ""
        else
            content = stripped[directive_prefix_end:end]
        end

        # Strip the single space that's typically after "#|" (if present)
        # This is YAML formatting, not indentation
        if !isempty(content) && content[1] == ' '
            content = content[2:end]
        end

        # NOW check if this line is indented (starts with space/tab for nesting)
        is_indented = !isempty(content) && (content[1] == ' ' || content[1] == '\t')
        content_stripped = strip(content)

        if isempty(content_stripped)
            i += 1
            continue
        end

        # If not indented and contains ":", this is a new top-level directive
        if !is_indented && occursin(":", content_stripped) && !startswith(content_stripped, "- ")
            # New top-level directive - stop parsing nested
            break
        end

        # Check indentation level by looking at content
        if startswith(content_stripped, "- ")
            # List item
            is_list = true
            if current_item !== nothing
                push!(result_list, current_item)
            end

            # Parse the rest of the line after "- "
            item_content = strip(content_stripped[3:end])

            if occursin(":", item_content)
                # It's a dict-like item: "- name: value"
                colon_pos = findfirst(':', item_content)
                key = strip(item_content[1:colon_pos-1])
                value = strip(item_content[colon_pos+1:end])
                current_item = Dict{String, Any}(key => parse_value(value))
            else
                # Simple list item
                current_item = parse_value(item_content)
            end
        elseif occursin(":", content_stripped)
            # Key-value pair (must be indented if we get here)
            colon_pos = findfirst(':', content_stripped)
            key = strip(content_stripped[1:colon_pos-1])
            value = strip(content_stripped[colon_pos+1:end])

            if is_list && current_item isa Dict
                # Continuation of list item dict
                current_item[key] = parse_value(value)
            else
                # Dict key-value (nested item)
                result_dict[key] = parse_value(value)
            end
        else
            # Something else - end parsing
            break
        end

        i += 1
    end

    # Add last list item if any
    if is_list && current_item !== nothing
        push!(result_list, current_item)
    end

    # Return appropriate structure
    result = is_list ? result_list : result_dict
    return result, i - 1
end

"""
    parse_value(s::AbstractString) -> Any

Parse a string value into appropriate type.
"""
function parse_value(s::AbstractString)
    s = String(strip(s))

    # Remove quotes if present
    if (startswith(s, '"') && endswith(s, '"')) || (startswith(s, '\'') && endswith(s, '\''))
        return s[2:end-1]
    end

    # Try to parse as integer
    int_match = tryparse(Int, s)
    if int_match !== nothing
        return int_match
    end

    # Try to parse as float
    float_match = tryparse(Float64, s)
    if float_match !== nothing
        return float_match
    end

    # Boolean
    if lowercase(s) in ["true", "yes"]
        return true
    elseif lowercase(s) in ["false", "no"]
        return false
    end

    # Return as string
    return s
end

"""
    get_directive(cell::NotebookCell, key::String, default=nothing) -> Any

Get a directive value from a cell.
"""
function get_directive(cell::NotebookCell, key::String, default=nothing)
    return get(cell.directives, key, default)
end

"""
    has_directive(cell::NotebookCell, key::String) -> Bool

Check if a cell has a specific directive.
"""
function has_directive(cell::NotebookCell, key::String)
    return haskey(cell.directives, key)
end
