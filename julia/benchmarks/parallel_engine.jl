"""
Benchmark: OneShotEngine vs ParallelEngine

    julia --project=. --threads=N benchmarks/parallel_engine.jl

Pipelines of CPU-bound modules (each spins for a fixed time without
yielding):
- wide: 16 independent modules feeding one sum
- layered: 4 layers of 8 modules, each depending on two modules of the previous layer
- chain: 16 modules in sequence (no parallelism available)
plus 2000 trivial modules, to measure the scheduling overhead per module.
"""

include(joinpath(@__DIR__, "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Printf

const VT = VisTrailsJL
const PKG = "org.vistrails.benchmark"

struct BWork end

function VT.compute(mod::VT.ModuleInstance, ::Type{BWork})
    stop = time_ns() + round(UInt64, mod.parameters["ms"] * 1e6)
    x = 0.0
    while time_ns() < stop
        x += sin(x)
    end
    mod.outputs["value"] = sum(get_input_list(mod, "in"); init=0) + 1
    return mod.outputs
end

VT.register_module!(VT.ModuleDescriptor(PKG, "Work", BWork,
    [VT.InputPort("in", Int; optional=true)], [VT.OutputPort("value", Int)], Tuple{String, Type}[]))

function work!(p, ms, sources...)
    m = add_module!(p, PKG, "Work")
    set_parameter!(m, "ms", ms)
    foreach(s -> add_connection!(p, s, "value", m, "in"), sources)
    return m
end

function wide(ms)
    p = Pipeline()
    work!(p, 0, [work!(p, ms) for _ in 1:16]...)
    return p
end

function layered(ms)
    p = Pipeline()
    layer = [work!(p, ms) for _ in 1:8]
    for _ in 2:4
        layer = [work!(p, ms, layer[i], layer[mod1(i + 1, 8)]) for i in 1:8]
    end
    return p
end

function chain(ms)
    p = Pipeline()
    m = work!(p, ms)
    for _ in 2:16
        m = work!(p, ms, m)
    end
    return p
end

function trivial(n)
    p = Pipeline()
    mods = [work!(p, 0) for _ in 1:n÷2]
    for i in 1:n÷2
        work!(p, 0, mods[i])
    end
    return p
end

best_time(engine, p; reps=3) = minimum(@elapsed(run!(engine, p; enable_logging=false)) for _ in 1:reps)

println("Threads: $(Threads.nthreads())")
for (name, p) in [("wide", wide(50)), ("layered", layered(50)), ("chain", chain(50))]
    run!(ParallelEngine(), p; enable_logging=false)  # warm up
    serial = best_time(OneShotEngine(), p)
    parallel = best_time(ParallelEngine(), p)
    @printf("%-8s %2d modules × 50 ms: one-shot %6.3f s, parallel %6.3f s, speedup %4.2f×\n",
            name, length(p.modules), serial, parallel, serial / parallel)
end

p = trivial(2000)
run!(OneShotEngine(), p; enable_logging=false); run!(ParallelEngine(), p; enable_logging=false)
serial = best_time(OneShotEngine(), p)
parallel = best_time(ParallelEngine(), p)
@printf("trivial  2000 modules:        one-shot %6.1f µs/module, parallel %6.1f µs/module\n",
        1e6 * serial / 2000, 1e6 * parallel / 2000)
