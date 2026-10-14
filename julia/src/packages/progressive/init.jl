"""
Progressive Package (org.vistrails.progressive, short name `progressive`)

Modules for the progressive engine (docs/EXECUTION.md):

- sources: `RandomTable`, `CSVLoader`, `ArrowLoader`, `ParquetLoader`; input: `Variable`
- folds over a table: `Count`, `Min`, `Max`, `Mean`, `Var`, `Histogram1D`, `Histogram2D`,
  `Quantiles`, `KLLSketch`, `Histogram1DCategorical`, `Distinct`, `Corr`, `IdxMin`, `IdxMax`
- maps over a table: `Filter`, `Select`
- `Sample`: a random sample of rows, kept up to date (reservoir)
- indexes and queries: `BinningIndex`; `RangeQuery`, `RangeQuery2D`, `SimpleFilter`,
  `CategoricalQuery`, `Intersection` (selection views); `Percentiles`
- element-wise: `Unary`, `ColsBinary`, `Reduce`, `LinearMap`
- grouping and joins: `GroupBy`, `Aggregate`, `Join`, `JoinById`, `Switch`
- `Sink`: consumes its input

They also run in the one-shot engines, as a single unbounded pass.
"""

include("sources.jl")
include("statistics.jl")
include("relational.jl")
include("sampling.jl")
include("indexes.jl")
include("elementwise.jl")
include("grouping.jl")
include("joins.jl")

const PROGRESSIVE_PACKAGE = "org.vistrails.progressive"

function initialize_progressive_package!()
    println("Initializing progressive package...")
    register_progressive_sources!()
    register_progressive_statistics!()
    register_progressive_relational!()
    register_progressive_sampling!()
    register_progressive_indexes!()
    register_progressive_elementwise!()
    register_progressive_grouping!()
    register_progressive_joins!()
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
