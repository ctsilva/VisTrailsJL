"""
Execution Log

Stores complete execution history for a vistrail.
Similar to Python VisTrails' core/log/log.py
"""

using Dates

include("workflow_exec.jl")

"""
    Log

Complete execution log containing multiple workflow executions.
Maps to the <log> element in .vt files.
"""
mutable struct Log
    id::Int
    vistrail_id::String
    workflow_execs::Vector{WorkflowExec}

    function Log(;
        id::Int=-1,
        vistrail_id::String="",
        workflow_execs::Vector{WorkflowExec}=WorkflowExec[]
    )
        new(id, vistrail_id, workflow_execs)
    end
end

"""
    add_workflow_exec!(log::Log, wf_exec::WorkflowExec)

Add a workflow execution to the log.
"""
function add_workflow_exec!(log::Log, wf_exec::WorkflowExec)
    push!(log.workflow_execs, wf_exec)
end

"""
    get_last_exec_id(log::Log) -> Int

Get the ID of the last workflow execution.
"""
function get_last_exec_id(log::Log)
    if isempty(log.workflow_execs)
        return -1
    end
    return maximum(wf_exec.id for wf_exec in log.workflow_execs)
end

"""
    get_execs_for_version(log::Log, version::Int) -> Vector{WorkflowExec}

Get all executions for a specific vistrail version.
"""
function get_execs_for_version(log::Log, version::Int)
    return filter(wf -> wf.parent_version == version, log.workflow_execs)
end

"""
    successful_execs(log::Log) -> Vector{WorkflowExec}

Get all successful workflow executions.
"""
function successful_execs(log::Log)
    return filter(wf -> wf.completed == 1, log.workflow_execs)
end

"""
    failed_execs(log::Log) -> Vector{WorkflowExec}

Get all failed workflow executions.
"""
function failed_execs(log::Log)
    return filter(wf -> wf.completed == -1, log.workflow_execs)
end

"""
    print_summary(log::Log)

Print a summary of the execution log.
"""
function print_summary(log::Log)
    println("=" ^ 60)
    println("Execution Log Summary")
    println("=" ^ 60)

    println("\nTotal executions: ", length(log.workflow_execs))

    success = successful_execs(log)
    failed = failed_execs(log)

    println("  Successful: ", length(success))
    println("  Failed: ", length(failed))

    if !isempty(log.workflow_execs)
        # Group by version
        versions = unique(wf.parent_version for wf in log.workflow_execs)
        println("\nExecutions by version:")
        for version in sort(collect(versions))
            execs = get_execs_for_version(log, version)
            println("  Version $version: $(length(execs)) executions")
        end

        # Show recent executions
        println("\nRecent executions:")
        recent = sort(log.workflow_execs, by=wf->wf.ts_start, rev=true)[1:min(5, end)]
        for wf_exec in recent
            status = wf_exec.completed == 1 ? "✓" : (wf_exec.completed == -1 ? "✗" : "?")
            dur = duration(wf_exec)
            dur_str = dur !== nothing ? " ($(dur.value)ms)" : ""
            println("  $status Version $(wf_exec.parent_version) - $(wf_exec.ts_start)$dur_str")

            # Show failed modules
            if wf_exec.completed == -1
                for mod_exec in failed_modules(wf_exec)
                    println("      Failed: $(mod_exec.module_name) - $(mod_exec.error)")
                end
            end
        end
    end
end
