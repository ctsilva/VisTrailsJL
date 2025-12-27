"""
Test HTTP Workflow - Real Network Request

Tests HTTPFile module with actual HTTP fetching from httpbin.org.
"""

using Test

# Load VisTrailsJL with notebook support
include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("=" ^ 60)
println("TEST: HTTP Workflow (Real Network Request)")
println("=" ^ 60)

@testset "HTTP Workflow" begin

    @testset "Load HTTP Package" begin
        package_path = joinpath(@__DIR__, "http_package.ipynb")
        pkg = load_package_from_notebook(package_path)

        @test pkg.identifier == "org.vistrails.vistrails.http"
        @test pkg.version == "1.0.0"
        @test length(pkg.modules) == 2

        # Register the package
        register_notebook_package!(pkg)

        @test module_exists("org.vistrails.vistrails.http", "HTTPFile")
        @test module_exists("org.vistrails.vistrails.http", "JSONParser")

        println("  ✓ HTTP package loaded with HTTPFile and JSONParser")
    end

    @testset "Parse HTTP Workflow" begin
        workflow_path = joinpath(@__DIR__, "http_workflow.ipynb")
        workflow = parse_workflow_notebook(workflow_path)

        @test workflow.name == "http_test"
        @test length(workflow.modules) == 2

        # Check module IDs
        module_ids = [m.id for m in workflow.modules]
        @test "fetch_json" in module_ids
        @test "parse_json" in module_ids

        # Debug: print workflow modules and their connections
        println("\n  Workflow modules:")
        for mod in workflow.modules
            println("    - $(mod.id): $(mod.module_type)")
            println("      params: $(mod.params)")
            println("      inputs: $(mod.inputs)")
        end

        println("  ✓ HTTP workflow parsed successfully")
    end

    @testset "Execute HTTP Workflow" begin
        println("\n  Executing workflow with real HTTP request...")

        workflow_path = joinpath(@__DIR__, "http_workflow.ipynb")
        workflow = parse_workflow_notebook(workflow_path)
        pipeline, id_to_module = build_pipeline_from_workflow(workflow)

        # Debug: print module IDs and names
        println("\n  Pipeline modules:")
        for (id, mod) in pipeline.modules
            println("    Module $id: $(mod.descriptor.name)")
        end

        println("\n  Pipeline connections:")
        for conn in pipeline.connections
            println("    $(conn.source_module_id) → $(conn.dest_module_id)")
        end

        println("\n  Workflow outputs:")
        for output in workflow.outputs
            println("    $(output.name) ← $(output.source)")
        end

        # Execute with output extraction
        cache, workflow_outputs = execute_notebook_pipeline(pipeline, workflow, id_to_module=id_to_module)

        # Test that we got the expected outputs
        @test haskey(workflow_outputs, "json_data")
        @test haskey(workflow_outputs, "slideshow")

        json_data = workflow_outputs["json_data"]
        slideshow = workflow_outputs["slideshow"]

        @test !isempty(json_data)
        @test occursin("author", slideshow) || occursin("title", slideshow) || occursin("Dict", slideshow)

        println("\n  ✓ HTTP workflow executed successfully")
        println("  ✓ Workflow outputs:")
        println("    - json_data: $(length(json_data)) bytes")
        println("    - slideshow: $slideshow")
    end

end

println("\n" * "=" ^ 60)
println("HTTP Workflow Test Complete!")
println("=" ^ 60)
