"""
Progressive TaxiVis on VisTrailsJL (see README.md): the example as a module.
"""
module TaxiVis

using VisTrailsJL

include("regions.jl")
include("dataflow.jl")
include("server.jl")

export load_regions, locate, Region, normalize_query, constraints, build_dataflow, Dataflow
export register_taxivis_modules!, start_app, stop_app, serve, snapshot, set_query!, set_view!
export render_map, encode_png, Summary, App

__init__() = register_taxivis_modules!()

end
