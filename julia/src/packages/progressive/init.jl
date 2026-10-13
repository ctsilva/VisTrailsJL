"""
Progressive Package (org.vistrails.progressive, short name `progressive`)

Modules for the progressive engine (docs/EXECUTION.md):

- sources: `RandomTable`, `CSVLoader`
- folds over a table: `Count`, `Min`, `Max`, `Mean`, `Var`, `Histogram1D`, `Histogram2D`
- maps over a table: `Filter`, `Select`
- `Sink`: consumes its input

They also run in the one-shot engines, as a single unbounded pass.
"""

include("sources.jl")
include("statistics.jl")
include("relational.jl")

const PROGRESSIVE_PACKAGE = "org.vistrails.progressive"

function initialize_progressive_package!()
    println("Initializing progressive package...")
    register_progressive_sources!()
    register_progressive_statistics!()
    register_progressive_relational!()
    register_package_short_name!("progressive", PROGRESSIVE_PACKAGE)
    println("  ✓ Progressive package initialized")
end

# Parameter conversion (values from notebooks or .vt files may be strings)
as_int(x) = x isa AbstractString ? parse(Int, x) : Int(x)
as_float(x) = x isa AbstractString ? parse(Float64, x) : Float64(x)
as_symbols(x) = Symbol.(x isa AbstractVector ? x : [x])

function required_param(ctx::StepContext, name::String)
    v = param(ctx, name)
    v === nothing && error("$(ctx.mod.descriptor.name): parameter '$name' is required")
    return v
end
