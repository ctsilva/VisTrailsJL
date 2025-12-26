#!/usr/bin/env julia

# Test script to verify JSON conversion works

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using JSON3

# Load VisTrailsJL
include("../src/VisTrailsJL.jl")

println("Testing workflow to JSON conversion...")
println("="^50)

# Load GCD workflow
vt_file = "../../examples/gcd.vt"
println("\nLoading: $vt_file")
vt = VisTrailsJL.load_vistrail(vt_file)

# Get latest version
pipeline = VisTrailsJL.get_pipeline(vt)

println("\nPipeline loaded:")
println("  Modules: ", length(pipeline.modules))
println("  Connections: ", length(pipeline.connections))

# Convert to JSON
modules = map(collect(pipeline.modules)) do (id, mod)
    # Module instances don't have position info in the basic pipeline structure
    # Positions would come from layout in the .vt file's action annotations
    Dict(
        "id" => id,
        "name" => mod.descriptor.name,
        "package" => mod.descriptor.package,
        "x" => 100.0 + id * 150.0,  # Default layout for now
        "y" => 100.0,
        "inputs" => map(p -> Dict("name" => p.name, "type" => string(p.type)), mod.descriptor.input_ports),
        "outputs" => map(p -> Dict("name" => p.name, "type" => string(p.type)), mod.descriptor.output_ports)
    )
end

connections = map(pipeline.connections) do conn
    Dict(
        "source_id" => conn.source_module_id,
        "source_port" => conn.source_port,
        "target_id" => conn.dest_module_id,
        "target_port" => conn.dest_port
    )
end

result = Dict(
    "modules" => modules,
    "connections" => connections,
    "version_id" => vt.current_version
)

# Convert to JSON
json_str = JSON3.write(result, allow_inf=true)

println("\n" * "="^50)
println("JSON OUTPUT:")
println("="^50)
println(JSON3.pretty(result))
println("="^50)

println("\n✅ JSON conversion successful!")
println("\nSummary:")
println("  - $(length(modules)) modules")
println("  - $(length(connections)) connections")
println("  - Version: $(result["version_id"])")
