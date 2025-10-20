"""
VisTrailsJL

A Julia reimplementation of VisTrails workflow management system.

Maintains compatibility with original Python VisTrails .vt files while
providing native Julia execution and new capabilities.
"""
module VisTrailsJL

using Dates

# Core types
include("core/vistrail/port.jl")
include("core/vistrail/connection.jl")
include("core/vistrail/module.jl")
include("core/vistrail/pipeline.jl")
include("core/vistrail/vistrail.jl")

# Database/XML handling
include("db/services/io.jl")
include("db/services/locator.jl")
include("core/db/io.jl")

# Module registry
include("core/modules/module_registry.jl")

# Interpreter
include("core/interpreter/default.jl")

# Rendering
include("rendering/workflow_svg.jl")
include("rendering/tree_layout.jl")
include("rendering/version_tree_layout.jl")
include("rendering/version_tree_svg.jl")

# Packages
include("packages/basic/init.jl")
include("packages/julia/init.jl")
include("packages/control_flow/init.jl")
include("packages/pythoncalc/init.jl")

# Exports
export load_vistrail, execute_pipeline
export Vistrail, Pipeline, ModuleInstance, Connection
export add_module!, add_connection!, set_parameter!
export print_vistrail_info, print_pipeline_info
export get_pipeline
export render_pipeline_svg, save_pipeline_svg
export render_version_tree_svg, save_version_tree_svg

# Initialize packages on module load
function __init__()
    initialize_basic_package!()
    initialize_julia_package!()
    initialize_control_flow_package!()
    initialize_pythoncalc_package!()
end

end # module
