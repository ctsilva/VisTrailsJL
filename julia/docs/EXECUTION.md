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
| Parallel progressive execution: modules, producer/consumer overlap, data-parallel folds | Phase 4 | [Parallel progressive execution](#parallel-progressive-execution) |
| Live inputs (`Variable`, `set_variable!`), parameters driven by inputs, interactive priority | Phase 5a | [Live inputs and interaction](#live-inputs-and-interaction) |
| Progressive state kept across runs and edits (`ProgressiveStateCache`, `restart!`) | Phase 5b | [Edits during a run](#edits-during-a-run) |
| Progress of partial results in provenance; execution history for ProgressiVis' viewer | Phase 5b | [Provenance of progressive runs](#provenance-of-progressive-runs) |
| Live input changes recorded as versions (`VersionRecorder`) | Phase 5b | [Provenance of progressive runs](#provenance-of-progressive-runs) |
| Arrow source (`ArrowLoader`), reads at arbitrary row ids (`gather`); example: progressive TaxiVis | TaxiVis | [Progressive modules](#progressive-modules) |
| ProgressiVis modules, tier 1: `ParquetLoader`, `Quantiles`, `KLLSketch`, `Histogram1DCategorical`, `Distinct`, `Corr`, `IdxMin`, `IdxMax`, `Sample` | ProgressiVis modules | [Progressive modules](#progressive-modules) |
| Selection views of tables (`selection_view`, `select!`, `deselect!`, `set_selection!`, `touch!`); linear-time `RowIds` set operations | ProgressiVis modules | [Selection views](#selection-views) |
| ProgressiVis modules, tier 2: `BinningIndex`, `RangeQuery`, `RangeQuery2D`, `SimpleFilter`, `CategoricalQuery`, `Intersection`, `Percentiles` | ProgressiVis modules | [Progressive modules](#progressive-modules) |
| ProgressiVis modules, tier 3: `Unary`, `ColsBinary`, `Reduce`, `LinearMap`, `GroupBy`, `Aggregate`, `Join`, `JoinById`, `Switch`; maps with extra table inputs and readiness | ProgressiVis modules | [Progressive modules](#progressive-modules) |
| ProgressiVis modules, tier 4: `Blobs`, `MVBlobs`, `MinMaxScaler`, `MBKMeans`, `MBKMeansFilter`, `PPCA`, `PPCATransformer`, `KernelDensity`, `TSNE`; bulk updates (`update_rows!`) | ProgressiVis modules | [Progressive modules](#progressive-modules) |
| Convergence: sources load only while a result downstream needs more data (`converged`), and resume when one does again | TaxiVis | [Convergence](#convergence) |

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
| `ProgressiveEngine(; quantum, step_size, max_time, workers)` | Runs progressive modules in bounded steps, publishing improving partial results, on `workers` threads. See [Progressive execution](#progressive-execution). |

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
after a few milliseconds; the complete results take about as long as with
the one-shot engine (see [the measurements](#parallel-progressive-execution)).

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

- A module runs a step when it has work: new input changes, or more to
  produce (a source); otherwise it is blocked. With `workers = 1` the
  scheduler **sweeps** the modules in topological order, one step at a
  time; with more workers, steps of different modules run in parallel (see
  [below](#parallel-progressive-execution)).
- **Step sizes** come from a time predictor: items per second over the
  module's last 7 steps, times `quantum` (default 0.1 s). Each module's
  first step that processes items is ignored, since it includes JIT
  compilation; empty steps are ignored too. Until data
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

### Parallel progressive execution

With `workers > 1` (default: `Threads.nthreads()`; start Julia with
`--threads=auto`), three kinds of parallelism combine:

- **Task parallelism**: steps of independent modules run at the same time.
- **Pipeline parallelism**: a producer and its consumers run at the same
  time; consumers read the rows already published while the producer
  appends more. This is safe because tables publish rows only after
  writing them and their storage never moves (ProgressiVis has to keep
  connected modules apart instead).
- **Data parallelism**: folds that define `merge` split each step's rows
  into blocks of 16 384 rows and the blocks into at most 16 groups of
  consecutive blocks; each group is folded into its own accumulator, on
  several threads, and the groups are merged in order (all the statistics
  modules do). The split does not depend on the number of threads, so
  neither do the results; a step makes at most 16 accumulators (a 512²
  histogram's is 2 MB).

Rules: at most `workers` steps run at once; two steps of the same module
never do; when more modules need a step than workers are free, the module
that stepped least recently goes first; modules with
`thread_affinity(T) == :main` (Python, plotting) step on the scheduler's
task, which must run on the main thread.

Determinism: final results are the same with any number of workers (to
rounding for mean and variance, since step boundaries depend on timing).
With `workers = 1`, they are bit-identical whatever the number of threads,
because fold blocks do not depend on it. Intermediate results in parallel
runs depend on timing: a one-shot module downstream of a progressive one
may see more or fewer intermediate values.

Measured with `benchmarks/progressive_engine.jl` (Apple M5, 10 cores;
RandomTable of 20 M rows → Min, Mean, Var, Histogram1D, Histogram2D
256×256, Filter → Count):

| Julia threads | engine | first filtered count | complete |
|--------------:|--------|---------------------:|---------:|
| 1 | one-shot | — | 2.98 s |
| 1 | progressive, 1 worker | 13-39 ms | 3.0-3.3 s |
| 8 | one-shot (data-parallel folds) | — | 1.09 s |
| 8 | progressive, 1 worker | 5-35 ms | 1.0-1.15 s |
| 8 | progressive, 8 workers | < 1 ms | 0.86-0.89 s |

The source draws its random numbers sequentially (0.45 s for 20 M rows),
which bounds the speedup of this pipeline.

### Live inputs and interaction

An input module (`Variable`) receives values from outside while a run is
going. Connect it to a module's input port named like a parameter and it
drives that parameter: every fold and map module (all statistics, `Filter`,
`Select`, and modules defined with `define_fold_module!`/`define_map_module!`)
has an optional input port per parameter.

```julia
p = Pipeline()
src = add_module!(p, "org.vistrails.progressive", "RandomTable")
set_parameter!(src, "rows", 50_000_000)
threshold = add_module!(p, "org.vistrails.progressive", "Variable")
set_parameter!(threshold, "value", 0.5)
filt = add_module!(p, "org.vistrails.progressive", "Filter")
set_parameter!(filt, "column", "x"); set_parameter!(filt, "op", "<")
add_connection!(p, src, "result", filt, "table")
add_connection!(p, threshold, "result", filt, "value")   # drives the "value" parameter

pr = start!(ProgressiveEngine(), p)
set_variable!(pr, threshold, 0.1)    # e.g. from a slider callback
close_inputs!(pr)                    # no more input: the run ends when everything caught up
wait(pr)
```

- A changed parameter restarts the module: a fold starts over from all
  rows, a map deletes its output rows and maps every row again. Both then
  proceed progressively, so a result for the new value appears quickly.
- In a module's own code, `param(ctx, name, default)` returns the input's
  current value when one is connected, else the parameter.
- **Runs with inputs** started with `start!` keep going (input modules
  never finish while inputs are open) until `close_inputs!(pr)` or
  `stop!(pr)`. With `run!`, inputs are closed from the start: a `Variable`
  is a constant. One-shot engines treat it as a constant too.
- **While nothing is left to do**, a run with open inputs sleeps until the
  next value or `stop!`: no busy loop.

**Interactive priority.** After `set_variable!`, the modules downstream of
the input form the *interactive selection* until they have caught up:

- they step with `interactive_quantum` (default 0.02 s) instead of
  `quantum`;
- serially, sweeps visit only them;
- in parallel, only they start new steps (steps already running finish),
  one step beyond `workers` may run for them (a reserved slot), they go to
  Julia's interactive threadpool when it exists, and background folds stop
  using data parallelism meanwhile.

Observers get `on_interaction(obs, run, module_id, value)` and, once the
selection caught up, `on_interaction_done(obs, run, seconds)`.

Measured (8 threads, Apple M5) while a 1-billion-row branch with `Var` and a
256×256 `Histogram2D` keeps running: after a new threshold, a `Filter` →
`Count` branch over 300 000 rows has caught up in 1.5-2.5 ms (8 workers;
2-6 ms with 1 worker), over 3 million rows in 10-95 ms.

### Convergence

A progressive result is often good enough long before all the data is
read: a histogram drawn with 256 color levels stops changing visibly, an
estimate's confidence interval gets narrow enough. A module says so with

```julia
VisTrailsJL.converged(s::MyState) = s.rows >= 10_000   # true, false, or nothing
```

`true`: converged; `false`: needs more data; `nothing` (the default): no
opinion, it needs what its consumers need. The engine calls it after every
step of the module (on the thread that ran the step) and at setup.

Where some module at or below a module reports convergence:

- a module **needs data** unless it is finished or converged; with no
  opinion, if it has no consumers or one of them wants more data;
- it **wants more data** if it needs data and has consumed all its input
  (**backpressure**: a consumer that is behind would not converge sooner
  with more data, so a fast source stays about one step ahead of the
  slowest consumer still needing data). For a module stepping on another
  thread, the engine uses the backlog recorded after its last step, or new
  output from a producer since its step started.

Steps then depend on what changed:

- **control inputs** (values and dicts: parameters, a view, a revision)
  always step the module, so an interaction reaches the modules that
  consume it, and if they no longer converge (a new query, a zoom) the
  sources resume;
- **data** (new table rows) and work left over step a module only while it
  needs data: a converged module leaves rows that arrived meanwhile;
- a module `:ready` on its own (a source) steps only while it wants more
  data. Otherwise it is **paused**.

Without modules that report convergence, nothing changes: every leaf wants
all the data.

- `run!`: once nothing can progress and the paused modules are all that
  is left, they complete (annotated `converged` in the execution log) and
  their consumers finish by propagation. The run read only the data its
  results needed.
- `start!`: paused sources wait (no steps, no CPU) for an input that makes
  a module downstream want data again.
- `module_converged(run, id)`, `is_paused(run, id)`: a module's last answer,
  and whether the last sweep paused it.
- With several workers, a source and the modules between it and a
  converged module may run a few steps ahead while it catches up (the
  pipeline in flight); a converged module does not consume those rows.
- A module that converged can skip work in `step!` when stepped for a
  control input (e.g. return `StepResult(:blocked, 0)`).

Tests: `test/progressive/test_convergence.jl` (a source stops when its
consumer converged, the most demanding consumer decides, backpressure from
a slow consumer, leaves without an opinion want everything, through a
filter, a live input resumes a paused source and no steps happen while
paused; 1 and 4 workers). Example: TaxiVis on a year of trips
(`examples/taxivis/README.md`) loads 18% of 173 M trips before its
displays converge.

### Edits during a run

Give the engine a `ProgressiveStateCache` and every module's progressive
state (accumulators, output tables, positions in its inputs) is kept when a
run ends, keyed by the module's [signature](#signatures). A later run with
the same engine resumes each module whose signature is unchanged and whose
producers were all resumed; the others start over and read their inputs from
the beginning. This is VisTrails' caching applied to progressive state.

```julia
engine = ProgressiveEngine(state_cache=ProgressiveStateCache())
pr = start!(engine, version_a)
# ... while it runs, edit the pipeline (e.g. in the editor: a new version)
pr = restart!(pr, version_b)    # stop, then start version_b with the kept states
```

- Unchanged modules **continue**: a source keeps producing from where it
  stopped (into the same table), statistics keep their accumulators.
- Edited modules and everything downstream of them **start over**, reading
  all rows already produced.
- Switching back to an earlier version resumes its modules too, including
  modules that run stopped half-way.
- `restart!` keeps the observers; it is `stop!`, `wait` and `start!` with
  the same engine. `run!` and `start!` use the cache the same way.
- Step and item counts (`module_steps`) of a resumed module are cumulative.
- Kept states hold their tables: `ProgressiveStateCache(max_entries=256)`
  drops the least recently kept beyond that, and `empty!(cache)` drops all.
- Not kept: failed and cancelled modules, non-cacheable modules and their
  downstream, and `Variable`s (their current value is not in their
  signature), so modules downstream of a `Variable` start over.

### Provenance of progressive runs

**Partial results.** `module_progress(run, id)` returns `(done, total)` for
a progressive module: rows produced by a `RandomTable` (of `rows`), bytes
read by a `CSVLoader`, rows consumed by a fold or map (of the rows available
so far); module types can extend `progress(state)`. The execution log
records it: each `ModuleExec` of a progressive run has the annotations
`steps`, `items`, `status` and `progress`. Modules that had not finished
when a run was stopped are logged too, with `partial = "true"` and
`completed = 0`, so the log says how far each partial result got. Resumed
modules have `resumed = "true"`; those already finished are logged as
cached.

**Execution history.** `ExecutionHistory()` is an observer recording every
step (start, end, work, state) of every module. Export it in the JSON format
of ProgressiVis' execution history (schema version 1) and open it in its
offline viewer (`progressivis-parallel/tools/execution-viewer/index.html`)
to replay the run, with the steps' overlap:

```julia
history = ExecutionHistory()
run!(ProgressiveEngine(), pipeline; observers=[history])
export_execution_history(history, "capture.json")
```

**Live input changes as versions.** `VersionRecorder(vistrail, version)`
records each `set_variable!` of a run of `vistrail.pipelines[version]` as a
new version: a child of the previous one, whose pipeline has the new value
as the `Variable`'s `value` parameter, and whose action lists the change. An
exploration session becomes a branch of the version tree; running its last
version reproduces where the session ended.

```julia
recorder = VersionRecorder(vt, v)
pr = start!(ProgressiveEngine(), vt.pipelines[v]; observers=[recorder])
set_variable!(pr, threshold, 0.1); set_variable!(pr, threshold, 0.3)
recorder.versions    # two new versions, children of v
```

### Progressive modules

Package `org.vistrails.progressive` (short name `progressive` in workflow
notebooks). Tables flow through ports named `table` (input) and `result`
(output).

| Module | Parameters | Output `result` |
|--------|-----------|-----------------|
| `RandomTable` | `columns` (default `["x", "y"]`), `rows` (1 000 000), `seed` (0) | table of uniform `Float64`; same rows whatever the step sizes |
| `CSVLoader` | `path`, `columns` (optional subset) | table; types inferred from the first 1 000 rows, integers widened to `Float64` |
| `ArrowLoader` | `path`, `columns` (optional subset), `throttle` (max rows per step, 0: none), `rate` (max rows per second, in chunks of 50 ms of rows; 0: none) | table with the file's column types; the file is memory-mapped |
| `ParquetLoader` | `path`, `columns` (optional subset) | table with the file's column types (nullable floats: plain, null as NaN; other nullable columns keep `missing`); decodes one row group at a time (Parquet2.jl, ~90 M values/s), loaded on first use |
| `Count` | — | `ProgressiveValue{Int}` |
| `Min`, `Max`, `Mean`, `Var` | `columns` (default: numeric columns) | `ProgressiveDict` column → value |
| `Histogram1D` | `column`, `bins` (64), `min`, `max` | `ProgressiveValue{Vector{Int}}` |
| `Histogram2D` | `x_column`, `y_column`, `xbins`, `ybins`, `xmin`, `xmax`, `ymin`, `ymax` | `ProgressiveValue{Matrix{Int}}` |
| `Quantiles` | `columns` (default: numeric), `quantiles` (`[0.25, 0.5, 0.75]`), `k` (200) | `ProgressiveDict` column → quantile values; KLL sketch, rank error ≈ 1.65/k (0 and 1: exact min, max) |
| `KLLSketch` | `column`, `quantiles`, `binning` (number of bins), `k` (200) | `ProgressiveDict`: `n`, `min`, `max`, `quantiles`, and with `binning` `splits` (bin edges) and `pmf` (approximate fraction per bin) |
| `Histogram1DCategorical` | `column` (any type) | `ProgressiveDict` value → count |
| `Distinct` | `columns` (default: all), `threshold` (56) | `ProgressiveDict` column → `Set` of values, or `nothing` once more than `threshold` |
| `Corr` | `columns` (default: numeric), `mode` (`"Pearson"` or `"CovarianceOnly"`) | `ProgressiveDict` `(a, b)` → correlation (covariance), every ordered pair |
| `IdxMin`, `IdxMax` | `columns` (default: numeric) | `ProgressiveDict` column → `(id=row id, value=)`; ties: first row; NaN skipped |
| `Sample` | `samples` (50), `seed` (42) | table of `samples` uniformly sampled rows (reservoir, Algorithm L), replaced in place as rows arrive; port `select`: their input row ids; the same sample whatever the step sizes; input deletions restart it |
| `BinningIndex` | `column` or `columns`, `tol` (bin width; negative: \|tol\| % of the 5th-95th percentile range of the first rows; -1), `init_threshold` (rows before sizing bins; 10 000) | `result`: selection view of the indexed rows, carrying the index (`meta[:index]`); `min`, `max`: `ProgressiveDict` per column |
| `RangeQuery` | input `index` (a `BinningIndex` result); `column`, `lower`, `upper` (`lower` ≤ value < `upper`; unset or NaN: unbounded) | selection view of the matching rows |
| `RangeQuery2D` | input `index`; `x_column`, `y_column`, `x_lower`, `x_upper`, `y_lower`, `y_upper` | selection view |
| `SimpleFilter` | input `index`; `column`, `op` (`<`, `<=`, `>`, `>=`, `==`), `value` | selection view |
| `CategoricalQuery` | `column`, `choice` (values to keep) | selection view (scans; no index) |
| `Intersection` | several selection views of one table on `table` | selection view of the rows in all of them |
| `Percentiles` | input `index`; `column`, `percentiles` (0-100; `[25, 50, 75]`) | `ProgressiveDict` percentile → value; exact (numpy's "lower") |
| `Unary` | `function` (`abs`, `sqrt`, `log`, `exp`, `sin`, `floor`, `isnan`, ...: `ELEMENTWISE_UNARY`), `columns` (default: numeric) | table of those columns, transformed; types follow the function |
| `ColsBinary` | `function` (`+`, `-`, `*`, `/`, `^`, `min`, `max`, `hypot`, `atan2`, comparisons, ...: `ELEMENTWISE_BINARY`), `first`, `second` (column lists, pairwise), `cols_out` (default `first`) | table of the results |
| `Reduce` | `function` (associative: `+`, `*`, `min`, `max`, `&`, `\|`, `xor`), `columns` | `ProgressiveDict` column → reduction |
| `LinearMap` | inputs `vectors` (rows: k columns, `columns`) and `transformation` (k rows × m columns, `transformation_columns`) | table of m columns (the transformation's names): each row times the matrix; rows wait until the matrix has k rows, and a change in it remaps all |
| `GroupBy` | `by` (columns) | selection view of all rows, carrying the groups (`meta[:groups].rows`: key → row ids; key: the value, or a tuple) |
| `Aggregate` | `compute` (`"column:function"`, functions `count`, `sum`, `mean`, `var`, `std`, `min`, `max`; `":count"`), `by` (or from a `GroupBy` input) | table: one row per group (`by` columns, then `column_function`), appended in order of appearance and updated in place; input updates and deletions recompute all groups |
| `Join` | inputs `primary` (unique key) and `related`; `on` (or `primary_on` and `related_on`), `how` (`"inner"`, `"outer"`), `primary_columns`, `related_columns`, `suffix` (`"_primary"`) | table: each related row with its primary row's columns; inner: rows wait for their key; outer: `missing` until the key arrives, then filled in (updates) |
| `JoinById` | several tables on `table` (views of one table) | table of the rows in every input, all columns (clashes: `name_k`) |
| `Switch` | `condition` (`Bool`; unset: wait) | `result` (rows while true), `result_else` (while false): selection views; a change moves the rows |
| `Blobs` | `rows` (100 000), `centers` (a number, drawn in `center_box` `[-10, 10]`, or a list of points; 3), `cluster_std` (one, or one per center; 1.0), `columns` (names, or a number n: `_1`…`_n`), `seed` | table of Gaussian blobs (sklearn's `make_blobs`); port `labels`: table `label` (1-based center), row i for row i; same rows whatever the step sizes |
| `MVBlobs` | `means`, `covs` (one covariance matrix per mean, as rows), `rows`, `columns`, `seed` | multivariate normal blobs; port `labels` |
| `MinMaxScaler` | inputs `min`, `max` (from `Min`, `Max`); `columns` (default: numeric), `delta` (margin: < 0, % of the extent; -5), `ignore_max` (0), `reset_threshold` (1000) | table: `columns` scaled to [0, 1] with the bounds fixed at the first rows, others passed through; values out by at most `delta` clipped, rows further out dropped (up to `ignore_max`), else a reset (new bounds, all rows again); bound changes reset while ≤ `reset_threshold` rows are out; port `info`: `clipped`, `ignored`, `resets` |
| `MBKMeans` | `n_clusters`, `columns` (default: numeric), `batch_size` (1024), `tol` (largest center move to converge; 1e-5), `seed`; optional input `moved_center` (`Dict` cluster → coordinates) | table of the centers (one row per cluster, updated in place); port `labels`: table `row` (input row id), `label` (1-based), in passes over the rows as centers move; port `converged` |
| `MBKMeansFilter` | inputs `table` (data), `labels` (from `MBKMeans`); `cluster` | selection view of the rows of that cluster, following the labels |
| `PPCA` | `n_components` (2), `columns` (default: numeric) | selection view of the rows fitted; port `transformer`: the `PCAModel` (`components`, `mean`, `explained_variance`, ...), a new one per step (incremental PCA, one SVD per step) |
| `PPCATransformer` | inputs `table`, `transformer`; `n_components` (as the model's), `rtol` (0.001), `threshold` (rows after which it stops resetting; none), `samples` (100), `seed` | table `_pc1`…: each row projected with the model of the last reset; a model drifting by more than `rtol` (on sample rows) resets: every row projected again, in place |
| `KernelDensity` | `x_column`, `y_column` (`x`, `y`), `knn` (100), `bandwidth` (0.2), `samples` (points) or `bins` (32: a grid over the points' extent), `threshold` (rows between estimates; 1000) | table `x`, `y`, `density` per sample point, updated in place: mean Gaussian kernel over the k nearest points (exact) |
| `TSNE` | `columns` (default: numeric), `output_columns` (`["x", "y"]`), `perplexity` (30), `max_iter` (1000 after the last new rows), `iterations` (per step; 1), `theta` (0.5), `learning_rate` (`"auto"`), `early_exaggeration` (12), `exaggeration_iterations` (250), `seed` | table of the embedding, one row per input row, moving in place |
| `Filter` | `column`, `op` (`<`, `<=`, `>`, `>=`, `==`, `!=`), `value` | table of the matching rows |
| `Select` | `columns` | table with those columns |
| `Sink` | — (consumes any input) | port `count`: rows consumed |
| `Variable` | `value` (initial) | `ProgressiveValue`: an input, set with `set_variable!` |

The modules after `Count`…`Histogram2D` in the table are ports of
ProgressiVis' (`progressivis/stats`, `io`). Differences: `Quantiles`
publishes the requested quantiles instead of answering per-quantile hints;
`IdxMin`/`IdxMax` publish the current row and value instead of a table of
the last few; `Sample` outputs a table of the sampled rows rather than a
view of the input. Sketch results (`Quantiles`, `KLLSketch`) are within
their rank error at every step but are not bit-identical across step sizes
(sketches merge along step boundaries); the other results are exact.
Queries (tier 2) work as ProgressiVis': a bound change re-queries the
index (whole bins between the bounds' bins, values checked in those two
bins only, so results are exact) and consumers receive just the difference
in the selection; new, updated and deleted rows are checked as they come.
Bounds are parameters, so a connected `Variable` drives them live. Only
non-empty bins are stored (ProgressiVis allocates every bin from min to
max: taxi coordinates with outliers at 0 would need millions). In the
one-shot engines, query inputs arrive as plain tables without the index
and queries scan; `Intersection` needs the progressive engine (row ids).
On the 14.8 M January trips (10 threads, compiled): load, index two
columns and query a box of 7.9 M trips in 0.56 s; re-query a zoomed box
(585 K trips, histogram and count downstream) in 0.24 s.

Tier 3 differs from ProgressiVis in: one module per kind of element-wise
operation, taking the function by name (`register_elementwise!` adds
functions), instead of a class per NumPy function; `Join` and `JoinById`
copy values into a new table (ProgressiVis: views with computed columns),
and handle inputs arriving in any order (ProgressiVis' `JoinById`, `Merge`
and `CombineFirst` recompute from scratch at each step); `Switch` can
change its mind; grouping by parts of datetime columns is left to a map
deriving a key column. Not ported: `CombineFirst`, `Paste`, `UniqueIndex`
(inside `Join`). Loading the January trips (0.11 s) and aggregating by
passenger count (mean distance, count): 0.29 s; joining every trip with a
10-row lookup table: 0.57 s.

Tier 4 (analytics) differs from ProgressiVis in: `MBKMeans` labels every
row (ProgressiVis: only the rows of its mini-batches) in passes that
restart while the centers move, and seeds with greedy k-means++ on one
batch as sklearn; `MinMaxScaler` clips and drops rows at every step
(ProgressiVis only in the step where the bounds changed; its tests are
skipped as "not ready yet"); `PPCATransformer` re-projects rows in place
rather than truncating its output; `KernelDensity` and `TSNE` are native
(ProgressiVis wraps pynene's C++): exact neighbors (a Z-order index of
sorted runs for the densities; brute force with BLAS for t-SNE, O(N² d):
practical up to some tens of thousands of rows), Barnes-Hut repulsion for
2-D embeddings. On the 14.8 M January trips (10 threads, compiled):
k-means converges in 0.34 s (median of five seeds; ProgressiVis 3.5 s),
PPCA fits in 1.3 s (2.6 s), MinMaxScaler with Min and Max 0.50 s (9.7 s),
densities of the pickups at 32² points 2.0 s; t-SNE of 10 000 rows in
50-D: 8.2 s (`benchmarks/compare/results/analytics/summary.md`).

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
  `ProgressiveValue` instead of a dict; `key_type` sets the dict's key type
  (default `Symbol`); `row_ids=true` adds the field `_id` to each chunk
  (the row ids it covers). A dict result reports only changed keys, so
  return new objects rather than mutated ones. Parameters: `param(ctx, "name", default)`.
- A map's output rows follow their input rows: updated inputs are
  re-mapped, deleted inputs delete their outputs. `extra_inputs` adds table
  inputs that `map` reads through `ctx` (a change there remaps all rows);
  rows wait while `ready(ctx)` is false.

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
done, `default_step_size(::Type{MyModule})` for the first steps,
`progress(state)` for provenance, `converged(state)` to stop loading once
its result is good enough ([Convergence](#convergence)). A module
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
update_rows!(t, [3, 7], (x=[0.0, 1.0],))   # update many rows at once
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
  views covering a range of ids, e.g. `sum(sum, segment_views(col, r))`;
  `t[ids, :x]` copies values through them; `gather(column(t, :x), ids)`
  reads values at arbitrary ids (e.g. a selection's).

### Selection views

A selection view is a table of selected rows of another table
(ProgressiVis' `PTableSelectedView`); queries output them. It shares the
base table's columns and row ids, so any module reads it like a table;
selecting and deselecting rows reach its subscribers as created and deleted
rows.

```julia
v = selection_view(t)               # empty selection of t's rows
select!(v, RowIds([2, 5, 9]))       # subscribers: created
deselect!(v, RowIds([5]))           # subscribers: deleted (it can be selected again)
set_selection!(v, ids)              # subscribers get only the difference
touch!(v, ids)                      # selected rows among ids changed in t: updated
v.meta[:index]                      # what its producer attached (BinningIndex: the index)
```

Unselected ids up to `last_id(v)` are its `deleted` set, so `length` and
progress count only selected rows. Appends and writes go to the base table.
Scattered ids (ranges of fewer than 32 ids on average) are read by
gathering values (`t[ids, :x]`, fold chunks) rather than range by range.
`RowIds` set operations (`union`, `setdiff`, `intersect`) merge in one pass
when both sides have many ranges; a scattered selection costs 16 bytes per
row (a range per id), against about 2 for ProgressiVis' roaring bitmaps.

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

- **ProgressiVis modules, tier 4 (2026-10-14)**: `Blobs`, `MVBlobs`,
  `MinMaxScaler`, `MBKMeans`, `MBKMeansFilter`, `PPCA`, `PPCATransformer`
  (`PCAModel`, `transform`, `inverse_transform`), `KernelDensity`,
  `TSNE`; `update_rows!` (bulk updates of a table). Tests:
  `test_analytics_modules.jl`; benchmarks: `benchmarks/compare/analytics.*`.
- **ProgressiVis modules, tier 3 (2026-10-14)**: `Unary`, `ColsBinary`,
  `Reduce`, `LinearMap`, `GroupBy`, `Aggregate`, `Join`, `JoinById`,
  `Switch`; `define_map_module!` takes `extra_inputs` and `ready`. Fixed: a
  fold restarted with no rows left (a view emptied) kept its old result.
  Tests: `test_relational_modules.jl`.
- **ProgressiVis modules, tier 2 (2026-10-13)**: selection views of tables
  (`selection_view`, `select!`, `deselect!`, `set_selection!`, `touch!`,
  `meta`); linear-time `RowIds` `union`/`setdiff`/`intersect`; scattered ids
  read by gathering; `producers_done(ctx)`. Modules `BinningIndex` (sparse
  equal-width bins), `RangeQuery`, `RangeQuery2D`, `SimpleFilter`,
  `CategoricalQuery`, `Intersection`, `Percentiles`. Tests:
  `test_indexes.jl`.

- **ProgressiVis modules, tier 1 (2026-10-13)**: `ParquetLoader`
  (Parquet2.jl), `Quantiles` and `KLLSketch` (KLL sketch, mergeable, so
  data-parallel), `Histogram1DCategorical`, `Distinct`, `Corr`, `IdxMin`,
  `IdxMax` (folds), `Sample` (reservoir, Algorithm L); folds take
  `key_type` and `row_ids`. Parquet2.jl is loaded only when a
  `ParquetLoader` runs (loading it slowed the Arrow dashboard by ~12%).
  Tests: `test_progressivis_modules.jl`.

- **Performance (2026-10-13)**: folds with `merge` fold groups of
  blocks (at most 16 accumulators per step) instead of one accumulator per
  16 384-row block; histogram loops behind a function barrier (their
  bounds are untyped parameters). The taxi dashboard (14.8 M rows, two 512²
  histograms) went from 5.4 s to 0.15 s on one thread; `RandomTable` writes
  its columns directly (no matrix and copies: 0.36 → 0.24 s for 40 M values,
  same rows). `ready_to_step(state,
  ctx)` hook: a fold whose parameter comes from an input without a value
  yet is not stepped (it completes if that never changes).
- **Convergence (2026-10-13)**: `converged(state)` hook; sources and
  modules with work left over step only while a module downstream wants
  data, and resume when one does again; `run!` completes paused modules
  (annotated `converged`); `module_converged`, `is_paused`. Then:
  backpressure (a source waits for consumers still needing data to catch
  up), control inputs vs data (table rows step a module only while it
  needs data).
- **TaxiVis (2026-10-13)**: `ArrowLoader` progressive source (with
  `throttle` and `rate`, to watch a fast source load), `gather`;
  example `examples/taxivis/` (port of ProgressiVis' progressive TaxiVis:
  14.8 M trips, 39 modules, live queries over HTTP).
- **Phase 5b (2026-10-13)**: `ProgressiveStateCache` (progressive state
  kept by signature across runs, edits and versions; LRU), `restart!`;
  `progress`/`module_progress` and progress annotations, partial results of
  stopped runs logged; `ExecutionHistory` and `export_execution_history`
  (ProgressiVis viewer format, validated with its parser);
  `VersionRecorder`; `add_version!` takes `operations` and no longer reuses
  ids of non-contiguous version trees.
- **Phase 5a (2026-10-13)**: `Variable` input module, `set_variable!`,
  `close_inputs!`, `is_input_module`; parameters driven by connected inputs
  (`param`), with an optional input port per fold/map parameter; restart of
  folds and maps on parameter changes; interactive selection with
  `interactive_quantum`, serial sweeps limited to it, parallel priority,
  reserved slot and interactive threadpool; idle runs sleep;
  `on_interaction`, `on_interaction_done`.
- **Phase 4 (2026-10-13)**: parallel progressive scheduler
  (`ProgressiveEngine(workers=N)`: task and pipeline parallelism, one step
  per module at a time, least-recently-stepped first, main-thread modules on
  the scheduler task); data-parallel folds (`merge` in
  `define_fold_module!`, used by all statistics modules); the time
  predictor skips the first non-empty step; faster maps and table reads
  (Filter pipeline 3.6 s → 0.87 s for 20 M rows).
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
