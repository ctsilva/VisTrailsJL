"""
TaxiVis application state and HTTP server (port of ProgressiVis' `taxivis/app.py`).

Same endpoints and JSON as the ProgressiVis version, so the same page works:
`GET /`, `/client.js`, `/state`, `/map.png`, `/regions`, `/debug`, and
`POST /query`, `POST /view`. Listens on 127.0.0.1 only.
"""

using HTTP
using JSON3
using CodecZlib

const STATIC = joinpath(@__DIR__, "static")

mutable struct QueryState
    i::Int
    color::String
    spec::Dict{String, Any}
    revision::Int
    started::Union{Nothing, Float64}
    latency_ms::Union{Nothing, Int}
    modules::QueryModules
end

mutable struct App
    flow::Dataflow
    regions::Vector{Region}
    pr::ProgressiveRun
    queries::Vector{QueryState}
    view::Dict{String, Float64}
    mode::String
    t0::Float64
    view_revision::Int
    view_started::Union{Nothing, Float64}
    view_latency_ms::Union{Nothing, Int}
    bins::Int
    workers::Int
    total::Int
    lock::ReentrantLock        # state read by snapshots
    mutation::ReentrantLock    # serializes edits
end

"""
    start_app(path; workers, bins, throttle, rate, accuracy, tolerance) -> App

Build the dataflow over the trips in the Arrow file `path` and start it.
With `accuracy > 0` (default 0.99), loading pauses once no display would
visibly change (see `build_dataflow`).
"""
function start_app(path::AbstractString; workers::Int=Threads.nthreads(), bins::Int=512, throttle::Int=0,
                   rate::Real=0, accuracy::Real=0.99, tolerance::Real=DEFAULT_TOLERANCE)
    regions = load_regions()
    flow = build_dataflow(path, length(regions); bins=bins, throttle=throttle, rate=rate,
                          accuracy=accuracy, tolerance=tolerance)
    pr = start!(ProgressiveEngine(workers=workers), flow.pipeline; enable_logging=false)
    queries = [QueryState(i, COLORS[i], normalize_query(Dict{String, Any}(), length(regions)), 0,
                          nothing, nothing, flow.queries[i]) for i in 1:3]
    total = flow.total
    return App(flow, regions, pr, queries, copy(NYC), "pickup", time(), 0, nothing, nothing,
               bins, workers, total, ReentrantLock(), ReentrantLock())
end

stop_app(app::App) = (stop!(app.pr); wait(app.pr); app)

# ---------------------------------------------------------------- reading results

output(app::App, m::ModuleInstance, port="result") = app.pr.run.outputs[m.id][port]

function published(app::App, m::ModuleInstance)
    v = output(app, m)
    return has_value(v) ? current_value(v)::Summary : nothing
end

loaded_rows(app::App) = last_id(output(app, app.flow.loader))
loading_done(app::App) = module_status(app.pr.run, app.flow.loader.id) == :done
loading_paused(app::App) = is_paused(app.pr.run, app.flow.loader.id)

# Counts from a sample of `read` trips, scaled to estimates for all trips
scale(app::App, read::Int) = app.total / max(read, 1)
estimate(values, s) = round.(Int, values .* s)
filter_progress(app::App, q::QueryState) = current_value(output(app, q.modules.filter, "progress"))

view_tuple(view) = (view["x0"], view["x1"], view["y0"], view["y1"])

# A map layer for the current view, rows north first, as estimated counts
# for all trips (nothing if not computed yet); `read`: trips the counts are
# from (default: the histogram's own, for all trips)
function map_layer(app::App, m::ModuleInstance, view, revision::Int=0, read=nothing)
    pub = published(app, m)
    (pub === nothing || pub.revision != revision || pub.bounds != view_tuple(view)) && return nothing
    return reverse(pub.values, dims=1) .* scale(app, something(read, pub.processed))
end

"""
    query_snapshot(app, q, rows, done, view) -> Dict

One query's part of `/state`: counts, histograms, readiness (every summary
has counts for the current revision), completeness (everything loaded
processed, and either all trips loaded or every summary converged) and
latency, as in app.py. Counts are estimates for all trips: the sample's
counts scaled by trips / trips scanned.
"""
function query_snapshot(app::App, q::QueryState, rows::Int, done::Bool, view)
    revision = q.revision
    m = q.modules
    summaries = [m.maps..., (m.hists)..., m.nbhd...]
    pubs = Dict(h.id => published(app, h) for (_, h) in summaries)
    actual, scanned, selected = filter_progress(app, q)
    current = actual == revision
    enabled = q.spec["enabled"]
    empty = current && selected == 0 && (scanned > 0 || done && rows == 0)
    ready, complete = !enabled || empty, !enabled
    if enabled && current
        ok(p, f) = p !== nothing && p.revision == revision && f(p)
        ready = empty || all(ok(p, p -> p.processed > 0) for p in values(pubs))
        # Complete: every summary converged (they may skip trips already
        # loaded), or all trips loaded and processed
        converged = !empty && all(ok(p, p -> p.converged) for p in values(pubs))
        processed_all = done && scanned == rows && (empty || all(ok(p, p -> p.processed == selected) for p in values(pubs)))
        complete = converged || processed_all
    end
    s = scale(app, scanned)
    if complete && enabled && !empty
        complete = all(pubs[h.id] !== nothing && pubs[h.id].bounds == view_tuple(view) for h in values(m.maps))
    end
    usable(p) = enabled && !empty && p !== nothing && p.revision == revision
    hists, excluded = Dict{String, Any}(), Dict{String, Any}()
    for (col, h) in m.hists
        p = pubs[h.id]
        nbins = Dict(app.flow.attrs)[col][3]
        hists[col] = empty && enabled ? zeros(Int, nbins) : usable(p) ? estimate(p.values, s) : nothing
        excluded[col] = empty ? 0 : usable(p) ? round(Int, max(0, p.processed - sum(p.values)) * s) : nothing
    end
    nbhd = Dict{String, Any}()
    for (end_, h) in m.nbhd
        p = pubs[h.id]
        nbhd[end_] = empty && enabled ? zeros(Int, length(app.regions)) : usable(p) ? estimate(p.values, s) : nothing
    end
    if ready && q.started !== nothing && q.latency_ms === nothing
        ready_at = if !enabled
            q.started
        elseif empty
            first_rev, first_at = app.pr.run.engine_state.modules[m.filter.id].state.first_result
            first_rev == revision && first_at !== nothing ? first_at : q.started
        else
            maximum(p.ready_at for p in values(pubs) if p !== nothing && p.ready_at !== nothing; init=q.started)
        end
        q.latency_ms = max(0, round(Int, 1000 * (ready_at - q.started)))
    end
    return Dict("color" => q.color, "spec" => q.spec, "revision" => revision,
                "count" => enabled && current ? round(Int, selected * s) : 0, "hists" => hists, "nbhd" => nbhd,
                "excluded" => excluded, "scanned" => current && enabled ? scanned : 0,
                "ready" => ready, "complete" => complete, "latency_ms" => q.latency_ms)
end

"The JSON of `GET /state`"
function snapshot(app::App)
    rows = loaded_rows(app)
    done = loading_done(app)
    st = lock(app.lock) do
        view = copy(app.view)
        queries = [query_snapshot(app, q, rows, done, view) for q in app.queries]
        # Map layers needed for the view: all trips, and every non-empty enabled query
        maps = [(h, 0) for h in values(app.flow.base_maps)]
        for (q, s) in zip(app.queries, queries)
            q.spec["enabled"] && s["count"] > 0 && append!(maps, [(h, q.revision) for h in values(q.modules.maps)])
        end
        view_ready = all(map_layer(app, h, view, r) !== nothing for (h, r) in maps) || (done && rows == 0)
        if view_ready && app.view_started !== nothing && app.view_latency_ms === nothing
            ready_ats = [p.ready_at for p in (published(app, h) for (h, _) in maps) if p !== nothing && p.ready_at !== nothing]
            ready_at = isempty(ready_ats) ? app.view_started : maximum(ready_ats)
            app.view_latency_ms = max(0, round(Int, 1000 * (ready_at - app.view_started)))
        end
        bases = [values(app.flow.base_maps)..., values(app.flow.base_nbhd)...]
        Dict{String, Any}(
            "view" => view, "mode" => app.mode, "t0" => app.t0, "view_revision" => app.view_revision,
            "view_latency_ms" => app.view_latency_ms, "queries" => queries,
            "pending" => !view_ready || any(!s["ready"] for s in queries),
            "view_ready" => view_ready,
            "complete" => all(s["complete"] for s in queries) && view_ready &&
                          (rows == 0 ? done : all((p = published(app, h)) !== nothing &&
                                            (p.converged || done && p.processed == rows) for h in bases)))
    end
    all_nbhd = Dict(e => (p = published(app, h)) === nothing ? nothing : estimate(p.values, scale(app, p.processed))
                    for (e, h) in app.flow.base_nbhd)
    merge!(st, Dict("rows" => rows, "total" => app.total, "workers" => app.workers, "home" => NYC,
                    "elapsed" => round(time() - app.t0, digits=1), "all_nbhd" => all_nbhd,
                    "attrs" => Dict(c => Dict("min" => a[1], "max" => a[2], "bins" => a[3], "label" => a[4]) for (c, a) in app.flow.attrs),
                    "period" => period_name(app.flow.attrs),
                    "loading_done" => done, "loading_paused" => !done && loading_paused(app),
                    "converged" => st["complete"] && rows < app.total))
    return st
end

# ---------------------------------------------------------------- edits

"""
    set_query!(app, body) -> Dict

Apply a query edit: validated, then given to the query's constraints
`Variable`, which restarts its filter and summaries (an interaction for the
progressive engine). Unchanged specs keep their revision.
"""
function set_query!(app::App, body)
    body isa AbstractDict || throw(ArgumentError("Expected a JSON object"))
    qi = get(body, "q", nothing)
    (qi isa Integer && !(qi isa Bool) && 0 <= qi < length(app.queries)) ||
        throw(ArgumentError("Query must be an integer from 0 to $(length(app.queries) - 1)"))
    spec = normalize_query(body, length(app.regions))
    lock(app.mutation) do
        q = app.queries[qi + 1]
        spec == q.spec && return Dict("q" => qi, "revision" => q.revision, "spec" => q.spec, "changed" => false)
        revision = q.revision + 1
        started = time()
        set_variable!(app.pr, q.modules.constraints, constraints(spec, revision, length(app.regions)))
        lock(app.lock) do
            q.spec, q.revision, q.started, q.latency_ms = spec, revision, started, nothing
        end
        return Dict("q" => qi, "revision" => q.revision, "spec" => q.spec, "changed" => true)
    end
end

function set_view!(app::App, body)
    body isa AbstractDict || throw(ArgumentError("Expected a JSON object"))
    isempty(setdiff(keys(body), ["mode", "bounds"])) || throw(ArgumentError("Unknown view fields"))
    haskey(body, "mode") && !(body["mode"] in ("pickup", "dropoff", "both")) &&
        throw(ArgumentError("mode must be pickup, dropoff or both"))
    bounds = haskey(body, "bounds") ? rectangle(body["bounds"]) : nothing
    lock(app.mutation) do
        bounds = bounds === nothing ? app.view : Dict{String, Float64}(bounds)
        mode = get(body, "mode", app.mode)
        changed = bounds != app.view || mode != app.mode
        # Maps follow the bounds, and compute only while their end is shown
        changed && set_variable!(app.pr, app.flow.view, view_value(bounds, mode))
        if bounds != app.view
            started = time()
            lock(() -> (app.view, app.view_started, app.view_latency_ms) = (bounds, started, nothing), app.lock)
        end
        lock(app.lock) do
            app.mode = mode
            app.view_revision += Int(changed)
            Dict("revision" => app.view_revision, "changed" => changed)
        end
    end
end

# ---------------------------------------------------------------- map image

hex_color(c) = [parse(Int, c[k:k+1], base=16) for k in (2, 4, 6)]

"""
    render_map(app; light=false) -> (png bytes, revisions)

All trips in gray (log scale), each enabled query in its color, as in app.py.
"""
function render_map(app::App; light::Bool=false)
    view, mode, query_states, revisions = lock(app.lock) do
        (copy(app.view), app.mode, [(q, q.spec["enabled"], q.revision) for q in app.queries],
         [app.view_revision, (q.revision for q in app.queries)...])
    end
    ends = mode == "both" ? ["pickup", "dropoff"] : [mode]
    function layer(maps, revision=0, read=nothing)
        parts = filter(!isnothing, [map_layer(app, maps[e], view, revision, read) for e in ends])
        isempty(parts) ? nothing : sum(parts)
    end
    n = app.bins
    rgb = fill(light ? 255.0 : 0.0, n, n, 3)
    base = layer(app.flow.base_maps)
    if base !== nothing && maximum(base) > 0
        v = log1p.(base) ./ log1p(maximum(base))
        gray = light ? 255 .- v .^ 0.8 .* 170 : v .^ 0.8 .* 200
        for c in 1:3
            rgb[:, :, c] .= gray
        end
    end
    for (q, enabled, revision) in query_states
        enabled || continue
        actual, scanned, _ = filter_progress(app, q)
        a = actual == revision ? layer(q.modules.maps, revision, scanned) : nothing
        (a === nothing || maximum(a) <= 0) && continue
        alpha = ifelse.(a .> 0, 0.35 .+ 0.65 .* log1p.(a) ./ log1p(maximum(a)), 0.0)
        color = hex_color(q.color)
        for c in 1:3
            rgb[:, :, c] .= rgb[:, :, c] .* (1 .- alpha) .+ color[c] .* alpha
        end
    end
    return encode_png(round.(UInt8, clamp.(rgb, 0, 255))), revisions
end

# Minimal PNG encoder: 8-bit RGB, no filtering, zlib-compressed
const CRC_TABLE = [let c = UInt32(n)
                       for _ in 1:8
                           c = isodd(c) ? 0xedb88320 ⊻ (c >> 1) : c >> 1
                       end
                       c
                   end for n in 0:255]

function crc32(data::AbstractVector{UInt8})
    c = 0xffffffff
    for b in data
        c = CRC_TABLE[((c ⊻ b) & 0xff) + 1] ⊻ (c >> 8)
    end
    return c ⊻ 0xffffffff
end

function png_chunk(io::IO, kind::String, data::Vector{UInt8})
    write(io, hton(UInt32(length(data))))
    body = vcat(Vector{UInt8}(kind), data)
    write(io, body)
    write(io, hton(crc32(body)))
end

function encode_png(rgb::Array{UInt8, 3})
    h, w, _ = size(rgb)
    raw = Vector{UInt8}(undef, h * (1 + 3w))
    k = 0
    for y in 1:h
        raw[k += 1] = 0x00   # filter: none
        for x in 1:w, c in 1:3
            raw[k += 1] = rgb[y, x, c]
        end
    end
    io = IOBuffer()
    write(io, UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    header = IOBuffer()
    write(header, hton(UInt32(w)), hton(UInt32(h)), UInt8[8, 2, 0, 0, 0])
    png_chunk(io, "IHDR", take!(header))
    png_chunk(io, "IDAT", transcode(ZlibCompressor, raw))
    png_chunk(io, "IEND", UInt8[])
    return take!(io)
end

# ---------------------------------------------------------------- HTTP

json_value(x) = x
json_value(x::JSON3.Object) = Dict{String, Any}(String(k) => json_value(v) for (k, v) in pairs(x))
json_value(x::JSON3.Array) = Any[json_value(v) for v in x]

respond(body, ctype; status=200, headers=Pair{String, String}[]) =
    HTTP.Response(status, ["Content-Type" => ctype, "Cache-Control" => "no-store", headers...], body)
json_response(x; status=200) = respond(JSON3.write(x), "application/json"; status=status)

function debug_info(app::App)
    run = app.pr.run
    steps = sort([(m.descriptor.name * " " * string(id), module_steps(run, id).steps,
                   module_steps(run, id).items, string(module_status(run, id)),
                   something(module_converged(run, id), "-"), is_paused(run, id))
                  for (id, m) in run.instances], by=r -> -r[3])
    maps = Dict(string(h.id) => (p = published(app, h)) === nothing ? nothing : sum(p.values)
                for h in [values(app.flow.base_maps)...; [h for q in app.queries for h in values(q.modules.maps)]])
    return Dict("steps" => steps, "map_totals" => maps)
end

function handle(app::App, req::HTTP.Request)
    path = first(split(req.target, '?'))
    try
        if req.method == "GET"
            path == "/" && return respond(read(joinpath(STATIC, "index.html")), "text/html; charset=utf-8")
            path == "/client.js" && return respond(read(joinpath(STATIC, "client.js")), "text/javascript; charset=utf-8")
            path == "/state" && return json_response(snapshot(app))
            path == "/regions" && return json_response(regions_json(app.regions))
            path == "/debug" && return json_response(debug_info(app))
            if path == "/map.png"
                png, revisions = render_map(app; light=occursin("theme=light", req.target))
                return respond(png, "image/png"; headers=["X-Taxivis-Revisions" => JSON3.write(revisions)])
            end
        elseif req.method == "POST" && path in ("/query", "/view")
            length(req.body) <= 65536 || throw(ArgumentError("Request too large"))
            body = try
                isempty(req.body) ? Dict{String, Any}() : json_value(JSON3.read(req.body))
            catch
                throw(ArgumentError("Invalid JSON"))
            end
            return json_response(path == "/query" ? set_query!(app, body) : set_view!(app, body))
        end
        return respond("not found", "text/plain"; status=404)
    catch e
        # Invalid requests: 400 with the reason; they never reach the dataflow
        e isa ArgumentError && return json_response(Dict("error" => e.msg); status=400)
        return json_response(Dict("error" => sprint(showerror, e)); status=500)
    end
end

"""
    serve(app; port=8767) -> HTTP.Server

Serve the page and API on 127.0.0.1:`port` (non-blocking; `close(server)` stops it).
"""
serve(app::App; port::Int=8767) = HTTP.serve!(req -> handle(app, req), "127.0.0.1", port; verbose=false)
