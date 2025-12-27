"""
Test Vector Operations

Tests the vector operation modules from the Control Flow package:
Sum, Cross, Dot, ElementwiseProduct
"""

using Test

# Load VisTrailsJL with notebook support
include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("=" ^ 60)
println("TEST: Vector Operations (Control Flow)")
println("=" ^ 60)

@testset "Vector Operations" begin

    @testset "Verify Vector Modules Registered" begin
        @test module_exists("org.vistrails.vistrails.control_flow", "Sum")
        @test module_exists("org.vistrails.vistrails.control_flow", "Cross")
        @test module_exists("org.vistrails.vistrails.control_flow", "Dot")
        @test module_exists("org.vistrails.vistrails.control_flow", "ElementwiseProduct")

        println("  ✓ All vector operation modules registered")
    end

    @testset "Parse Vector Ops Workflow" begin
        workflow_path = joinpath(@__DIR__, "vector_ops_workflow.ipynb")
        workflow = parse_workflow_notebook(workflow_path)

        @test workflow.name == "vector_ops_test"
        @test length(workflow.modules) == 14  # 9 JuliaSource modules + 5 vector operations

        # Check outputs
        @test length(workflow.outputs) == 5
        output_names = [o.name for o in workflow.outputs]
        @test "sum_result" in output_names
        @test "cross_result" in output_names
        @test "dot_result" in output_names
        @test "elem_num_result" in output_names
        @test "elem_tuple_result" in output_names

        println("  ✓ Vector ops workflow parsed successfully")
    end

    @testset "Execute Vector Ops Workflow" begin
        println("\n  Executing vector operations workflow...")

        workflow_path = joinpath(@__DIR__, "vector_ops_workflow.ipynb")
        workflow = parse_workflow_notebook(workflow_path)
        pipeline, id_to_module = build_pipeline_from_workflow(workflow)

        # Execute workflow
        cache, workflow_outputs = execute_notebook_pipeline(pipeline, workflow, id_to_module=id_to_module)

        # Test that we got all expected outputs
        @test haskey(workflow_outputs, "sum_result")
        @test haskey(workflow_outputs, "cross_result")
        @test haskey(workflow_outputs, "dot_result")
        @test haskey(workflow_outputs, "elem_num_result")
        @test haskey(workflow_outputs, "elem_tuple_result")

        # Verify output values
        @test workflow_outputs["sum_result"] == 10.0  # 1 + 2 + 3 + 4

        # Cross product: [1, 2, -1] × [0, 2, 5] = [12, -5, 2]
        @test workflow_outputs["cross_result"] ≈ [12.0, -5.0, 2.0]

        # Dot product: [2, 0, -1] · [4, 2, 3] = 8 + 0 - 3 = 5
        @test workflow_outputs["dot_result"] == 5.0

        # Element-wise product (numerical): [1, 2, 3] ⊙ [2, 0, -1] = [2, 0, -3]
        @test workflow_outputs["elem_num_result"] == [2.0, 0.0, -3.0]

        # Element-wise product (tuple): [1, 2, 3] ⊙ [2, 0, -1] = [(1,2), (2,0), (3,-1)]
        expected_tuples = [(1.0, 2.0), (2.0, 0.0), (3.0, -1.0)]
        @test workflow_outputs["elem_tuple_result"] == expected_tuples

        println("\n  ✓ Vector operations workflow executed successfully")
        println("  ✓ Workflow outputs:")
        println("    - Sum([1, 2, 3, 4]) = $(workflow_outputs["sum_result"])")
        println("    - Cross([1, 2, -1], [0, 2, 5]) = $(workflow_outputs["cross_result"])")
        println("    - Dot([2, 0, -1], [4, 2, 3]) = $(workflow_outputs["dot_result"])")
        println("    - ElementwiseProduct([1, 2, 3], [2, 0, -1], numerical) = $(workflow_outputs["elem_num_result"])")
        println("    - ElementwiseProduct([1, 2, 3], [2, 0, -1], tuple) = $(workflow_outputs["elem_tuple_result"])")
    end

    @testset "Test Sum Module Directly" begin
        # Test empty list
        pipeline = Pipeline()
        sum_mod = add_module!(pipeline, "org.vistrails.vistrails.control_flow", "Sum")
        sum_mod.inputs["InputList"] = []
        compute_result = VisTrailsJL.compute(sum_mod, VisTrailsJL.SumModule)
        @test compute_result["Result"] == 0.0

        # Test single element
        sum_mod.inputs["InputList"] = [42.0]
        compute_result = VisTrailsJL.compute(sum_mod, VisTrailsJL.SumModule)
        @test compute_result["Result"] == 42.0

        # Test negative numbers
        sum_mod.inputs["InputList"] = [10.0, -5.0, 3.0, -2.0]
        compute_result = VisTrailsJL.compute(sum_mod, VisTrailsJL.SumModule)
        @test compute_result["Result"] == 6.0

        println("  ✓ Sum module unit tests passed")
    end

    @testset "Test Cross Product Validation" begin
        pipeline = Pipeline()
        cross_mod = add_module!(pipeline, "org.vistrails.vistrails.control_flow", "Cross")

        # Test wrong length for v1
        cross_mod.inputs["v1"] = [1.0, 2.0]  # Only 2 elements
        cross_mod.inputs["v2"] = [0.0, 2.0, 5.0]
        @test_throws VisTrailsJL.ModuleError VisTrailsJL.compute(cross_mod, VisTrailsJL.CrossModule)

        # Test wrong length for v2
        cross_mod.inputs["v1"] = [1.0, 2.0, -1.0]
        cross_mod.inputs["v2"] = [0.0, 2.0, 5.0, 1.0]  # 4 elements
        @test_throws VisTrailsJL.ModuleError VisTrailsJL.compute(cross_mod, VisTrailsJL.CrossModule)

        println("  ✓ Cross product validation tests passed")
    end

    @testset "Test Dot Product Validation" begin
        pipeline = Pipeline()
        dot_mod = add_module!(pipeline, "org.vistrails.vistrails.control_flow", "Dot")

        # Test mismatched lengths
        dot_mod.inputs["v1"] = [1.0, 2.0, 3.0]
        dot_mod.inputs["v2"] = [4.0, 5.0]  # Different length
        @test_throws VisTrailsJL.ModuleError VisTrailsJL.compute(dot_mod, VisTrailsJL.DotModule)

        # Test valid computation with different lengths
        dot_mod.inputs["v1"] = [1.0, 2.0, 3.0, 4.0, 5.0]
        dot_mod.inputs["v2"] = [2.0, 0.0, 1.0, -1.0, 3.0]
        compute_result = VisTrailsJL.compute(dot_mod, VisTrailsJL.DotModule)
        # 1*2 + 2*0 + 3*1 + 4*(-1) + 5*3 = 2 + 0 + 3 - 4 + 15 = 16
        @test compute_result["Result"] == 16.0

        println("  ✓ Dot product validation tests passed")
    end

    @testset "Test ElementwiseProduct Modes" begin
        pipeline = Pipeline()
        elem_mod = add_module!(pipeline, "org.vistrails.vistrails.control_flow", "ElementwiseProduct")

        elem_mod.inputs["v1"] = [5.0, 10.0, 15.0]
        elem_mod.inputs["v2"] = [2.0, 3.0, 4.0]

        # Test numerical mode
        elem_mod.parameters["NumericalProduct"] = true
        compute_result = VisTrailsJL.compute(elem_mod, VisTrailsJL.ElementwiseProductModule)
        @test compute_result["Result"] == [10.0, 30.0, 60.0]

        # Test tuple mode
        elem_mod.parameters["NumericalProduct"] = false
        compute_result = VisTrailsJL.compute(elem_mod, VisTrailsJL.ElementwiseProductModule)
        @test compute_result["Result"] == [(5.0, 2.0), (10.0, 3.0), (15.0, 4.0)]

        # Test length validation
        elem_mod.inputs["v2"] = [2.0, 3.0]  # Different length
        @test_throws VisTrailsJL.ModuleError VisTrailsJL.compute(elem_mod, VisTrailsJL.ElementwiseProductModule)

        println("  ✓ ElementwiseProduct mode tests passed")
    end

end

println("\n" * "=" ^ 60)
println("Vector Operations Test Complete!")
println("=" ^ 60)
