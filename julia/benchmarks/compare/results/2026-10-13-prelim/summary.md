# Julia vs Python, preliminary (2026-10-13 16:35:43)

Apple M5, 10 cores; ProgressiVis tree `d6bef450`; VisTrailsJL `a7777c8ec`; julia version 1.12.7. Medians of the repeats.

## E1: taxi dashboard (January 2013, 14.8 M rows)

Wall time of the run (s), time to the first pickup heatmap (ms), heatmap updates, histogram resets, peak memory (MB), all runs exact. Julia: after a warm-up run (compilation not included; see the cold column, a first run on 200 000 rows).

| Source | Var | System | W | wall (s) | first map (ms) | updates | resets | MB | exact | Julia cold (s) |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| memory | no | Julia 1 thr | 1 | 0.110 | 2.0 | 4 | 3 | 1978 | True (3) | 2.9 |
| memory | no | Julia 10 thr | 1 | 0.053 | 1.9 | 4 | 3 | 2122 | True (3) | 3.1 |
| memory | no | Julia 10 thr | 4 | 0.082 | 4.6 | 5 | 3 | 1988 | True (3) | 3.2 |
| memory | no | Python ft | 1 | 0.878 | 12.7 | 9 | 5 | 1064 | True (3) |  |
| memory | no | Python ft | 2 | 0.267 | 22.5 | 9 | 5 | 1179 | True (3) |  |
| memory | no | Python ft | 4 | 0.345 | 11.9 | 9 | 5 | 1112 | True (3) |  |
| memory | no | Python std | 1 | 0.932 | 4.2 | 9 | 5 | 1034 | True (3) |  |
| memory | no | Python std | 2 | 0.281 | 12.2 | 9 | 5 | 1134 | True (3) |  |
| memory | no | Python std | 4 | 0.370 | 22.6 | 9 | 5 | 1063 | True (3) |  |
| memory | yes | Julia 1 thr | 1 | 0.170 | 2.9 | 4 | 3 | 2030 | True (3) | 4.1 |
| memory | yes | Julia 10 thr | 1 | 0.053 | 2.1 | 4 | 3 | 2179 | True (3) | 3.7 |
| memory | yes | Julia 10 thr | 4 | 0.036 | 2.9 | 4 | 2 | 2099 | True (3) | 3.0 |
| memory | yes | Python ft | 1 | 0.883 | 12.8 | 9 | 5 | 1073 | True (3) |  |
| memory | yes | Python ft | 2 | 0.281 | 17.8 | 9 | 5 | 1179 | True (3) |  |
| memory | yes | Python ft | 4 | 0.346 | 14.0 | 9 | 5 | 1122 | True (3) |  |
| memory | yes | Python std | 1 | 1.070 | 6.6 | 9 | 5 | 1033 | True (3) |  |
| memory | yes | Python std | 2 | 0.373 | 14.4 | 9 | 5 | 1113 | True (3) |  |
| memory | yes | Python std | 4 | 0.433 | 16.6 | 9 | 5 | 1074 | True (3) |  |
| arrow | yes | Julia 1 thr | 1 | 0.306 | 2.5 | 4 | 3 | 2503 | True (3) | 3.7 |
| arrow | yes | Julia 10 thr | 4 | 0.194 | 109.8 | 6 | 9 | 2370 | True (3) | 3.4 |
| parquet | yes | Python ft | 1 | 1.821 | 17.2 | 10 | 6 | 1464 | True (3) |  |
| parquet | yes | Python ft | 4 | 1.396 | 28.0 | 10 | 6 | 1496 | True (3) |  |
| parquet | yes | Python std | 1 | 1.735 | 16.7 | 10 | 6 | 1499 | True (3) |  |
| parquet | yes | Python std | 4 | 1.460 | 31.6 | 10 | 6 | 1478 | True (3) |  |

## E3: graph shapes (K = 4, 1 M rows)

| Shape | System | W=1 wall (s) | W=4 wall (s) | W=4 speedup | W=4 first result (ms) |
| --- | --- | ---: | ---: | ---: | ---: |
| pipelines | Julia 1 thr | 0.293 | 0.203 | 1.44x | 9.5 |
| pipelines | Julia 10 thr | 0.143 | 0.133 | 1.07x | 4.4 |
| pipelines | Python ft | 0.584 | 0.154 | 3.78x | 2.4 |
| pipelines | Python std | 0.575 | 0.383 | 1.50x | 5.2 |
| fanout | Julia 1 thr | 0.036 | 0.046 | 0.79x | 3.0 |
| fanout | Julia 10 thr | 0.030 | 0.025 | 1.20x | 2.8 |
| fanout | Python ft | 0.385 | 0.122 | 3.16x | 1.8 |
| fanout | Python std | 0.374 | 0.179 | 2.09x | 2.9 |
| uneven | Julia 1 thr | 0.058 | 0.052 | 1.13x | 9.5 |
| uneven | Julia 10 thr | 0.050 | 0.029 | 1.72x | 3.6 |
| uneven | Python ft | 0.295 | 0.121 | 2.43x | 2.5 |
| uneven | Python std | 0.281 | 0.201 | 1.40x | 4.5 |
| narrow | Julia 1 thr | 0.022 | 0.022 | 1.02x | 2.5 |
| narrow | Julia 10 thr | 0.021 | 0.020 | 1.05x | 2.3 |
| narrow | Python ft | 0.059 | 0.061 | 0.98x | 1.5 |
| narrow | Python std | 0.063 | 0.062 | 1.02x | 1.7 |

## E4: one module, 20 M x 8 Float64 in memory (2 workers)

Wall time (s) by data width: Python's forced step width, Julia's thread count; speedup is width 1 over the best.

| Module | System | w=1 | w=2 | w=4 | w=8 | w=10 | best speedup | exact |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| var | Python std | 0.114 | 0.141 | 0.119 | 0.116 | 0.122 | 1.00x | True |
| var | Python ft | 0.125 | 0.080 | 0.064 | 0.054 | 0.057 | 2.31x | True |
| var | Julia | 0.048 | 0.062 | 0.019 | 0.015 | 0.015 | 3.29x | True |
| minmax | Python std | 0.106 | 0.129 | 0.132 | 0.130 | 0.130 | 1.00x | True |
| minmax | Python ft | 0.067 | 0.069 | 0.060 | 0.065 | 0.058 | 1.14x | True |
| minmax | Julia | 0.043 | 0.035 | 0.033 | 0.024 | 0.023 | 1.88x | True |
| hist1d | Python std | 0.198 | 0.204 | 0.201 | 0.199 | 0.194 | 1.02x | True |
| hist1d | Python ft | 0.166 | 0.119 | 0.096 | 0.088 | 0.089 | 1.89x | True |
| hist1d | Julia | 0.069 | 0.062 | 0.042 | 0.031 | 0.027 | 2.56x | True |
| hist2d | Python std | 1.898 | 1.096 | 0.665 | 0.483 | 0.464 | 4.09x | True |
| hist2d | Python ft | 1.933 | 1.105 | 0.686 | 0.373 | 0.375 | 5.18x | True |
| hist2d | Julia | 0.102 | 0.077 | 0.059 | 0.081 | 0.040 | 2.54x | True |

