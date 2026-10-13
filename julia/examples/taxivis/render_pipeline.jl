"""
Draw the TaxiVis dataflow with VisTrailsJL's workflow renderer.

    julia --project=julia julia/examples/taxivis/render_pipeline.jl [output.svg]

Builds the pipeline exactly as the app does (`build_dataflow`, which reads the
prepared Arrow file to size the time histograms), keeps one of the three
identical queries, labels each module by its role (VisTrails' `__desc__`
annotation) and writes `pipeline.svg` (default) next to this script.
"""

using VisTrailsJL

include(joinpath(@__DIR__, "TaxiVis.jl"))
using .TaxiVis

function render_taxivis_pipeline(output::AbstractString)
    data = joinpath(@__DIR__, "data")
    files = isdir(data) ? sort(filter(f -> endswith(f, ".arrow"), readdir(data; join=true)), by=filesize) : String[]
    isempty(files) && error("no prepared Arrow file in $data: run prepare_data.jl first")
    flow = build_dataflow(first(files), length(load_regions()))
    p = flow.pipeline

    # Queries 2 and 3 are copies of query 1: draw one
    drop = Set{Int}()
    for q in flow.queries[2:end]
        push!(drop, q.constraints.id, q.filter.id)
        foreach(m -> push!(drop, m.id), values(q.maps))
        foreach(((_, m),) -> push!(drop, m.id), q.hists)
        foreach(m -> push!(drop, m.id), values(q.nbhd))
    end
    foreach(id -> delete!(p.modules, id), drop)
    filter!(c -> !(c.source_module_id in drop || c.dest_module_id in drop), p.connections)

    # Labels: the module's role
    for m in values(p.modules)
        name, pr = m.descriptor.name, m.parameters
        m.annotations["__desc__"] =
            name == "ArrowLoader" ? "ArrowLoader (trips)" :
            name == "TripFilter" ? "TripFilter (query)" :
            name == "Variable" ? (m.id == flow.view.id ? "Variable (view)" : "Variable (query constraints)") :
            haskey(pr, "x_column") ? "Map: " * replace(String(pr["x_column"]), "_long" => "") :
            "Histogram: " * replace(String(pr["column"]), "_amount" => "", "_nbhd" => " neighborhood")
    end
    for m in [values(flow.base_maps)..., values(flow.base_nbhd)...]
        m.annotations["__desc__"] *= " (all trips)"
    end

    svg = render_pipeline_svg(p; width=nothing, height=nothing)
    write(output, svg)
    println("$(length(p.modules)) modules, $(length(p.connections)) connections -> $output")
    return output
end

if abspath(PROGRAM_FILE) == @__FILE__
    render_taxivis_pipeline(isempty(ARGS) ? joinpath(@__DIR__, "pipeline.svg") : ARGS[1])
end
