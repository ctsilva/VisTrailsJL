"""
Test Optional Inputs Workflow

Tests modules with optional input ports that have default behavior when inputs are missing.
"""

using Test

# Load VisTrailsJL with notebook support
include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("=" ^ 60)
println("TEST: Optional Inputs Workflow")
println("=" ^ 60)

@testset "Optional Inputs Workflow" begin

    @testset "Load Required Packages" begin
        # Load branching package (needed for StringSource in workflow)
        branching_path = joinpath(@__DIR__, "branching_package.ipynb")
        branching_pkg = load_package_from_notebook(branching_path)
        register_notebook_package!(branching_pkg)
        println("  ✓ Branching package loaded (dependency)")

        # Load optional package
        package_path = joinpath(@__DIR__, "optional_package.ipynb")
        pkg = load_package_from_notebook(package_path)

        @test pkg.identifier == "org.vistrails.vistrails.optional"
        @test pkg.version == "1.0.0"
        @test length(pkg.modules) == 4

        # Register the package
        register_notebook_package!(pkg)

        @test module_exists("org.vistrails.vistrails.optional", "NumberSource")
        @test module_exists("org.vistrails.vistrails.optional", "OptionalAdd")
        @test module_exists("org.vistrails.vistrails.optional", "OptionalMultiply")
        @test module_exists("org.vistrails.vistrails.optional", "FormatNumber")

        println("  ✓ Optional package loaded with 4 modules")
    end

    @testset "Parse Optional Workflow" begin
        workflow_path = joinpath(@__DIR__, "optional_workflow.ipynb")
        workflow = parse_workflow_notebook(workflow_path)

        @test workflow.name == "optional_test"
        @test length(workflow.modules) == 22  # 10 sources + 4 adds/mults + 4 formats + 4 string sources

        # Check outputs
        @test length(workflow.outputs) == 8
        output_names = [o.name for o in workflow.outputs]
        @test "add_no_b" in output_names
        @test "add_with_b" in output_names
        @test "mult_no_factor" in output_names
        @test "mult_with_factor" in output_names
        @test "format_plain" in output_names
        @test "format_prefix" in output_names
        @test "format_suffix" in output_names
        @test "format_both" in output_names

        println("  ✓ Optional workflow parsed successfully")
    end

    @testset "Execute Optional Workflow" begin
        println("\n  Executing optional inputs workflow...")

        workflow_path = joinpath(@__DIR__, "optional_workflow.ipynb")
        workflow = parse_workflow_notebook(workflow_path)
        pipeline, id_to_module = build_pipeline_from_workflow(workflow)

        # Execute workflow
        cache, workflow_outputs = execute_notebook_pipeline(pipeline, workflow, id_to_module=id_to_module)

        # Test that we got all expected outputs
        @test haskey(workflow_outputs, "add_no_b")
        @test haskey(workflow_outputs, "add_with_b")
        @test haskey(workflow_outputs, "mult_no_factor")
        @test haskey(workflow_outputs, "mult_with_factor")
        @test haskey(workflow_outputs, "format_plain")
        @test haskey(workflow_outputs, "format_prefix")
        @test haskey(workflow_outputs, "format_suffix")
        @test haskey(workflow_outputs, "format_both")

        # Verify output values
        @test workflow_outputs["add_no_b"] == 10.0  # 10 + 0 (default)
        @test workflow_outputs["add_with_b"] == 12.0  # 5 + 7
        @test workflow_outputs["mult_no_factor"] == 20.0  # 20 * 1 (default)
        @test workflow_outputs["mult_with_factor"] == 15.0  # 3 * 5
        @test workflow_outputs["format_plain"] == "42.0"  # no prefix/suffix
        @test workflow_outputs["format_prefix"] == "\$99.0"  # with prefix
        @test workflow_outputs["format_suffix"] == "88.0 km"  # with suffix
        @test workflow_outputs["format_both"] == "[77.0]"  # with both

        println("\n  ✓ Optional inputs workflow executed successfully")
        println("  ✓ Workflow outputs:")
        println("    - add_no_b: $(workflow_outputs["add_no_b"]) (optional b defaulted to 0)")
        println("    - add_with_b: $(workflow_outputs["add_with_b"])")
        println("    - mult_no_factor: $(workflow_outputs["mult_no_factor"]) (optional factor defaulted to 1)")
        println("    - mult_with_factor: $(workflow_outputs["mult_with_factor"])")
        println("    - format_plain: \"$(workflow_outputs["format_plain"])\" (no prefix/suffix)")
        println("    - format_prefix: \"$(workflow_outputs["format_prefix"])\" (prefix only)")
        println("    - format_suffix: \"$(workflow_outputs["format_suffix"])\" (suffix only)")
        println("    - format_both: \"$(workflow_outputs["format_both"])\" (both prefix and suffix)")
    end

    @testset "Verify Optional Port Metadata" begin
        # Check that optional ports are marked correctly in module descriptors
        desc_add = get_module_descriptor("org.vistrails.vistrails.optional", "OptionalAdd")
        @test length(desc_add.input_ports) == 2

        # Find port 'b'
        port_b = findfirst(p -> p.name == "b", desc_add.input_ports)
        @test port_b !== nothing
        @test desc_add.input_ports[port_b].optional == true

        # Port 'a' should not be optional
        port_a = findfirst(p -> p.name == "a", desc_add.input_ports)
        @test port_a !== nothing
        @test desc_add.input_ports[port_a].optional == false

        desc_mult = get_module_descriptor("org.vistrails.vistrails.optional", "OptionalMultiply")
        port_factor = findfirst(p -> p.name == "factor", desc_mult.input_ports)
        @test port_factor !== nothing
        @test desc_mult.input_ports[port_factor].optional == true

        desc_format = get_module_descriptor("org.vistrails.vistrails.optional", "FormatNumber")
        port_prefix = findfirst(p -> p.name == "prefix", desc_format.input_ports)
        port_suffix = findfirst(p -> p.name == "suffix", desc_format.input_ports)
        @test port_prefix !== nothing
        @test port_suffix !== nothing
        @test desc_format.input_ports[port_prefix].optional == true
        @test desc_format.input_ports[port_suffix].optional == true

        println("\n  ✓ Optional port metadata verified correctly")
    end

end

println("\n" * "=" ^ 60)
println("Optional Inputs Workflow Test Complete!")
println("=" ^ 60)
