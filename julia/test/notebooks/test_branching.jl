"""
Test Branching Workflow - Complex Module Dependencies

Tests workflow execution with branching (one module → multiple modules).
"""

using Test

# Load VisTrailsJL with notebook support
include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("=" ^ 60)
println("TEST: Branching Workflow (One → Many)")
println("=" ^ 60)

@testset "Branching Workflow" begin

    @testset "Load Branching Package" begin
        package_path = joinpath(@__DIR__, "branching_package.ipynb")
        pkg = load_package_from_notebook(package_path)

        @test pkg.identifier == "org.vistrails.vistrails.branching"
        @test pkg.version == "1.0.0"
        @test length(pkg.modules) == 5

        # Register the package
        register_notebook_package!(pkg)

        @test module_exists("org.vistrails.vistrails.branching", "StringSource")
        @test module_exists("org.vistrails.vistrails.branching", "StringLength")
        @test module_exists("org.vistrails.vistrails.branching", "StringUpper")
        @test module_exists("org.vistrails.vistrails.branching", "StringReverse")
        @test module_exists("org.vistrails.vistrails.branching", "CombineStrings")

        println("  ✓ Branching package loaded with 5 string utility modules")
    end

    @testset "Parse Branching Workflow" begin
        workflow_path = joinpath(@__DIR__, "branching_workflow.ipynb")
        workflow = parse_workflow_notebook(workflow_path)

        @test workflow.name == "branching_test"
        @test length(workflow.modules) == 7  # source, length, upper, reverse, combine_upper_reverse, length_to_string, final_combine

        # Check module IDs
        module_ids = [m.id for m in workflow.modules]
        @test "source" in module_ids
        @test "length" in module_ids
        @test "upper" in module_ids
        @test "reverse" in module_ids
        @test "combine_upper_reverse" in module_ids
        @test "length_to_string" in module_ids
        @test "final_combine" in module_ids

        # Debug: print workflow structure
        println("\n  Workflow modules:")
        for mod in workflow.modules
            println("    - $(mod.id): $(mod.module_type)")
            if !isempty(mod.inputs)
                for (port, source) in mod.inputs
                    println("      input $port ← $source")
                end
            end
        end

        # Check outputs
        @test length(workflow.outputs) == 5
        output_names = [o.name for o in workflow.outputs]
        @test "length" in output_names
        @test "upper" in output_names
        @test "reverse" in output_names
        @test "combined" in output_names
        @test "final" in output_names

        println("  ✓ Branching workflow parsed successfully")
    end

    @testset "Execute Branching Workflow" begin
        println("\n  Executing branching workflow...")

        workflow_path = joinpath(@__DIR__, "branching_workflow.ipynb")
        workflow = parse_workflow_notebook(workflow_path)
        pipeline, id_to_module = build_pipeline_from_workflow(workflow)

        # Debug: print execution order
        println("\n  Pipeline execution order:")
        interp_order = VisTrailsJL.topological_sort(pipeline)
        for (idx, module_id) in enumerate(interp_order)
            mod = pipeline.modules[module_id]
            println("    $idx. Module $module_id ($(mod.descriptor.name))")
        end

        # Verify topological order correctness by checking module IDs
        # source must come before all others
        source_id = id_to_module["source"].id
        source_idx = findfirst(==(source_id), interp_order)
        @test source_idx == 1

        # length, upper, reverse must all come after source
        length_id = id_to_module["length"].id
        upper_id = id_to_module["upper"].id
        reverse_id = id_to_module["reverse"].id
        length_idx = findfirst(==(length_id), interp_order)
        upper_idx = findfirst(==(upper_id), interp_order)
        reverse_idx = findfirst(==(reverse_id), interp_order)
        @test length_idx > source_idx
        @test upper_idx > source_idx
        @test reverse_idx > source_idx

        # combine_upper_reverse must come after both upper and reverse
        combine_id = id_to_module["combine_upper_reverse"].id
        combine_idx = findfirst(==(combine_id), interp_order)
        @test combine_idx > upper_idx
        @test combine_idx > reverse_idx

        # length_to_string must come after length
        length_str_id = id_to_module["length_to_string"].id
        length_str_idx = findfirst(==(length_str_id), interp_order)
        @test length_str_idx > length_idx

        # final_combine must come after both length_to_string and combine_upper_reverse
        final_id = id_to_module["final_combine"].id
        final_idx = findfirst(==(final_id), interp_order)
        @test final_idx > length_str_idx
        @test final_idx > combine_idx

        println("\n  ✓ Topological sort respects all dependencies")

        # Execute workflow
        cache, workflow_outputs = execute_notebook_pipeline(pipeline, workflow, id_to_module=id_to_module)

        # Test that we got all expected outputs
        @test haskey(workflow_outputs, "length")
        @test haskey(workflow_outputs, "upper")
        @test haskey(workflow_outputs, "reverse")
        @test haskey(workflow_outputs, "combined")
        @test haskey(workflow_outputs, "final")

        # Verify output values
        @test workflow_outputs["length"] == 11
        @test workflow_outputs["upper"] == "HELLO WORLD"
        @test workflow_outputs["reverse"] == "dlroW olleH"
        @test workflow_outputs["combined"] == "HELLO WORLD + dlroW olleH"
        @test workflow_outputs["final"] == "11: HELLO WORLD + dlroW olleH"

        println("\n  ✓ Branching workflow executed successfully")
        println("  ✓ Workflow outputs:")
        println("    - length: $(workflow_outputs["length"])")
        println("    - upper: $(workflow_outputs["upper"])")
        println("    - reverse: $(workflow_outputs["reverse"])")
        println("    - combined: $(workflow_outputs["combined"])")
        println("    - final: $(workflow_outputs["final"])")
    end

end

println("\n" * "=" ^ 60)
println("Branching Workflow Test Complete!")
println("=" ^ 60)
