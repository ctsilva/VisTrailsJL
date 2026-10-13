"""
Execution observers

Observers receive events while an engine runs a pipeline: for console
output, saving results into notebooks, and (later) progress streaming.
Subtype `ExecutionObserver` and extend the callbacks you need; the defaults
do nothing.
"""

abstract type ExecutionObserver end

"""Called once before any module runs."""
on_run_start(::ExecutionObserver, run) = nothing

"""Called before a module computes, after its inputs are gathered."""
on_module_start(::ExecutionObserver, run, mod) = nothing

"""Called after a module computes successfully."""
on_module_done(::ExecutionObserver, run, mod, outputs) = nothing

"""Called instead of start/done when a module's outputs are reused from a cache."""
on_module_cached(::ExecutionObserver, run, mod, outputs) = nothing

"""Called after each step of a module in a progressive run, with its `StepResult`."""
on_module_step(::ExecutionObserver, run, mod, result, seconds) = nothing

"""Called after each sweep over the modules of a progressive run."""
on_sweep(::ExecutionObserver, run, sweep) = nothing

"""Called when a module throws; the run is then aborted."""
on_module_error(::ExecutionObserver, run, mod, err) = nothing

"""Called once at the end of a run; `err` is `nothing` on success."""
on_run_done(::ExecutionObserver, run, err) = nothing

"""
ConsoleObserver

Prints execution progress to stdout (the interpreter's historical output).
"""
struct ConsoleObserver <: ExecutionObserver end

function on_run_start(::ConsoleObserver, run)
    println("Executing pipeline with $(length(run.pipeline.modules)) modules...")
    println("Execution order: ", run.order)
end

function on_module_start(::ConsoleObserver, run, mod)
    println("  Module $(mod.id) ($(mod.descriptor.name)): computing...")
end

function on_module_done(::ConsoleObserver, run, mod, outputs)
    if !isempty(outputs)
        output_str = join(["$k=$(first(repr(v), 50))" for (k, v) in outputs], ", ")
        println("    Outputs: ", output_str)
    end
    println("    ✓ Complete")
end

function on_module_cached(::ConsoleObserver, run, mod, outputs)
    println("  Module $(mod.id) ($(mod.descriptor.name)): using cached results")
end

function on_module_error(::ConsoleObserver, run, mod, err)
    println("    ✗ Error: ", err)
end

function on_run_done(::ConsoleObserver, run, err)
    err === nothing && println("Pipeline execution complete!")
end
