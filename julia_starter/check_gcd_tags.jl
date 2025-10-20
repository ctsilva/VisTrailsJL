using Pkg
Pkg.activate(@__DIR__)

using VisTrailsJL

vt = load_vistrail("../examples/gcd.vt")
println("Current version: ", vt.current_version)
println("Tags: ", length(vt.tags))
for tag in vt.tags
    println("  ", tag.name, " -> ", tag.version_id)
end

if haskey(vt.pipelines, vt.current_version)
    p = vt.pipelines[vt.current_version]
    println("\nCurrent pipeline: ", length(p.modules), " modules, ", length(p.connections), " connections")
    positioned = count(m -> m.layout_position !== nothing, values(p.modules))
    println("Positioned modules: ", positioned)
end
