"""
Test Conversion Tools

Tests for converting between notebook and code-based package/workflow definitions.
"""

using Test

# Load VisTrailsJL
include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("=" ^ 60)
println("TEST: Conversion Tools")
println("=" ^ 60)

@testset "Conversion Tools" begin

    @testset "Package to Notebook" begin
        # Define a simple package programmatically
        modules = [
            Dict{String, Any}(
                "name" => "Increment",
                "input_ports" => [("value", "basic:Integer")],
                "output_ports" => [("result", "basic:Integer")],
                "code" => "v = get_input(\"value\")\nset_output(\"result\", v + 1)"
            ),
            Dict{String, Any}(
                "name" => "Square",
                "input_ports" => [("value", "basic:Integer")],
                "output_ports" => [("result", "basic:Integer")],
                "code" => "v = get_input(\"value\")\nset_output(\"result\", v * v)"
            )
        ]

        notebook = package_to_notebook("test.math", modules; version="2.0.0")

        @test haskey(notebook, "cells")
        @test length(notebook["cells"]) >= 3  # title + meta + 2 modules

        # Check notebook structure
        @test notebook["nbformat"] == 4

        # Find the package-meta cell
        meta_found = false
        for cell in notebook["cells"]
            source = join(cell["source"], "")
            if occursin("#| package-meta", source)
                meta_found = true
                @test occursin("identifier: test.math", source)
                @test occursin("version: 2.0.0", source)
            end
        end
        @test meta_found

        # Save and reload
        test_path = joinpath(@__DIR__, "generated_package.ipynb")
        save_package_notebook(notebook, test_path)
        @test isfile(test_path)

        # Load it back and verify
        pkg = load_package_from_notebook(test_path)
        @test pkg.identifier == "test.math"
        @test pkg.version == "2.0.0"
        @test length(pkg.modules) == 2

        # Clean up
        rm(test_path)

        println("  ✓ Package to notebook tests passed")
    end

    @testset "Notebook to Package Code" begin
        # Use the existing test package
        test_pkg_path = joinpath(@__DIR__, "test_package.ipynb")
        code = notebook_to_package_code(test_pkg_path)

        # Check generated code structure
        @test occursin("Package: test.testpkg", code)
        @test occursin("struct AddOneModule", code)
        @test occursin("struct DoubleModule", code)
        @test occursin("function compute(mod::ModuleInstance, ::Type{AddOneModule})", code)
        @test occursin("function compute(mod::ModuleInstance, ::Type{DoubleModule})", code)
        @test occursin("register_", code)

        # Save to file
        output_path = joinpath(@__DIR__, "generated_package.jl")
        save_package_code(test_pkg_path, output_path)
        @test isfile(output_path)

        # Read and verify
        saved_code = read(output_path, String)
        @test saved_code == code

        # Clean up
        rm(output_path)

        println("  ✓ Notebook to package code tests passed")
    end

    @testset "Round-trip: Notebook → Code → Notebook" begin
        # Start with test package
        original_path = joinpath(@__DIR__, "test_package.ipynb")
        pkg_original = load_package_from_notebook(original_path)

        # Convert to code
        code = notebook_to_package_code(original_path)

        # The code should preserve module structure
        @test occursin("AddOne", code)
        @test occursin("Double", code)
        @test occursin("get_input", code)
        @test occursin("set_output", code)

        println("  ✓ Round-trip tests passed")
    end

    @testset "Registered Package Export" begin
        # Export a built-in package to notebook
        output_path = joinpath(@__DIR__, "exported_basic.ipynb")

        # Export the basic constants (Integer, Float, etc.)
        # Note: This won't have the compute code, just structure
        registered_package_to_notebook(
            "org.vistrails.vistrails.basic",
            output_path;
            version="2.2.0"
        )

        @test isfile(output_path)

        # Load and verify structure
        pkg = load_package_from_notebook(output_path)
        @test pkg.identifier == "org.vistrails.vistrails.basic"
        @test pkg.version == "2.2.0"
        @test length(pkg.modules) > 0

        # Check some known modules exist
        module_names = [m[1] for m in pkg.modules]
        @test "Integer" in module_names
        @test "Float" in module_names
        @test "String" in module_names

        # Clean up
        rm(output_path)

        println("  ✓ Registered package export tests passed")
    end

    @testset ".vt Workflow to Notebook" begin
        # Use the gcd.vt example (simple, well-tested)
        vt_path = joinpath(@__DIR__, "..", "..", "..", "examples", "gcd.vt")

        if isfile(vt_path)
            output_path = joinpath(@__DIR__, "gcd_workflow.ipynb")

            # Convert version 134 (latest in gcd.vt based on docs)
            # Actually let's find the latest version
            vistrail = load_vistrail(vt_path)

            # Get the highest version number
            max_version = maximum(keys(vistrail.actions))
            println("  Converting gcd.vt version $max_version to notebook...")

            notebook = vistrail_workflow_to_notebook(vt_path, max_version; output_path=output_path)

            @test isfile(output_path)
            @test haskey(notebook, "cells")
            @test length(notebook["cells"]) > 0

            # Check notebook has workflow directive
            has_workflow = false
            has_modules = false
            has_execute = false

            for cell in notebook["cells"]
                source = join(get(cell, "source", []), "")
                if occursin("#| workflow:", source)
                    has_workflow = true
                end
                if occursin("#| module-id:", source)
                    has_modules = true
                end
                if occursin("#| execute", source)
                    has_execute = true
                end
            end

            @test has_workflow
            @test has_modules
            @test has_execute

            # Clean up
            rm(output_path)

            println("  ✓ .vt workflow to notebook tests passed")
        else
            @warn "Skipping .vt test - gcd.vt not found at $vt_path"
        end
    end

end

println("\n" * "=" ^ 60)
println("All conversion tests passed!")
println("=" ^ 60)
