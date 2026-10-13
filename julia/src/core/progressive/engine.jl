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

A module parameter, or `default` if it is not set.
"""
param(ctx::StepContext, name::AbstractString, default=nothing) = get(ctx.mod.parameters, String(name), default)

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
# module's first step (it includes JIT compilation)

const PREDICTOR_WINDOW = 7
const MAX_STEP_SIZE = 1 << 30

mutable struct StepPredictor
    first_step::Bool
    items::Vector{Int}
    seconds::Vector{Float64}
end

StepPredictor() = StepPredictor(true, Int[], Float64[])

function record!(p::StepPredictor, items::Int, seconds::Float64)
    if p.first_step
        p.first_step = false
        return p
    end
    items > 0 || return p
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
    ProgressiveEngine(; quantum=0.1, step_size=nothing, max_time=Inf)

Runs pipelines progressively: progressive modules in bounded steps of about
`quantum` seconds each (sized by a time predictor), one-shot modules
recomputed when their inputs change. `step_size`, if given, is called as
`step_size(module_id)` to choose every step's size instead (for tests).
`max_time` bounds the whole run, in seconds.

`run!` blocks until every module is done; `start!` runs in the background
and returns a `ProgressiveRun` to watch, `stop!` and `wait` on.
"""
Base.@kwdef struct ProgressiveEngine <: Engine
    quantum::Float64 = 0.1
    step_size::Union{Nothing, Function} = nothing
    max_time::Float64 = Inf
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
end

"""
    ProgressiveRun

A progressive run in the background (from `start!`). `pr.run` is the
`PipelineRun`, whose `outputs` hold the live output containers.
"""
struct ProgressiveRun
    run::PipelineRun
    task::Task
end

"""
    start!(engine::ProgressiveEngine, pipeline; observers=[], enable_logging=true) -> ProgressiveRun

Start a progressive run in a background task on the current thread.
Results are readable from `pr.run.outputs` while it runs.
"""
function start!(engine::ProgressiveEngine, pipeline::Pipeline;
                observers=ExecutionObserver[], enable_logging::Bool=true)
    run = PipelineRun(pipeline; observers=observers, enable_logging=enable_logging)
    setup_progressive!(run)
    task = @async execute_run!(engine, run)
    return ProgressiveRun(run, task)
end

"""
    stop!(pr::ProgressiveRun)

Ask a progressive run to stop after the current step; partial results stay
in the outputs. `wait(pr)` then returns normally.
"""
stop!(pr::ProgressiveRun) = (@atomic pr.run.engine_state.stop_requested = true; pr)

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

function setup_progressive!(run::PipelineRun)
    run.engine_state isa ProgressiveState && return run.engine_state
    state = ProgressiveState(Dict{Int, ModuleProgress}(), 0, false, Tuple{Int, Any, Any}[])
    run.engine_state = state

    for id in run.order
        mod = run.instances[id]
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
                                           0, 0, false, nothing)
    end
    return state
end

# Scheduling

finished(status::Symbol) = status in (:done, :failed, :cancelled)

function schedule_modules!(engine::ProgressiveEngine, run::PipelineRun)
    state = setup_progressive!(run)
    deadline = time() + engine.max_time

    while !all(finished(m.status) for m in values(state.modules))
        (@atomic state.stop_requested) && break
        time() > deadline && break

        for id in run.order
            (@atomic state.stop_requested) && break
            progress = state.modules[id]
            finished(progress.status) && continue
            advance!(engine, run, state, id, progress)
        end

        state.sweeps += 1
        notify_observers(on_sweep, run, state.sweeps)
        yield()  # let other tasks (viewers, input handlers) run between sweeps
    end

    if !isempty(state.failures)
        if length(state.failures) == 1
            throw(state.failures[1][2])
        end
        throw(CompositeException([CapturedException(e, bt) for (_, e, bt) in state.failures]))
    end
end

function advance!(engine::ProgressiveEngine, run::PipelineRun, state::ProgressiveState,
                  id::Int, progress::ModuleProgress)
    ctx = progress.context
    producer_status = [state.modules[p].status for p in ctx.producers]

    # A failed producer cancels its consumers
    if any(s -> s in (:failed, :cancelled), producer_status)
        progress.status = :cancelled
        return
    end
    producers_done = all(==(:done), producer_status)
    changes = input_has_changes(ctx)

    if progress.style isa OneShot
        # Recompute when inputs changed (or never computed, once inputs exist)
        if (progress.state === false || changes) && one_shot_inputs_available(ctx)
            run_step!(engine, run, state, id, progress, () -> one_shot_step!(run, ctx, progress))
        end
        progress.status != :failed && producers_done && !input_has_changes(ctx) && progress.state === true &&
            complete!(run, id, progress)
        return
    end

    if progress.status == :ready || changes
        budget = engine.step_size === nothing ?
            predict(progress.predictor, engine.quantum, default_step_size(ctx.mod.descriptor.module_type)) :
            max(1, Int(engine.step_size(id)))
        run_step!(engine, run, state, id, progress, () -> step!(progress.state, ctx, budget))
    elseif producers_done && !changes
        finish!(progress.state, ctx)
        complete!(run, id, progress)
    end
end

function run_step!(engine, run::PipelineRun, state::ProgressiveState, id::Int,
                   progress::ModuleProgress, step_function)
    mod = progress.context.mod
    if !progress.started
        progress.started = true
        progress.mod_exec = new_module_exec(run, mod)
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
        progress.mod_exec.annotations["steps"] = string(progress.steps)
        progress.mod_exec.annotations["items"] = string(progress.items)
        mark_completed!(progress.mod_exec)
        lock(() -> add_module_exec!(run.workflow_exec, progress.mod_exec), run.lock)
    end
    notify_observers(on_module_done, run, mod, run.outputs[id])
end

function fail!(run::PipelineRun, state::ProgressiveState, id::Int, progress::ModuleProgress, e, bt)
    progress.status = :failed
    push!(state.failures, (id, e, bt))
    if progress.mod_exec !== nothing
        mark_failed!(progress.mod_exec, string(e))
        lock(() -> add_module_exec!(run.workflow_exec, progress.mod_exec), run.lock)
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
