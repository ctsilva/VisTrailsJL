using Pkg
Pkg.activate(".")

using VisTrailsJL

println("Testing action replay...")

# Load XML
include("src/db/services/io.jl")
root = load_vt_xml("../examples/gcd.vt")

# Try action replay
try
    pipeline = replay_actions_to_version(root, 134)
    println("✓ Success! Pipeline has $(length(pipeline.modules)) modules and $(length(pipeline.connections)) connections")

    # Show some modules
    for (id, mod) in sort(collect(pipeline.modules), by=first)[1:min(5, length(pipeline.modules))]
        println("  Module $id: $(mod.descriptor.name)")
        if !isempty(mod.parameters)
            for (k, v) in mod.parameters
                println("    $k = $v")
            end
        end
    end
catch e
    println("✗ Error during action replay:")
    showerror(stdout, e, catch_backtrace())
    println()
end
