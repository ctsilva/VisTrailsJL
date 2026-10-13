"""
`using VisTrailsJL` must precompile: other tests include the source
directly and would not notice, e.g., a method overwritten during precompilation.
"""

using Test

@testset "Package precompiles and loads" begin
    project = joinpath(@__DIR__, "..", "..")
    err = IOBuffer()
    ok = success(pipeline(`$(Base.julia_cmd()) --project=$project -e "using VisTrailsJL"`;
                          stdout=devnull, stderr=err))
    log = String(take!(err))
    @test ok
    @test !occursin("overwritten", log)
    @test !occursin("ERROR", log)
end
