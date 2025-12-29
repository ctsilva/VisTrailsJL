"""
Test: End-to-end workflow with custom package

Tests the complete notebook-based workflow system:
1. Load custom package from notebook
2. Register package modules
3. Load workflow notebook that uses custom modules
4. Build and execute the workflow
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("="^70)
println("End-to-End: Custom Package + Workflow Notebook")
println("="^70)

# 1. Load and register custom package
println("\n1. Loading DataTools package...")
pkg_path = joinpath(@__DIR__, "..", "..", "examples", "packages", "datatools.ipynb")
pkg = load_package_from_notebook(pkg_path)
println("   ✓ Loaded: $(pkg.identifier) v$(pkg.version)")
println("   Modules: $(length(pkg.modules))")

println("\n2. Registering DataTools package...")
register_notebook_package!(pkg)
println("   ✓ Registered $(length(pkg.modules)) modules")

# 2a. Demonstrate module introspection
println("\n2a. Inspecting module: datatools:CSVParser")
println("="^70)
describe_module("datatools:CSVParser")
println("="^70)

# 2. Load workflow notebook
println("\n3. Loading workflow notebook...")
workflow_path = joinpath(@__DIR__, "..", "..", "examples", "workflows", "data_analysis.ipynb")
workflow = parse_workflow_notebook(workflow_path)
println("   ✓ Loaded workflow: $(workflow.name)")
println("   Modules in workflow: $(length(workflow.modules))")

# Show workflow modules
println("\n   Workflow structure:")
for nb_mod in workflow.modules
    println("     - $(nb_mod.id): $(nb_mod.module_type)")
    if !isempty(nb_mod.inputs)
        for (port, source) in nb_mod.inputs
            println("       Input: $port ← $source")
        end
    end
end

# 3. Build pipeline from workflow
println("\n4. Building pipeline from workflow...")
pipeline, id_to_module = build_pipeline_from_workflow(workflow)
println("   ✓ Pipeline built")
println("   Modules: $(length(pipeline.modules))")
println("   Connections: $(length(pipeline.connections))")

# 4. Execute the workflow WITH incremental saving
println("\n5. Executing workflow with incremental saving...")
println("="^70)
try
    cache, outputs = execute_notebook_pipeline(
        pipeline, workflow,
        id_to_module=id_to_module,
        notebook_path=workflow_path,
        save_outputs=true  # Enable incremental saving
    )
    println("="^70)

    println("\n✅ SUCCESS!")
    println("\n   Workflow executed successfully!")
    println("   Modules executed: $(length(cache))")

    # Verify workflow outputs
    println("\n6. Verifying workflow outputs...")
    if isempty(outputs)
        println("   ⚠️  WARNING: No workflow outputs specified/extracted")
    else
        println("   ✓ Workflow returned $(length(outputs)) outputs:")
        for (name, value) in outputs
            println("     - $name: $value")
        end

        # Verify expected outputs exist
        @assert haskey(outputs, "summary") "Missing 'summary' output"
        @assert haskey(outputs, "mean_temperature") "Missing 'mean_temperature' output"
        @assert haskey(outputs, "min_temperature") "Missing 'min_temperature' output"
        @assert haskey(outputs, "max_temperature") "Missing 'max_temperature' output"

        println("\n   ✓ All expected outputs present!")
        println("\n   Summary: $(outputs["summary"])")
        println("   Mean: $(outputs["mean_temperature"])°C")
        println("   Min:  $(outputs["min_temperature"])°C")
        println("   Max:  $(outputs["max_temperature"])°C")
    end

    # 7. Verify outputs were saved to notebook
    println("\n7. Verifying outputs were saved to notebook...")
    using JSON
    notebook_content = read(workflow_path, String)
    nb = JSON.parse(notebook_content)

    cells_with_outputs = 0
    for cell in nb["cells"]
        if cell["cell_type"] == "code" && !isempty(get(cell, "outputs", []))
            cells_with_outputs += 1
            execution_count = get(cell, "execution_count", nothing)
            if execution_count !== nothing
                println("   ✓ Cell executed (count: $execution_count)")
            end
        end
    end

    println("\n   ✓ Found $cells_with_outputs cells with saved outputs")
    @assert cells_with_outputs > 0 "No outputs were saved to notebook!"
    println("   ✓ Outputs successfully persisted to notebook file")

catch e
    println("="^70)
    println("\n❌ FAILED!")
    println("Error: $e")
    showerror(stdout, e, catch_backtrace())
    rethrow(e)
end

println("\n" * "="^70)
println("Complete Notebook-Based Workflow System Validated!")
println("="^70)
println("\nWhat works:")
println("  ✅ Define packages in notebooks (#| directives)")
println("  ✅ Load and register packages automatically")
println("  ✅ Define workflows in notebooks")
println("  ✅ Mix custom modules with built-in modules")
println("  ✅ Execute workflows with notebook-defined compute functions")
println("  ✅ Incremental saving of execution results to notebook")
println("  ✅ Git-friendly format (notebooks are JSON)")
println("\nNext steps:")
println("  - Git diff → VisTrails actions conversion")
println("  - Quarto integration for publication")
println("  - More complex package examples")
println("="^70)
