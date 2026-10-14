# Julia vs Python: preliminary comparison

VisTrailsJL's progressive engine against ProgressiVis (`parallel-scheduler`
branch), on a subset of the experiments of the ProgressiVis paper
(`progressivis-parallel/paper`, Sec. "Evaluation"), same machine and data.
Preliminary: few repeats, no load control beyond running on an otherwise
idle machine. Results and their summary: `results/<name>/`.

| Exp | Workload | Python (unchanged paper drivers) | Julia |
| --- | --- | --- | --- |
| E1 | taxi dashboard: source → Min, Max → two 512² Histogram2D (bounds by ProgressiVis' 5% rule), ± Var; January 2013, 14.8 M rows, stratified order; in memory and from file | `design/benchmarks/master_vs_branch/bench_one.py`, CPython 3.14 std and free-threaded (`PYTHON_GIL=0`), W = 1, 2, 4 | `dashboard.jl`, 1 thread (W = 1), all cores (W = 1, 4) |
| E3 | graph shapes: 4 pipelines, fan-out, uneven, narrow; 1 M rows × 10 columns | `scripts/bench_parallel.py 4 1000000` | `shapes.jl`, 1 thread and all cores |
| E4 | one module (Var, Min+Max, Histogram1D, Histogram2D) over 20 M × 8 in memory | `scripts/bench_data_parallel.py`, widths 1 … cores | `modules.jl`, threads 1 … cores |

## Running

```sh
cd julia/benchmarks/compare
./setup_python.sh                 # tree of progressivis-parallel HEAD (git archive) + .venv-std, .venv-ft
.venv-std/bin/python -I prepare_data.py   # data/strat.{npz,parquet,arrow} from the TaxiVis January file
python3 run.py --name NAME        # ~40 min; --only e1,e3,e4, --repeats N
python3 summarize.py results/NAME > results/NAME/summary.md
```

`prepare_data.py` needs `julia/examples/taxivis/data/taxivis_2013_01_stratified.arrow`
(`julia/examples/taxivis/prepare_data.jl`), identical to ProgressiVis'
Parquet file of the paper. `py_shim.py` runs ProgressiVis' scripts
unchanged on macOS (no `os.sched_getaffinity`; `ru_maxrss` in bytes).

## Protocol and differences to keep in mind

- Fresh process per E1 run, configurations shuffled per repeat; E3 and E4
  run all repeats in one process per system (as the Python scripts do).
- **Julia compiles**: each Julia process first runs the same graph on 200 000
  rows (warm-up) and then the measured run. The cold column of the summary
  is that warm-up's time (mostly compilation, ~3-5 s), which a user pays
  once per session.
- **Threads**: ProgressiVis' W workers plus helper threads for data-parallel
  steps (up to cores/W per step; W = 1 has none). Julia's W workers, and
  folds split each step over all of Julia's threads (`--threads`): Julia
  on one thread is the serial baseline.
- **Exactness**: each system checks its pickup histogram against a batch
  count of all rows with its final bounds (Python against
  `np.histogram2d`, Julia against its own counting function), and Var
  against a batch variance.
- **From file**: Python reads Parquet (`ParquetLoader`, pyarrow); Julia
  reads the same Parquet file (`ParquetLoader`, Parquet2.jl) or Arrow
  (`ArrowLoader`, memory-mapped, uncompressed). Only the Parquet rows
  compare loaders like for like.
- **Steps**: both size steps to a time quantum; Julia's steps cover more
  rows, so it updates the heatmap fewer times.

## Preliminary results (2026-10-13, Apple M5, 10 cores)

Full tables: [`results/2026-10-13-prelim/summary.md`](results/2026-10-13-prelim/summary.md)
(3 repeats, medians; every run exact).

| | Python std | Python ft | Julia, 1 thread | Julia, 10 threads |
| --- | ---: | ---: | ---: | ---: |
| E1 dashboard in memory, no Var, W = 1 | 0.93 s | 0.88 s | 0.11 s | 0.05 s |
| E1 best W (no Var) | 0.28 s (W=2) | 0.27 s (W=2) | – | 0.05 s (W=1) |
| E1 with Var, best W | 0.37 s | 0.28 s | 0.17 s | 0.04 s (W=4) |
| E1 from file, with Var (Python Parquet / Julia Arrow) | 1.46 s (W=4) | 1.40 s (W=4) | 0.31 s | 0.19 s (W=4) |
| E1 from Parquet, with Var (both), W = 1 / best | 1.74 / 1.46 s | 1.82 / 1.40 s | 1.92 s | 1.02 s (W=4) |
| E1 first heatmap, memory, W = 1 | 4 ms | 13 ms | 2 ms | 2 ms |
| E3 four pipelines, W = 4 | 0.38 s | 0.15 s | 0.20 s | 0.13 s |
| E3 fan-out, W = 4 | 0.18 s | 0.12 s | 0.05 s | 0.03 s |
| E4 Histogram2D 512², 20 M rows, best width | 0.46 s | 0.38 s | 0.10 s | 0.04 s |
| E4 Var, 20 M × 8, best width | 0.11 s | 0.05 s | 0.05 s | 0.015 s |

Reading them:

- Serially, Julia runs the dashboard 8× faster than either Python build;
  with all cores, 5-8× faster than Python's best configuration. The
  largest gap is the 2-D histogram (E4: 19× serially), a compiled loop
  against NumPy's `histogram2d`; Min/Max and Var are memory-bound in both
  and differ 2-3×.
- Julia pays compilation instead: 3-4 s for the first run of a graph in a
  fresh process (the cold column), more than the whole Python run.
- Python's task parallelism scales better (four pipelines: 3.8× from W = 1
  to 4 on ft; Julia 1.1-1.4×), but from a much slower serial baseline:
  Julia's folds already use every thread at W = 1, so workers add little.
- Julia updates the heatmap fewer times (4-5 vs 9-10): steps are sized to
  the same kind of time quantum, and each covers more rows.
- From Arrow with 4 workers on 10 threads, Julia resets the histograms
  more (9 vs 3 at W = 1) and shows its first heatmap later (110 ms): the
  histograms start on bounds from the first rows while the loader runs
  ahead (the paper's E13 observes the same with pipeline overlap).
- From the same Parquet file, the gap closes: Julia is slower on one
  thread (1.92 s vs 1.74 s) and 1.4× faster with all cores (1.02 s vs
  1.40 s), and shows its first heatmap later (250 ms vs 17-31 ms).
  Parquet2.jl decodes about 90 M values/s, 1.0 s of the 1.9 s, and decodes
  a whole row group (1 M rows) before the first rows go out; decoding
  further row groups on other threads did not help. (Measured after the
  preliminary run: 3 runs per configuration, not in `results/`.)
- Julia uses about twice the memory (2.0-2.5 GB vs 1.0-1.5 GB): its
  in-memory table is a copy of the Arrow data, and the runtime is larger.

Found and fixed while setting up (VisTrailsJL `a7777c8ec` and after): one
accumulator per 16 K-row block in data-parallel folds, dynamically
dispatched histogram loops (dashboard 5.4 → 0.15 s), and a slow
`RandomTable`; Arrow files written by PyArrow in 64 K-row batches load as
`ChainedVector`s in Julia, slower and compiled separately (`prepare_data.py`
writes one batch).

Next, for a full set: more repeats with load control; the remaining
experiments (E5 overlap, E6 latency under load, E8 quality over time, C2
the year); Julia's CSV loader against Python's; a faster Parquet decoder
(or decoding pages rather than whole row groups); and both systems on the
Linux machine of the paper.


## Analytics modules (tier 4, 2026-10-14)

`analytics.py` (ProgressiVis) and `analytics.jl` (Julia): MBKMeans,
PPCA (+ PPCATransformer), MinMaxScaler, Blobs on the January trips in
memory; KernelDensity and TSNE in Julia only (ProgressiVis' need pynene).

```sh
PYTHONPATH=trees/head .venv-std/bin/python py_shim.py analytics.py [rows|0 [kmeans,ppca,scaler,blobs]]
julia --project=../.. --threads=N analytics.jl [rows|all [kmeans,ppca,scaler,blobs,kde,tsne]]
```

Results and notes (ProgressiVis needed three workarounds):
[`results/analytics/summary.md`](results/analytics/summary.md). In short,
Julia on 10 threads: k-means 0.34 s median to converge (Python 3.5 s;
0.06-0.19 ms per iteration against 1.45 ms), PPCA fit 1.3 s (2.6 s), with
projection 2.8 s (4.9 s), MinMaxScaler 0.50 s (9.7 s), Blobs 0.23 s
(1.0 s).
