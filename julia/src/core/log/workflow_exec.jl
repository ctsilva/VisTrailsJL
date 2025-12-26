"""
Workflow Execution Record

Stores information about a complete workflow execution.
Similar to Python VisTrails' core/log/workflow_exec.py
"""

using Dates

include("machine.jl")
include("module_exec.jl")

"""
    WorkflowExec

Records the execution of a complete workflow, including all module executions.
"""
mutable struct WorkflowExec
    id::Int
    user::String                # User who executed
    ip::String                  # IP address
    session::Int                # Session ID
    vt_version::String          # VisTrails version
    ts_start::DateTime          # Start timestamp
    ts_end::Union{DateTime, Nothing}  # End timestamp
    parent_type::String         # Usually "vistrail"
    parent_id::String           # Vistrail ID
    parent_version::Int         # Version number executed
    name::String                # Workflow name/description
    completed::Int              # 1=success, -1=error, 0=incomplete

    # Execution details
    machines::Vector{Machine}
    module_execs::Vector{ModuleExec}
    annotations::Dict{String, String}

    function WorkflowExec(;
        id::Int=-1,
        user::String=get(ENV, "USER", "unknown"),
        ip::String=get_local_ip(),
        session::Int=1,
        vt_version::String="0.1.0-julia",
        ts_start::DateTime=now(),
        ts_end::Union{DateTime, Nothing}=nothing,
        parent_type::String="vistrail",
        parent_id::String="",
        parent_version::Int=-1,
        name::String="",
        completed::Int=0,
        machines::Vector{Machine}=Machine[],
        module_execs::Vector{ModuleExec}=ModuleExec[],
        annotations::Dict{String, String}=Dict{String, String}()
    )
        new(id, user, ip, session, vt_version, ts_start, ts_end,
            parent_type, parent_id, parent_version, name, completed,
            machines, module_execs, annotations)
    end
end

"""
    get_local_ip() -> String

Get local IP address (simple version).
"""
function get_local_ip()
    try
        # Try to get hostname-based IP
        return string(getipaddr())
    catch
        return "127.0.0.1"
    end
end

"""
    duration(exec::WorkflowExec) -> Union{Millisecond, Nothing}

Calculate total workflow execution duration.
"""
function duration(exec::WorkflowExec)
    if exec.ts_end !== nothing
        return exec.ts_end - exec.ts_start
    end
    return nothing
end

"""
    add_machine!(exec::WorkflowExec, machine::Machine)

Add machine information to workflow execution.
"""
function add_machine!(exec::WorkflowExec, machine::Machine)
    push!(exec.machines, machine)
end

"""
    add_module_exec!(exec::WorkflowExec, mod_exec::ModuleExec)

Add module execution record with auto-incrementing ID.
"""
function add_module_exec!(exec::WorkflowExec, mod_exec::ModuleExec)
    # Auto-assign ID if not set
    if mod_exec.id == -1
        mod_exec.id = length(exec.module_execs) + 1
    end
    push!(exec.module_execs, mod_exec)
end

"""
    add_annotation!(exec::WorkflowExec, key::String, value::String)

Add annotation to workflow execution.
"""
function add_annotation!(exec::WorkflowExec, key::String, value::String)
    exec.annotations[key] = value
end

"""
    mark_completed!(exec::WorkflowExec)

Mark workflow execution as successfully completed.
"""
function mark_completed!(exec::WorkflowExec)
    exec.ts_end = now()
    exec.completed = 1
end

"""
    mark_failed!(exec::WorkflowExec, error_msg::String="")

Mark workflow execution as failed with optional error message.
"""
function mark_failed!(exec::WorkflowExec, error_msg::String="")
    exec.ts_end = now()
    exec.completed = -1
    if !isempty(error_msg)
        add_annotation!(exec, "error", error_msg)
    end
end

"""
    is_successful(exec::WorkflowExec) -> Bool

Check if workflow completed successfully.
"""
function is_successful(exec::WorkflowExec)
    return exec.completed == 1
end

"""
    failed_modules(exec::WorkflowExec) -> Vector{ModuleExec}

Get list of modules that failed.
"""
function failed_modules(exec::WorkflowExec)
    return filter(m -> m.completed == -1, exec.module_execs)
end

"""
    cached_modules(exec::WorkflowExec) -> Vector{ModuleExec}

Get list of modules that used cached results.
"""
function cached_modules(exec::WorkflowExec)
    return filter(m -> m.cached, exec.module_execs)
end
