"""
Notebook I/O - Save execution results to notebooks

Functions for reading/writing Jupyter notebooks and updating cells with execution outputs.
"""

using JSON
using Base64
using Plots

"""
    load_notebook_json(path::String) -> Dict

Load a notebook as a JSON dictionary.
"""
function load_notebook_json(path::String)
    content = read(path, String)
    return JSON.parse(content)
end

"""
    save_notebook_json(path::String, notebook::Dict)

Save a notebook JSON dictionary to a file.
"""
function save_notebook_json(path::String, notebook::Dict)
    open(path, "w") do f
        JSON.print(f, notebook, 1)  # indent=1 for readability
    end
end

"""
    find_cell_by_module_id(notebook::Dict, module_id::String) -> Union{Int, Nothing}

Find the index of a cell that defines a module with the given ID.
Returns the cell index (1-based) or nothing if not found.
"""
function find_cell_by_module_id(notebook::Dict, module_id::String)
    cells = get(notebook, "cells", [])

    for (idx, cell) in enumerate(cells)
        if cell["cell_type"] != "code"
            continue
        end

        # Check if cell source contains module-id directive
        source = if cell["source"] isa Vector
            join(cell["source"], "")
        else
            cell["source"]
        end

        # Look for #| module-id: <module_id>
        if occursin(r"#\|\s*module-id:\s*" * module_id * r"(\s|$)", source)
            return idx
        end
    end

    return nothing
end

"""
    format_output_for_notebook(value) -> Vector{String}

Format a value for display in notebook output.
Returns a vector of strings (one per line).
"""
function format_output_for_notebook(value)
    # Convert value to string representation
    str = sprint(show, "text/plain", value)

    # Split into lines and add newlines
    lines = split(str, '\n')
    return [line * "\n" for line in lines]
end

"""
    render_plot_to_png(plot) -> Vector{UInt8}

Render a Plots.jl plot to PNG format in memory.
Returns PNG data as bytes.
"""
function render_plot_to_png(plot)
    # Create a temporary file for the PNG
    tmpfile = tempname() * ".png"

    try
        # Save plot to temporary file
        Plots.savefig(plot, tmpfile)

        # Read the PNG data
        png_data = read(tmpfile)

        return png_data
    finally
        # Clean up temporary file
        if isfile(tmpfile)
            rm(tmpfile)
        end
    end
end

"""
    is_plot_object(value) -> Bool

Check if a value is a Plots.jl Plot object.
"""
function is_plot_object(value)
    return isa(value, Plots.Plot)
end

"""
    find_plot_in_outputs(outputs::Dict) -> Union{Plots.Plot, Nothing}

Search through outputs dictionary for a Plot object.
Returns the first Plot found, or nothing.
"""
function find_plot_in_outputs(outputs::Dict)
    for (key, value) in outputs
        if is_plot_object(value)
            return value
        end
    end
    return nothing
end

"""
    create_execute_result(outputs::Dict, execution_count::Int) -> Dict

Create an execute_result output for a notebook cell.
Automatically detects and includes Plot objects as image/png data.
"""
function create_execute_result(outputs::Dict, execution_count::Int)
    # Format the outputs dictionary as text
    output_text = format_output_for_notebook(outputs)

    # Create base data dictionary with text representation
    data = Dict{String, Any}(
        "text/plain" => output_text
    )

    # Check if outputs contain a Plot object
    plot_obj = find_plot_in_outputs(outputs)

    if plot_obj !== nothing
        try
            # Render plot to PNG
            png_bytes = render_plot_to_png(plot_obj)

            # Encode as base64
            png_base64 = base64encode(png_bytes)

            # Add image data to output
            data["image/png"] = png_base64

            println("    📊 Added plot image to notebook output")
        catch e
            @warn "Failed to render plot to PNG: $e"
        end
    end

    return Dict(
        "output_type" => "execute_result",
        "execution_count" => execution_count,
        "data" => data,
        "metadata" => Dict()
    )
end

"""
    update_cell_outputs!(notebook::Dict, cell_idx::Int, outputs::Dict, execution_count::Int)

Update a cell's outputs with execution results.
"""
function update_cell_outputs!(notebook::Dict, cell_idx::Int, outputs::Dict, execution_count::Int)
    cells = notebook["cells"]

    if cell_idx < 1 || cell_idx > length(cells)
        @warn "Cell index $cell_idx out of bounds (1-$(length(cells)))"
        return
    end

    cell = cells[cell_idx]

    # Update execution count
    cell["execution_count"] = execution_count

    # Create output
    output = create_execute_result(outputs, execution_count)

    # Replace outputs (clear previous outputs)
    cell["outputs"] = [output]
end

"""
    update_notebook_with_execution(
        notebook_path::String,
        module_id::String,
        outputs::Dict,
        execution_count::Int
    )

Update a notebook cell with execution results and save the notebook.
"""
function update_notebook_with_execution(
    notebook_path::String,
    module_id::String,
    outputs::Dict,
    execution_count::Int
)
    # Load notebook
    notebook = load_notebook_json(notebook_path)

    # Find the cell
    cell_idx = find_cell_by_module_id(notebook, module_id)

    if cell_idx === nothing
        @warn "Could not find cell for module '$module_id' in notebook"
        return
    end

    # Update the cell
    update_cell_outputs!(notebook, cell_idx, outputs, execution_count)

    # Save the notebook
    save_notebook_json(notebook_path, notebook)
end

"""
    clear_notebook_outputs(notebook_path::String)

Clear all outputs and execution counts from a notebook.
Useful for resetting a notebook before re-execution.
"""
function clear_notebook_outputs(notebook_path::String)
    notebook = load_notebook_json(notebook_path)

    for cell in get(notebook, "cells", [])
        if cell["cell_type"] == "code"
            cell["outputs"] = []
            cell["execution_count"] = nothing
        end
    end

    save_notebook_json(notebook_path, notebook)
    println("Cleared outputs from: $notebook_path")
end
