"""
Analyze examples/api/simplemath.vt
"""

include("../src/VisTrailsJL.jl")
using .VisTrailsJL

vt = load_vistrail_internal("examples/api/simplemath.vt")

println("="^70)
println("📄 simplemath.vt")
println("="^70)

println("Name: ", vt.name)
println("Versions: ", length(vt.actions))
println("Tags: ", length(vt.tags))
if !isempty(vt.tags)
    println("  Tag names: ", [t.name for t in vt.tags])
end

if !isempty(vt.pipelines)
    ver = first(keys(vt.pipelines))
    pipeline = vt.pipelines[ver]
    println("\nPipeline (version $ver):")
    println("  Modules: ", length(pipeline.modules))
    println("  Connections: ", length(pipeline.connections))

    # Show all modules
    println("\n  Module Details:")
    for (id, mod) in sort(collect(pipeline.modules), by=x->x[1])
        params = []
        if haskey(mod.parameters, "name")
            push!(params, "name=$(mod.parameters["name"])")
        end
        if haskey(mod.parameters, "value")
            push!(params, "value=$(mod.parameters["value"])")
        end
        if haskey(mod.parameters, "op")
            push!(params, "op=$(mod.parameters["op"])")
        end
        param_str = isempty(params) ? "" : " (" * join(params, ", ") * ")"
        println("    [$id] $(mod.descriptor.name)$param_str")
    end

    # Show connections
    println("\n  Connections:")
    for conn in pipeline.connections
        src_mod = pipeline.modules[conn.source_module_id]
        dst_mod = pipeline.modules[conn.dest_module_id]
        println("    [$conn.source_module_id] $(src_mod.descriptor.name).$(conn.source_port) → [$conn.dest_module_id] $(dst_mod.descriptor.name).$(conn.dest_port)")
    end

    # Identify InputPorts and OutputPorts
    println("\n  Input Ports:")
    for (id, mod) in pipeline.modules
        if mod.descriptor.name == "InputPort"
            name = haskey(mod.parameters, "name") ? mod.parameters["name"] : "unnamed"
            println("    • $name")
        end
    end

    println("\n  Output Ports:")
    for (id, mod) in pipeline.modules
        if mod.descriptor.name == "OutputPort"
            name = haskey(mod.parameters, "name") ? mod.parameters["name"] : "unnamed"
            println("    • $name")
        end
    end
end

println("\n" * "="^70)
