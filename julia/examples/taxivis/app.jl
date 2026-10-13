"""
Progressive TaxiVis on VisTrailsJL.

    julia --project=julia julia/examples/taxivis/prepare_data.jl     # once (needs ~/data/FOIL2013)
    julia --project=julia --threads=auto julia/examples/taxivis/app.jl [--workers N] [--port 8767]
                                                                       [--bins 512] [--rate ROWS_PER_S] [--throttle ROWS] [--rows N]

then open http://127.0.0.1:8767/ (this machine only). Ctrl-C stops it.
"""

using VisTrailsJL

include(joinpath(@__DIR__, "TaxiVis.jl"))
using .TaxiVis

arrow_path(rows=nothing) = joinpath(@__DIR__, "data", "taxivis_2013_01_stratified" *
                                    (rows === nothing ? "" : "_$rows") * ".arrow")

function option(name, default)
    i = findfirst(==("--$name"), ARGS)
    return i === nothing ? default : parse(typeof(something(default, 0)), ARGS[i + 1])
end

function main()
    rows = option("rows", nothing)
    path = arrow_path(rows)
    isfile(path) || error("$path not found: run julia/examples/taxivis/prepare_data.jl" *
                          (rows === nothing ? "" : " --rows $rows"))
    workers = option("workers", Threads.nthreads())
    app = start_app(path; workers=workers, bins=option("bins", 512), throttle=option("throttle", 0),
                    rate=option("rate", 0.0))
    port = option("port", 8767)
    server = serve(app; port=port)
    println("open http://127.0.0.1:$port/  ($(app.total) trips, $workers workers, " *
            "$(Threads.nthreads()) threads; Ctrl-C to stop)")
    try
        wait(app.pr)
    catch e
        e isa InterruptException || rethrow()
    finally
        close(server)
        stop_app(app)
    end
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
