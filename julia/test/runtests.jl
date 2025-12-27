"""
VisTrailsJL Test Suite Runner

Runs all tests with incremental progress reporting.

Usage:
    julia --project=. test/runtests.jl              # Run all tests
    julia --project=. test/runtests.jl notebooks    # Run only notebook tests
    julia --project=. test/runtests.jl legacy       # Run only legacy tests
"""

println("="^70)
println("VisTrailsJL Test Suite")
println("="^70)
println()

# Parse command line arguments
const TEST_CATEGORY = length(ARGS) > 0 ? ARGS[1] : "all"

# Test configuration
const TEST_SUITES = Dict(
    "notebooks" => Dict(
        "name" => "Notebook System Tests",
        "path" => "notebooks",
        "tests" => [
            "test_notebook_system.jl",
            "test_conversion.jl",
            "test_http.jl",
            "test_math.jl",
            "test_branching.jl",
            "test_optional.jl",
            "test_vector_ops.jl"
        ]
    ),
    "legacy" => Dict(
        "name" => "Legacy .vt File Tests",
        "path" => "legacy",
        "tests" => [
            "test_vistrail.jl",
            "test_action_replay.jl",
            "test_version_tree_structure.jl",
            "test_tags.jl"
        ]
    ),
    "rendering" => Dict(
        "name" => "Rendering Tests",
        "path" => "rendering",
        "tests" => [
            "test_svg_rendering.jl",
            "test_pipeline_rendering.jl",
            "test_version_tree_rendering.jl",
            "test_workflow_rendering.jl"
        ]
    ),
    "execution" => Dict(
        "name" => "Execution Tests",
        "path" => "execution",
        "tests" => [
            "test_python_modules.jl",
            "test_python_advanced.jl",
            "test_logging_simple.jl",
            "test_pythoncalc_params.jl",
            "test_port_specs.jl"
        ]
    )
)

"""
    run_test_suite(suite_name::String, suite_config::Dict)

Run a single test suite with progress reporting.
"""
function run_test_suite(suite_name::String, suite_config::Dict)
    println("\n" * "="^70)
    println("📦 $(suite_config["name"])")
    println("="^70)

    suite_path = joinpath(@__DIR__, suite_config["path"])
    test_files = suite_config["tests"]

    # Filter to only existing test files
    existing_tests = filter(test_files) do test_file
        isfile(joinpath(suite_path, test_file))
    end

    if isempty(existing_tests)
        println("⚠️  No test files found in $(suite_path)")
        return Dict{String, Bool}()
    end

    println("Found $(length(existing_tests)) test file(s)\n")

    suite_results = Dict{String, Bool}()

    for (idx, test_file) in enumerate(existing_tests)
        test_path = joinpath(suite_path, test_file)
        test_name = replace(test_file, ".jl" => "")

        print("[$idx/$(length(existing_tests))] Running $test_name... ")
        flush(stdout)

        try
            # Run test as subprocess to avoid module conflicts
            result = run(pipeline(
                `julia --project=. $test_path`,
                stdout=devnull,  # Suppress stdout
                stderr=devnull   # Suppress stderr
            ); wait=true)

            if result.exitcode == 0
                println("✅ PASSED")
                suite_results[test_file] = true
            else
                println("❌ FAILED (exit code: $(result.exitcode))")
                suite_results[test_file] = false
            end

        catch e
            println("❌ ERROR: $e")
            suite_results[test_file] = false
        end
    end

    # Suite summary
    println("\n" * "-"^70)
    passed = count(values(suite_results))
    total = length(suite_results)

    if passed == total
        println("✅ Suite PASSED: $passed/$total tests")
    else
        failed = total - passed
        println("⚠️  Suite INCOMPLETE: $passed passed, $failed failed")

        println("\nFailed tests:")
        for (test, result) in sort(collect(suite_results), by=first)
            if !result
                println("  ❌ $test")
            end
        end
    end

    return suite_results
end

"""
    print_final_summary(all_results::Dict)

Print final summary of all test results.
"""
function print_final_summary(all_results::Dict)
    println("\n" * "="^70)
    println("📊 FINAL SUMMARY")
    println("="^70)

    total_passed = 0
    total_failed = 0

    for (suite_name, suite_results) in sort(collect(all_results), by=first)
        passed = count(values(suite_results))
        failed = length(suite_results) - passed
        total_passed += passed
        total_failed += failed

        status = failed == 0 ? "✅" : "⚠️"
        println("$status $(TEST_SUITES[suite_name]["name"]): $passed/$(passed + failed) passed")
    end

    println("\n" * "-"^70)
    total_tests = total_passed + total_failed

    if total_failed == 0
        println("🎉 ALL TESTS PASSED: $total_tests/$total_tests")
    else
        percentage = round(100 * total_passed / total_tests, digits=1)
        println("📈 OVERALL: $total_passed/$total_tests passed ($percentage%)")
        println("   Failed: $total_failed test file(s)")
    end

    println("="^70)
end

# Main execution
all_results = Dict{String, Dict{String, Bool}}()

if TEST_CATEGORY == "all"
    # Run all test suites
    for (suite_name, suite_config) in sort(collect(TEST_SUITES), by=first)
        results = run_test_suite(suite_name, suite_config)
        if !isempty(results)
            all_results[suite_name] = results
        end
    end

    print_final_summary(all_results)

elseif haskey(TEST_SUITES, TEST_CATEGORY)
    # Run specific test suite
    suite_config = TEST_SUITES[TEST_CATEGORY]
    results = run_test_suite(TEST_CATEGORY, suite_config)

    if !isempty(results)
        passed = count(values(results))
        total = length(results)

        println("\n" * "="^70)
        if passed == total
            println("🎉 ALL TESTS PASSED: $total/$total")
        else
            percentage = round(100 * passed / total, digits=1)
            println("📈 RESULT: $passed/$total passed ($percentage%)")
        end
        println("="^70)
    end

else
    println("❌ Unknown test category: $TEST_CATEGORY")
    println("\nAvailable categories:")
    for (name, config) in sort(collect(TEST_SUITES), by=first)
        println("  - $name: $(config["name"])")
    end
    println("  - all: Run all tests")
    exit(1)
end

# Exit with appropriate code
if TEST_CATEGORY == "all"
    total_failed = sum(length(results) - count(values(results)) for results in values(all_results))
    exit(total_failed > 0 ? 1 : 0)
elseif haskey(TEST_SUITES, TEST_CATEGORY) && haskey(all_results, TEST_CATEGORY)
    results = all_results[TEST_CATEGORY]
    failed = length(results) - count(values(results))
    exit(failed > 0 ? 1 : 0)
end
