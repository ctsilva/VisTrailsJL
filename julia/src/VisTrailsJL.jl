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

# Execution logging and engines
include("core/log/log.jl")
include("core/interpreter/observers.jl")
include("core/interpreter/signatures.jl")
include("core/interpreter/engine.jl")
include("core/interpreter/parallel.jl")

# Progressive data layer
include("core/progressive/progressive.jl")

# Rendering
include("rendering/workflow_svg.jl")
include("rendering/tree_layout.jl")
include("rendering/version_tree_svg.jl")
include("rendering/auto_layout.jl")

# Packages
include("packages/basic/init.jl")
include("packages/julia/init.jl")
include("packages/control_flow/init.jl")
include("packages/pythoncalc/init.jl")
include("packages/matplotlib/init.jl")
include("packages/progressive/init.jl")

# Notebook support
include("notebook/init.jl")

# High-level API
include("api/api.jl")

# Exports
export load_vistrail, load_vistrail_internal, execute_pipeline, execute

# Execution engine exports
export Engine, OneShotEngine, CachedEngine, ParallelEngine, PipelineRun, run!, clear_cache!
export ExecutionObserver, ConsoleObserver
export on_run_start, on_module_start, on_module_done, on_module_cached, on_module_error, on_run_done
export module_signature, subpipeline_signatures, is_cacheable, thread_affinity
export get_input_list

# Progressive data layer exports
export RowIds, add!, remove!, take_first!, ranges
export ProgressiveTable, SegmentedColumn, column, column_names, row_ids, last_id, segment_views
export ProgressiveDict, snapshot, ProgressiveValue, set!, has_value, current_value
export subscribe!, unsubscribe!, has_changes, reset!, pending
export AbstractSubscription, TableSubscription, DictSubscription, ValueSubscription
export next_created!, next_updated!, next_deleted!, take_changes!, take_value!

# Progressive engine exports
export ProgressiveEngine, ProgressiveRun, start!, stop!, module_status, module_steps
export ExecutionStyle, OneShot, Progressive, execution_style, StepResult, StepContext
export init_state, step!, finish!, default_step_size
export param, has_input, input_container, input_subscription, input_value, set_output!
export define_fold_module!, define_map_module!, numeric_columns, consumed_rows
export on_module_step, on_sweep
export Vistrail, Pipeline, ModuleInstance, Connection
export add_module!, add_connection!, set_parameter!
export print_vistrail_info, print_pipeline_info
export get_pipeline
export render_pipeline_svg, save_pipeline_svg
export render_version_tree_svg, save_version_tree_svg
export auto_layout_pipeline!, ensure_layout!, has_layout_positions

# High-level API exports
export VistrailWrapper, PipelineWrapper, ExecutionResult
export load_workflow, load_package
export select_version!, select_latest_version!
export output_port, module_output
export get_input, get_module

# Notebook exports
export parse_notebook, NotebookCell, get_directive, has_directive
export load_package_from_notebook, register_notebook_package!, NotebookPackage
export parse_workflow_notebook, build_pipeline_from_workflow, execute_notebook_pipeline
export NotebookWorkflow, NotebookModuleDef

# Module registry exports
export module_exists, get_module_descriptor, list_modules, describe_module

# Conversion exports
export package_to_notebook, save_package_notebook, registered_package_to_notebook
export notebook_to_package_code, save_package_code
export vistrail_workflow_to_notebook, pipeline_to_notebook

# Initialize packages on module load
function __init__()
    initialize_basic_package!()
    initialize_julia_package!()
    initialize_control_flow_package!()
    initialize_pythoncalc_package!()
    initialize_matplotlib_package!()
    initialize_progressive_package!()
end

end # module
