# Executing Workflows

How VisTrailsJL runs pipelines: engines, caching, observers, and what a
module implementation must do. This guide tracks the execution capabilities
as they are added; the design and the remaining phases are in
[PROGRESSIVE_EXECUTION_PLAN.md](PROGRESSIVE_EXECUTION_PLAN.md).

## Current capabilities

| Capability | Since | Section |
|------------|-------|---------|
| Pluggable engines (`run!`), runs that do not mutate the pipeline | Phase 0 | [Engines](#engines) |
| Observer callbacks during a run | Phase 0 | [Observers](#observers) |
| Several connections into one input port (`get_input_list`) | Phase 0 | [Writing modules](#writing-modules) |
| Notebook-defined modules in any pipeline, including `.vt` | Phase 0 | [Engines](#engines) |
| Caching across runs and versions (`CachedEngine`) | Phase 1 | [Caching](#caching) |
| Signatures of modules and subpipelines | Phase 1 | [Signatures](#signatures) |
| Cache use recorded in provenance | Phase 1 | [Provenance](#provenance) |
| Parallel execution of independent modules (`ParallelEngine`) | Phase 2 | [Parallel execution](#parallel-execution) |
| Thread affinity for Python and plotting modules | Phase 2 | [Parallel execution](#thread-affinity) |
| Change-tracked containers: `ProgressiveTable`, `ProgressiveDict`, `ProgressiveValue` | Phase 3a | [Progressive data](#progressive-data) |
| Progressive execution in time-bounded steps (`ProgressiveEngine`), background runs | Phase 3b | [Progressive execution](#progressive-execution) |
| Progressive modules: sources, statistics, histograms, filter, select | Phase 3b | [Progressive modules](#progressive-modules) |
| Writing progressive modules: folds, maps, or the step contract | Phase 3b | [Writing progressive modules](#writing-progressive-modules) |

Planned: parallel progressive execution (Phase 4), then live parameters,
interactive priority and recording live edits in the version tree (Phase 5).

## Quick start

```julia
using VisTrailsJL

vt = load_vistrail("examples/gcd.vt")    # VistrailWrapper
result = execute(vt)                     # computes every module
result = execute(vt)                     # reuses every cacheable module
```

The high-level API keeps a `CachedEngine` in each `VistrailWrapper`, so
repeated `execute` calls recompute only what changed. With pipelines directly:

```julia
engine = CachedEngine()
run = run!(engine, pipeline)                 # PipelineRun
run.outputs[module_id]["value"]              # a module's outputs
run.reused                                   # ids of modules taken from the cache

cache, workflow_exec = execute_pipeline(pipeline)                  # one-shot, prints progress
cache, workflow_exec = execute_pipeline(pipeline; engine=engine)   # cached
```

## Engines

A `Pipeline` is a specification; an engine executes it.

| Engine | Behavior |
|--------|----------|
| `OneShotEngine()` | Computes every module once, in topological order. Default of `execute_pipeline` and `execute_notebook_pipeline`. |
| `CachedEngine()` | Like one-shot, but reuses outputs whose [signature](#signatures) was computed before. Keep the same engine object across runs to benefit. Default of the high-level `execute`. |
| `ParallelEngine(base; max_tasks)` | Runs independent modules concurrently on threads; each module is executed by `base` (`OneShotEngine()` by default, or a `CachedEngine`). See [Parallel execution](#parallel-execution). |
| `ProgressiveEngine(; quantum, step_size, max_time)` | Runs progressive modules in bounded steps, publishing improving partial results. See [Progressive execution](#progressive-execution). |

```julia
run!(engine, pipeline; observers=ExecutionObserver[], enable_logging=true) -> PipelineRun
```

`PipelineRun` fields:

| Field | Content |
|-------|---------|
| `pipeline` | the pipeline that was run |
| `order` | module ids in execution order (deterministic: ties broken by id) |
| `instances` | per-run copies of the modules, with the inputs and outputs of this run |
| `outputs` | module id → `Dict` of output port → value |
| `signatures` | module id → subpipeline signature |
| `reusable` | module id → whether its results may be cached |
| `reused` | ids of modules whose outputs came from a cache |
| `workflow_exec` | provenance record (`nothing` if `enable_logging=false`) |

Execution never changes the pipeline: each run works on copies of its
modules, so the same pipeline can be run any number of times, by different
engines.

On a module error the run is aborted: the error is logged, observers get
`on_module_error` and `on_run_done`, and the exception is rethrown.

Every engine runs notebook-defined modules (registered with
`register_notebook_package!`) as well as built-in ones, in notebook workflows
and in `.vt` pipelines alike.

Entry points:

| Function | Engine | Returns |
|----------|--------|---------|
| `run!(engine, pipeline; ...)` | any | `PipelineRun` |
| `execute_pipeline(pipeline; engine=OneShotEngine(), observers=[ConsoleObserver()])` | any | `(outputs, workflow_exec)` |
| `execute_notebook_pipeline(pipeline, workflow; engine=OneShotEngine(), save_outputs=false, ...)` | any | `(outputs, named workflow outputs)` |
| `execute(vt_or_pipeline_wrapper; kwargs...)` | the wrapper's `CachedEngine` | `ExecutionResult` |

## Caching

`CachedEngine` stores each module's outputs under its subpipeline signature.
Before computing a module it looks the signature up; on a hit it reuses the
stored outputs and skips the computation. Consequences:

- **Re-running** an unchanged pipeline computes nothing (except
  non-cacheable modules).
- **Editing** a parameter recomputes that module and everything downstream
  of it; the rest is reused. Undoing the edit finds the earlier results.
- **Switching versions** reuses every subpipeline the versions share, since
  signatures do not depend on module ids.
- **Within one run**, a module that computes exactly the same thing as an
  earlier module (same type, parameters and upstream) reuses its outputs.

```julia
engine = CachedEngine()
run!(engine, pipeline)                     # computes everything
set_parameter!(pipeline.modules[3], "value", 7)
run = run!(engine, pipeline)               # recomputes module 3 and its downstream
run.reused                                 # everything else
clear_cache!(engine)                       # drop all cached results
```

### Cacheability

A module's results are reused only if its type is cacheable **and** so is
every module upstream of it (a non-deterministic producer invalidates its
consumers). Types are cacheable by default; declare side effects or
non-determinism with:

```julia
VisTrailsJL.is_cacheable(::Type{MyModule}) = false
```

Not cacheable today: `StandardOutput` (prints), `MplFigureOutput` (writes a
file).

### Signatures

`module_signature(mod)` covers the module on its own:

- package and name;
- implementation: the module's Julia type, or for notebook-defined modules
  the registered compute function, so re-registering an edited notebook
  package invalidates its modules;
- parameters;
- inputs preset on the module (e.g. by `execute(vt; in_a=2)`);
- port specs.

`subpipeline_signatures(pipeline)` combines each module signature with its
incoming connections (destination port, source port, upstream signature),
in connection-id order because that order defines list inputs.

Values are encoded with their type, so `5` and `"5"` differ. Module ids and
layout positions take no part. Signatures are SHA-1 hex strings.

### Limits

- The cache is in memory, unbounded, and lost when the session ends.
  Signatures of notebook-defined modules are valid only within a session.
- `HTTPFile` is cached by URL; a change of the remote file is not detected.
- Cached outputs are shared between runs: a module must not mutate the
  values it receives as inputs.
- Finding a module's connections scans all connections, so very large
  pipelines (thousands of modules) pay a quadratic setup cost per run.

## Parallel execution

`ParallelEngine` starts each module as a Julia task as soon as all its
producers have finished, with at most `max_tasks` modules running at once
(default: `Threads.nthreads()`). Results are the same as with its `base`
engine; only the order in which modules complete changes.

```julia
# julia --threads=auto
engine = ParallelEngine()                    # one-shot modules, in parallel
engine = ParallelEngine(CachedEngine())      # parallel and cached
engine = ParallelEngine(; max_tasks=4)
run = run!(engine, pipeline)

vt.engine = ParallelEngine(CachedEngine())   # use it for the high-level execute(vt)
```

Julia must be started with several threads (`julia --threads=auto` or
`JULIA_NUM_THREADS`); with one thread the engine works but runs modules one
after the other.

Measured with `benchmarks/parallel_engine.jl` (Apple M5, 10 cores;
modules spinning 50 ms each):

| Pipeline | 1 thread | 2 | 4 | 8 |
|----------|---------:|--:|--:|--:|
| wide: 16 independent modules + sum | 1.00× | 2.00× | 3.99× | 7.98× |
| layered: 4 layers × 8 modules | 1.00× | 2.00× | 3.99× | 7.99× |
| chain: 16 modules in sequence | 1.00× | 1.00× | 1.00× | 1.00× |

Scheduling costs about 10-20 µs per module more than the one-shot engine,
so parallelism pays for modules that take longer than that.

### Failures

On the first failure no new module starts; modules already running are
waited for, then the error is rethrown (a `CompositeException` holding every
error if several modules failed). Downstream modules of a failed module never
run. Outputs of completed modules stay in the `CachedEngine`, if one is used.
The same join happens if the run is interrupted.

### Thread affinity

Some modules must not run on worker threads: PyCall must be used from the
main thread, and Plots.jl is not thread-safe. Such module types declare

```julia
VisTrailsJL.thread_affinity(::Type{MyModule}) = :main   # default: :any
```

and `ParallelEngine` runs them on the calling task. Declared today:
`PythonSource`, `PythonCalc` and the matplotlib modules. Call `run!` from
the main task (the REPL or a script's top level) when a pipeline contains
such modules; from another task the run fails with an error saying so.

### What modules must guarantee

- Modules with `:any` affinity may run at the same time as other modules:
  they must not modify shared global state without synchronization.
- Inputs may be shared with other modules running at the same time (and,
  with caching, with other runs): do not mutate them.
- Observer callbacks are called one at a time (under the run's lock), so
  observers need no synchronization of their own.

## Progressive execution

`ProgressiveEngine` runs a pipeline so that results appear early and
improve: progressive modules process their inputs in bounded **steps**, each
sized to take about `quantum` seconds, and publish their current result
after each step. A pipeline over 20 M rows shows its first filtered count
after ~15-40 ms; the complete results take as long as with the one-shot
engine (6.1 s vs 6.2 s, `benchmarks/progressive_engine.jl`).

```julia
p = Pipeline()
src = add_module!(p, "org.vistrails.progressive", "RandomTable")
set_parameter!(src, "rows", 10_000_000)
hist = add_module!(p, "org.vistrails.progressive", "Histogram1D")
foreach(((k, v),) -> set_parameter!(hist, k, v), ["column" => "x", "bins" => 64, "min" => 0.0, "max" => 1.0])
add_connection!(p, src, "result", hist, "table")

run = run!(ProgressiveEngine(), p)                 # blocks until every module is done
current_value(run.outputs[hist.id]["result"])     # the final counts
```

Outputs of a progressive run are containers (see [Progressive
data](#progressive-data)): a `ProgressiveTable`, a `ProgressiveDict` or a
`ProgressiveValue` per output port.

### Watching a run

`start!` runs in a background task (on the current thread) and returns at
once; the outputs can be read while the run improves them:

```julia
pr = start!(ProgressiveEngine(), p)
while !istaskdone(pr)
    sleep(0.2)
    counts = pr.run.outputs[hist.id]["result"]
    has_value(counts) && display(current_value(counts))
end
run = wait(pr)            # the PipelineRun; rethrows a failure
stop!(pr)                 # or stop early: partial results stay in the outputs
```

`module_status(run, id)` is `:ready`, `:blocked`, `:done`, `:failed` or
`:cancelled`; `module_steps(run, id)` gives `(steps, items)`. Observers also
receive `on_module_step(obs, run, mod, result, seconds)` after each step and
`on_sweep(obs, run, sweep)` after each pass over the modules.

### How it runs

- The scheduler **sweeps** the modules in topological order. A module runs
  a step when it has work: new input changes, or more to produce (a
  source). It is skipped when blocked.
- **Step sizes** come from a time predictor: items per second over the
  module's last 7 steps, times `quantum` (default 0.1 s). The first step of
  each module is ignored, since it includes JIT compilation; until data
  exists, a module's `default_step_size` is used. `step_size=id -> n`
  forces sizes (for tests).
- **Termination by propagation**: a module is done when it says so (a
  source that has produced everything), or when all its producers are done
  and it has consumed all their changes.
- **One-shot modules** take part: their outputs become `ProgressiveValue`s
  and they recompute whenever an input changed (inputs are passed as plain
  values: a table as a `NamedTuple` of columns, a dict as a `Dict`).
- **Failures** are isolated: a failing module is `:failed`, everything
  downstream of it `:cancelled`, the rest runs to completion; then `run!`
  rethrows the error (a `CompositeException` for several).
- `max_time` bounds a run; `stop!` ends it early.

Progressive modules also run in the other engines: `OneShotEngine`,
`CachedEngine` and `ParallelEngine` run them as a single unbounded step, so
the same pipeline gives the same final results everywhere.

### Guarantees (tested)

- **Prefix consistency**: after every step, a statistic equals the batch
  statistic over the rows the module has consumed so far; a filter's output
  equals the filter applied to those rows. Checked under random step sizes.
- **Eventual exactness**: final results equal the batch results.
- **Interleaving independence**: final results do not depend on step sizes
  (exactly for counts, min/max, histograms, filters; to rounding for
  mean/variance).
- Updates and deletions in a table reach every consumer: folds start over,
  maps update or delete the affected output rows.

Early results are prefixes of the input in arrival order, not samples: a
file sorted by time shows its first rows first.

### Progressive modules

Package `org.vistrails.progressive` (short name `progressive` in workflow
notebooks). Tables flow through ports named `table` (input) and `result`
(output).

| Module | Parameters | Output `result` |
|--------|-----------|-----------------|
| `RandomTable` | `columns` (default `["x", "y"]`), `rows` (1 000 000), `seed` (0) | table of uniform `Float64`; same rows whatever the step sizes |
| `CSVLoader` | `path`, `columns` (optional subset) | table; types inferred from the first 1 000 rows, integers widened to `Float64` |
| `Count` | — | `ProgressiveValue{Int}` |
| `Min`, `Max`, `Mean`, `Var` | `columns` (default: numeric columns) | `ProgressiveDict` column → value |
| `Histogram1D` | `column`, `bins` (64), `min`, `max` | `ProgressiveValue{Vector{Int}}` |
| `Histogram2D` | `x_column`, `y_column`, `xbins`, `ybins`, `xmin`, `xmax`, `ymin`, `ymax` | `ProgressiveValue{Matrix{Int}}` |
| `Filter` | `column`, `op` (`<`, `<=`, `>`, `>=`, `==`, `!=`), `value` | table of the matching rows |
| `Select` | `columns` | table with those columns |
| `Sink` | — (consumes any input) | port `count`: rows consumed |

In a workflow notebook:

```julia
#| module-id: points
#| module-type: progressive:RandomTable
#| params:
#|   rows: 20000

#| module-id: left
#| module-type: progressive:Filter
#| params:
#|   column: x
#|   op: <
#|   value: 0.5
#| inputs:
#|   table: points.result
```

and `execute_notebook_pipeline(pipeline, workflow; engine=ProgressiveEngine())`
(example: `test/progressive/progressive_workflow.ipynb`).

`CSVLoader` reads one line per row: quoted fields containing newlines are
not supported.

### Writing progressive modules

Most modules are a **fold** (an accumulator over rows) or a **map** (rows
in, rows out), and can be defined without touching subscriptions:

```julia
# A fold: sum of squares per column
define_fold_module!("my.package", "SumSquares";
    init   = (ctx, columns) -> Dict(c => 0.0 for c in columns),
    update = (acc, chunk, ctx) -> (foreach(c -> acc[c] += sum(abs2, chunk[c]), keys(chunk)); acc),
    result = (acc, ctx) -> acc)          # published into a ProgressiveDict

# A map: a derived column (add `_keep = Bool vector` to filter rows)
define_map_module!("my.package", "Radius";
    schema = (ctx, table) -> [:r => Float64],
    map    = (chunk, ctx) -> (r = sqrt.(chunk.x .^ 2 .+ chunk.y .^ 2),))
```

- A fold's `update` receives `chunk`, a `NamedTuple` of contiguous column
  views (one call per storage segment); updates or deletions in the input
  restart the fold from all rows. `output=:value` publishes `result` into a
  `ProgressiveValue` instead of a dict. Parameters: `param(ctx, "name", default)`.
- A map's output rows follow their input rows: updated inputs are
  re-mapped, deleted inputs delete their outputs.

For anything else, implement the step contract on your own module type:

```julia
struct MyModule end
VisTrailsJL.execution_style(::Type{MyModule}) = Progressive()

mutable struct MyState
    sub::TableSubscription
    out::ProgressiveValue{Int}
end

# Once, before the run: create outputs, keep subscriptions
VisTrailsJL.init_state(::Type{MyModule}, ctx) =
    MyState(input_subscription(ctx, "table"), set_output!(ctx, "result", ProgressiveValue{Int}(0)))

# Repeatedly: consume at most `budget` items, publish, report
function VisTrailsJL.step!(s::MyState, ctx, budget)
    ids = next_created!(s.sub, budget)
    isempty(ids) && return StepResult(:blocked, 0)
    set!(s.out, current_value(s.out) + length(ids))
    return StepResult(has_changes(s.sub) ? :ready : :blocked, length(ids))
end
```

and register it with a `ModuleDescriptor` as usual. `StepResult` status:
`:ready` (more work now), `:blocked` (waiting for input) or `:done`
(finished; sources). Optional: `finish!(state, ctx)` when the module is
done, `default_step_size(::Type{MyModule})` for the first steps. A module
without inputs must not return `:blocked` (it would be considered done).

## Progressive data

Progressive modules exchange data through containers that report what
changed, so each consumer processes only new, updated or deleted items, in
bounded chunks. They correspond to ProgressiVis' `PTable`, `PDict` and
`PIntSet`, and are usable on their own.

### ProgressiveTable

A columnar table that grows by appending rows.

```julia
t = ProgressiveTable(:x => Float64, :y => Int)        # or ProgressiveTable(namedtuple_or_any_Tables_table)
ids = append!(t, (x=rand(1000), y=rand(1:9, 1000)))   # new row ids (1:1000)
push!(t, (x=0.5, y=3))                                # one row; returns its id

t[5, :x]                  # a value
column(t, :x)             # the column, indexed by row id (AbstractVector)
t[RowIds([1, 5, 9]), :y]  # values at several ids
t[5, :x] = 1.0            # update
delete!(t, 10:20)         # delete rows (an id, a range or RowIds)
row_ids(t), length(t)     # live rows
Tables.columntable(t)     # a Tables.jl snapshot of the live rows (works with DataFrames, CSV, ...)
```

- Row ids start at 1, are positions in the columns, and are never reused;
  deleted rows keep their slot.
- **Storage never moves.** Columns are stored in fixed-size segments
  (`segment_size`, default 65 536 rows). A segment is never reallocated, so
  a consumer can read while the producer appends.
- **Rows are published after they are written**: they become visible (in
  `last_id`, column lengths and subscriptions) only once every column holds
  their values.
- **Bulk reads**: `segment_views(column(t, :x), range)` returns contiguous
  views covering a range of ids, e.g. `sum(sum, segment_views(col, r))`.

### Subscriptions

Each consumer subscribes and reads the changes since its own last read, at
its own pace:

```julia
sub = subscribe!(t)            # rows already in t are reported as created
pending(sub)                   # (created=…, updated=…, deleted=…)
ids = next_created!(sub, 10_000)   # up to 10 000 new row ids, smallest first (a RowIds)
for r in ranges(ids), v in segment_views(column(t, :x), r)
    # process v
end
next_updated!(sub); next_deleted!(sub)
has_changes(sub)
reset!(sub)                    # forget pending changes; re-read everything as created
unsubscribe!(sub)
```

Changes a consumer has not read yet are combined: a row created and then
updated is reported once, as created; a row created and then deleted is not
reported at all; a row read, updated and then deleted is reported as deleted.

`RowIds` is a set of ids stored as sorted ranges (one range for a run of
appends): `add!`, `remove!`, `union!`, `setdiff!`, `intersect`,
`take_first!`, `in`, iteration, `ranges`.

### ProgressiveDict and ProgressiveValue

`ProgressiveDict{K,V}` is a dictionary for small keyed results (min/max per
column, query bounds). Its subscriptions report created, updated and
deleted keys with `take_changes!(sub)`. Writing a value equal (`isequal`)
to the current one is not a change.

```julia
d = ProgressiveDict{Symbol, Float64}()
sub = subscribe!(d)
d[:max] = 3.0
take_changes!(sub)      # (created=Set([:max]), updated=Set(), deleted=Set())
snapshot(d)             # a Dict copy
```

`ProgressiveValue{T}` wraps any value; its only change is "replaced"
(`set!`). It lets ordinary values (a figure, a model) take part in a
progressive pipeline:

```julia
pv = ProgressiveValue{String}()
sub = subscribe!(pv)
set!(pv, "hello")
has_changes(sub)        # true
take_value!(sub)        # "hello"; has_changes(sub) is now false
current_value(pv)
```

### Threads

One producer writes a container while any number of consumers, on other
threads, read published rows and use their subscriptions. Writes and
subscription operations take the container's lock; reading published
values does not.

### Performance

On an Apple M5, single-threaded, two `Float64` columns: appending runs at
90-330 M rows/s (chunks of 10 000 to 100 000 rows); taking new ids and
summing a column through `segment_views` at 1.5-2 G rows/s. Reading
element by element (`col[id]`) is about 30 M rows/s: use segment views in
hot loops.

## Observers

Observers receive events during a run. Subtype `ExecutionObserver` and
extend the callbacks you need; the others do nothing.

| Callback | When |
|----------|------|
| `on_run_start(obs, run)` | before any module runs |
| `on_module_start(obs, run, mod)` | before a module computes, inputs gathered |
| `on_module_done(obs, run, mod, outputs)` | after a module computes |
| `on_module_cached(obs, run, mod, outputs)` | instead of start/done, when outputs come from a cache |
| `on_module_error(obs, run, mod, err)` | a module threw; the run aborts |
| `on_run_done(obs, run, err)` | at the end; `err === nothing` on success |

```julia
struct Timeline <: ExecutionObserver
    events::Vector{String}
end
VisTrailsJL.on_module_done(t::Timeline, run, mod, outputs) =
    push!(t.events, "computed $(mod.descriptor.name) #$(mod.id)")
VisTrailsJL.on_module_cached(t::Timeline, run, mod, outputs) =
    push!(t.events, "reused $(mod.descriptor.name) #$(mod.id)")

timeline = Timeline(String[])
run!(CachedEngine(), pipeline; observers=[timeline])
```

Provided observers: `ConsoleObserver` (progress on stdout; the default of
`execute_pipeline`) and `VisTrailsJL.NotebookOutputObserver` (writes outputs into the
workflow notebook; used by `execute_notebook_pipeline(...; save_outputs=true)`).

## Writing modules

A module type is a Julia type with a `compute` method; it reads
`mod.inputs` / `mod.parameters`, fills `mod.outputs`, and returns it:

```julia
struct AddAll end

function VisTrailsJL.compute(mod::VisTrailsJL.ModuleInstance, ::Type{AddAll})
    mod.outputs["value"] = sum(get_input_list(mod, "in"); init=0)
    return mod.outputs
end
```

- **Several connections into one port**: `get_input_list(mod, port)` returns
  every connected value in connection order; `mod.inputs[port]` holds the
  last one (the historical behavior).
- **Do not mutate inputs**: with caching they may be shared with other runs.
- **Side effects or randomness**: declare `is_cacheable(::Type{T}) = false`.
- **Not thread-safe** (Python, plotting, global state): declare
  `thread_affinity(::Type{T}) = :main`.

`mod` is a per-run copy; writing to it does not affect the pipeline.

## Provenance

With `enable_logging=true` (the default), each run produces a `WorkflowExec`
with one `ModuleExec` per module (see [LOGGING.md](LOGGING.md)):

- `cached = true` for modules reused from a cache;
- `annotations["signature"]` holds the module's subpipeline signature, so a
  log entry identifies the computation, not only the module id.

## Changelog

- **Phase 3b (2026-10-13)**: `ProgressiveEngine` (sweeps, time predictor,
  termination by propagation, isolated failures, `start!`/`stop!`/`wait`),
  one-shot modules in progressive runs and progressive modules in one-shot
  engines, `define_fold_module!`/`define_map_module!` and the step contract,
  package `progressive` (RandomTable, CSVLoader, Count, Min, Max, Mean, Var,
  Histogram1D/2D, Filter, Select, Sink), `on_module_step`/`on_sweep`,
  `benchmarks/progressive_engine.jl`.
- **Phase 3a (2026-10-13)**: progressive data layer: `ProgressiveTable`
  (segmented columns that never move, publish-after-write, Tables.jl),
  `RowIds`, `ProgressiveDict`, `ProgressiveValue`, subscriptions
  (`subscribe!`, `next_created!`/`next_updated!`/`next_deleted!`,
  `take_changes!`, `take_value!`, `reset!`), `segment_views`.
- **Phase 2 (2026-10-13)**: `ParallelEngine` (dependency-driven task
  scheduling on threads, composable with `CachedEngine`), `thread_affinity`
  (`:main` for Python and plotting modules), failure contract (stop
  admitting, join, `CompositeException`), thread-safe runs and cache;
  `benchmarks/parallel_engine.jl`.
- **Phase 1 (2026-10-13)**: `CachedEngine`, `module_signature`,
  `subpipeline_signatures`, `is_cacheable`, `clear_cache!`,
  `on_module_cached`; API wrappers keep a `CachedEngine`; `engine` option on
  `execute_pipeline` and `execute_notebook_pipeline`; signatures and cache
  use in provenance.
- **Phase 0 (2026-10-13)**: `Engine`, `OneShotEngine`, `run!`,
  `PipelineRun`; observers; `get_input_list`; runs no longer mutate the
  pipeline; one execution path for built-in and notebook modules;
  deterministic execution order.
