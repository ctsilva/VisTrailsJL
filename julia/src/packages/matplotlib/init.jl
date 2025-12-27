"""
Matplotlib package for VisTrailsJL

This package provides matplotlib-style plotting modules using Plots.jl as the backend.
Based on the Python VisTrails matplotlib package architecture.

Key design pattern from Python version:
- Plot modules (MplLinePlot, MplScatter, etc.) output FUNCTIONS (lambdas)
- MplFigure receives these functions via addPlot port and calls them
- MplFigureOutput renders/saves the final figure

Example workflow:
  MplLinePlot.value → MplFigure.addPlot → MplFigure.figure → MplFigureOutput.value
"""

using Plots

################################################################################
# Core Infrastructure
################################################################################

"""
    MplFigure

Container for matplotlib-style plots. Receives plot functions via addPlot port
and executes them to build the figure.

Inputs:
- addPlot: List of plot functions (from MplLinePlot, MplScatter, etc.)

Outputs:
- figure: Plots.jl Plot object
"""
struct MplFigure
    # No fields - stateless module
end

function compute(self::ModuleInstance, ::Type{MplFigure})
    # Get list of plot functions
    plot_functions = get_input(self, "addPlot")

    # Create new figure
    plt = Plots.plot()

    # Execute each plot function to add to figure
    for plot_fn in plot_functions
        plot_fn(plt)
    end

    # Set output
    set_output(self, "figure", plt)
end

"""
    MplFigureOutput

Output module for saving matplotlib figures to files.

Inputs:
- value: MplFigure to render

Outputs files to the standard VisTrails output location.
"""
struct MplFigureOutput
    # No fields
end

function compute(self::ModuleInstance, ::Type{MplFigureOutput})
    # Get the figure
    figure = get_input(self, "value")

    # TODO: Get output configuration (width, height, format, filename)
    # For now, save to a default location
    output_file = "matplotlib_output.png"

    # Save the plot
    Plots.savefig(figure, output_file)

    @info "Matplotlib figure saved to: $output_file"
end

################################################################################
# Plot Modules
################################################################################

"""
    MplLinePlot

Line plot module. Outputs a function that adds a line plot to a figure.

Inputs:
- x: X-axis data (optional, defaults to 1:length(y))
- y: Y-axis data (required)
- marker: Marker style (optional)
- color: Line color (optional)
- label: Line label for legend (optional)

Outputs:
- value: Function that adds line plot to figure
"""
struct MplLinePlot
    # No fields - configuration via ports
end

function compute(self::ModuleInstance, ::Type{MplLinePlot})
    # Get inputs
    y = get_input(self, "y")
    x = has_input(self, "x") ? get_input(self, "x") : collect(1:length(y))

    # Optional styling parameters
    marker = has_input(self, "marker") ? get_input(self, "marker") : nothing
    color = has_input(self, "color") ? get_input(self, "color") : nothing
    label_text = has_input(self, "label") ? get_input(self, "label") : nothing

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
    set_output(self, "value", plot_fn)
end

"""
    MplScatter

Scatter plot module.

Inputs:
- x: X-axis data (required)
- y: Y-axis data (required)
- marker: Marker style (optional)
- color: Point color (optional)
- label: Label for legend (optional)

Outputs:
- value: Function that adds scatter plot to figure
"""
struct MplScatter
    # No fields
end

function compute(self::ModuleInstance, ::Type{MplScatter})
    x = get_input(self, "x")
    y = get_input(self, "y")

    marker = has_input(self, "marker") ? get_input(self, "marker") : :circle
    color = has_input(self, "color") ? get_input(self, "color") : nothing
    label_text = has_input(self, "label") ? get_input(self, "label") : nothing

    plot_fn = function(figure)
        kwargs = Dict{Symbol, Any}(:marker => marker, :seriestype => :scatter)
        if color !== nothing
            kwargs[:color] = color
        end
        if label_text !== nothing
            kwargs[:label] = label_text
        end

        Plots.plot!(figure, x, y; kwargs...)
    end

    set_output(self, "value", plot_fn)
end

"""
    MplBar

Bar chart module.

Inputs:
- left: X positions (left edges of bars)
- height: Bar heights
- width: Bar width (optional, default 0.8)
- color: Bar color (optional)
- label: Label for legend (optional)

Outputs:
- value: Function that adds bar chart to figure
"""
struct MplBar
    # No fields
end

function compute(self::ModuleInstance, ::Type{MplBar})
    left = get_input(self, "left")
    height = get_input(self, "height")

    width = has_input(self, "width") ? get_input(self, "width") : 0.8
    color = has_input(self, "color") ? get_input(self, "color") : nothing
    label_text = has_input(self, "label") ? get_input(self, "label") : nothing

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

    set_output(self, "value", plot_fn)
end

"""
    MplHist

Histogram module.

Inputs:
- x: Data to histogram
- bins: Number of bins (optional, default: auto)
- color: Bar color (optional)
- label: Label for legend (optional)

Outputs:
- value: Function that adds histogram to figure
"""
struct MplHist
    # No fields
end

function compute(self::ModuleInstance, ::Type{MplHist})
    x = get_input(self, "x")

    bins = has_input(self, "bins") ? get_input(self, "bins") : :auto
    color = has_input(self, "color") ? get_input(self, "color") : nothing
    label_text = has_input(self, "label") ? get_input(self, "label") : nothing

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

    set_output(self, "value", plot_fn)
end

################################################################################
# Package Registration
################################################################################

function initialize_matplotlib_package!()
    @info "Initializing matplotlib package..."

    # Register MplFigure
    register_module!(
        ModuleDescriptor(
            package="org.vistrails.vistrails.matplotlib",
            name="MplFigure",
            module_type=MplFigure,
            input_ports=[
                PortDescriptor("addPlot", "basic:List", required=false)  # List of plot functions
            ],
            output_ports=[
                PortDescriptor("figure", "matplotlib:MplFigure")
            ],
            parameters=[]
        )
    )

    # Register MplFigureOutput
    register_module!(
        ModuleDescriptor(
            package="org.vistrails.vistrails.matplotlib",
            name="MplFigureOutput",
            module_type=MplFigureOutput,
            input_ports=[
                PortDescriptor("value", "matplotlib:MplFigure")
            ],
            output_ports=[],
            parameters=[]
        )
    )

    # Register MplLinePlot
    register_module!(
        ModuleDescriptor(
            package="org.vistrails.vistrails.matplotlib",
            name="MplLinePlot",
            module_type=MplLinePlot,
            input_ports=[
                PortDescriptor("x", "basic:List", required=false),
                PortDescriptor("y", "basic:List", required=true),
                PortDescriptor("marker", "basic:String", required=false),
                PortDescriptor("color", "basic:String", required=false),
                PortDescriptor("label", "basic:String", required=false)
            ],
            output_ports=[
                PortDescriptor("value", "matplotlib:MplLinePlot")
            ],
            parameters=[]
        )
    )

    # Register MplScatter
    register_module!(
        ModuleDescriptor(
            package="org.vistrails.vistrails.matplotlib",
            name="MplScatter",
            module_type=MplScatter,
            input_ports=[
                PortDescriptor("x", "basic:List", required=true),
                PortDescriptor("y", "basic:List", required=true),
                PortDescriptor("marker", "basic:String", required=false),
                PortDescriptor("color", "basic:String", required=false),
                PortDescriptor("label", "basic:String", required=false)
            ],
            output_ports=[
                PortDescriptor("value", "matplotlib:MplScatter")
            ],
            parameters=[]
        )
    )

    # Register MplBar
    register_module!(
        ModuleDescriptor(
            package="org.vistrails.vistrails.matplotlib",
            name="MplBar",
            module_type=MplBar,
            input_ports=[
                PortDescriptor("left", "basic:List", required=true),
                PortDescriptor("height", "basic:List", required=true),
                PortDescriptor("width", "basic:Float", required=false),
                PortDescriptor("color", "basic:String", required=false),
                PortDescriptor("label", "basic:String", required=false)
            ],
            output_ports=[
                PortDescriptor("value", "matplotlib:MplBar")
            ],
            parameters=[]
        )
    )

    # Register MplHist
    register_module!(
        ModuleDescriptor(
            package="org.vistrails.vistrails.matplotlib",
            name="MplHist",
            module_type=MplHist,
            input_ports=[
                PortDescriptor("x", "basic:List", required=true),
                PortDescriptor("bins", "basic:Integer", required=false),
                PortDescriptor("color", "basic:String", required=false),
                PortDescriptor("label", "basic:String", required=false)
            ],
            output_ports=[
                PortDescriptor("value", "matplotlib:MplHist")
            ],
            parameters=[]
        )
    )

    @info "  ✓ Matplotlib package initialized"
    @info "  Registered modules: MplFigure, MplFigureOutput, MplLinePlot, MplScatter, MplBar, MplHist"
end
