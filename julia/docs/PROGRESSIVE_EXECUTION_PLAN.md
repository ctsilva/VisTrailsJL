# Progressive Execution Plan for VisTrailsJL

Status: Phases 0-2 and 3a done (branch `progressive-engine`). Started 2026-10-13.

## Goal

Give VisTrailsJL a native Julia execution model that borrows the ideas of
ProgressiVis (`~/src/progressivis-parallel`): modules that run in bounded,
time-sized steps over change sets, so a workflow on large data produces
improving partial results while staying interactive, and that can use many
cores. VisTrails keeps what it is good at: the workflow model, the version
tree, provenance, and caching across edits.

The ProgressiVis side of this analysis is in
`progressivis-parallel/design/vistrails_compatibility.md` (two loops: VisTrails
is the outer loop, where the user edits; ProgressiVis the inner loop, where
data arrives). The model is described in `progressivis_model_from_code.md` and
the parallel work in `parallel_progressivis.md` and `phase3_pipeline_parallelism.md`.

## Decisions

1. **Native Julia engine**, borrowing the ProgressiVis model. No runtime
   dependency on ProgressiVis; interop is optional (Phase 6).
2. **Three layers**: workflow specification (engine-neutral), module
   implementations (one-shot `compute` and/or progressive `step!`, chosen by
   dispatch), engines (one-shot, cached, parallel, progressive).
3. **Updates and deletions**: start append-only; any other change resets the
   consumer (ProgressiVis' `@process_slot` default). True incremental
   updates per module later.
4. **Storage**: our own segmented, append-only column storage exposing the
   Tables.jl interface, designed from the start so readers never see a
   reallocation (ProgressiVis had to retrofit this in its Phase 3).

## Starting point (before Phase 0)

`src/core/interpreter/default.jl` (≈200 lines):
- runs modules in topological order **and** pulls upstream modules
  recursively in `collect_inputs!` (redundant; hidden by a per-run memo);
- no caching across runs: the "cache" is a per-run dict keyed by module id;
- execution state (`inputs`, `outputs`, `cache_state`) lives on
  `ModuleInstance`, i.e. on the workflow itself, so a run mutates the pipeline;
- several connections into one input port overwrite each other (last wins);
- a second executor in `src/notebook/workflow_parser.jl`
  (`execute_notebook_pipeline`); notebook-defined modules only run there;
- single-threaded, no partial results, no way to observe a run in progress.

## What to borrow from ProgressiVis, and what not

| Borrow | Avoid |
| --- | --- |
| Per-connection change sets (created/updated/deleted ids) with a bookmark per consumer | The implicit "one step at a time, one thread, no locks" assumption |
| Bounded steps sized by a time predictor against a quantum | A module exception stopping the whole run |
| Readiness from pending changes; termination by propagation | Change detection by object identity (`PDict`) |
| Reset when a change kind cannot be handled incrementally | Storage that reallocates under readers |
| Interactive priority: modules between an input and the outputs get a latency budget | Progress reporting stubbed out |
| Parallel rules: no adjacent overlap, transitive producer ordering, barrier between sweeps | |
| Prefix-consistency and interleaving-independence tests | |

Julia-specific: multiple dispatch makes "one module type, several
implementations" natural; threads have no GIL. JIT compilation lands in the
first step of each module: the time predictor must discard first-step
timings, and standard modules should be precompiled (PrecompileTools).

## Phases

### Phase 0 — separate the workflow from the engine (prerequisite)
- `abstract type Engine`; `run!(engine, pipeline; observers)`. The current
  behavior becomes `OneShotEngine`.
- Run state (`PipelineRun`) holds per-run module instances and outputs; the
  pipeline is not mutated by execution.
- Remove the recursive pull; one execution path for built-in and
  notebook-defined modules; `execute_notebook_pipeline` and the API's
  `execute` become thin wrappers.
- List-valued inputs: all values connected to a port, in connection order
  (`get_input_list`); `inputs[port]` keeps the last value for compatibility.
- Observer interface (`on_run_start`, `on_module_start`, `on_module_done`,
  `on_module_error`, `on_run_done`), used for console output and for saving
  outputs into notebooks; later for progress streaming to the backend.
- **Exit:** the existing test suite passes unchanged; new tests check that
  each module runs once, the pipeline is not mutated, list inputs, observer
  events and failure handling.

### Phase 1 — signatures and a cache across runs (the VisTrails half)
- `module_signature` (package, name, version, parameters, port specs) and
  `subpipeline_signature` (plus upstream signatures and connections,
  recursively), after `vistrails/core/cache/hasher.py` and
  `vistrails/core/vistrail/pipeline.py:774`. Stable hashing (SHA stdlib).
- `CachedEngine`: results keyed by signature, kept across runs and versions.
- `is_cacheable` trait; sources include data identity (URL + ETag/mtime).
- **Exit:** editing one parameter of `gcd.vt` recomputes only that module and
  its downstream; moving between versions reuses shared subpipelines.

### Phase 2 — task parallelism for one-shot modules
- Start each module with `Threads.@spawn` when all its producers are done
  (one-shot outputs are immutable once produced, so no adjacency rule).
- Thread-affinity trait: PyCall/`PythonSource`/matplotlib on the main thread.
- Failure contract: stop admitting work, join running modules, aggregate
  errors. Thread-safe logging.
- **Exit:** speedup with `-t N` on a synthetic wide pipeline; results equal
  to `OneShotEngine`.

### Phase 3 — progressive engine (3a: data layer, 3b: engine)
- **Data:** `ProgressiveTable` (segmented columns, row ids, deletion set),
  change log with per-consumer bookmarks (fast path: id ranges for
  appends), Tables.jl interface. `ProgressiveValue` for general types (only
  change: "replaced").
- **Contract:** `ExecutionStyle(::Type{T})` = `OneShot()` | `Progressive()`;
  `step!(m, ctx, budget) -> StepResult(state, items)`; states ready /
  blocked / zombie / terminated. Bridges: one-shot modules recompute on input
  replacement; progressive modules in a one-shot engine run unbounded.
- **Scheduler:** sweeps in topological order, readiness from pending
  changes, linear time predictor (last ~7 steps, capped, first step
  ignored), quantum.
- **Authoring:** `@progressive_map` (per chunk) and
  `@progressive_fold(init, update, merge)` so most modules never touch the
  change-set API; `merge` enables data parallelism later.
- **First modules:** chunked CSV loader, random table, Min/Max, Mean/Var
  (Welford/Chan), Histogram1D/2D, Filter, Sink — named after the
  `tabledata` vocabulary so one-shot and progressive versions share names.
- **Tests from day one:** prefix consistency under random step sizes,
  eventual exactness, interleaving independence.
- **Exit:** a user-guide-1.3-style pipeline (CSV → filter → 2D histogram) on
  taxi data streams improving results to the backend.

### Phase 4 — parallel progressive execution
Task parallelism with the ProgressiVis rules; then pipeline parallelism
across append-only connections (enabled by segmented storage); then data
parallelism inside steps via fold merges over fixed-size blocks. Measure each
step against serial; stop when it does not pay.

### Phase 5 — interaction and provenance
- Live parameters (`#| live: true`, `Variable` modules); input mode with a
  latency budget and a reserved worker.
- Live graph edits applied between sweeps and recorded as VisTrails actions:
  an exploration session becomes a branch of the version tree.
- Signature-keyed progressive state: unchanged modules keep state and
  bookmarks across edits; parked states per version with LRU eviction.
- Provenance of partial results: steps, items, progress, quality in
  `ModuleExec`; optional per-step trace in ProgressiVis' `execution_history`
  format (reuses its offline viewer).
- Notebook directives: `#| engine:`, `#| execute: {workers: N}`, slot hints
  `a.result[x, y]`, several sources per port.

### Phase 6 — optional ProgressiVis interop
Import its module catalog as descriptors, or drive it as an external engine.

## Progress log

- 2026-10-13: branch created; test suite repaired to 20/20 before any engine
  change (duplicate include broke precompilation; notebook `outputs` cell not
  parsed; stale tests after the `VistrailWrapper` API change).
- 2026-10-13: Phase 0 done. `src/core/interpreter/engine.jl` (`Engine`,
  `OneShotEngine`, `PipelineRun`, `run!`) and `observers.jl`
  (`ExecutionObserver`, `ConsoleObserver`) replace `default.jl`.
  `execute_pipeline`, `execute_notebook_pipeline` and the API's `execute`
  run through `run!`; notebook-defined modules now also run in `.vt`
  pipelines; saving outputs into notebooks is a `NotebookOutputObserver`;
  `get_input_list` gives every value connected to a port; topological order
  is deterministic. Tests: `test/execution/test_engine.jl`; suite 21/21.
- 2026-10-13: Phase 1 done. `src/core/interpreter/signatures.jl`:
  `module_signature` (package, name, implementation, parameters, preset
  inputs, port specs; typed canonical encoding, SHA-1) and
  `subpipeline_signatures` (plus incoming connections in id order, since
  that order defines list inputs). `CachedEngine` reuses outputs by
  signature across runs and versions, and within a run for identical
  modules (gcd.vt v122 has four). A module is reusable only if it and its
  whole upstream are `is_cacheable` (`StandardOutput` and `MplFigureOutput`
  are not). Notebook modules are identified by their compute closure, so
  re-registering a package invalidates them. Reuse is logged
  (`ModuleExec.cached`, `signature` annotation) and reported via
  `on_module_cached`. The API wrappers keep a `CachedEngine`, so repeated
  `execute` calls only recompute what changed. Tests:
  `test/execution/test_cached_engine.jl`; suite 22/22.

  Open points: the cache is unbounded and in memory (no eviction, no
  persistence; notebook-module signatures are session-local); `HTTPFile`
  is cached by URL only, not by ETag/modification time; cached outputs are
  shared between runs, so modules must not mutate their inputs.
  `select_version!` only works for versions already reconstructed (the
  loader replays one version), and only v122 of gcd.vt executes (earlier
  versions hit the `If`/`While` stubs) — both pre-existing.
- 2026-10-13: Phase 2 done. `ParallelEngine(base; max_tasks)` in
  `src/core/interpreter/parallel.jl`: dependency counting, ready modules
  spawned with `Threads.@spawn` in topological order, completions through a
  channel; `base` executes each module, so parallel + cached composes.
  `thread_affinity` trait: `:main` modules (`PythonSource`, `PythonCalc`,
  matplotlib) run inline on the calling task, which must be thread 1.
  Runs and `CachedEngine` are now lock-protected (outputs, log, observers,
  cache entries); `compute` runs outside the locks. Failures: stop
  admitting, join running tasks, rethrow (or `CompositeException`).
  Benchmark (`benchmarks/parallel_engine.jl`, 50 ms CPU-bound modules):
  7.98× on 8 threads for wide and layered pipelines, 1.00× for a chain;
  ~10-20 µs scheduling overhead per module. Tests:
  `test/execution/test_parallel_engine.jl` (run by the suite with 4
  threads; stable over repeated runs with 1, 2, 4 and 8 threads); suite 23/23.

  Lesson: two spawned tasks may share a thread, so tests must not assume
  that independent modules overlap; they check the contract instead.

  Open points: `get_connections_to` scans all connections (quadratic setup
  for pipelines with thousands of modules; precompute adjacency in
  `PipelineRun`). JuliaSource and notebook modules run on worker threads
  (they `eval` code; fine for self-contained code, not for code that
  defines globals). A failure cannot interrupt a running module.
- 2026-10-13: Phase 3a done (data layer, `src/core/progressive/`).
  `RowIds` (sorted disjoint ranges; named to avoid `Base.IdSet`);
  `ProgressiveTable` with `SegmentedColumn`s (fixed-size segments, the
  segment list replaced copy-on-grow and loaded atomically; rows published
  after all columns are written); per-consumer subscriptions filled at write
  time instead of a shared log with bookmarks (same semantics: combined
  created/updated/deleted per consumer, first read reports all rows as
  created); `ProgressiveDict` (changes recorded on write, equal values are
  not changes); `ProgressiveValue` (version counter); Tables.jl interface;
  `segment_views` for bulk reads. Tests: `test/progressive/test_data_layer.jl`
  (randomized RowIds-vs-Set oracle, a consumer mirroring a table through
  its changes under random appends/updates/deletes and random read sizes,
  a concurrent producer/consumer on two threads; sabotaging the publish
  order makes that test fail); new "progressive" suite, 24/24.
  Measured: append 90-330 M rows/s, consume + sum via segment views
  1.5-2 G rows/s, element-wise reads ~30 M rows/s.

  Open points: updates of a published value by the producer while a
  consumer reads it are not synchronized (fine for isbits values written
  atomically by the hardware, not for others); no back-pressure (a slow
  consumer's buffers grow, as in ProgressiVis); `ProgressiveDict`
  iteration is not synchronized (use `snapshot`).
