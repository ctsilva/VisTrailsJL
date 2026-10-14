"""
MinMaxScaler, after ProgressiVis' `MinMaxScaler`

Scales `columns` (default: the numeric columns) of the rows of `table` to
[0, 1] with bounds from its inputs `min` and `max` (the dicts of `Min` and
`Max` modules on the same table); other columns pass through. The bounds
are fixed when the first rows are scaled, and kept while the inputs keep
growing them, since the rows already scaled would have to change:

- values outside the bounds by at most `delta` are clipped to 0 or 1
  (`delta` < 0: that percentage of the bounds' extent; default -5);
- rows with a value further out are dropped, up to `ignore_max` rows in all
  (default 0);
- beyond that, or while the output has at most `reset_threshold` rows
  (default 1000), a change of `min` or `max` resets the scaler: it adopts
  the current bounds and scales every row again.

Input updates and deletions also reset it. The output `info` counts
`clipped` values, `ignored` rows and `resets`. (ProgressiVis applies the
clipping only in the step where the bounds changed, and its tests of the
module are marked "not ready yet".)
"""

struct MinMaxScalerModule end
execution_style(::Type{MinMaxScalerModule}) = Progressive()
default_step_size(::Type{MinMaxScalerModule}) = 100_000

mutable struct MinMaxScalerState
    table::ProgressiveTable
    sub::TableSubscription
    min::ProgressiveDict
    max::ProgressiveDict
    usecols::Vector{Symbol}
    out::ProgressiveTable
    info::ProgressiveDict{Symbol, Any}
    lo::Vector{Float64}                  # bounds of usecols (empty: not fixed yet)
    hi::Vector{Float64}
    clipped::Int
    ignored::Int
    resets::Int
end

function init_state(::Type{MinMaxScalerModule}, ctx::StepContext)
    table = input_container(ctx, "table")
    table isa ProgressiveTable || error("MinMaxScaler: input 'table' must be a table")
    mn, mx = input_container(ctx, "min"), input_container(ctx, "max")
    mn isa ProgressiveDict && mx isa ProgressiveDict || error("MinMaxScaler: inputs 'min' and 'max' must be dicts (Min, Max)")
    usecols = numeric_columns(ctx, table)
    schema = [n => (n in usecols ? Float64 : eltype(column(table, n))) for n in column_names(table)]
    out = set_output!(ctx, "result", ProgressiveTable(schema...))
    info = set_output!(ctx, "info", ProgressiveDict{Symbol, Any}(:clipped => 0, :ignored => 0, :resets => 0))
    return MinMaxScalerState(table, input_subscription(ctx, "table"), mn, mx, usecols, out, info,
                             Float64[], Float64[], 0, 0, 0)
end

# Bounds from the inputs, once they cover every scaled column
function input_bounds(s::MinMaxScalerState)
    all(c -> haskey(s.min, c) && haskey(s.max, c), s.usecols) || return nothing
    return Float64[s.min[c] for c in s.usecols], Float64[s.max[c] for c in s.usecols]
end

ready_to_step(s::MinMaxScalerState, ctx::StepContext) = input_bounds(s) !== nothing

function margins(s::MinMaxScalerState, ctx)
    delta = as_float(param(ctx, "delta", -5.0))
    return delta < 0 ? (s.hi .- s.lo) .* (-delta / 100) : fill(delta, length(s.lo))
end

function reset_scaler!(s::MinMaxScalerState, bounds)
    existing = row_ids(s.out)
    isempty(existing) || delete!(s.out, existing)
    reset!(s.sub)
    s.lo, s.hi = copy(bounds[1]), copy(bounds[2])
    s.clipped = s.ignored = 0
    s.resets += 1
end

function step!(s::MinMaxScalerState, ctx::StepContext, budget::Int)
    bounds = input_bounds(s)
    bounds_changed = take_control_changes!(ctx, "table")      # min, max (and parameters)
    counts = pending(s.sub)
    if isempty(s.lo)
        s.lo, s.hi = copy(bounds[1]), copy(bounds[2])
    elseif counts.updated > 0 || counts.deleted > 0
        reset_scaler!(s, bounds)
    elseif bounds_changed && length(s.out) <= as_int(param(ctx, "reset_threshold", 1000)) &&
           (bounds[1] != s.lo || bounds[2] != s.hi)
        reset_scaler!(s, bounds)       # little scaled yet: start over with the new bounds
    end
    deleted = next_deleted!(s.sub); next_updated!(s.sub)       # (reset above)

    created = next_created!(s.sub, budget)
    isempty(created) && return publish_info!(s, StepResult(:blocked, length(deleted)))
    names = column_names(s.table)
    chunk = Dict(n => s.table[created, n] for n in names)
    margin = margins(s, ctx)
    keep = trues(length(created))
    scaled = Dict{Symbol, Vector{Float64}}()
    for (j, c) in enumerate(s.usecols)
        scaled[c], s.clipped = scale_column!(keep, chunk[c], s.lo[j], s.hi[j], margin[j], s.clipped)
    end
    dropped = count(!, keep)
    if s.ignored + dropped > as_int(param(ctx, "ignore_max", 0))
        # Too many rows out of bounds: adopt the current bounds, scale everything
        # again. The bounds cover these rows even if min and max lag behind
        # them, so the next attempt keeps them.
        lo = [min(bounds[1][j], minimum(Float64, chunk[c])) for (j, c) in enumerate(s.usecols)]
        hi = [max(bounds[2][j], maximum(Float64, chunk[c])) for (j, c) in enumerate(s.usecols)]
        reset_scaler!(s, (lo, hi))
        return publish_info!(s, StepResult(:ready, length(created)))
    end
    s.ignored += dropped
    if any(keep)
        cols = Tuple((n in s.usecols ? scaled[n] : chunk[n])[keep] for n in names)
        append!(s.out, NamedTuple{Tuple(names)}(cols))
    end
    return publish_info!(s, StepResult(has_changes(s.sub) ? :ready : :blocked, length(created)))
end

# Scale values; clip those within the margin, mark rows further out as not kept
function scale_column!(keep::BitVector, v::AbstractVector, lo::Float64, hi::Float64, margin::Float64, clipped::Int)
    width = hi - lo
    out = Vector{Float64}(undef, length(v))
    @inbounds for i in eachindex(v)
        x = Float64(v[i])
        if x < lo - margin || x > hi + margin
            keep[i] = false
        elseif x < lo || x > hi
            clipped += 1
        end
        out[i] = width > 0 ? clamp((x - lo) / width, 0.0, 1.0) : 0.0
    end
    return out, clipped
end

function publish_info!(s::MinMaxScalerState, r::StepResult)
    for (k, v) in ((:clipped, s.clipped), (:ignored, s.ignored), (:resets, s.resets))
        s.info[k] == v || (s.info[k] = v)
    end
    return r
end

consumed_rows(s::MinMaxScalerState) = lock(() -> setdiff(live_ids(s.table), s.sub.created), s.table.lock)
progress(s::MinMaxScalerState) = input_progress(s.table, s.sub)

function register_progressive_scaling!()
    register_module!(ModuleDescriptor(PROGRESSIVE_PACKAGE, "MinMaxScaler", MinMaxScalerModule,
        vcat([InputPort("table", ProgressiveTable), InputPort("min", ProgressiveDict), InputPort("max", ProgressiveDict)],
             control_ports([("delta", Float64), ("ignore_max", Int), ("reset_threshold", Int)])),
        [OutputPort("result", ProgressiveTable), OutputPort("info", ProgressiveDict)],
        Tuple{String, Type}[("columns", Vector{String}), ("delta", Float64), ("ignore_max", Int),
                            ("reset_threshold", Int)]))
end
