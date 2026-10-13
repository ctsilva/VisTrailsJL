"""
ProgressiveEngine: modules run in bounded steps over change-tracked data

Progressive modules keep running state and, at each step, consume a bounded
number of new items (rows) from their inputs' subscriptions, then publish
improved results. The scheduler sweeps the modules in topological order;
each step's size comes from a time predictor so that a step takes about
`quantum` seconds. Modules finish by propagation: a module is done when its
producers are done and it has consumed all their changes.

One-shot modules take part too: their outputs are `ProgressiveValue`s, and
they recompute whenever an input changed (ProgressiVis does the same for
modules that cannot work incrementally).

Module contract (see docs/EXECUTION.md, "Writing progressive modules"):

    execution_style(::Type{T}) = Progressive()
    init_state(::Type{T}, ctx::StepContext) -> state     # create outputs, subscribe
    step!(state, ctx::StepContext, budget::Int) -> StepResult
    finish!(state, ctx::StepContext)                     # optional, when done
"""

abstract type ExecutionStyle end
struct OneShot <: ExecutionStyle end
struct Progressive <: ExecutionStyle end

"""
    execution_style(module_type::Type) -> OneShot() | Progressive()

How a module type executes: `OneShot()` (the default) through `compute`, or
`Progressive()` through `init_state` and `step!`.
"""
execution_style(::Type) = OneShot()

"""
    StepResult(status, items)

Returned by `step!`: `status` is `:ready` (more work available now),
`:blocked` (waiting for input changes) or `:done` (finished); `items` is the
amount of work done (e.g. rows consumed), used by the time predictor.
"""
struct StepResult
    status::Symbol
    items::Int

    function StepResult(status::Symbol, items::Integer)
        status in (:ready, :blocked, :done) ||
            throw(ArgumentError("step status must be :ready, :blocked or :done, got :$status"))
        return new(status, items)
    end
end

function init_state end
function step! end
finish!(state, ctx) = nothing

"""
    ready_to_step(state, ctx) -> Bool

Whether a progressive module can step now (default: yes). A module that is
not ready (e.g. a fold whose parameter comes from an input with no value
yet) is not stepped; once its producers are done it completes.
"""
ready_to_step(state, ctx) = true

"""
    is_input_module(module_type::Type) -> Bool

Input modules (e.g. `Variable`) receive values from outside during a run
(`set_variable!`). While a run's inputs are open they never finish, so a
run started with `start!` keeps going until `close_inputs!` or `stop!`.
"""
is_input_module(::Type) = false

"""
    default_step_size(module_type::Type) -> Int

Items in a module's first step, before the time predictor has data.
"""
default_step_size(::Type) = 1_000

"""
    StepContext

What a module sees while it runs: its parameters, its input containers and
subscriptions (per input port, in connection order), and its outputs.
"""
mutable struct StepContext
    run::Union{PipelineRun, Nothing}
    mod::ModuleInstance
    inputs::Dict{String, Vector{Any}}
    subscriptions::Dict{String, Vector{AbstractSubscription}}
    producers::Vector{Int}
    outputs::Dict{String, Any}
end

"""
    param(ctx, name, default=nothing)

A module parameter, or `default` if it is not set. If a value (e.g. a
`Variable`) is connected to an input port of the same name, its current
value wins: any parameter can be driven live.
"""
function param(ctx::StepContext, name::AbstractString, default=nothing)
    sources = get(ctx.inputs, String(name), nothing)
    if sources !== nothing && length(sources) == 1
        source = only(sources)
        source isa ProgressiveValue && has_value(source) && return current_value(source)
    end
    return get(ctx.mod.parameters, String(name), default)
end

has_input(ctx::StepContext, port::AbstractString) = !isempty(get(ctx.inputs, String(port), Any[]))

"""
    input_container(ctx, port) / input_subscription(ctx, port)

The container connected to an input port, and this module's subscription to
it (for ports with exactly one connection).
"""
function input_container(ctx::StepContext, port::AbstractString)
    sources = get(ctx.inputs, String(port), Any[])
    length(sources) == 1 || error("input port '$port' of $(ctx.mod.descriptor.name) has $(length(sources)) connections, expected 1")
    return only(sources)
end

function input_subscription(ctx::StepContext, port::AbstractString)
    subs = get(ctx.subscriptions, String(port), AbstractSubscription[])
    length(subs) == 1 || error("input port '$port' of $(ctx.mod.descriptor.name) has $(length(subs)) connections, expected 1")
    return only(subs)
end

"""
    input_value(ctx, port, default=nothing)

The current value of a `ProgressiveValue` input (e.g. from a constant module),
or `default` if the port is not connected or has no value yet.
"""
function input_value(ctx::StepContext, port::AbstractString, default=nothing)
    has_input(ctx, port) || return default
    pv = input_container(ctx, port)
    pv isa ProgressiveValue || error("input port '$port' is not connected to a single value")
    return has_value(pv) ? current_value(pv) : default
end

"""
    set_output!(ctx, port, container)

Declare an output container (in `init_state`). Outputs are assigned once.
"""
function set_output!(ctx::StepContext, port::AbstractString, container)
    outputs = ctx.outputs
    haskey(outputs, String(port)) && error("output '$port' of $(ctx.mod.descriptor.name) is already set")
    outputs[String(port)] = container
    return container
end

input_has_changes(ctx::StepContext) =
    any(has_changes(sub) for subs in values(ctx.subscriptions) for sub in subs)

# Time predictor: items per second over the last steps, ignoring each
# module's first step that processed items (it includes JIT compilation of
# the code that processes them; an earlier empty step may not)

const PREDICTOR_WINDOW = 7
const MAX_STEP_SIZE = 1 << 30

mutable struct StepPredictor
    first_step::Bool
    items::Vector{Int}
    seconds::Vector{Float64}
end

StepPredictor() = StepPredictor(true, Int[], Float64[])

function record!(p::StepPredictor, items::Int, seconds::Float64)
    items > 0 || return p
    if p.first_step
        p.first_step = false
        return p
    end
    push!(p.items, items); push!(p.seconds, seconds)
    if length(p.items) > PREDICTOR_WINDOW
        popfirst!(p.items); popfirst!(p.seconds)
    end
    return p
end

function predict(p::StepPredictor, quantum::Float64, default::Int)
    total_seconds = sum(p.seconds; init=0.0)
    (isempty(p.items) || total_seconds <= 0) && return default
    rate = sum(p.items) / total_seconds
    return clamp(ceil(Int, rate * quantum), 1, MAX_STEP_SIZE)
end

"""
    ProgressiveEngine(; quantum=0.1, step_size=nothing, max_time=Inf, workers=Threads.nthreads(),
                        interactive_quantum=0.02, state_cache=nothing)

Runs pipelines progressively: progressive modules in bounded steps of about
`quantum` seconds each (sized by a time predictor), one-shot modules
recomputed when their inputs change. `step_size`, if given, is called as
`step_size(module_id)` to choose every step's size instead (for tests).
`max_time` bounds the whole run, in seconds. With `workers > 1`, steps of
different modules run in parallel on threads (including a producer and its
consumers); with `workers = 1`, modules step one at a time in sweeps.
After an input changes (`set_variable!`), the modules downstream of it run
first, with steps of `interactive_quantum` seconds, until they caught up.
With a `state_cache` (a `ProgressiveStateCache`), each module's progressive
state is kept when a run ends and resumed by later runs in which the module
has the same signature (see `restart!`).

`run!` blocks until every module is done; `start!` runs in the background
and returns a `ProgressiveRun` to watch, `stop!` and `wait` on.
"""
Base.@kwdef struct ProgressiveEngine <: Engine
    quantum::Float64 = 0.1
    step_size::Union{Nothing, Function} = nothing
    max_time::Float64 = Inf
    workers::Int = Threads.nthreads()
    interactive_quantum::Float64 = 0.02
    state_cache::Any = nothing   # a ProgressiveStateCache: keep module states across runs
end

"""
    ModuleProgress

Scheduling state of one module in a progressive run.
"""
mutable struct ModuleProgress
    status::Symbol            # :ready, :blocked, :done, :failed, :cancelled
    style::ExecutionStyle
    state::Any                # progressive: the module's state; one-shot: computed?
    context::StepContext
    predictor::StepPredictor
    steps::Int
    items::Int
    started::Bool
    mod_exec::Union{ModuleExec, Nothing}
    converged::Union{Nothing, Bool}   # converged(state) after the last step (see `converged`)
    backlog::Bool                     # input left unconsumed after the last step
    launched_at::Int                  # step clock when its current or last step started
    completed_at::Int                 # step clock when its last step ended
end

"""
    ProgressiveState

The progressive scheduler's state, stored in `run.engine_state`.
"""
mutable struct ProgressiveState
    modules::Dict{Int, ModuleProgress}
    sweeps::Int
    @atomic stop_requested::Bool
    failures::Vector{Tuple{Int, Any, Any}}  # (module id, exception, backtrace)
    @atomic inputs_open::Bool               # input modules keep the run alive
    events::Channel{Int}                    # step completions (module id) and wake-ups (0)
    interactive::Set{Int}                   # modules downstream of a recent input change
    interaction_start::Float64
    consumers::Dict{Int, Vector{Int}}       # modules reading each module's outputs
    @atomic clock::Int                      # counts step completions
    paused::Set{Int}                        # ready modules no one downstream needed (last sweep;
                                            # replaced, never mutated, so other threads may read it)
end

# Wake the scheduler (an input value, stop!, close_inputs!)
wake!(state::ProgressiveState) = (put!(state.events, 0); state)

"""
    ProgressiveRun

A progressive run in the background (from `start!`). `pr.run` is the
`PipelineRun`, whose `outputs` hold the live output containers.
"""
struct ProgressiveRun
    run::PipelineRun
    task::Task
    engine::ProgressiveEngine
end

"""
    start!(engine::ProgressiveEngine, pipeline; observers=[], enable_logging=true) -> ProgressiveRun

Start a progressive run in a background task on the current thread.
Results are readable from `pr.run.outputs` while it runs. Its input modules
(`Variable`) accept values with `set_variable!` until `close_inputs!`.
"""
function start!(engine::ProgressiveEngine, pipeline::Pipeline;
                observers=ExecutionObserver[], enable_logging::Bool=true)
    run = PipelineRun(pipeline; observers=observers, enable_logging=enable_logging)
    state = setup_progressive!(run, engine)
    @atomic state.inputs_open = true
    task = @async execute_run!(engine, run)
    return ProgressiveRun(run, task, engine)
end

"""
    stop!(pr::ProgressiveRun)

Ask a progressive run to stop after the current step; partial results stay
in the outputs. `wait(pr)` then returns normally.
"""
function stop!(pr::ProgressiveRun)
    state = pr.run.engine_state
    @atomic state.stop_requested = true
    wake!(state)
    return pr
end

"""
    close_inputs!(pr::ProgressiveRun)

No more input values: input modules finish, and the run ends when every
other module has caught up.
"""
function close_inputs!(pr::ProgressiveRun)
    state = pr.run.engine_state
    @atomic state.inputs_open = false
    wake!(state)
    return pr
end

"""
    set_variable!(pr::ProgressiveRun, mod, value)

Give an input module (a `Variable`, by module or id) a new value during a
run. The modules downstream of it then get priority and short steps
(`interactive_quantum`) until they have caught up.
"""
function set_variable!(pr::ProgressiveRun, mod_or_id, value)
    run = pr.run
    state = run.engine_state
    id = mod_or_id isa ModuleInstance ? mod_or_id.id : Int(mod_or_id)
    mod = run.instances[id]
    is_input_module(mod.descriptor.module_type) || error("module $id ($(mod.descriptor.name)) is not an input module")
    (@atomic state.inputs_open) || error("the inputs of this run are closed")

    selection = downstream_modules(run.pipeline, id)
    lock(run.lock) do
        union!(state.interactive, selection)
        state.interaction_start = time()
    end
    set!(run.outputs[id]["result"], value)
    notify_observers(on_interaction, run, id, value)
    wake!(state)
    return pr
end

"""
    downstream_modules(pipeline, id) -> Set{Int}

The modules reachable from `id` through connections (not `id` itself).
"""
function downstream_modules(pipeline::Pipeline, id::Int)
    seen = Set{Int}()
    stack = [id]
    while !isempty(stack)
        for conn in get_connections_from(pipeline, pop!(stack))
            if !(conn.dest_module_id in seen)
                push!(seen, conn.dest_module_id)
                push!(stack, conn.dest_module_id)
            end
        end
    end
    return seen
end

interactive_selection(run::PipelineRun, state::ProgressiveState) = lock(() -> copy(state.interactive), run.lock)

"""
    background_during_interaction(ctx) -> Bool

Whether this module is outside the modules an ongoing interaction is
waiting for; such modules do not use data parallelism meanwhile, leaving
the threads to the interaction.
"""
function background_during_interaction(ctx::StepContext)
    run = ctx.run
    (run === nothing || !(run.engine_state isa ProgressiveState)) && return false
    selection = interactive_selection(run, run.engine_state)
    return !isempty(selection) && !(ctx.mod.id in selection)
end

function end_interaction!(run::PipelineRun, state::ProgressiveState)
    seconds = lock(run.lock) do
        isempty(state.interactive) && return nothing
        empty!(state.interactive)
        time() - state.interaction_start
    end
    seconds === nothing || notify_observers(on_interaction_done, run, seconds)
end

function Base.wait(pr::ProgressiveRun)
    try
        return fetch(pr.task)
    catch e
        e isa TaskFailedException ? throw(e.task.exception) : rethrow()
    end
end
Base.istaskdone(pr::ProgressiveRun) = istaskdone(pr.task)

"""
    module_status(run::PipelineRun, module_id) -> Symbol
    module_steps(run::PipelineRun, module_id) -> (steps, items)

Progress of a module in a progressive run.
"""
module_status(run::PipelineRun, id::Int) = run.engine_state.modules[id].status
module_steps(run::PipelineRun, id::Int) =
    (steps=run.engine_state.modules[id].steps, items=run.engine_state.modules[id].items)

# Setup: create every module's context, subscriptions and outputs, in
# topological order so that producers' outputs exist before consumers subscribe

function setup_progressive!(run::PipelineRun, engine=nothing)
    run.engine_state isa ProgressiveState && return run.engine_state
    cache = engine === nothing ? nothing : engine.state_cache
    state = ProgressiveState(Dict{Int, ModuleProgress}(), 0, false, Tuple{Int, Any, Any}[],
                             false, Channel{Int}(Inf), Set{Int}(), 0.0,
                             Dict(id => unique!([c.dest_module_id for c in get_connections_from(run.pipeline, id)])
                                  for id in run.order),
                             0, Set{Int}())
    run.engine_state = state

    for id in run.order
        mod = run.instances[id]
        resumed = resume_state!(cache, run, state, id)
        if resumed !== nothing
            state.modules[id] = resumed
            push!(run.reused, id)
            if resumed.status == :done && run.workflow_exec !== nothing
                # Finished in an earlier run: logged as reused, with its progress
                mod_exec = new_module_exec(run, mod)
                annotate_progress!(mod_exec, run, id, resumed)
                mod_exec.annotations["resumed"] = "true"
                mark_cached!(mod_exec)
                lock(() -> add_module_exec!(run.workflow_exec, mod_exec), run.lock)
            end
            continue
        end
        run.outputs[id] = Dict{String, Any}()
        ctx = StepContext(run, mod, Dict{String, Vector{Any}}(),
                          Dict{String, Vector{AbstractSubscription}}(), Int[], run.outputs[id])
        for conn in sort(get_connections_to(run.pipeline, id), by=c -> c.id)
            source_outputs = run.outputs[conn.source_module_id]
            haskey(source_outputs, conn.source_port) ||
                error("module $(conn.source_module_id) has no output '$(conn.source_port)' " *
                      "(needed by $(mod.descriptor.name) $id)")
            container = source_outputs[conn.source_port]
            push!(get!(Vector{Any}, ctx.inputs, conn.dest_port), container)
            push!(get!(Vector{AbstractSubscription}, ctx.subscriptions, conn.dest_port),
                  subscribe!(container))
            conn.source_module_id in ctx.producers || push!(ctx.producers, conn.source_module_id)
        end

        style = execution_style(mod.descriptor.module_type)
        module_state = if style isa Progressive
            init_state(mod.descriptor.module_type, ctx)
        else
            # One-shot outputs: a replaceable value per declared or connected port
            ports = Set(p.name for p in mod.descriptor.output_ports)
            union!(ports, c.source_port for c in get_connections_from(run.pipeline, id))
            for port in ports
                run.outputs[id][port] = ProgressiveValue{Any}()
            end
            false  # not computed yet
        end
        state.modules[id] = ModuleProgress(:ready, style, module_state, ctx, StepPredictor(),
                                           0, 0, false, nothing,
                                           style isa Progressive ? converged(module_state) : nothing, false, 0, 0)
    end
    return state
end

# Scheduling

finished(status::Symbol) = status in (:done, :failed, :cancelled)

function schedule_modules!(engine::ProgressiveEngine, run::PipelineRun)
    state = setup_progressive!(run, engine)
    try
        if engine.workers <= 1
            schedule_serial!(engine, run, state)
        else
            schedule_parallel!(engine, run, state)
        end
    finally
        log_unfinished!(run, state)
        engine.state_cache === nothing || park_states!(engine.state_cache, run, state)
    end

    if !isempty(state.failures)
        if length(state.failures) == 1
            throw(state.failures[1][2])
        end
        throw(CompositeException([CapturedException(e, bt) for (_, e, bt) in state.failures]))
    end
end

all_finished(state::ProgressiveState) = all(finished(m.status) for m in values(state.modules))
should_stop(state::ProgressiveState, deadline) = (@atomic state.stop_requested) || time() > deadline

"""
    next_action(state, progress) -> :step | :complete | :cancel | :none

What a module needs now: a step (it has work), completion (its producers are
done and it consumed everything), cancellation (a producer failed), or nothing
(waiting for input).
"""
function next_action(state::ProgressiveState, progress::ModuleProgress, sweep=nothing)
    ctx = progress.context
    producer_status = [state.modules[p].status for p in ctx.producers]
    any(s -> s in (:failed, :cancelled), producer_status) && return :cancel
    producers_done = all(==(:done), producer_status)
    changes = input_has_changes(ctx)

    if progress.style isa OneShot
        # Recompute when inputs changed (or never computed, once inputs exist)
        available = one_shot_inputs_available(ctx)
        (progress.state === false || changes) && available && return :step
        # Done once computed, or if its producers finished without providing inputs
        producers_done && !changes && (progress.state === true || !available) && return :complete
        return :none
    end
    if !ready_to_step(progress.state, ctx)
        return producers_done ? :complete : :none
    end
    # Control inputs (values, dicts: parameters, view, revisions) always
    # step; data (table rows) and work left over only while someone needs it
    changes && (sweep === nothing || control_changes(ctx)) && return :step
    if changes || progress.status == :ready
        (sweep === nothing || needs_data!(sweep, state, ctx.mod.id)) && return :step
        push!(sweep.paused, ctx.mod.id)
        return :none
    end
    if is_input_module(ctx.mod.descriptor.module_type) && (@atomic state.inputs_open)
        return :none
    end
    producers_done && return :complete
    return :none
end

# What one sweep learned: which modules want data and which have an opinion
# downstream (memoized), which were paused; `running`: modules stepping on
# other threads (their subscriptions are not read: their backlog is the one
# recorded after their last step)
struct Sweep
    need::Dict{Int, Bool}
    demand::Dict{Int, Bool}
    opinion::Dict{Int, Bool}
    paused::Set{Int}
    running::Set{Int}
end
Sweep(running=Set{Int}()) = Sweep(Dict{Int, Bool}(), Dict{Int, Bool}(), Dict{Int, Bool}(), Set{Int}(), running)

# Whether `id` or a module downstream of it reports convergence
function opinion_downstream!(sweep::Sweep, state::ProgressiveState, id::Int)
    get!(sweep.opinion, id) do
        state.modules[id].converged !== nothing ||
            any(c -> opinion_downstream!(sweep, state, c), state.consumers[id])
    end
end

control_changes(ctx::StepContext) =
    any(has_changes(sub) for subs in values(ctx.subscriptions) for sub in subs if !(sub isa TableSubscription))

"""
    needs_data!(sweep, state, id) -> Bool
    wants_data!(sweep, state, id) -> Bool

Whether module `id` needs data (to process what it has, or more), and
whether it wants *more* data. Without a module reporting convergence at or
below it: yes (every leaf wants all the data). Otherwise it needs data
unless it is finished or has converged (`converged(state) == true`); if it
has not converged (`false`) it does, and with no opinion (`nothing`) if it
has no consumers or one of them wants more data. It wants more data if it
needs data and has no input left to consume (backpressure: more data would
not help it converge sooner).
"""
function needs_data!(sweep::Sweep, state::ProgressiveState, id::Int)
    get!(sweep.need, id) do
        p = state.modules[id]
        opinion_downstream!(sweep, state, id) || return !finished(p.status)
        if finished(p.status) || p.converged === true
            false
        elseif p.converged === false
            true
        else
            consumers = state.consumers[id]
            isempty(consumers) || any(c -> wants_data!(sweep, state, c), consumers)
        end
    end
end

function wants_data!(sweep::Sweep, state::ProgressiveState, id::Int)
    get!(sweep.demand, id) do
        p = state.modules[id]
        opinion_downstream!(sweep, state, id) || return !finished(p.status)
        # A running module: its backlog after its last step, or new input since
        # its current step started
        backlog = id in sweep.running ?
            p.backlog || any(q -> state.modules[q].completed_at > p.launched_at, p.context.producers) :
            input_has_changes(p.context)
        !backlog && needs_data!(sweep, state, id)
    end
end

# End of a sweep: publish the modules it paused
end_sweep!(state::ProgressiveState, sweep::Sweep) = (state.paused = sweep.paused; state)

# Nothing can progress and no input can change that: modules paused because
# everything downstream converged are complete (their consumers then finish
# by propagation). Returns whether any was completed.
function complete_converged!(run::PipelineRun, state::ProgressiveState)
    ((@atomic state.inputs_open) || isempty(state.paused)) && return false
    for id in run.order
        id in state.paused || continue
        progress = state.modules[id]
        finished(progress.status) && continue
        progress.mod_exec === nothing || (progress.mod_exec.annotations["converged"] = "true")
        finish!(progress.state, progress.context)
        complete!(run, id, progress)
    end
    state.paused = Set{Int}()
    return true
end

function apply_action!(engine::ProgressiveEngine, run::PipelineRun, state::ProgressiveState,
                       id::Int, progress::ModuleProgress, action::Symbol)
    if action == :cancel
        progress.status = :cancelled
    elseif action == :complete
        progress.style isa Progressive && finish!(progress.state, progress.context)
        complete!(run, id, progress)
    elseif action == :step
        perform_step!(engine, run, state, id, progress)
    end
end

function perform_step!(engine::ProgressiveEngine, run::PipelineRun, state::ProgressiveState,
                       id::Int, progress::ModuleProgress)
    ctx = progress.context
    if progress.style isa OneShot
        run_step!(engine, run, state, id, progress, () -> one_shot_step!(run, ctx, progress))
    else
        quantum = id in interactive_selection(run, state) ? engine.interactive_quantum : engine.quantum
        budget = engine.step_size === nothing ?
            predict(progress.predictor, quantum, default_step_size(ctx.mod.descriptor.module_type)) :
            max(1, Int(engine.step_size(id)))
        run_step!(engine, run, state, id, progress, () -> step!(progress.state, ctx, budget))
    end
end

# Serial: sweeps in topological order, one step at a time
# Serial: sweeps in topological order, one step at a time. After an input
# change, sweeps cover only the modules downstream of it until they caught up.
function schedule_serial!(engine::ProgressiveEngine, run::PipelineRun, state::ProgressiveState)
    deadline = time() + engine.max_time
    while !all_finished(state) && !should_stop(state, deadline)
        selection = interactive_selection(run, state)
        progressed = false
        sweep = Sweep()
        for id in run.order
            should_stop(state, deadline) && break
            # Re-read: an input may change during the sweep (a step can yield)
            selection = interactive_selection(run, state)
            isempty(selection) || id in selection || continue
            progress = state.modules[id]
            finished(progress.status) && continue
            action = next_action(state, progress, sweep)
            action == :none && continue
            apply_action!(engine, run, state, id, progress, action)
            progressed = true
            empty!(sweep.need); empty!(sweep.demand)   # a step may change what has converged
        end
        end_sweep!(state, sweep)
        state.sweeps += 1
        notify_observers(on_sweep, run, state.sweeps)
        if !isempty(selection) && !progressed
            end_interaction!(run, state)      # the interactive modules caught up
        elseif !progressed
            complete_converged!(run, state) || idle!(state)
        else
            yield()  # let other tasks (viewers, input handlers) run between sweeps
        end
    end
end

# Nothing to do: wait for an input value or stop! if inputs are open
# (the serial scheduler only receives wake-ups on the event channel)
function idle!(state::ProgressiveState)
    if (@atomic state.inputs_open) && !(@atomic state.stop_requested)
        take!(state.events)
        while isready(state.events)   # coalesce several wake-ups
            take!(state.events)
        end
    else
        yield()
    end
end

# Parallel: steps of different modules run at the same time on worker
# threads, at most `engine.workers` at once and never two of the same module.
# A producer and its consumers may overlap: tables publish rows only after
# writing them and their storage never moves (pipeline parallelism). When
# more modules need a step than workers are free, the module that stepped
# least recently goes first, so no module starves.
function schedule_parallel!(engine::ProgressiveEngine, run::PipelineRun, state::ProgressiveState)
    deadline = time() + engine.max_time
    running = Set{Int}()
    events = state.events   # completions (module id > 0) and wake-ups (0)
    last_started = Dict(id => 0 for id in run.order)
    clock = 0

    function launch!(id, progress)
        clock += 1
        last_started[id] = clock
        progress.launched_at = @atomic state.clock
        if thread_affinity(progress.context.mod.descriptor.module_type) == :main
            perform_step!(engine, run, state, id, progress)   # on this task
            return
        end
        push!(running, id)
        step_task() = try
            perform_step!(engine, run, state, id, progress)
        finally
            put!(events, id)
        end
        # Interactive steps go to Julia's interactive threadpool when there is
        # one, so they do not queue behind busy background work
        if Threads.nthreads(:interactive) > 0 && id in interactive_selection(run, state)
            Threads.@spawn :interactive step_task()
        else
            Threads.@spawn step_task()
        end
    end

    try
        while true
            stopping = should_stop(state, deadline)
            started = false
            if !stopping
                candidates = Int[]
                sweep = Sweep(copy(running))
                for id in run.order
                    id in running && continue
                    progress = state.modules[id]
                    finished(progress.status) && continue
                    action = next_action(state, progress, sweep)
                    action == :step ? push!(candidates, id) :
                        apply_action!(engine, run, state, id, progress, action)
                end
                end_sweep!(state, sweep)
                selection = interactive_selection(run, state)
                if !isempty(selection)
                    if !any(in(selection), candidates) && !any(in(selection), running)
                        end_interaction!(run, state)
                    else
                        # During an interaction only the selected modules start steps;
                        # background steps already running finish (bounded by the quantum)
                        filter!(in(selection), candidates)
                    end
                end
                # Least recently stepped first (stable: ties in topological order)
                sort!(candidates, by=id -> last_started[id])
                # During an interaction one more step may run: a slot reserved for it
                limit = isempty(selection) ? engine.workers : engine.workers + 1
                for id in candidates
                    length(running) >= limit && break
                    launch!(id, state.modules[id])
                    started = true
                end
                state.sweeps += 1
                notify_observers(on_sweep, run, state.sweeps)
            end

            if isempty(running)
                (stopping || all_finished(state)) && break
                started || complete_converged!(run, state) || idle!(state)
                continue
            end
            # Wait for a step to finish or a wake-up (then take everything pending)
            if !started || length(running) >= engine.workers || stopping
                delete!(running, take!(events))
            end
            while isready(events)
                delete!(running, take!(events))
            end
        end
    catch
        # Interrupted: let running steps finish before leaving
        while !isempty(running)
            delete!(running, take!(events))
        end
        rethrow()
    end
end

function run_step!(engine, run::PipelineRun, state::ProgressiveState, id::Int,
                   progress::ModuleProgress, step_function)
    mod = progress.context.mod
    if !progress.started
        progress.started = true
        progress.mod_exec = new_module_exec(run, mod)
        progress.mod_exec !== nothing && id in run.reused && (progress.mod_exec.annotations["resumed"] = "true")
        notify_observers(on_module_start, run, mod)
    end

    t0 = time()
    result = try
        step_function()
    catch e
        fail!(run, state, id, progress, e, catch_backtrace())
        return
    end
    seconds = time() - t0

    progress.steps += 1
    progress.items += result.items
    if progress.style isa Progressive
        progress.converged = converged(progress.state)
        progress.backlog = input_has_changes(progress.context)
    end
    progress.completed_at = (@atomic state.clock += 1)
    record!(progress.predictor, result.items, seconds)
    notify_observers(on_module_step, run, mod, result, seconds)

    if result.status == :done
        finish!(progress.state, progress.context)
        complete!(run, id, progress)
    else
        progress.status = result.status
    end
end

function complete!(run::PipelineRun, id::Int, progress::ModuleProgress)
    progress.status = :done
    mod = progress.context.mod
    if progress.mod_exec !== nothing
        annotate_progress!(progress.mod_exec, run, id, progress)
        mark_completed!(progress.mod_exec)
        lock(() -> add_module_exec!(run.workflow_exec, progress.mod_exec), run.lock)
        progress.mod_exec = nothing
    end
    notify_observers(on_module_done, run, mod, run.outputs[id])
end

function fail!(run::PipelineRun, state::ProgressiveState, id::Int, progress::ModuleProgress, e, bt)
    progress.status = :failed
    lock(() -> push!(state.failures, (id, e, bt)), run.lock)
    if progress.mod_exec !== nothing
        annotate_progress!(progress.mod_exec, run, id, progress)
        mark_failed!(progress.mod_exec, string(e))
        lock(() -> add_module_exec!(run.workflow_exec, progress.mod_exec), run.lock)
        progress.mod_exec = nothing
    end
    notify_observers(on_module_error, run, progress.context.mod, e)
end

# Progressive modules in a one-shot engine: one unbounded pass over complete inputs

as_container(x::Union{ProgressiveTable, ProgressiveDict, ProgressiveValue}) = x
as_container(x) = ProgressiveValue{Any}(x)

"""
    compute_progressive(mod::ModuleInstance) -> Dict{String, Any}

Run a progressive module to completion on its (complete) inputs: what the
one-shot engines do with progressive modules. Plain input values are wrapped
in `ProgressiveValue`s; outputs are the module's containers.
"""
function compute_progressive(mod::ModuleInstance)
    ctx = StepContext(nothing, mod, Dict{String, Vector{Any}}(),
                      Dict{String, Vector{AbstractSubscription}}(), Int[], Dict{String, Any}())
    for (port, values_) in mod.input_lists
        containers = Any[as_container(v) for v in values_]
        ctx.inputs[port] = containers
        ctx.subscriptions[port] = AbstractSubscription[subscribe!(c) for c in containers]
    end
    # Preset inputs without connections (e.g. from the API)
    for (port, v) in mod.inputs
        haskey(ctx.inputs, port) && continue
        c = as_container(v)
        ctx.inputs[port] = Any[c]
        ctx.subscriptions[port] = AbstractSubscription[subscribe!(c)]
    end

    state = init_state(mod.descriptor.module_type, ctx)
    while true
        result = step!(state, ctx, MAX_STEP_SIZE)
        (result.status == :done || (result.status == :blocked && !input_has_changes(ctx))) && break
    end
    finish!(state, ctx)
    return ctx.outputs
end

# One-shot modules in a progressive run

# Plain values for one-shot code: a value's current value, a snapshot of a
# table (as a NamedTuple of vectors) or of a dict
materialize(pv::ProgressiveValue) = current_value(pv)
materialize(t::ProgressiveTable) = Tables.columntable(t)
materialize(d::ProgressiveDict) = snapshot(d)

consume_all!(sub::ValueSubscription) = take_value!(sub)
consume_all!(sub::TableSubscription) = (next_created!(sub); next_updated!(sub); next_deleted!(sub))
consume_all!(sub::DictSubscription) = take_changes!(sub)

one_shot_inputs_available(ctx::StepContext) =
    all(!(c isa ProgressiveValue) || has_value(c) for cs in values(ctx.inputs) for c in cs)

function one_shot_step!(run::PipelineRun, ctx::StepContext, progress::ModuleProgress)
    foreach(consume_all!, (sub for subs in values(ctx.subscriptions) for sub in subs))

    # A fresh copy of the pipeline module for each computation
    mod = instance_for_run(run.pipeline.modules[ctx.mod.id])
    for (port, containers) in ctx.inputs
        values_ = Any[materialize(c) for c in containers]
        mod.inputs[port] = last(values_)
        mod.input_lists[port] = values_
    end

    outputs = compute_module(mod)
    for (port, v) in outputs
        container = get(run.outputs[ctx.mod.id], port, nothing)
        if container === nothing
            run.outputs[ctx.mod.id][port] = ProgressiveValue{Any}(v)
        else
            set!(container, v)
        end
    end
    progress.state = true  # computed
    return StepResult(:blocked, 1)
end

# Progressive state kept across runs (VisTrails caching for progressive modules)

"""
    ProgressiveStateCache(; max_entries=256)

Keeps the progressive state of modules when a run ends (finished, stopped
or failed elsewhere), keyed by subpipeline signature. A later run with the
same engine resumes a module from its kept state, outputs and input
positions, if the module has the same signature and all its producers were
resumed too; other modules start from scratch and read their inputs from
the beginning. Least recently kept states are dropped beyond `max_entries`.
"""
mutable struct ProgressiveStateCache
    entries::Dict{String, ModuleProgress}
    order::Vector{String}   # least recently kept first
    max_entries::Int
    lock::ReentrantLock
end

ProgressiveStateCache(; max_entries::Int=256) =
    ProgressiveStateCache(Dict{String, ModuleProgress}(), String[], max_entries, ReentrantLock())

Base.length(c::ProgressiveStateCache) = @lock c.lock length(c.entries)

function Base.empty!(c::ProgressiveStateCache)
    @lock c.lock begin
        foreach(release_subscriptions!, values(c.entries))
        empty!(c.entries); empty!(c.order)
    end
    return c
end

release_subscriptions!(p::ModuleProgress) =
    foreach(unsubscribe!, (sub for subs in values(p.context.subscriptions) for sub in subs))

function park_states!(cache::ProgressiveStateCache, run::PipelineRun, state::ProgressiveState)
    @lock cache.lock begin
        for id in run.order
            progress = state.modules[id]
            progress.status in (:failed, :cancelled) && continue
            run.reusable[id] || continue
            signature = run.signatures[id]
            haskey(cache.entries, signature) && continue   # an identical module was kept already
            cache.entries[signature] = progress
            push!(cache.order, signature)
        end
        while length(cache.order) > cache.max_entries
            dropped = popfirst!(cache.order)
            release_subscriptions!(pop!(cache.entries, dropped))
        end
    end
end

function resume_state!(cache, run::PipelineRun, state::ProgressiveState, id::Int)
    cache isa ProgressiveStateCache || return nothing
    run.reusable[id] || return nothing
    producers = unique(c.source_module_id for c in get_connections_to(run.pipeline, id))
    all(p -> p in run.reused, producers) || return nothing   # inputs must be the same containers

    signature = run.signatures[id]
    progress = @lock cache.lock begin
        p = pop!(cache.entries, signature, nothing)
        p === nothing || filter!(!=(signature), cache.order)
        p
    end
    progress === nothing && return nothing

    # Rebind to this run (module ids may differ between versions)
    ctx = progress.context
    ctx.run = run
    ctx.mod = run.instances[id]
    ctx.producers = producers
    run.outputs[id] = ctx.outputs
    progress.started = false
    progress.mod_exec = nothing
    return progress
end

"""
    restart!(pr::ProgressiveRun, pipeline; observers=[], enable_logging=true) -> ProgressiveRun

A live edit: stop the run and start `pipeline` (typically an edited version
of it) with the same engine. With a `state_cache`, every module whose
signature did not change continues where it was; edited modules and their
downstream start over. Inputs stay open as in `start!`.
"""
function restart!(pr::ProgressiveRun, pipeline::Pipeline;
                  observers=pr.run.observers, enable_logging::Bool=true)
    stop!(pr)
    wait(pr)
    return start!(pr.engine, pipeline; observers=observers, enable_logging=enable_logging)
end

# Progress of partial results

"""
    progress(state) -> Union{Nothing, Tuple{Int, Int}}

How far a progressive module is, as `(done, total)` in its own unit (rows
produced, rows consumed of those available, bytes read), or `nothing` if
unknown. Module types may extend it.
"""
progress(state) = nothing

"""
    converged(state) -> Union{Nothing, Bool}

Whether a progressive module's result is good enough (e.g. a display that
more data would not visibly change): `true` (converged), `false` (needs
more data), or `nothing` (no opinion, the default: it needs what its
consumers need). Called after each step, on the stepping thread. Modules
upstream that are ready only to produce more (sources, work left over) step
only while some module downstream wants data, so a run can stop loading
once its displays converged and resume when one no longer has (a new
query, a zoom); `run!` then completes the paused modules. Module types may
extend it.
"""
converged(state) = nothing

"""
    module_converged(run, id) -> Union{Nothing, Bool}
    is_paused(run, id) -> Bool

A module's last `converged` answer; whether it was paused in the last sweep
because no module downstream wanted data.
"""
module_converged(run::PipelineRun, id::Int) = run.engine_state.modules[id].converged
is_paused(run::PipelineRun, id::Int) = id in run.engine_state.paused

"""
    module_progress(run::PipelineRun, id) -> Union{Nothing, Tuple{Int, Int}}

The progress of a module in a progressive run (see `progress`).
"""
module_progress(run::PipelineRun, id::Int) = progress(run.engine_state.modules[id].state)

function annotate_progress!(mod_exec::ModuleExec, run::PipelineRun, id::Int, p::ModuleProgress)
    mod_exec.annotations["steps"] = string(p.steps)
    mod_exec.annotations["items"] = string(p.items)
    mod_exec.annotations["status"] = string(p.status)
    pr = progress(p.state)
    pr === nothing || (mod_exec.annotations["progress"] = "$(pr[1])/$(pr[2])")
end

# Record modules that started but did not finish (a stopped run): their
# results are partial, and the log says how far they got
function log_unfinished!(run::PipelineRun, state::ProgressiveState)
    for id in run.order
        p = state.modules[id]
        (p.mod_exec === nothing || finished(p.status)) && continue
        annotate_progress!(p.mod_exec, run, id, p)
        p.mod_exec.annotations["partial"] = "true"
        p.mod_exec.ts_end = now()
        lock(() -> add_module_exec!(run.workflow_exec, p.mod_exec), run.lock)
        p.mod_exec = nothing
    end
end
