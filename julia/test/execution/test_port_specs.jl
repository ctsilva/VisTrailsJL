# Load VisTrailsJL module
include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

vt = load_vistrail(joinpath(@__DIR__, "..", "..", "..", "examples", "gcd.vt"))
p = vt.pipelines[vt.current_version]

println("\nModule Port Counts (from parsed portSpecs):")
println("=" ^ 70)

for (id, mod) in sort(collect(p.modules), by=x->x[1])
    input_specs = filter(ps -> ps.port_type == :input, mod.port_specs)
    output_specs = filter(ps -> ps.port_type == :output, mod.port_specs)

    if !isempty(input_specs) || !isempty(output_specs)
        label = get(mod.annotations, "__desc__", mod.descriptor.name)
        println("  Module $id ($label): $(length(input_specs)) inputs, $(length(output_specs)) outputs")

        if !isempty(input_specs)
            for spec in sort(input_specs, by=s->s.sort_key)
                println("    Input: $(spec.name) (sort_key=$(spec.sort_key))")
            end
        end

        if !isempty(output_specs)
            for spec in sort(output_specs, by=s->s.sort_key)
                println("    Output: $(spec.name) (sort_key=$(spec.sort_key))")
            end
        end
    end
end
