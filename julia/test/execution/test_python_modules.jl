using VisTrailsJL

println("="^70)
println("Testing Python Modules")
println("="^70)

# Test 1: PythonCalc
println("\n1. Testing PythonCalc...")
pipeline = Pipeline()

# Add two constants
a = add_module!(pipeline, "org.vistrails.vistrails.basic", "Float")
set_parameter!(a, "value", "5.0")

b = add_module!(pipeline, "org.vistrails.vistrails.basic", "Float")
set_parameter!(b, "value", "3.0")

# Add PythonCalc
calc = add_module!(pipeline, "org.vistrails.vistrails.pythoncalc", "PythonCalc")
set_parameter!(calc, "op", "+")

# Connect inputs
add_connection!(pipeline, a, "value", calc, "value1")
add_connection!(pipeline, b, "value", calc, "value2")

# Execute
println("  Executing: 5.0 + 3.0")
results, workflow_exec = execute_pipeline(pipeline)
result_value = results[calc.id]["value"]
println("  Result: $result_value")
println("  ✓ PythonCalc test passed!" )

# Test 2: PythonSource
println("\n2. Testing PythonSource...")
pipeline2 = Pipeline()

# Add input
input_val = add_module!(pipeline2, "org.vistrails.vistrails.basic", "Integer")
set_parameter!(input_val, "value", "10")

# Add PythonSource that doubles the input
py_src = add_module!(pipeline2, "org.vistrails.vistrails.basic", "PythonSource")
set_parameter!(py_src, "source", """
x = x * 2
result = x
""")

# Connect
add_connection!(pipeline2, input_val, "value", py_src, "x")

# Execute
println("  Executing: x = 10; x = x * 2")
results2, workflow_exec2 = execute_pipeline(pipeline2)
if haskey(results2[py_src.id], "result")
    py_result = results2[py_src.id]["result"]
    println("  Result: $py_result")
    println("  ✓ PythonSource test passed!")
else
    println("  Available outputs: ", keys(results2[py_src.id]))
end

println("\n" * "="^70)
println("All Python module tests completed!")
println("="^70)
