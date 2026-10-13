"""
Modules and helpers shared by the comparison benchmarks (dashboard.jl,
shapes.jl, modules.jl): an in-memory source and ProgressiVis' histogram
bounds rule.
"""

using VisTrailsJL
using JSON3

const VT = VisTrailsJL
const P = "org.vistrails.progressive"
const BENCH = "org.vistrails.bench"
const DELTA = 0.05   # ProgressiVis' xdelta = ydelta = -5 (percent of the range)

# ---------------------------------------------------------------- modules

# ConstantTable: outputs a table built before the run (ProgressiVis' Constant)
const CONSTANT_TABLES = Dict{String, ProgressiveTable}()

struct ConstantTableModule end
VT.execution_style(::Type{ConstantTableModule}) = Progressive()
VT.init_state(::Type{ConstantTableModule}, ctx::StepContext) =
    (VT.set_output!(ctx, "result", CONSTANT_TABLES[String(VT.param(ctx, "key"))]); nothing)
VT.step!(::Nothing, ctx::StepContext, budget::Int) = StepResult(:done, 0)

# Bounds2D: histogram bounds from Min and Max, with ProgressiVis' margin rule
struct Bounds2DModule end
VT.execution_style(::Type{Bounds2DModule}) = Progressive()

mutable struct Bounds2DState
    min_sub::DictSubscription
    max_sub::DictSubscription
    min::ProgressiveDict
    max::ProgressiveDict
    x::Symbol
    y::Symbol
    bounds::Union{Nothing, NTuple{4, Float64}}
    changes::Int                    # after the first: restarts of the histogram
    outputs::NTuple{4, ProgressiveValue{Float64}}
end

function VT.init_state(::Type{Bounds2DModule}, ctx::StepContext)
    outs = Tuple(VT.set_output!(ctx, p, ProgressiveValue{Float64}()) for p in ("xmin", "xmax", "ymin", "ymax"))
    return Bounds2DState(input_subscription(ctx, "min"), input_subscription(ctx, "max"),
                         VT.input_container(ctx, "min"), VT.input_container(ctx, "max"),
                         Symbol(VT.param(ctx, "x_column")), Symbol(VT.param(ctx, "y_column")),
                         nothing, 0, outs)
end

function VT.step!(s::Bounds2DState, ctx::StepContext, budget::Int)
    has_changes(s.min_sub) && take_changes!(s.min_sub)
    has_changes(s.max_sub) && take_changes!(s.max_sub)
    lo, hi = snapshot(s.min), snapshot(s.max)
    all(haskey(d, c) for d in (lo, hi) for c in (s.x, s.y)) || return StepResult(:blocked, 0)
    xmin, xmax = minmax(Float64(lo[s.x]), Float64(hi[s.x]))
    ymin, ymax = minmax(Float64(lo[s.y]), Float64(hi[s.y]))
    dx, dy = (xmax - xmin) * DELTA, (ymax - ymin) * DELTA
    dx, dy = isnan(dx) ? 0.0 : dx, isnan(dy) ? 0.0 : dy
    widened = (xmin - dx, xmax + dx, ymin - dy, ymax + dy)
    if s.bounds === nothing
        s.bounds = widened
    else
        d = s.bounds
        if xmin < d[1] || xmax > d[2] || ymin < d[3] || ymax > d[4] ||
           xmin > d[1] + dx || xmax < d[2] - dx || ymin > d[3] + dy || ymax < d[4] - dy
            s.bounds = widened
            s.changes += 1
        else
            return StepResult(:blocked, 1)
        end
    end
    foreach((out, v) -> set!(out, v), s.outputs, s.bounds)
    return StepResult(:blocked, 1)
end

function register_bench_modules!()
    VT.register_module!(VT.ModuleDescriptor(BENCH, "ConstantTable", ConstantTableModule,
        VT.InputPort[], [VT.OutputPort("result", ProgressiveTable)], Tuple{String, Type}[("key", String)]))
    VT.register_module!(VT.ModuleDescriptor(BENCH, "Bounds2D", Bounds2DModule,
        [VT.InputPort("min", ProgressiveDict), VT.InputPort("max", ProgressiveDict)],
        [VT.OutputPort(p, ProgressiveValue) for p in ("xmin", "xmax", "ymin", "ymax")],
        Tuple{String, Type}[("x_column", String), ("y_column", String)]))
end


function node!(p, package, name, sources...; port="table", params...)
    m = add_module!(p, package, name)
    foreach(((k, v),) -> set_parameter!(m, String(k), v), params)
    foreach(s -> add_connection!(p, s, "result", m, port), sources)
    return m
end

# Min, Max → Bounds2D → Histogram2D over columns x, y of `src`
function bounded_histogram2d!(p, src, mn, mx, x, y, bins)
    b = node!(p, BENCH, "Bounds2D"; x_column=x, y_column=y)
    add_connection!(p, mn, "result", b, "min")
    add_connection!(p, mx, "result", b, "max")
    h = node!(p, P, "Histogram2D", src; x_column=x, y_column=y, xbins=bins, ybins=bins)
    foreach(q -> add_connection!(p, b, q, h, q), ("xmin", "xmax", "ymin", "ymax"))
    return h, b
end

# Min, Max → Bounds2D (on x only) → Histogram1D over column x
function bounded_histogram1d!(p, src, mn, mx, x, bins)
    b = node!(p, BENCH, "Bounds2D"; x_column=x, y_column=x)
    add_connection!(p, mn, "result", b, "min")
    add_connection!(p, mx, "result", b, "max")
    h = node!(p, P, "Histogram1D", src; column=x, bins=bins)
    add_connection!(p, b, "xmin", h, "min")
    add_connection!(p, b, "xmax", h, "max")
    return h, b
end

result_json(r) = println("RESULT ", JSON3.write(r))
