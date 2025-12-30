"""
Analyze the example .vt files in examples/api/
"""

include("../src/VisTrailsJL.jl")
using .VisTrailsJL

files = [
    "../../examples/api/simplemath.vt",
    "../../examples/api/outputs.vt",
    "../../examples/api/imagemagick.vt",
    "../../examples/api/brain_output.xml",
    "../../examples/api/out_html.xml",
    "../../examples/api/table.xml"
]

for filepath in files
    if !isfile(filepath)
        println("⚠ File not found: $filepath")
        continue
    end

    println("\n" * "="^70)
    println("📄 ", basename(filepath))
    println("="^70)

    try
        vt = load_vistrail_internal(filepath)

        println("Name: ", vt.name)
        println("Versions: ", length(vt.actions))
        println("Tags: ", length(vt.tags), " - ", [t.name for t in vt.tags])

        if !isempty(vt.pipelines)
            ver = first(keys(vt.pipelines))
            pipeline = vt.pipelines[ver]
            println("\nPipeline (v$ver):")
            println("  Modules: ", length(pipeline.modules))
            println("  Connections: ", length(pipeline.connections))

            # Show module types
            module_types = Dict{String, Int}()
            for (id, mod) in pipeline.modules
                name = mod.descriptor.name
                module_types[name] = get(module_types, name, 0) + 1
            end

            println("\n  Module types:")
            for (name, count) in sort(collect(module_types), by=x->x[1])
                println("    • $name: $count")
            end

            # Show InputPort and OutputPort modules
            inputs = []
            outputs = []
            for (id, mod) in pipeline.modules
                if mod.descriptor.name == "InputPort"
                    if haskey(mod.parameters, "name")
                        push!(inputs, mod.parameters["name"])
                    end
                elseif mod.descriptor.name == "OutputPort"
                    if haskey(mod.parameters, "name")
                        push!(outputs, mod.parameters["name"])
                    end
                end
            end

            if !isempty(inputs)
                println("\n  Input Ports: ", join(inputs, ", "))
            end
            if !isempty(outputs)
                println("  Output Ports: ", join(outputs, ", "))
            end
        else
            println("\n⚠ No pipelines loaded (action replay needed)")
        end

    catch e
        println("❌ Error loading file: ", e)
    end
end

println("\n" * "="^70)
println("Analysis complete!")
println("="^70)
