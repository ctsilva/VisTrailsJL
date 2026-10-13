"""
Data parallelism within one module (the ProgressiVis paper's E4,
scripts/bench_data_parallel.py) on VisTrailsJL's progressive engine: a
table of ROWS × COLS standard-normal Float64 values, already in memory,
served to one analytics module. One process (the number of threads is
fixed at start: run once per thread count); one `RESULT {json}` line per
run.

    julia --project=julia --threads=N modules.jl [ROWS=20000000] [COLS=8] [REPEATS=3] [WORKERS=2]

Scenarios (as ProgressiVis'): var (Var, all columns); minmax (Min and Max,
all columns); hist1d (Min, Max → Histogram1D(_0), 512 bins); hist2d (Min,
Max → Histogram2D(_0, _1), 512² bins); histogram bounds by ProgressiVis'
rule. Each result is checked against a batch computation.
"""

include(joinpath(@__DIR__, "common.jl"))
using Random
using Statistics

const BINS = 512

function build(scenario, key)
    p = Pipeline()
    src = node!(p, BENCH, "ConstantTable"; key=key)
    if scenario == "var"
        return p, src, (; var=node!(p, P, "Var", src))
    end
    mn, mx = node!(p, P, "Min", src), node!(p, P, "Max", src)
    scenario == "minmax" && return p, src, (; mn, mx)
    h, b = scenario == "hist1d" ? bounded_histogram1d!(p, src, mn, mx, "_0", BINS) :
                                  bounded_histogram2d!(p, src, mn, mx, "_0", "_1", BINS)
    return p, src, (; h, b)
end

function check(scenario, run, m, data)
    out(x) = run.outputs[x.id]["result"]
    if scenario == "var"
        r = snapshot(out(m.var))
        return all(isapprox(r[c], var(v); rtol=1e-9) for (c, v) in pairs(data))
    elseif scenario == "minmax"
        lo, hi = snapshot(out(m.mn)), snapshot(out(m.mx))
        return all(lo[c] == minimum(v) && hi[c] == maximum(v) for (c, v) in pairs(data))
    end
    xmin, xmax, ymin, ymax = run.engine_state.modules[m.b.id].state.bounds
    counts = current_value(out(m.h))
    if scenario == "hist1d"
        expected = zeros(Int, BINS)
        VT.count_bins!(expected, data._0, xmin, xmax)
    else
        expected = zeros(Int, BINS, BINS)
        VT.count_bins!(expected, data._0, data._1, xmin, xmax, ymin, ymax)
    end
    return counts == expected
end

function run_once(scenario, key, workers, data)
    p, src, m = build(scenario, key)
    GC.gc()
    t0 = time()
    run = run!(ProgressiveEngine(workers=workers), p; enable_logging=false)
    wall = time() - t0
    return wall, data === nothing || check(scenario, run, m, data)
end

function main()
    rows = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 20_000_000
    cols = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 8
    repeats = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 3
    workers = length(ARGS) >= 4 ? parse(Int, ARGS[4]) : 2
    register_bench_modules!()
    rng = Xoshiro(42)
    data = NamedTuple{Tuple(Symbol("_$i") for i in 0:cols-1)}(Tuple(randn(rng, rows) for _ in 1:cols))
    CONSTANT_TABLES["all"] = ProgressiveTable(data)
    CONSTANT_TABLES["warmup"] = ProgressiveTable(map(c -> c[1:min(rows, 100_000)], data))
    scenarios = ("var", "minmax", "hist1d", "hist2d")
    foreach(s -> run_once(s, "warmup", workers, nothing), scenarios)   # compile
    for scenario in scenarios, repeat in 0:repeats-1
        wall, ok = run_once(scenario, "all", workers, data)
        result_json(Dict("system" => "julia", "scenario" => scenario, "threads" => Threads.nthreads(),
                         "workers" => workers, "rows" => rows, "cols" => cols, "repeat" => repeat,
                         "wall" => wall, "ok" => ok))
    end
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
