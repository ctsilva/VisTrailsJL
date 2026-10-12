"""
Load a .vt file, render its version tree and largest pipeline.

Usage: julia --project=. test/legacy/test_vistrail.jl [path_to_vt_file]
Defaults to examples/gcd.vt when no path is given.
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Test

vt_file = length(ARGS) >= 1 ? ARGS[1] : joinpath(@__DIR__, "..", "..", "..", "examples", "gcd.vt")
out_dir = mktempdir()
base_name = splitext(basename(vt_file))[1]

println("="^70)
println("Loading $vt_file...")
println("="^70)

vt = load_vistrail_internal(vt_file)

println("\nVistrail Info:")
println("  Name: $(vt.name)")
println("  Current version: $(vt.current_version)")
println("  Total versions: $(length(vt.pipelines))")
println("  Total actions: $(length(vt.actions))")

# Render version tree
println("\n" * "="^70)
println("Rendering Version Tree")
println("="^70)

tree_svg = render_version_tree_svg(vt, width=1200, height=800)
tree_filename = joinpath(out_dir, "$(base_name)_tree.svg")
write(tree_filename, tree_svg)
println("✓ Saved version tree to: $tree_filename")

# Find largest pipeline
function find_largest_pipeline(pipelines)
    largest_version = nothing
    largest_size = 0
    largest_positioned = 0

    for (version, pipeline) in pipelines
        num_modules = length(pipeline.modules)
        positioned = sum(1 for (id, m) in pipeline.modules if m.layout_position !== nothing)
        
        if num_modules > largest_size
            largest_size = num_modules
            largest_version = version
            largest_positioned = positioned
        end
    end
    
    return (largest_version, largest_size, largest_positioned)
end

largest_version, largest_size, largest_positioned = find_largest_pipeline(vt.pipelines)

println("\n" * "="^70)
println("Largest Pipeline:")
println("  Version: $largest_version")
println("  Modules: $largest_size")
println("  Positioned: $largest_positioned")
println("="^70)

if largest_version !== nothing && largest_positioned > 0
    pipeline = vt.pipelines[largest_version]
    println("\nRendering version $largest_version to SVG...")
    svg = render_pipeline_svg(pipeline, width=2000, height=1600, module_width=120.0, module_height=60.0, port_size=6.0, margin=80.0)
    workflow_filename = joinpath(out_dir, "$(base_name)_workflow.svg")
    write(workflow_filename, svg)
    println("✓ Saved workflow to: $workflow_filename")
end

@testset "Load and render $(basename(vt_file))" begin
    @test !isempty(vt.actions)
    @test !isempty(vt.pipelines)
    @test occursin("<svg", tree_svg)
    @test largest_version !== nothing
    @test largest_positioned > 0
    @test isfile(workflow_filename)
end
