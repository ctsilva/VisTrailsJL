"""
Parallel scheduling of one-shot modules (`ParallelEngine`)

Dependency counting over the pipeline: a module becomes ready when all its
producers have finished, ready modules start as Julia tasks (in topological
order, at most `max_tasks` at a time), and each completion releases its
consumers. One-shot outputs do not change once produced, so unlike the
progressive engine no further exclusion between modules is needed.

Failure contract (after ProgressiVis' parallel scheduler): after the first
failure no new module starts; running modules are waited for; then the error
is rethrown, or a `CompositeException` if several modules failed. The same
join happens if the scheduler itself is interrupted.
"""

function schedule_modules!(engine::ParallelEngine, run::PipelineRun)
    position = Dict(id => i for (i, id) in enumerate(run.order))
    producers = Dict(id => unique(c.source_module_id for c in get_connections_to(run.pipeline, id))
                     for id in run.order)
    consumers = Dict(id => Int[] for id in run.order)
    for (id, sources) in producers, source in sources
        push!(consumers[source], id)
    end

    waiting = Dict(id => length(producers[id]) for id in run.order)
    ready = [id for id in run.order if waiting[id] == 0]
    finished = Channel{Tuple{Int, Any}}(Inf)
    running = 0
    failures = Tuple{Any, Any}[]  # (exception, backtrace)

    function complete!(module_id, failure)
        if failure !== nothing
            push!(failures, failure)
            return
        end
        for consumer in consumers[module_id]
            waiting[consumer] -= 1
            if waiting[consumer] == 0
                push!(ready, consumer)
            end
        end
        sort!(ready, by=id -> position[id])
    end

    function attempt(module_id)
        try
            execute_module!(engine.base, run, module_id)
            return nothing
        catch e
            return (e, catch_backtrace())
        end
    end

    try
        while true
            while isempty(failures) && !isempty(ready) && running < engine.max_tasks
                next_id = popfirst!(ready)
                if thread_affinity(run.instances[next_id].descriptor.module_type) == :main
                    # Run on this task, which must be the main thread
                    complete!(next_id, run_on_main_thread(attempt, run, next_id))
                else
                    let id = next_id  # each task gets its own binding
                        Threads.@spawn put!(finished, (id, attempt(id)))
                    end
                    running += 1
                end
            end

            running == 0 && break

            done_id, failure = take!(finished)
            running -= 1
            complete!(done_id, failure)
        end
    catch
        # The scheduler itself was interrupted: join running modules first
        while running > 0
            take!(finished)
            running -= 1
        end
        rethrow()
    end

    if length(failures) == 1
        throw(first(failures)[1])
    elseif length(failures) > 1
        throw(CompositeException([CapturedException(e, bt) for (e, bt) in failures]))
    end
end

function run_on_main_thread(attempt, run::PipelineRun, module_id::Int)
    if Threads.threadid() != 1
        mod = run.instances[module_id]
        err = ErrorException("module $(mod.descriptor.name) (id $module_id) must run on the main " *
                             "thread: call run! with a ParallelEngine from the main task")
        return (err, backtrace())
    end
    return attempt(module_id)
end
