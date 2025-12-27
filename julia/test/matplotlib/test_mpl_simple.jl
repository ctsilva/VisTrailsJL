"""
Simple test of matplotlib package functionality

Tests basic JuliaSource → MplLinePlot → MplFigure → MplFigureOutput workflow
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("="^70)
println("Testing Matplotlib Package - Simple Line Plot")
println("="^70)

# Create a simple pipeline manually
println("\n1. Creating pipeline...")
pipeline = Pipeline()

# Add JuliaSource to generate Y data
println("2. Adding JuliaSource for Y data...")
ysource = add_module!(pipeline, "org.vistrails.vistrails.julia", "JuliaSource")
set_parameter!(ysource, "source", "set_output(\"value\", [1.0, 4.0, 2.0, 3.0, 5.0])")
println("   ✓ JuliaSource added (id=$(ysource.id))")

# Add MplLinePlot module
println("3. Adding MplLinePlot module...")
lineplot = add_module!(pipeline, "org.vistrails.vistrails.matplotlib", "MplLinePlot")
println("   ✓ MplLinePlot added (id=$(lineplot.id))")

# Add MplFigure module
println("4. Adding MplFigure module...")
figure = add_module!(pipeline, "org.vistrails.vistrails.matplotlib", "MplFigure")
println("   ✓ MplFigure added (id=$(figure.id))")

# Add MplFigureOutput module
println("5. Adding MplFigureOutput module...")
output = add_module!(pipeline, "org.vistrails.vistrails.matplotlib", "MplFigureOutput")
println("   ✓ MplFigureOutput added (id=$(output.id))")

# Connect ysource → lineplot.y
println("6. Connecting modules...")
add_connection!(pipeline, ysource.id, "value", lineplot.id, "y")
println("   ✓ Connected YSource.value → MplLinePlot.y")

# Connect lineplot → figure
add_connection!(pipeline, lineplot_id, "value", figure_id, "addPlot")
println("   ✓ Connected MplLinePlot.value → MplFigure.addPlot")

# Connect figure → output
add_connection!(pipeline, figure_id, "figure", output_id, "value")
println("   ✓ Connected MplFigure.figure → MplFigureOutput.value")

println("\n7. Pipeline structure:")
println("   Modules: $(length(pipeline.modules))")
println("   Connections: $(length(pipeline.connections))")

# Execute pipeline
println("\n8. Executing pipeline...")
try
    results, workflow_exec = execute_pipeline(pipeline)
    println("   ✓ Pipeline executed successfully!")

    # Check if output file was created
    if isfile("matplotlib_output.png")
        println("\n✅ SUCCESS: Matplotlib figure saved to matplotlib_output.png")
        println("   File size: $(filesize("matplotlib_output.png")) bytes")
    else
        println("\n⚠️  WARNING: Output file not found")
    end

catch e
    println("\n❌ ERROR: Pipeline execution failed")
    println("   Error: $e")
    showerror(stdout, e, catch_backtrace())
    rethrow(e)
end

println("\n" * "="^70)
println("Test complete!")
println("="^70)
