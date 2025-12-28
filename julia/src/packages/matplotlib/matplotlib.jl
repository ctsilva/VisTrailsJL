"""
Matplotlib Package - Plotting modules using Plots.jl backend

Based on Python VisTrails matplotlib package architecture.
Plot modules output functions (lambdas) that MplFigure calls to build the plot.
"""

using Plots
using JSON

################################################################################
# Helper Functions
################################################################################

"""
Parse parameter value - handles JSON strings from .vt files
"""
function parse_param_value(val)
    if val isa String && startswith(val, "[")
        try
            return JSON.parse(val)
        catch
            return val
        end
    end
    return val
end

################################################################################
# MplFigure - Container for plots
################################################################################

struct MplFigure
end

function compute(self::ModuleInstance, ::Type{MplFigure})
    # Get plot functions from inputs - can be single function or array
    addplot_input = get(self.inputs, "addPlot", nothing)

    # Normalize to array
    plot_functions = if addplot_input isa Function
        [addplot_input]
    elseif addplot_input isa AbstractArray
        collect(addplot_input)
    elseif addplot_input === nothing
        []
    else
        [addplot_input]
    end

    # Create new figure
    plt = Plots.plot()

    # Execute each plot function to add to figure
    for plot_fn in plot_functions
        plot_fn(plt)
    end

    # Set outputs - both "figure" and "self" for compatibility
    self.outputs["figure"] = plt
    self.outputs["self"] = plt  # Python VisTrails uses "self" as output port name

    self.uptodate = true
    self.cache_state = :valid
    return self.outputs
end

################################################################################
# MplFigureOutput - Save figure to file
################################################################################

struct MplFigureOutput
end

function compute(self::ModuleInstance, ::Type{MplFigureOutput})
    # Get the figure
    figure = get(self.inputs, "value", nothing)

    # TODO: Get output configuration (width, height, format, filename)
    # For now, save to a default location
    output_file = "matplotlib_output.png"

    # Save the plot
    Plots.savefig(figure, output_file)

    @info "Matplotlib figure saved to: $output_file"

    self.uptodate = true
    self.cache_state = :valid
    return self.outputs
end

################################################################################
# MplLinePlot - Line plots
################################################################################

struct MplLinePlot
end

function compute(self::ModuleInstance, ::Type{MplLinePlot})
    # Get inputs - try inputs first, then parameters
    # Parse JSON strings from .vt files
    y_raw = get(self.inputs, "y", get(self.parameters, "y", nothing))
    y = parse_param_value(y_raw)

    x_raw = haskey(self.inputs, "x") ? get(self.inputs, "x", nothing) :
            haskey(self.parameters, "x") ? get(self.parameters, "x", nothing) : nothing
    x = if x_raw !== nothing
        parse_param_value(x_raw)
    elseif y !== nothing
        collect(1:length(y))
    else
        nothing
    end

    # Check if we have data
    if y === nothing
        error("MplLinePlot requires 'y' data via input port or parameter")
    end

    # Optional styling parameters
    marker = haskey(self.inputs, "marker") ? get(self.inputs, "marker", nothing) : nothing
    color = haskey(self.inputs, "color") ? get(self.inputs, "color", nothing) : nothing
    label_text = haskey(self.inputs, "label") ? get(self.inputs, "label", nothing) : nothing

    # Create plot function (lambda) like Python version
    plot_fn = function(figure)
        # Build kwargs
        kwargs = Dict{Symbol, Any}()
        if marker !== nothing
            kwargs[:marker] = Symbol(marker)
        end
        if color !== nothing
            kwargs[:color] = color
        end
        if label_text !== nothing
            kwargs[:label] = label_text
        end

        # Add line plot to existing figure
        Plots.plot!(figure, x, y; kwargs...)
    end

    # Output the function (not the plot itself!)
    self.outputs["value"] = plot_fn

    self.uptodate = true
    self.cache_state = :valid
    return self.outputs
end

################################################################################
# MplScatter - Scatter plots
################################################################################

struct MplScatter
end

function compute(self::ModuleInstance, ::Type{MplScatter})
    x = get(self.inputs, "x", nothing)
    y = get(self.inputs, "y", nothing)

    marker = haskey(self.inputs, "marker") ? get(self.inputs, "marker", nothing) : :circle
    color = haskey(self.inputs, "color") ? get(self.inputs, "color", nothing) : nothing
    label_text = haskey(self.inputs, "label") ? get(self.inputs, "label", nothing) : nothing

    # Add support for 's' parameter (marker size in points²)
    # In matplotlib, s is the marker area in points²
    # In Plots.jl, markersize is the marker radius/size
    s = haskey(self.inputs, "s") ? get(self.inputs, "s", nothing) : nothing

    plot_fn = function(figure)
        kwargs = Dict{Symbol, Any}(:marker => marker, :seriestype => :scatter)
        if color !== nothing
            kwargs[:color] = color
        end
        if label_text !== nothing
            kwargs[:label] = label_text
        end

        # Handle marker size
        if s !== nothing
            # Convert matplotlib s (area in points²) to Plots.jl markersize
            # matplotlib: s is area, so radius = sqrt(s/π)
            # Plots.jl markersize is roughly the radius in points
            # Scale factor to make sizes reasonable
            if s isa AbstractArray
                # Array of sizes - convert each
                markersize = [sqrt(si / π) * 0.5 for si in s]
                kwargs[:markersize] = markersize
            else
                # Scalar size
                markersize = sqrt(s / π) * 0.5
                kwargs[:markersize] = markersize
            end
        end

        Plots.plot!(figure, x, y; kwargs...)
    end

    self.outputs["value"] = plot_fn

    self.uptodate = true
    self.cache_state = :valid
    return self.outputs
end

################################################################################
# MplBar - Bar charts
################################################################################

struct MplBar
end

function compute(self::ModuleInstance, ::Type{MplBar})
    left = get(self.inputs, "left", nothing)
    height = get(self.inputs, "height", nothing)

    width = haskey(self.inputs, "width") ? get(self.inputs, "width", nothing) : 0.8
    color = haskey(self.inputs, "color") ? get(self.inputs, "color", nothing) : nothing
    label_text = haskey(self.inputs, "label") ? get(self.inputs, "label", nothing) : nothing

    plot_fn = function(figure)
        kwargs = Dict{Symbol, Any}(:bar_width => width, :seriestype => :bar)
        if color !== nothing
            kwargs[:color] = color
        end
        if label_text !== nothing
            kwargs[:label] = label_text
        end

        Plots.plot!(figure, left, height; kwargs...)
    end

    self.outputs["value"] = plot_fn

    self.uptodate = true
    self.cache_state = :valid
    return self.outputs
end

################################################################################
# MplHist - Histograms
################################################################################

struct MplHist
end

function compute(self::ModuleInstance, ::Type{MplHist})
    # Check inputs first, then parameters (like MplLinePlot)
    x_raw = haskey(self.inputs, "x") ? get(self.inputs, "x", nothing) :
            haskey(self.parameters, "x") ? get(self.parameters, "x", nothing) : nothing
    x = parse_param_value(x_raw)

    bins = haskey(self.inputs, "bins") ? get(self.inputs, "bins", nothing) :
           haskey(self.parameters, "bins") ? parse_param_value(get(self.parameters, "bins", nothing)) : :auto
    color = haskey(self.inputs, "color") ? get(self.inputs, "color", nothing) : nothing
    label_text = haskey(self.inputs, "label") ? get(self.inputs, "label", nothing) : nothing

    plot_fn = function(figure)
        kwargs = Dict{Symbol, Any}(:bins => bins, :seriestype => :histogram)
        if color !== nothing
            kwargs[:color] = color
        end
        if label_text !== nothing
            kwargs[:label] = label_text
        end

        Plots.histogram!(figure, x; kwargs...)
    end

    self.outputs["value"] = plot_fn

    self.uptodate = true
    self.cache_state = :valid
    return self.outputs
end
