# Analytics modules (tier 4): Julia vs ProgressiVis, preliminary

2026-10-14, Apple M5 (10 cores), one run each (k-means: five seeds).
January 2013 taxi trips, 14 776 615 rows, in memory (Python: `Constant`
source; Julia: `ConstantTable`). Julia after a warm-up run on 200 000 rows
(compilation). Python: CPython 3.14 (standard), ProgressiVis
`parallel-scheduler` tree `trees/head`, numpy/sklearn with their own
threads. Logs: `python_std*.log`, `julia_t10.log`, `julia_t1.log`
(t-SNE after its optimization: see below).

| Workload | Python | Julia, 1 thread | Julia, 10 threads |
| --- | ---: | ---: | ---: |
| MBKMeans k = 10 on the pickups: time to converge, median of seeds 0-4 | 3.5 s | 0.34 s | 0.34 s |
| … iterations to converge (seeds 0-4) | 1 066 – 10 955 | 758 – 20 930 | 758 – 20 930 |
| … time per iteration (1024 rows) | 1.45 ms | 0.06 – 0.28 ms | 0.06 – 0.19 ms |
| … and every row labelled (Julia only: ProgressiVis labels only mini-batch rows) | — | 1.2 – 2.8 s | 1.2 – 2.8 s |
| PPCA, 2 components, six columns (fit) | 2.63 s | 1.63 s | 1.29 s |
| PPCA + PPCATransformer (every row projected) | 4.91 s | 4.59 s | 2.76 s |
| MinMaxScaler with Min and Max, six columns | 9.68 s | 0.77 s | 0.50 s |
| Blobs, 14.8 M rows, 2 columns | 1.01 s | 0.32 s | 0.23 s |
| KernelDensity of the pickups, 32² sample points (no pynene: Julia only) | — | 2.50 s | 2.03 s |
| TSNE, 10 000 rows of 50-D blobs, 1000 iterations (Julia only) | — | 21.3 s | 8.2 s |

Notes

- Iterations to converge depend much on the seed in both systems: the
  pickups have scattered bad coordinates (0, 0; far outliers), and a center
  among them keeps moving more than the tolerance (1e-5) as samples hit
  it. Compare times per iteration; the seeds' random streams differ.
- ProgressiVis needed workarounds: `MBKMeans` with a column hint fails
  writing its centers ("Adding new columns (...) via __setitem__ not
  implemented"), so it gets a two-column table; a greedy `MBKMeans` (the
  default) keeps iterating after converging and the run never ends, so
  `is_greedy=False`; `MinMaxScaler` without a `control` input fails
  ("slot 'control' not connected"), so it gets a `ConstDict` (as its own,
  skipped, test).
- PPCATransformer resets (re-projects every row) when the model drifts:
  Julia's resets 11-13 times here, which is most of the difference between
  its fit and fit + transform.
- t-SNE (10 threads) went from 20.4 s to 8.2 s by packing the Barnes-Hut
  nodes, symmetric affinities (forces per row, on threads), and visiting
  points in Z-order; the logs' TSNE lines predate that.
