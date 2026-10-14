"""
The analytics modules (tier 4) on VisTrailsJL's progressive engine, the
counterpart of analytics.py: the January taxi trips (data/strat.arrow, 14.8 M
rows, in memory as ProgressiVis' Constant source) and generated blobs. Each
workload runs first on 200 000 rows (warm-up: compilation), then measured.
One `RESULT {json}` line per workload.

    julia --project=julia --threads=N analytics.jl [ROWS=all] [WORKLOADS=all]

Workloads: kmeans (MBKMeans, k = 10, on the pickups, seeds 0-4: time to
convergence and per iteration, and to all rows labelled), ppca (PPCA of the six columns, 2 components;
with PPCATransformer projecting every row), scaler (MinMaxScaler with Min
and Max), blobs (Blobs, as many rows, 2 columns, 3 centers); Julia only (no
pynene in ProgressiVis' environment): kde (KernelDensity of the pickups),
tsne (TSNE of 10 000 blobs in 50-D, 1000 iterations).
"""

include(joinpath(@__DIR__, "common.jl"))
using Arrow
using Tables
using Statistics

const COLUMNS = [:pickup_long, :pickup_lat, :dropoff_long, :dropoff_lat, :distance, :passengers]
const WARMUP_ROWS = 200_000

# Records when a module's `converged` output first became true
mutable struct ConvergenceClock <: ExecutionObserver
    id::Int
    start::Float64
    converged_at::Float64
end
function VT.on_module_step(o::ConvergenceClock, run, mod, result, seconds)
    mod.id == o.id && o.converged_at == 0 && current_value(run.outputs[o.id]["converged"]) &&
        (o.converged_at = time() - o.start)
end

function timed(p; observers=ExecutionObserver[])
    t0 = time()
    foreach(o -> o isa ConvergenceClock && (o.start = t0), observers)
    run = run!(ProgressiveEngine(), p; enable_logging=false, observers=observers)
    return time() - t0, run
end

source!(p, key) = node!(p, BENCH, "ConstantTable"; key=key)

function kmeans(key, seed=0)
    p = Pipeline()
    km = node!(p, P, "MBKMeans", source!(p, key); n_clusters=10, batch_size=1024, seed=seed,
               columns=["pickup_long", "pickup_lat"])
    clock = ConvergenceClock(km.id, 0.0, 0.0)
    t, run = timed(p; observers=[clock])
    s = run.engine_state.modules[km.id].state
    C = Tables.columntable(run.outputs[km.id]["result"])
    return (workload="MBKMeans k=10", seed=seed, seconds_converged=clock.converged_at, seconds=t,
            iterations=s.iterations, ms_per_iteration=1000 * clock.converged_at / s.iterations,
            labelled=length(run.outputs[km.id]["labels"]))
end

function ppca(key, transform)
    p = Pipeline()
    src = source!(p, key)
    pca = node!(p, P, "PPCA", src; n_components=2)
    if transform
        tr = node!(p, P, "PPCATransformer", src; n_components=2)
        add_connection!(p, pca, "transformer", tr, "transformer")
    end
    t, run = timed(p)
    return transform ? (workload="PPCA + PPCATransformer", seconds=t, projected=length(run.outputs[tr.id]["result"]),
                        resets=run.engine_state.modules[tr.id].state.resets) :
                       (workload="PPCA (fit)", seconds=t)
end

function scaler(key)
    p = Pipeline()
    src = source!(p, key)
    mn, mx = node!(p, P, "Min", src), node!(p, P, "Max", src)
    sc = node!(p, P, "MinMaxScaler", src; reset_threshold=10_000)
    add_connection!(p, mn, "result", sc, "min"); add_connection!(p, mx, "result", sc, "max")
    t, run = timed(p)
    return (workload="MinMaxScaler (+ Min, Max)", seconds=t, scaled=length(run.outputs[sc.id]["result"]),
            info=snapshot(run.outputs[sc.id]["info"]))
end

function blobs(rows)
    p = Pipeline()
    b = node!(p, P, "Blobs"; rows=rows, centers=[[0.0, 0.0], [6.0, 6.0], [-6.0, 6.0]], seed=1)
    t, run = timed(p)
    return (workload="Blobs", rows=length(run.outputs[b.id]["result"]), seconds=t)
end

function kde(key)
    p = Pipeline()
    k = node!(p, P, "KernelDensity", source!(p, key); x_column="pickup_long", y_column="pickup_lat",
              samples=[[x, y] for x in range(-74.05, -73.75, 32) for y in range(40.6, 40.9, 32)])
    t, run = timed(p)
    return (workload="KernelDensity (pickups, 32² samples)", seconds=t)
end

function tsne(rows)
    p = Pipeline()
    b = node!(p, P, "Blobs"; rows=rows, centers=10, columns=50, seed=2)
    ts = node!(p, P, "TSNE", b; max_iter=1000)
    t, run = timed(p)
    s = run.engine_state.modules[ts.id].state
    return (workload="TSNE (50-D blobs)", rows=rows, seconds=t, iterations=s.iteration)
end

function main()
    rows = length(ARGS) >= 1 && ARGS[1] != "all" ? parse(Int, ARGS[1]) : nothing
    only = length(ARGS) >= 2 ? split(ARGS[2], ",") : ["kmeans", "ppca", "scaler", "blobs", "kde", "tsne"]
    register_bench_modules!()
    file = Arrow.Table(joinpath(@__DIR__, "data", "strat.arrow"))
    cols = map(c -> Float64.(collect(Tables.getcolumn(file, c))), NamedTuple{Tuple(COLUMNS)}(COLUMNS))
    n = rows === nothing ? length(first(cols)) : rows
    CONSTANT_TABLES["all"] = ProgressiveTable(map(c -> c[1:n], cols))
    CONSTANT_TABLES["warmup"] = ProgressiveTable(map(c -> c[1:WARMUP_ROWS], cols))
    CONSTANT_TABLES["pickups"] = ProgressiveTable((pickup_long=cols.pickup_long[1:n], pickup_lat=cols.pickup_lat[1:n]))
    CONSTANT_TABLES["pickups_warmup"] = ProgressiveTable((pickup_long=cols.pickup_long[1:WARMUP_ROWS],
                                                          pickup_lat=cols.pickup_lat[1:WARMUP_ROWS]))
    # Iterations to convergence depend on the seed (outliers): five seeds
    for (name, measure) in (("kmeans", () -> reduce(vcat, [[kmeans("pickups_warmup", seed), kmeans("pickups", seed)] for seed in 0:4])),
                            ("ppca", () -> [ppca("warmup", false), ppca("all", false), ppca("warmup", true), ppca("all", true)]),
                            ("scaler", () -> [scaler("warmup"), scaler("all")]),
                            ("blobs", () -> [blobs(WARMUP_ROWS), blobs(n)]),
                            ("kde", () -> [kde("pickups_warmup"), kde("pickups")]),
                            ("tsne", () -> [tsne(1_000), tsne(10_000)]))
        name in only || continue
        results = measure()
        for (i, r) in enumerate(results)
            warm = isodd(i) && length(results) > 1   # every other result is a warm-up
            result_json(merge(r, (rows=get(r, :rows, warm ? WARMUP_ROWS : n), warmup=warm, threads=Threads.nthreads())))
        end
    end
end

main()
