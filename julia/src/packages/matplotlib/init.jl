"""
Matplotlib Package Initialization

Registers matplotlib plotting modules with the VisTrails module registry.
"""

include("matplotlib.jl")

################################################################################
# Module Registration Functions
################################################################################

function register_mplfigure!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.matplotlib",
        "MplFigure",
        MplFigure,
        [InputPort("addPlot", Vector, optional=true)],  # List of plot functions
        [OutputPort("figure", Any), OutputPort("self", Any)],  # Plots.jl figure (self for compatibility)
        Tuple{String, Type}[]  # No parameters
    )
    register_module!(descriptor)
end

function register_mplfigureoutput!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.matplotlib",
        "MplFigureOutput",
        MplFigureOutput,
        [InputPort("value", Any)],  # MplFigure
        OutputPort[],  # No outputs
        Tuple{String, Type}[]
    )
    register_module!(descriptor)
end

function register_mpllineplot!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.matplotlib",
        "MplLinePlot",
        MplLinePlot,
        [
            InputPort("x", Vector, optional=true),
            InputPort("y", Vector),
            InputPort("marker", String, optional=true),
            InputPort("color", String, optional=true),
            InputPort("label", String, optional=true)
        ],
        [OutputPort("value", Function)],  # Returns a function
        Tuple{String, Type}[]
    )
    register_module!(descriptor)
end

function register_mplscatter!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.matplotlib",
        "MplScatter",
        MplScatter,
        [
            InputPort("x", Vector),
            InputPort("y", Vector),
            InputPort("s", Any, optional=true),  # Marker size (scalar or array)
            InputPort("marker", String, optional=true),
            InputPort("color", String, optional=true),
            InputPort("label", String, optional=true)
        ],
        [OutputPort("value", Function)],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)
end

function register_mplbar!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.matplotlib",
        "MplBar",
        MplBar,
        [
            InputPort("left", Vector),
            InputPort("height", Vector),
            InputPort("width", Float64, optional=true),
            InputPort("color", String, optional=true),
            InputPort("label", String, optional=true)
        ],
        [OutputPort("value", Function)],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)
end

function register_mplhist!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.matplotlib",
        "MplHist",
        MplHist,
        [
            InputPort("x", Vector),
            InputPort("bins", Int, optional=true),
            InputPort("color", String, optional=true),
            InputPort("label", String, optional=true)
        ],
        [OutputPort("value", Function)],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)
end

################################################################################
# Package Initialization
################################################################################

function initialize_matplotlib_package!()
    @info "Initializing matplotlib package..."

    register_mplfigure!()
    register_mplfigureoutput!()
    register_mpllineplot!()
    register_mplscatter!()
    register_mplbar!()
    register_mplhist!()

    @info "  ✓ Matplotlib package initialized"
    @info "  Registered modules: MplFigure, MplFigureOutput, MplLinePlot, MplScatter, MplBar, MplHist"
end
