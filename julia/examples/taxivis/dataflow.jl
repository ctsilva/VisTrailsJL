"""
Progressive TaxiVis on VisTrailsJL: queries, modules and dataflow.

A Julia port of ProgressiVis' `taxivis` (progressivis-parallel/taxivis): the
same data, queries and page, on VisTrailsJL's progressive engine. See
README.md in this directory.

Dataflow (built as a VisTrailsJL `Pipeline`, run by a `ProgressiveEngine`):

    ArrowLoader ─┬─ TripHistogram (all trips: pickup and dropoff maps, neighborhoods)
                 └─ TripFilter_q (constraints_q: Variable) ── TripHistogram_q (maps,
                                                              attributes, neighborhoods)

`TripFilter` scans the trips in chunks and outputs the ids of the matching
trips; when its constraints change it empties its selection and rescans from
the first trip. Each `TripHistogram` counts the values of its selection (or of
all trips) and publishes an immutable `Summary` after every step, tagged with
the query revision it counts. Map histograms also follow the view bounds.
"""

const VT = VisTrailsJL

const TAXIVIS = "org.vistrails.taxivis"
const PROG = "org.vistrails.progressive"

const NYC = Dict("x0" => -74.09, "x1" => -73.72, "y0" => 40.60, "y1" => 40.88)  # same scale on both axes
# Attribute histograms: column => (min, max, bins, label), in display order
const ATTRS = [
    "hour" => (0.0, 744.0, 744, "Pickups per hour, January 2013"),
    "fare_amount" => (0.0, 80.0, 80, "Fare (\$)"),
    "tip_amount" => (0.0, 20.0, 80, "Tip (\$)"),
    "distance" => (0.0, 25.0, 100, "Distance (miles)"),
    "duration" => (0.0, 90.0, 90, "Duration (minutes)"),
]
const ATTR_NAMES = Set(first.(ATTRS))
const ENDS = ["pickup" => ("pickup_long", "pickup_lat"), "dropoff" => ("dropoff_long", "dropoff_lat")]
const COLORS = ["#f28e2b", "#e15759", "#4e79a7"]   # orange, red, blue as in the paper
const FIRST_WEEKDAY = 1                            # 2013-01-01 was a Tuesday (Monday = 0)

# ---------------------------------------------------------------- queries

"""
    normalize_query(spec, neighborhood_count) -> Dict

Validate and canonicalize a query request (port of `query_spec.normalize`);
throws `ArgumentError` for invalid input, which never reaches the dataflow.
"""
function normalize_query(spec, neighborhood_count::Int)
    spec isa AbstractDict || throw(ArgumentError("Expected a JSON object"))
    allowed = Set(["q", "enabled", "attrs", "weekdays", "hours", "pickup", "dropoff",
                   "pickup_nbhds", "dropoff_nbhds"])
    isempty(setdiff(keys(spec), allowed)) || throw(ArgumentError("Unknown query fields"))
    enabled = get(spec, "enabled", false)
    enabled isa Bool || throw(ArgumentError("enabled must be a boolean"))
    out = Dict{String, Any}("enabled" => enabled)
    for (end_, _) in ENDS
        rect = get(spec, end_, nothing)
        out[end_] = rect === nothing ? nothing : rectangle(rect)
        out[end_ * "_nbhds"] = indices(get(spec, end_ * "_nbhds", Any[]), neighborhood_count, "Neighborhood")
        out[end_] !== nothing && !isempty(out[end_ * "_nbhds"]) &&
            throw(ArgumentError("Choose a rectangle or neighborhoods for each end"))
    end
    attrs = get(spec, "attrs", Dict{String, Any}())
    attrs isa AbstractDict || throw(ArgumentError("Expected a JSON object"))
    isempty(setdiff(keys(attrs), ATTR_NAMES)) || throw(ArgumentError("Unknown attribute"))
    out["attrs"] = Dict{String, Any}()
    for (key, pair) in attrs
        (pair isa AbstractVector && length(pair) == 2) || throw(ArgumentError("An attribute range needs two bounds"))
        lo, hi = number(pair[1]), number(pair[2])
        lo < hi || throw(ArgumentError("Attribute bounds must be increasing"))
        out["attrs"][key] = [lo, hi]
    end
    for (key, size) in (("weekdays", 7), ("hours", 24))
        v = get(spec, key, nothing)
        v = v === nothing ? nothing : indices(v, size, key)
        out[key] = (v === nothing || length(v) == size) ? nothing : v
    end
    return out
end

function number(v)
    (v isa Real && !(v isa Bool) && isfinite(v)) || throw(ArgumentError("Bounds must be finite numbers"))
    return Float64(v)
end

function rectangle(v)
    v isa AbstractDict || throw(ArgumentError("Expected a JSON object"))
    Set(keys(v)) == Set(["x0", "x1", "y0", "y1"]) || throw(ArgumentError("A region needs x0, x1, y0 and y1"))
    r = Dict(k => number(x) for (k, x) in v)
    (-180 <= r["x0"] < r["x1"] <= 180 && -90 <= r["y0"] < r["y1"] <= 90) ||
        throw(ArgumentError("Region bounds must be ordered longitude/latitude coordinates"))
    return r
end

function indices(v, size::Int, label)
    v isa AbstractVector || throw(ArgumentError("$label must be a list"))
    for x in v
        (x isa Integer && !(x isa Bool) && 0 <= x < size) ||
            throw(ArgumentError("$label must be an integer from 0 to $(size - 1)"))
    end
    return sort!(unique(Int.(v)))
end

"""
    Constraints

A query as the filter tests it: `lo <= value < hi` for every range, value in
every set, and pickup (weekday, hour of day) allowed by `week`.
"""
struct Constraints
    enabled::Bool
    ranges::Vector{Tuple{Symbol, Float64, Float64}}
    sets::Vector{Tuple{Symbol, BitVector}}   # allowed neighborhood ids, index id + 2 (ids from -1)
    week::Union{Nothing, BitMatrix}          # 7 weekdays (Monday first) × 24 hours
    revision::Int
end

key(c::Constraints) = (c.enabled, c.ranges, c.sets, c.week)

function constraints(spec::AbstractDict, revision::Int, neighborhood_count::Int)
    enabled = spec["enabled"]
    ranges = Tuple{Symbol, Float64, Float64}[(Symbol(k), v[1], v[2]) for (k, v) in sort(collect(spec["attrs"]))]
    sets = Tuple{Symbol, BitVector}[]
    for (end_, (cx, cy)) in ENDS
        r = spec[end_]
        if r !== nothing
            push!(ranges, (Symbol(cx), r["x0"], r["x1"]), (Symbol(cy), r["y0"], r["y1"]))
        end
        if !isempty(spec[end_ * "_nbhds"])
            allowed = falses(neighborhood_count + 1)
            foreach(k -> allowed[k + 2] = true, spec[end_ * "_nbhds"])
            push!(sets, (Symbol(end_ * "_nbhd"), allowed))
        end
    end
    days, hours = spec["weekdays"], spec["hours"]
    week = nothing
    if days !== nothing || hours !== nothing
        week = falses(7, 24)
        for d in (days === nothing ? (0:6) : days), h in (hours === nothing ? (0:23) : hours)
            week[d + 1, h + 1] = true
        end
    end
    return Constraints(enabled, ranges, sets, week, revision)
end

# ---------------------------------------------------------------- TripFilter

struct TripFilterModule end
VT.execution_style(::Type{TripFilterModule}) = Progressive()
VT.default_step_size(::Type{TripFilterModule}) = 200_000

mutable struct TripFilterState
    table::ProgressiveTable
    sub::TableSubscription
    csub::ValueSubscription
    constraints::Union{Nothing, Constraints}
    selection::ProgressiveTable                # column :id, ids of the matching trips
    progress::ProgressiveValue{NTuple{3, Int}} # (revision, scanned, selected)
    revision::ProgressiveValue{Int}            # changes only on a restart
    scanned::Int
    selected::Int
    first_result::Tuple{Int, Union{Nothing, Float64}}  # (revision, time of its first scanned chunk)
end

function VT.init_state(::Type{TripFilterModule}, ctx::StepContext)
    table = input_container(ctx, "table")
    return TripFilterState(table, input_subscription(ctx, "table"), input_subscription(ctx, "constraints"),
                           nothing, set_output!(ctx, "result", ProgressiveTable(:id => Int)),
                           set_output!(ctx, "progress", ProgressiveValue((0, 0, 0))),
                           set_output!(ctx, "revision", ProgressiveValue(0)), 0, 0, (0, nothing))
end

function VT.step!(s::TripFilterState, ctx::StepContext, budget::Int)
    if has_changes(s.csub)
        c = take_value!(s.csub)::Constraints
        if s.constraints === nothing || key(c) != key(s.constraints) || c.revision != s.constraints.revision
            # Restart: empty the selection, rescan every trip
            s.constraints = c
            s.scanned = s.selected = 0
            existing = row_ids(s.selection)
            isempty(existing) || delete!(s.selection, existing)
            reset!(s.sub)
            set!(s.revision, c.revision)
        end
    end
    c = s.constraints
    if c === nothing || !c.enabled
        next_created!(s.sub)   # disabled: drop pending trips
        set!(s.progress, (c === nothing ? 0 : c.revision, 0, 0))
        return StepResult(:blocked, 0)
    end
    ids = next_created!(s.sub, budget)
    if isempty(ids)
        set!(s.progress, (c.revision, s.scanned, s.selected))
        return StepResult(:blocked, 0)
    end
    for r in ranges(ids)
        matching = r[trip_mask(s.table, c, r)]
        isempty(matching) || append!(s.selection, (id=matching,))
        s.selected += length(matching)
    end
    s.scanned += length(ids)
    s.first_result[1] == c.revision && s.first_result[2] !== nothing ||
        (s.first_result = (c.revision, time()))
    set!(s.progress, (c.revision, s.scanned, s.selected))
    return StepResult(has_changes(s.sub) ? :ready : :blocked, length(ids))
end

# Which trips of the id range `r` satisfy the constraints
function trip_mask(table::ProgressiveTable, c::Constraints, r::UnitRange{Int})
    ids = RowIds(r)
    mask = trues(length(r))
    for (col, lo, hi) in c.ranges
        v = table[ids, col]
        mask .&= (v .>= lo) .& (v .< hi)   # Float32 values compare as Float64, as in numpy
    end
    for (col, allowed) in c.sets
        v = table[ids, col]
        mask .&= [1 <= x + 2 <= length(allowed) && allowed[x + 2] for x in v]
    end
    if c.week !== nothing
        for (i, hour) in enumerate(table[ids, :hour])
            h = max(floor(Int, hour), 0)
            mask[i] &= c.week[(h ÷ 24 + FIRST_WEEKDAY) % 7 + 1, h % 24 + 1]
        end
    end
    return mask
end

VT.progress(s::TripFilterState) = (s.scanned, last_id(s.table))

# ---------------------------------------------------------------- TripHistogram

"""
    Summary

Immutable snapshot published by a histogram after each step: the query
revision it counts, the selected trips processed, the counts, the bounds
(maps), and when the first counts for this revision and bounds appeared.
"""
struct Summary
    revision::Int
    processed::Int
    values::Array{Int}
    bounds::Union{Nothing, NTuple{4, Float64}}   # x0, x1, y0, y1
    ready_at::Union{Nothing, Float64}
end

struct TripHistogramModule end
VT.execution_style(::Type{TripHistogramModule}) = Progressive()
VT.default_step_size(::Type{TripHistogramModule}) = 200_000

mutable struct TripHistogramState
    table::ProgressiveTable
    selection::Union{Nothing, ProgressiveTable}
    sub::TableSubscription                    # on the selection, or on all trips
    revision_sub::Union{Nothing, ValueSubscription}
    bounds_sub::Union{Nothing, ValueSubscription}
    columns::Vector{Symbol}                   # one (1D) or two (2D: x, y)
    bins::Int
    lo::Vector{Float64}
    hi::Vector{Float64}
    counts::Array{Int}                        # 1D: bins; 2D: [y bin, x bin]
    revision::Int
    processed::Int
    ready_at::Union{Nothing, Float64}
    out::ProgressiveValue{Summary}
end

optional_subscription(ctx, port) = has_input(ctx, port) ? input_subscription(ctx, port) : nothing

function VT.init_state(::Type{TripHistogramModule}, ctx::StepContext)
    table = input_container(ctx, "table")
    selection = has_input(ctx, "selection") ? input_container(ctx, "selection") : nothing
    sub = selection === nothing ? input_subscription(ctx, "table") : input_subscription(ctx, "selection")
    bins = Int(param(ctx, "bins"))
    if param(ctx, "y_column") === nothing
        columns, lo, hi = [Symbol(param(ctx, "column"))], [Float64(param(ctx, "min"))], [Float64(param(ctx, "max"))]
        counts = zeros(Int, bins)
    else
        columns = Symbol.([param(ctx, "x_column"), param(ctx, "y_column")])
        lo, hi = [NYC["x0"], NYC["y0"]], [NYC["x1"], NYC["y1"]]   # until the bounds input says otherwise
        counts = zeros(Int, bins, bins)
    end
    state = TripHistogramState(table, selection, sub, optional_subscription(ctx, "revision"),
                               optional_subscription(ctx, "bounds"), columns, bins, lo, hi, counts,
                               0, 0, nothing, set_output!(ctx, "result", ProgressiveValue{Summary}()))
    publish!(state)
    return state
end

bounds(s::TripHistogramState) = length(s.columns) == 2 ? (s.lo[1], s.hi[1], s.lo[2], s.hi[2]) : nothing

publish!(s::TripHistogramState) =
    set!(s.out, Summary(s.revision, s.processed, copy(s.counts), bounds(s), s.ready_at))

# Bin of x in [lo, hi] with `bins` equal bins (hi in the last bin), 0 outside
@inline function bin_of(x::Real, lo::Float64, hi::Float64, bins::Int)
    xf = Float64(x)
    (lo <= xf <= hi) || return 0
    return xf == hi ? bins : min(bins, floor(Int, (xf - lo) / (hi - lo) * bins) + 1)
end

function VT.step!(s::TripHistogramState, ctx::StepContext, budget::Int)
    # With a selection, the trips table is only read through it: discard its
    # changes, or they would keep this module ready forever
    s.selection === nothing || VT.consume_all!(input_subscription(ctx, "table"))
    restart = false
    if s.revision_sub !== nothing && has_changes(s.revision_sub)
        s.revision = take_value!(s.revision_sub)
        restart = true
    end
    if s.bounds_sub !== nothing && has_changes(s.bounds_sub)
        b = take_value!(s.bounds_sub)
        s.lo, s.hi = [b["x0"], b["y0"]], [b["x1"], b["y1"]]
        restart = true
    end
    pending_ = pending(s.sub)
    restart |= pending_.updated > 0 || pending_.deleted > 0   # the selection was emptied
    if restart
        reset!(s.sub)
        fill!(s.counts, 0)
        s.processed = 0
        s.ready_at = nothing
    end

    ids = next_created!(s.sub, budget)
    if !isempty(ids)
        trip_ids = s.selection === nothing ? collect(ids) : s.selection[ids, :id]
        if length(s.columns) == 1
            for x in gather(column(s.table, s.columns[1]), trip_ids)
                b = bin_of(x, s.lo[1], s.hi[1], s.bins)
                b > 0 && (s.counts[b] += 1)
            end
        else
            xs = gather(column(s.table, s.columns[1]), trip_ids)
            ys = gather(column(s.table, s.columns[2]), trip_ids)
            for i in eachindex(xs, ys)
                bx = bin_of(xs[i], s.lo[1], s.hi[1], s.bins)
                by = bin_of(ys[i], s.lo[2], s.hi[2], s.bins)
                (bx > 0 && by > 0) && (s.counts[by, bx] += 1)
            end
        end
        s.processed += length(ids)
        s.ready_at === nothing && (s.ready_at = time())
    end
    (restart || !isempty(ids)) && publish!(s)
    return StepResult(has_changes(s.sub) ? :ready : :blocked, length(ids))
end

VT.progress(s::TripHistogramState) = (s.processed, s.processed + pending(s.sub).created)

function register_taxivis_modules!()
    VT.register_module!(VT.ModuleDescriptor(TAXIVIS, "TripFilter", TripFilterModule,
        [VT.InputPort("table", ProgressiveTable), VT.InputPort("constraints", Any)],
        [VT.OutputPort("result", ProgressiveTable), VT.OutputPort("progress", ProgressiveValue),
         VT.OutputPort("revision", ProgressiveValue)], Tuple{String, Type}[]))
    VT.register_module!(VT.ModuleDescriptor(TAXIVIS, "TripHistogram", TripHistogramModule,
        [VT.InputPort("table", ProgressiveTable), VT.InputPort("selection", ProgressiveTable; optional=true),
         VT.InputPort("revision", ProgressiveValue; optional=true), VT.InputPort("bounds", Any; optional=true)],
        [VT.OutputPort("result", ProgressiveValue)],
        Tuple{String, Type}[("column", String), ("x_column", String), ("y_column", String),
                            ("bins", Int), ("min", Float64), ("max", Float64)]))
end

# ---------------------------------------------------------------- dataflow

"""
    Dataflow

The pipeline and its modules: the loader, the view bounds, the summaries of
all trips, and per query its constraints, filter and summaries.
"""
struct QueryModules
    constraints::ModuleInstance
    filter::ModuleInstance
    maps::Dict{String, ModuleInstance}
    hists::Vector{Pair{String, ModuleInstance}}
    nbhd::Dict{String, ModuleInstance}
end

struct Dataflow
    pipeline::Pipeline
    loader::ModuleInstance
    view::ModuleInstance
    base_maps::Dict{String, ModuleInstance}
    base_nbhd::Dict{String, ModuleInstance}
    queries::Vector{QueryModules}
end

function build_dataflow(path::AbstractString, neighborhood_count::Int; bins::Int=512, throttle::Int=0,
                        rate::Real=0)
    p = Pipeline()
    node(package, name; params...) = (m = add_module!(p, package, name);
                                      foreach(((k, v),) -> set_parameter!(m, String(k), v), params); m)
    connect(a, out, b, in_) = add_connection!(p, a, out, b, in_)

    loader = node(PROG, "ArrowLoader"; path=String(path), throttle=throttle, rate=Float64(rate))
    view = node(PROG, "Variable"; value=copy(NYC))

    function map_histogram(end_, filter=nothing)
        cx, cy = Dict(ENDS)[end_]
        h = node(TAXIVIS, "TripHistogram"; x_column=cx, y_column=cy, bins=bins)
        connect(loader, "result", h, "table")
        connect(view, "result", h, "bounds")
        filter === nothing || (connect(filter, "result", h, "selection"); connect(filter, "revision", h, "revision"))
        return h
    end
    function histogram(column, lo, hi, nbins, filter=nothing)
        h = node(TAXIVIS, "TripHistogram"; column=column, bins=nbins, min=lo, max=hi)
        connect(loader, "result", h, "table")
        filter === nothing || (connect(filter, "result", h, "selection"); connect(filter, "revision", h, "revision"))
        return h
    end
    nbhd_histogram(end_, filter=nothing) =
        histogram("$(end_)_nbhd", 0.0, Float64(neighborhood_count), neighborhood_count, filter)

    base_maps = Dict(e => map_histogram(e) for (e, _) in ENDS)
    base_nbhd = Dict(e => nbhd_histogram(e) for (e, _) in ENDS)
    queries = map(1:3) do i
        spec = normalize_query(Dict{String, Any}(), neighborhood_count)
        c = node(PROG, "Variable"; value=constraints(spec, 0, neighborhood_count))
        f = node(TAXIVIS, "TripFilter")
        connect(loader, "result", f, "table")
        connect(c, "result", f, "constraints")
        QueryModules(c, f, Dict(e => map_histogram(e, f) for (e, _) in ENDS),
                     [col => histogram(col, lo, hi, nb, f) for (col, (lo, hi, nb, _)) in ATTRS],
                     Dict(e => nbhd_histogram(e, f) for (e, _) in ENDS))
    end
    return Dataflow(p, loader, view, base_maps, base_nbhd, queries)
end
