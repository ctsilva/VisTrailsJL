"""
Graph shapes (the ProgressiVis paper's E3, scripts/bench_parallel.py) on
VisTrailsJL's progressive engine. One process: a warm-up, then for each
shape `repeats` runs alternating 1 and K workers; one `RESULT {json}` line
per run.

    julia --project=julia --threads=N shapes.jl [K=4] [ROWS=1000000] [REPEATS=3]

Shapes, from RandomTable sources of ROWS rows × 10 columns (`_1` … `_10`):
- pipelines: K independent pipelines, each Min, Max → Histogram2D(_1, _2),
  256² bins (bounds by ProgressiVis' rule), and Var;
- fanout: one source (max(10, 2K) columns) feeding Min, Max, Var and K
  histograms on column pairs (_1, _2), (_3, _4), …;
- uneven: pipelines whose sources after the first have ROWS ÷ 4 rows;
- narrow: source → Var.

Reports wall time, the first and last first-results of the Histogram2D and
Var modules, and the number of steps.
"""

include(joinpath(@__DIR__, "common.jl"))

columns(n) = ["_$i" for i in 1:n]

function pipeline!(p, rows, seed)
    src = node!(p, P, "RandomTable"; columns=columns(10), rows=rows, seed=seed)
    mn, mx = node!(p, P, "Min", src), node!(p, P, "Max", src)
    h, _ = bounded_histogram2d!(p, src, mn, mx, "_1", "_2", 256)
    return [h, node!(p, P, "Var", src)]
end

function build(shape, k, rows)
    p = Pipeline()
    outputs = if shape in ("pipelines", "uneven")
        reduce(vcat, [pipeline!(p, shape == "pipelines" || i == 1 ? rows : max(1, rows ÷ 4), i) for i in 1:k])
    elseif shape == "narrow"
        src = node!(p, P, "RandomTable"; columns=columns(10), rows=rows, seed=1)
        [node!(p, P, "Var", src)]
    elseif shape == "fanout"
        src = node!(p, P, "RandomTable"; columns=columns(max(10, 2k)), rows=rows, seed=1)
        mn, mx = node!(p, P, "Min", src), node!(p, P, "Max", src)
        [node!(p, P, "Var", src); [first(bounded_histogram2d!(p, src, mn, mx, "_$(2i - 1)", "_$(2i)", 256)) for i in 1:k]]
    else
        error("unknown shape $shape")
    end
    return p, Set(m.id for m in outputs)
end

struct FirstResults <: ExecutionObserver
    t0::Float64
    outputs::Set{Int}
    first::Dict{Int, Float64}
    steps::Ref{Int}
end
function VT.on_module_step(o::FirstResults, run, mod, result, seconds)
    o.steps[] += 1
    mod.id in o.outputs && result.items > 0 && !haskey(o.first, mod.id) && (o.first[mod.id] = time() - o.t0)
end

function in_engine(shape, k, rows, workers)
    p, outputs = build(shape, k, rows)
    GC.gc()
    obs = FirstResults(time(), outputs, Dict{Int, Float64}(), Ref(0))
    t0 = time()
    run!(ProgressiveEngine(workers=workers), p; observers=[obs], enable_logging=false)
    wall = time() - t0
    firsts = collect(values(obs.first))
    return Dict("system" => "julia", "shape" => shape, "workers" => workers, "k" => k, "rows" => rows,
                "threads" => Threads.nthreads(), "wall_s" => wall,
                "first_result_s" => isempty(firsts) ? nothing : minimum(firsts),
                "all_first_results_s" => length(firsts) == length(outputs) ? maximum(firsts) : nothing,
                "step_count" => obs.steps[])
end

function main()
    k = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 4
    rows = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 1_000_000
    repeats = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 3
    register_bench_modules!()
    for shape in ("pipelines", "fanout", "narrow", "uneven")   # warm-up: compile
        in_engine(shape, k, max(1, rows ÷ 10), 1); in_engine(shape, k, max(1, rows ÷ 10), k)
    end
    for shape in ("pipelines", "fanout", "narrow", "uneven"), repeat in 0:repeats-1
        for workers in (iseven(repeat) ? (1, k) : (k, 1))
            result_json(merge(in_engine(shape, k, rows, workers), Dict("repeat" => repeat)))
        end
    end
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
