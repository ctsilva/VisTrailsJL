"""
Module Execution Record

Stores information about a single module execution.
Similar to Python VisTrails' core/log/module_exec.py
"""

using Dates

"""
    ModuleExec

Records the execution of a single module in a workflow.
"""
mutable struct ModuleExec
    id::Int
    module_id::Int              # ID of module in pipeline
    module_name::String         # Name of module class
    ts_start::DateTime          # Start timestamp
    ts_end::Union{DateTime, Nothing}  # End timestamp
    cached::Bool                # Was result cached?
    completed::Int              # 1=success, -1=error, 0=incomplete
    error::String               # Error message if failed
    machine_id::Int             # Which machine executed this
    annotations::Dict{String, String}  # Additional metadata

    function ModuleExec(;
        id::Int=-1,
        module_id::Int=-1,
        module_name::String="",
        ts_start::DateTime=now(),
        ts_end::Union{DateTime, Nothing}=nothing,
        cached::Bool=false,
        completed::Int=0,
        error::String="",
        machine_id::Int=1,
        annotations::Dict{String, String}=Dict{String, String}()
    )
        new(id, module_id, module_name, ts_start, ts_end, cached,
            completed, error, machine_id, annotations)
    end
end

"""
    duration(exec::ModuleExec) -> Union{Millisecond, Nothing}

Calculate execution duration.
"""
function duration(exec::ModuleExec)
    if exec.ts_end !== nothing
        return exec.ts_end - exec.ts_start
    end
    return nothing
end

"""
    mark_completed!(exec::ModuleExec)

Mark execution as successfully completed.
"""
function mark_completed!(exec::ModuleExec)
    exec.ts_end = now()
    exec.completed = 1
end

"""
    mark_failed!(exec::ModuleExec, error::String)

Mark execution as failed with error message.
"""
function mark_failed!(exec::ModuleExec, error_msg::String)
    exec.ts_end = now()
    exec.completed = -1
    exec.error = error_msg
end

"""
    mark_cached!(exec::ModuleExec)

Mark execution as using cached result.
"""
function mark_cached!(exec::ModuleExec)
    exec.ts_end = now()
    exec.completed = 1
    exec.cached = true
end
