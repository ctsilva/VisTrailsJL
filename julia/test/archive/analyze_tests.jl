"""
Analyze all test_*.jl files in the julia directory to categorize them.
"""

using Pkg
Pkg.activate(@__DIR__)

test_files = filter(f -> startswith(f, "test_") && endswith(f, ".jl"), readdir(@__DIR__))

println("="^60)
println("Test File Analysis")
println("="^60)
println("\nFound $(length(test_files)) test files:\n")

categories = Dict(
    "vt_loading" => String[],
    "rendering" => String[],
    "execution" => String[],
    "notebook" => String[],
    "other" => String[]
)

for file in sort(test_files)
    println("📄 $file")

    # Read first 20 lines
    lines = readlines(joinpath(@__DIR__, file))[1:min(20, end)]
    content = join(lines, "\n")

    # Categorize
    if occursin(r"(load.*vistrail|load.*vt|gcd\.vt|lung\.vt|parse.*vt)"i, content)
        push!(categories["vt_loading"], file)
        println("   → .vt file loading/parsing")
    elseif occursin(r"(render|svg|graph|tree|visual)"i, content)
        push!(categories["rendering"], file)
        println("   → Rendering/visualization")
    elseif occursin(r"(execute|workflow|pipeline|module.*exec|logging)"i, content)
        push!(categories["execution"], file)
        println("   → Workflow execution")
    elseif occursin(r"(notebook|ipynb)"i, content)
        push!(categories["notebook"], file)
        println("   → Notebook system")
    else
        push!(categories["other"], file)
        println("   → Other/misc")
    end

    # Check if it uses old activation pattern
    if occursin("Pkg.activate(\".\")", content)
        println("   ⚠️  Uses old Pkg.activate pattern")
    end

    # Check if it uses include() instead of using
    if occursin(r"include\(\"src/", content)
        println("   ⚠️  Uses direct include() instead of module")
    end

    println()
end

println("\n" * "="^60)
println("Summary by Category")
println("="^60)

for (category, files) in sort(collect(categories), by=first)
    println("\n$(uppercase(category)) ($(length(files)) files):")
    for file in files
        println("  - $file")
    end
end

println("\n" * "="^60)
println("Recommendations")
println("="^60)
println("""
1. VT Loading Tests: These test legacy .vt file loading
   - Keep if still working, move to test/legacy/

2. Rendering Tests: Test SVG/graph rendering
   - Keep if still working, move to test/rendering/

3. Execution Tests: Test workflow execution
   - Consolidate with new notebook tests in test/notebooks/

4. Notebook Tests: Should already be in test/notebooks/

5. Other: Review individually
""")
