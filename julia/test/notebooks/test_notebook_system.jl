"""
Test Notebook System - Uses Refactored Modules

Tests the integrated notebook-based workflow system.
"""

using Test

# Load VisTrailsJL with notebook support
include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("=" ^ 60)
println("TEST: Notebook-Based Workflow System (Refactored)")
println("=" ^ 60)

@testset "Notebook Workflow System" begin

    @testset "Parser" begin
        # Test parsing the package notebook
        package_path = joinpath(@__DIR__, "test_package.ipynb")
        cells = parse_notebook(package_path)

        @test length(cells) >= 3  # markdown + package-meta + 2 modules

        # Check package-meta cell
        meta_cells = filter(c -> has_directive(c, "package-meta"), cells)
        @test length(meta_cells) == 1
        @test get_directive(meta_cells[1], "identifier") == "test.testpkg"

        # Check module cells
        module_cells = filter(c -> has_directive(c, "module"), cells)
        @test length(module_cells) == 2

        println("  ✓ Parser tests passed")
    end

    @testset "Package Loading" begin
        package_path = joinpath(@__DIR__, "test_package.ipynb")
        pkg = load_package_from_notebook(package_path)

        @test pkg.identifier == "test.testpkg"
        @test pkg.version == "1.0.0"
        @test length(pkg.modules) == 2

        # Check module names
        module_names = [m[1] for m in pkg.modules]
        @test "AddOne" in module_names
        @test "Double" in module_names

        # Register the package
        register_notebook_package!(pkg)

        # Check modules are registered
        @test module_exists("test.testpkg", "AddOne")
        @test module_exists("test.testpkg", "Double")

        println("  ✓ Package loading tests passed")
    end

    @testset "Workflow Parsing" begin
        workflow_path = joinpath(@__DIR__, "test_workflow.ipynb")
        workflow = parse_workflow_notebook(workflow_path)

        @test workflow.name == "test_computation"
        @test length(workflow.modules) == 3
        @test workflow.execute == true

        # Check module IDs
        module_ids = [m.id for m in workflow.modules]
        @test "const1" in module_ids
        @test "add" in module_ids
        @test "double" in module_ids

        println("  ✓ Workflow parsing tests passed")
    end

    @testset "Pipeline Building" begin
        workflow_path = joinpath(@__DIR__, "test_workflow.ipynb")
        workflow = parse_workflow_notebook(workflow_path)
        pipeline, id_to_module = build_pipeline_from_workflow(workflow)

        @test length(pipeline.modules) == 3
        @test length(pipeline.connections) == 2
        @test length(id_to_module) == 3

        println("  ✓ Pipeline building tests passed")
    end

    @testset "Execution" begin
        workflow_path = joinpath(@__DIR__, "test_workflow.ipynb")
        workflow = parse_workflow_notebook(workflow_path)
        pipeline, id_to_module = build_pipeline_from_workflow(workflow)

        cache, workflow_outputs = execute_notebook_pipeline(pipeline, workflow; id_to_module=id_to_module)

        # Find the Double module result
        double_result = nothing
        for (id, mod) in pipeline.modules
            if mod.descriptor.name == "Double"
                double_result = cache[id]["result"]
                break
            end
        end

        @test double_result == 12  # (5 + 1) * 2 = 12

        println("  ✓ Execution tests passed")
    end

end

println("\n" * "=" ^ 60)
println("All tests passed!")
println("=" ^ 60)
