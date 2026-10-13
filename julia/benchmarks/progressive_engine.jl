"""
Benchmark: progressive vs one-shot execution

    julia --project=. benchmarks/progressive_engine.jl [rows]

RandomTable (x, y) → Min, Mean, Var, Histogram1D, Histogram2D, and
Filter(y < 0.3) → Count. Reports when the first partial results appear,
the total time, and the one-shot time for the same pipeline.
"""

include(joinpath(@__DIR__, "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Printf

const P = "org.vistrails.progressive"
rows = isempty(ARGS) ? 20_000_000 : parse(Int, ARGS[1])

function node!(p, name, sources...; params...)
    m = add_module!(p, P, name)
    foreach(((k, v),) -> set_parameter!(m, String(k), v), params)
    foreach(s -> add_connection!(p, s, "result", m, "table"), sources)
    return m
end

function pipeline_(rows)
    p = Pipeline()
    src = node!(p, "RandomTable"; rows=rows, seed=1)
    for name in ("Min", "Mean", "Var")
        node!(p, name, src)
    end
    node!(p, "Histogram1D", src; column="x", bins=256, min=0.0, max=1.0)
    node!(p, "Histogram2D", src; x_column="x", y_column="y", xbins=256, ybins=256,
          xmin=0.0, xmax=1.0, ymin=0.0, ymax=1.0)
    count = node!(p, "Count", node!(p, "Filter", src; column="y", op="<", value=0.3))
    return p, count
end

struct FirstResult <: ExecutionObserver
    id::Int
    t0::Float64
    first::Ref{Float64}
end
VisTrailsJL.on_module_step(o::FirstResult, run, mod, result, seconds) =
    (mod.id == o.id && isnan(o.first[])) && (o.first[] = time() - o.t0)

# Warm up (compilation) on a small instance
let (p, _) = pipeline_(200_000)
    run!(ProgressiveEngine(), p; enable_logging=false)
    run!(OneShotEngine(), p; enable_logging=false)
end

p, count = pipeline_(rows)
for quantum in (0.05, 0.1)
    first = Ref(NaN)
    t0 = time()
    run = run!(ProgressiveEngine(quantum=quantum), p; observers=[FirstResult(count.id, t0, first)],
               enable_logging=false)
    total = time() - t0
    @printf("progressive (quantum %.2f s): first filtered count after %.3f s, done in %.2f s, %d sweeps\n",
            quantum, first[], total, run.engine_state.sweeps)
end
t = @elapsed run!(OneShotEngine(), p; enable_logging=false)
@printf("one-shot: %.2f s (%d rows)\n", t, rows)
