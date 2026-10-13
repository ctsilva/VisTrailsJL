"""
Progressive relational operators, defined as maps (`define_map_module!`)

- `Filter`: keeps the rows where `column op value` holds
  (`op` one of "<", "<=", ">", ">=", "==", "!=")
- `Select`: keeps the columns listed in `columns`
"""

const FILTER_OPS = Dict("<" => <, "<=" => <=, ">" => >, ">=" => >=, "==" => ==, "!=" => !=)

function filter_predicate(ctx::StepContext)
    op = String(param(ctx, "op", "<"))
    haskey(FILTER_OPS, op) || error("Filter: unknown op '$op' (use one of $(join(keys(FILTER_OPS), ", ")))")
    threshold = param(ctx, "value")
    threshold === nothing && error("Filter: parameter 'value' is required")
    threshold = threshold isa AbstractString ? something(tryparse(Float64, threshold), threshold) : threshold
    return FILTER_OPS[op], threshold
end

function register_progressive_relational!()
    P = PROGRESSIVE_PACKAGE

    define_map_module!(P, "Filter";
        map=function (chunk, ctx)
            op, threshold = filter_predicate(ctx)
            values = chunk[Symbol(required_param(ctx, "column"))]
            merge(chunk, (_keep=[op(v, threshold) for v in values],))
        end,
        parameters=[("column", String), ("op", String), ("value", Any)])

    define_map_module!(P, "Select";
        schema=(ctx, t) -> [c => eltype(column(t, c)) for c in as_symbols(required_param(ctx, "columns"))],
        map=(chunk, ctx) -> NamedTuple{Tuple(as_symbols(required_param(ctx, "columns")))}(chunk),
        parameters=[("columns", Vector{String})])
end
