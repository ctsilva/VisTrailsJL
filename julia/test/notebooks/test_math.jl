"""
Test Math Package - Python VisTrails Compatibility

Tests modules that match Python VisTrails examples:
- Divide (with error handling)
- Add
- Multiply
"""

using Test

# Load VisTrailsJL with notebook support
include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("=" ^ 60)
println("TEST: Math Package (Python VisTrails Compatibility)")
println("=" ^ 60)

@testset "Math Package" begin

    @testset "Load Math Package" begin
        package_path = joinpath(@__DIR__, "math_package.ipynb")
        pkg = load_package_from_notebook(package_path)

        @test pkg.identifier == "org.vistrails.vistrails.math"
        @test pkg.version == "1.0.0"
        @test length(pkg.modules) == 3

        # Register the package
        register_notebook_package!(pkg)

        @test module_exists("org.vistrails.vistrails.math", "Divide")
        @test module_exists("org.vistrails.vistrails.math", "Add")
        @test module_exists("org.vistrails.vistrails.math", "Multiply")

        println("  ✓ Math package loaded with Divide, Add, Multiply")
    end

    @testset "Test Port Labels" begin
        # Check that port labels are preserved
        descriptor = get_module_descriptor("org.vistrails.vistrails.math", "Divide")

        @test length(descriptor.input_ports) == 2
        @test length(descriptor.output_ports) == 1

        # Check input port labels
        arg1_port = descriptor.input_ports[1]
        arg2_port = descriptor.input_ports[2]

        @test arg1_port.name == "arg1"
        @test arg1_port.label == "dividend"

        @test arg2_port.name == "arg2"
        @test arg2_port.label == "divisor"

        # Check output port label
        result_port = descriptor.output_ports[1]
        @test result_port.name == "result"
        @test result_port.label == "quotient"

        println("  ✓ Port labels working correctly")
    end

    @testset "Execute Math Workflow" begin
        println("\n  Executing math workflow: (10 + 5) / 3 * 2 = 10")

        workflow_path = joinpath(@__DIR__, "math_workflow.ipynb")
        workflow = parse_workflow_notebook(workflow_path)
        pipeline, id_to_module = build_pipeline_from_workflow(workflow)

        @test length(workflow.modules) == 7  # 4 constants + 3 operations
        @test length(workflow.outputs) == 1

        # Execute with output extraction
        cache, workflow_outputs = execute_notebook_pipeline(pipeline, workflow, id_to_module=id_to_module)

        # Test the final result
        @test haskey(workflow_outputs, "final_result")

        final_result = workflow_outputs["final_result"]
        @test final_result == 10.0

        println("\n  ✓ Math workflow executed successfully")
        println("  ✓ Result: (10 + 5) / 3 * 2 = $final_result")
    end

    @testset "Test Division by Zero Error" begin
        println("\n  Testing division by zero error handling...")

        # Create a simple pipeline with division by zero
        pipeline = Pipeline()

        # Add Float constant modules
        zero = add_module!(pipeline, "org.vistrails.vistrails.basic", "Float")
        set_parameter!(zero, "value", 0.0)

        ten = add_module!(pipeline, "org.vistrails.vistrails.basic", "Float")
        set_parameter!(ten, "value", 10.0)

        # Add Divide module
        divide = add_module!(pipeline, "org.vistrails.vistrails.math", "Divide")

        # Connect: 10 / 0
        add_connection!(pipeline, ten, "value", divide, "arg1")
        add_connection!(pipeline, zero, "value", divide, "arg2")

        # This should throw a ModuleError
        @test_throws VisTrailsJL.ModuleError execute_notebook_pipeline(pipeline)

        println("  ✓ Division by zero error handled correctly")
    end

end

println("\n" * "=" ^ 60)
println("Math Package Tests Complete!")
println("=" ^ 60)
