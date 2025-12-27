"""
Run all test_*.jl files and report which ones pass/fail.
"""

test_files = filter(f -> startswith(f, "test_") && endswith(f, ".jl") && f != "test_logging_simple.jl", readdir(@__DIR__))

println("="^60)
println("Running All Test Files")
println("="^60)
println()

results = Dict{String, Bool}()

for file in sort(test_files)
    print("Testing $file... ")

    try
        # Run the test file and capture output
        output = read(`julia --project=. $file`, String)

        # Check if it completed without error
        if occursin("ERROR", output) || occursin("failed", lowercase(output))
            results[file] = false
            println("❌ FAILED")
        else
            results[file] = true
            println("✅ PASSED")
        end
    catch e
        results[file] = false
        println("❌ ERROR: $e")
    end
end

println()
println("="^60)
println("Summary")
println("="^60)

passed = count(values(results))
total = length(results)

println("\nPassed: $passed / $total")

println("\n✅ PASSED:")
for (file, passed) in sort(collect(results), by=first)
    if passed
        println("  - $file")
    end
end

println("\n❌ FAILED:")
for (file, passed) in sort(collect(results), by=first)
    if !passed
        println("  - $file")
    end
end
