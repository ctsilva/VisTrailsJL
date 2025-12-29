"""
Analyze matplotlib example .vt files to determine what modules they use
"""

using VisTrailsJL

function analyze_vt_file(filepath::String)
    println("\n" * "="^80)
    println("Analyzing: $filepath")
    println("="^80)

    # Load the vistrail
    vt = load_vistrail(filepath)

    # Get the current version
    current_version = vt.current_version
    println("\nCurrent version: $current_version")

    # Get the pipeline for the current version
    pipeline = get_pipeline(vt, current_version)

    if pipeline === nothing
        println("ERROR: Could not get pipeline for version $current_version")
        return
    end

    println("\nModules in pipeline:")
    println("-" * "="^79)

    # Track unique module types
    module_types = Set{String}()

    # Analyze each module
    for (id, mod) in pipeline.modules
        module_type = mod.descriptor.name
        package = mod.descriptor.package
        push!(module_types, module_type)

        println("\nModule ID: $id")
        println("  Type: $module_type")
        println("  Package: $package")

        # Print parameters
        if !isempty(mod.parameters)
            println("  Parameters:")
            for (param_name, param_value) in mod.parameters
                # Truncate long values
                value_str = string(param_value)
                if length(value_str) > 60
                    value_str = value_str[1:57] * "..."
                end
                println("    $param_name = $value_str")
            end
        end

        # Print input/output ports
        if !isempty(mod.inputs)
            println("  Inputs: $(keys(mod.inputs))")
        end
        if !isempty(mod.outputs)
            println("  Outputs: $(keys(mod.outputs))")
        end
    end

    # Print connections
    println("\n\nConnections:")
    println("-" * "="^79)
    for conn in pipeline.connections
        src_mod = get(pipeline.modules, conn.source_module_id, nothing)
        dst_mod = get(pipeline.modules, conn.dest_module_id, nothing)

        src_type = src_mod !== nothing ? src_mod.descriptor.name : "?"
        dst_type = dst_mod !== nothing ? dst_mod.descriptor.name : "?"

        println("  $(conn.source_module_id) ($src_type).$(conn.source_port)")
        println("    → $(conn.dest_module_id) ($dst_type).$(conn.dest_port)")
    end

    # Summary
    println("\n\nSummary:")
    println("-" * "="^79)
    println("  Total modules: $(length(pipeline.modules))")
    println("  Total connections: $(length(pipeline.connections))")
    println("  Unique module types: $(length(module_types))")
    println("\n  Module types used:")
    for mtype in sort(collect(module_types))
        println("    - $mtype")
    end
end

# Analyze all three files
files = [
    "/Users/csilva/github-ctsilva/VisTrailsJL/examples/matplotlib/bar_ex1.vt",
    "/Users/csilva/github-ctsilva/VisTrailsJL/examples/matplotlib/hist_ex1.vt",
    "/Users/csilva/github-ctsilva/VisTrailsJL/examples/matplotlib/scatter.vt"
]

for file in files
    if isfile(file)
        try
            analyze_vt_file(file)
        catch e
            println("\nERROR analyzing $file:")
            println(e)
            println()
            for (exc, bt) in Base.catch_stack()
                showerror(stdout, exc, bt)
                println()
            end
        end
    else
        println("File not found: $file")
    end
end

println("\n\n" * "="^80)
println("Analysis complete")
println("="^80)
