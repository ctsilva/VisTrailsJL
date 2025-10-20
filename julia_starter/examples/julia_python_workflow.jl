#!/usr/bin/env julia
"""
Mixed Julia/Python Workflow Example

Demonstrates a workflow that uses both Julia and Python modules together.
This example:
1. Generates data in Julia
2. Processes it with Python (statistics)
3. Does further computation in Julia
4. Uses PythonCalc for final calculation
"""

using VisTrailsJL

println("="^70)
println("Mixed Julia/Python Workflow Example")
println("="^70)

# Create pipeline
pipeline = Pipeline()

# Step 1: Generate data in Julia
println("\n1. Generating data with JuliaSource...")
julia_gen = add_module!(pipeline, "org.vistrails.vistrails.julia", "JuliaSource")
set_parameter!(julia_gen, "source", """
# Generate some data
data = [1.5, 2.3, 4.7, 3.2, 5.1]
set_output("data", data)
set_output("description", "Random measurements")
""")

# Step 2: Process with Python
println("2. Processing with PythonSource...")
py_stats = add_module!(pipeline, "org.vistrails.vistrails.basic", "PythonSource")
set_parameter!(py_stats, "source", """
import statistics

# Compute statistics
mean_val = statistics.mean(data)
median_val = statistics.median(data)
stdev_val = statistics.stdev(data)

# Output
summary = f"Data: {description}\\nMean: {mean_val:.2f}, Median: {median_val:.2f}, StdDev: {stdev_val:.2f}"
""")

add_connection!(pipeline, julia_gen, "data", py_stats, "data")
add_connection!(pipeline, julia_gen, "description", py_stats, "description")

# Step 3: Further processing in Julia
println("3. Additional computation with JuliaSource...")
julia_proc = add_module!(pipeline, "org.vistrails.vistrails.julia", "JuliaSource")
set_parameter!(julia_proc, "source", """
# Get Python's mean and add 10%
adjusted = mean_val * 1.10
set_output("adjusted_mean", adjusted)
""")

add_connection!(pipeline, py_stats, "mean_val", julia_proc, "mean_val")

# Step 4: Use PythonCalc for final calculation
println("4. Final calculation with PythonCalc...")
const_val = add_module!(pipeline, "org.vistrails.vistrails.basic", "Float")
set_parameter!(const_val, "value", "2.0")

calc = add_module!(pipeline, "org.vistrails.vistrails.pythoncalc", "PythonCalc")
set_parameter!(calc, "op", "*")

add_connection!(pipeline, julia_proc, "adjusted_mean", calc, "value1")
add_connection!(pipeline, const_val, "value", calc, "value2")

# Execute the entire pipeline
println("\n" * "="^70)
println("Executing Mixed Julia/Python Pipeline")
println("="^70)

results = execute_pipeline(pipeline)

# Display results
println("\nResults:")
println("-"^70)
println("From JuliaSource:")
println("  Data: ", results[julia_gen.id]["data"])
println("  Description: ", results[julia_gen.id]["description"])

println("\nFrom PythonSource:")
println("  ", results[py_stats.id]["summary"])
println("  Mean: ", results[py_stats.id]["mean_val"])
println("  Median: ", results[py_stats.id]["median_val"])  
println("  StdDev: ", results[py_stats.id]["stdev_val"])

println("\nFrom JuliaSource (processing):")
println("  Adjusted Mean (+10%): ", results[julia_proc.id]["adjusted_mean"])

println("\nFrom PythonCalc:")
println("  Final Result (×2): ", results[calc.id]["value"])

println("\n" * "="^70)
println("✓ Mixed Julia/Python workflow completed successfully!")
println("="^70)
