"""
Test reconstructing a pipeline by replaying the actions in gcd.vt
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using .VisTrailsJL: load_vt_xml, replay_actions_to_version
using Test

println("Testing action replay...")

vt_file = joinpath(@__DIR__, "..", "..", "..", "examples", "gcd.vt")
root = load_vt_xml(vt_file)

@testset "Action replay (gcd.vt v134)" begin
    pipeline = replay_actions_to_version(root, 134)
    println("Pipeline has $(length(pipeline.modules)) modules and $(length(pipeline.connections)) connections")

    # Show some modules
    for (id, mod) in sort(collect(pipeline.modules), by=first)[1:min(5, length(pipeline.modules))]
        println("  Module $id: $(mod.descriptor.name)")
        for (k, v) in mod.parameters
            println("    $k = $v")
        end
    end

    @test !isempty(pipeline.modules)
    @test !isempty(pipeline.connections)
end
