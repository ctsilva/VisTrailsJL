using VisTrailsJL

println("="^70)
println("Advanced Python Module Tests")
println("="^70)

# Test 1: PythonCalc with different operators
println("\n1. Testing PythonCalc with all operators...")
for (op, v1, v2, expected) in [("+", 5.0, 3.0, 8.0), 
                                  ("-", 10.0, 4.0, 6.0),
                                  ("*", 3.0, 7.0, 21.0),
                                  ("/", 15.0, 3.0, 5.0)]
    pipeline = Pipeline()
    
    a = add_module!(pipeline, "org.vistrails.vistrails.basic", "Float")
    set_parameter!(a, "value", string(v1))
    
    b = add_module!(pipeline, "org.vistrails.vistrails.basic", "Float")
    set_parameter!(b, "value", string(v2))
    
    calc = add_module!(pipeline, "org.vistrails.vistrails.pythoncalc", "PythonCalc")
    set_parameter!(calc, "op", op)
    
    add_connection!(pipeline, a, "value", calc, "value1")
    add_connection!(pipeline, b, "value", calc, "value2")

    results, _ = execute_pipeline(pipeline)
    result = results[calc.id]["value"]
    
    status = abs(result - expected) < 0.0001 ? "✓" : "✗"
    println("  $status $v1 $op $v2 = $result (expected: $expected)")
end

# Test 2: PythonSource with complex computations
println("\n2. Testing PythonSource with complex Python code...")
pipeline2 = Pipeline()

nums = add_module!(pipeline2, "org.vistrails.vistrails.basic", "String")
set_parameter!(nums, "value", "1,2,3,4,5")

py_src = add_module!(pipeline2, "org.vistrails.vistrails.basic", "PythonSource")
set_parameter!(py_src, "source", """
# Parse comma-separated numbers
numbers = [int(x) for x in nums.split(',')]

# Compute statistics
total = sum(numbers)
count = len(numbers)
average = total / count
maximum = max(numbers)
minimum = min(numbers)

# Create result dictionary
stats = {
    'total': total,
    'average': average,
    'max': maximum,
    'min': minimum,
    'count': count
}
""")

add_connection!(pipeline2, nums, "value", py_src, "nums")

results2, _ = execute_pipeline(pipeline2)
if haskey(results2[py_src.id], "stats")
    stats = results2[py_src.id]["stats"]
    println("  Input: 1,2,3,4,5")
    println("  Statistics computed:")
    println("    Total: ", stats["total"])
    println("    Average: ", stats["average"])
    println("    Max: ", stats["max"])
    println("    Min: ", stats["min"])
    println("    Count: ", stats["count"])
    println("  ✓ PythonSource complex computation test passed!")
end

# Test 3: PythonSource with NumPy (if available)
println("\n3. Testing PythonSource with Python libraries...")
pipeline3 = Pipeline()

py_numpy = add_module!(pipeline3, "org.vistrails.vistrails.basic", "PythonSource")
set_parameter!(py_numpy, "source", """
try:
    import numpy as np
    
    # Create array
    arr = np.array([1, 2, 3, 4, 5])
    
    # Compute
    mean_val = float(np.mean(arr))
    std_val = float(np.std(arr))
    
    result = f"NumPy available: mean={mean_val:.2f}, std={std_val:.2f}"
    has_numpy = True
except ImportError:
    result = "NumPy not available (optional)"
    has_numpy = False
""")

results3, _ = execute_pipeline(pipeline3)
if haskey(results3[py_numpy.id], "result")
    println("  ", results3[py_numpy.id]["result"])
    if haskey(results3[py_numpy.id], "has_numpy")
        if results3[py_numpy.id]["has_numpy"]
            println("  ✓ NumPy integration test passed!")
        else
            println("  ℹ NumPy not installed (optional)")
        end
    end
end

println("\n" * "="^70)
println("All advanced Python tests completed!")
println("="^70)
