"""
The taxi dashboard of the ProgressiVis paper (Fig. "wf-dashboard"), on
VisTrailsJL's progressive engine: one run, printed as `RESULT {json}`.

    julia --project=julia --threads=N dashboard.jl '{"source": "memory", "workers": 4, "var": false}'

Graph (as ProgressiVis' design/benchmarks/master_vs_branch/bench_one.py):
source → Min, Max → Bounds2D (pickup), Bounds2D (dropoff) → Histogram2D
(pickup), Histogram2D (dropoff), 512² bins; optionally Var. `Bounds2D`
follows ProgressiVis' Histogram2D: bounds are min/max widened by 5% of
their range, and change (restarting the histogram) only when min/max leave
them or shrink by more than that margin.

Sources: "memory" (the six columns of January, stratified order, already in
a ProgressiveTable, as ProgressiVis' Constant), "arrow" (ArrowLoader over
data/strat.arrow, memory-mapped) or "parquet" (ParquetLoader over
data/strat.parquet, Python's file source). A warm-up run on the first 200 000 rows,
from the same kind of source, compiles the code first unless "warmup": false.

Checks: the pickup histogram equals a batch count of all rows with the final
bounds; Var equals the batch variance (rtol 1e-6).
"""

include(joinpath(@__DIR__, "common.jl"))
using Arrow
using Tables
using Statistics

const DATA = joinpath(@__DIR__, "data", "strat.arrow")
const WARMUP_ARROW = joinpath(@__DIR__, "data", "strat_warmup.arrow")   # first 200 000 rows
const PARQUET = joinpath(@__DIR__, "data", "strat.parquet")
const WARMUP_PARQUET = joinpath(@__DIR__, "data", "strat_warmup.parquet")   # prepare_data.py
const COLUMNS = [:pickup_long, :pickup_lat, :dropoff_long, :dropoff_lat, :distance, :passengers]
const BINS = 512

# ---------------------------------------------------------------- the run

struct Timing <: ExecutionObserver
    t0::Ref{Float64}
    pickup::Int
    source::Int
    updates::Vector{Float64}       # end of every pickup-histogram step that counted rows
    source_steps::Vector{Float64}
end
VT.on_module_step(o::Timing, run, mod, result, seconds) =
    result.items > 0 && (mod.id == o.pickup ? push!(o.updates, time() - o.t0[]) :
                         mod.id == o.source ? push!(o.source_steps, time() - o.t0[]) : nothing)


function build(source::String; var::Bool, rows=nothing)
    p = Pipeline()
    src = if source == "memory"
        node!(p, BENCH, "ConstantTable"; key=rows === nothing ? "all" : "warmup")
    elseif source == "parquet"
        node!(p, P, "ParquetLoader"; path=rows === nothing ? PARQUET : WARMUP_PARQUET)
    else
        node!(p, P, "ArrowLoader"; path=rows === nothing ? DATA : WARMUP_ARROW)
    end
    mn, mx = node!(p, P, "Min"), node!(p, P, "Max")
    add_connection!(p, src, "result", mn, "table")
    add_connection!(p, src, "result", mx, "table")
    hists = Dict{String, Any}()
    for end_ in ("pickup", "dropoff")
        b = node!(p, BENCH, "Bounds2D"; x_column="$(end_)_long", y_column="$(end_)_lat")
        add_connection!(p, mn, "result", b, "min")
        add_connection!(p, mx, "result", b, "max")
        h = node!(p, P, "Histogram2D"; x_column="$(end_)_long", y_column="$(end_)_lat", xbins=BINS, ybins=BINS)
        add_connection!(p, src, "result", h, "table")
        foreach(q -> add_connection!(p, b, q, h, q), ("xmin", "xmax", "ymin", "ymax"))
        hists[end_] = (h, b)
    end
    v = nothing
    if var
        v = node!(p, P, "Var")
        add_connection!(p, src, "result", v, "table")
    end
    return p, src, hists, v
end

function run_dashboard(cfg; rows=nothing)
    source = String(get(cfg, :source, "memory"))
    workers = Int(get(cfg, :workers, 1))
    var = Bool(get(cfg, :var, true))
    t_prep = time()
    p, src, hists, v = build(source; var=var, rows=rows)
    pickup, pickup_bounds = hists["pickup"]
    timing = Timing(Ref(0.0), pickup.id, src.id, Float64[], Float64[])
    engine = ProgressiveEngine(workers=workers)
    t_prep = time() - t_prep
    GC.gc()
    timing.t0[] = time()
    cpu0 = time_ns()
    run = run!(engine, p; observers=[timing], enable_logging=false)
    wall = time() - timing.t0[]

    table = run.outputs[src.id]["result"]
    counts = current_value(run.outputs[pickup.id]["result"])
    b = pickup_bounds_state(run, pickup_bounds)
    x, y = collect(column(table, :pickup_long)), collect(column(table, :pickup_lat))
    expected = zeros(Int, BINS, BINS)
    for i in eachindex(x, y)
        bx = VT.histogram_bin(x[i], b[1], b[2], BINS)
        by = VT.histogram_bin(y[i], b[3], b[4], BINS)
        (bx > 0 && by > 0) && (expected[bx, by] += 1)
    end
    ok_heat = counts == expected
    ok_var = v === nothing || begin
        r = snapshot(run.outputs[v.id]["result"])
        all(isapprox(r[c], var_of(collect(column(table, c))); rtol=1e-6) for c in (:distance, :pickup_long))
    end
    return Dict("system" => "julia", "source" => source, "workers" => workers, "var" => var,
                "threads" => Threads.nthreads(), "rows" => length(table), "wall" => wall, "prep" => t_prep,
                "first_heatmap" => isempty(timing.updates) ? nothing : first(timing.updates),
                "last_heatmap" => isempty(timing.updates) ? nothing : last(timing.updates),
                "heatmap_updates" => length(timing.updates),
                "source_done" => isempty(timing.source_steps) ? 0.0 : last(timing.source_steps),
                "resets" => sum(run.engine_state.modules[bb.id].state.changes for (_, bb) in values(hists)),
                "ok" => ok_heat && ok_var, "ok_heat" => ok_heat, "ok_var" => ok_var,
                "maxrss_mb" => Sys.maxrss() / 2^20)
end

pickup_bounds_state(run, b) = run.engine_state.modules[b.id].state.bounds
var_of(v) = (x = Float64.(v); m = mean(x); sum(abs2, x .- m) / (length(x) - 1))

# The in-memory tables (only for source "memory": a 2 GB heap would also
# slow the garbage collector in file runs) and the warm-up Arrow file
function load_memory_tables!(warmup_rows::Int; memory::Bool=true)
    file = Arrow.Table(DATA)
    isfile(WARMUP_ARROW) || Arrow.write(WARMUP_ARROW, map(c -> Tables.getcolumn(file, c)[1:warmup_rows],
                                                         NamedTuple{Tuple(COLUMNS)}(Tuple(COLUMNS))))
    memory || return
    cols = NamedTuple{Tuple(COLUMNS)}(Tuple(copy(Tables.getcolumn(file, c)) for c in COLUMNS))
    CONSTANT_TABLES["all"] = ProgressiveTable(cols)
    CONSTANT_TABLES["warmup"] = ProgressiveTable(map(c -> c[1:warmup_rows], cols))
end

function main()
    cfg = JSON3.read(isempty(ARGS) ? "{}" : ARGS[1])
    register_bench_modules!()
    warmup = Bool(get(cfg, :warmup, true))
    t = time()
    load_memory_tables!(200_000; memory=get(cfg, :source, "memory") == "memory")
    load_s = time() - t
    cold = nothing
    if warmup
        t = time()
        run_dashboard(cfg; rows=200_000)   # same source, so its code is compiled too
        cold = time() - t
    end
    result = run_dashboard(cfg)
    result["warmup_s"] = cold
    result["table_build_s"] = load_s
    result["config"] = cfg
    println("RESULT ", JSON3.write(result))
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
