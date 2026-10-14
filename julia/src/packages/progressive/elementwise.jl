"""
Element-wise operations, after ProgressiVis' `linalg` modules

ProgressiVis generates one module class per NumPy function (`Absolute`,
`Add`, `ColsAdd`, `AddReduce`, ...); here one module per kind takes the
function by name:

- `Unary`: `function` applied to each value of `columns` (maps rows);
- `ColsBinary`: `function` of two columns of a row, pairwise for the
  columns in `first` and `second`, into `cols_out`;
- `Reduce`: a per-column reduction with an associative `function` (fold);
- `LinearMap`: each row of `columns` (a vector of length k) times the k × m
  matrix of the table on input `transformation`; rows wait until it has k
  rows, and a change in it remaps every row.

Function names come from `ELEMENTWISE_UNARY` and `ELEMENTWISE_BINARY`;
`register_elementwise!(name, f; binary=false)` adds one.
"""

const ELEMENTWISE_UNARY = Dict{String, Function}(
    "abs" => abs, "negative" => -, "sign" => sign, "sqrt" => sqrt, "cbrt" => cbrt, "square" => abs2,
    "reciprocal" => inv, "exp" => exp, "exp2" => exp2, "expm1" => expm1, "log" => log, "log2" => log2,
    "log10" => log10, "log1p" => log1p, "sin" => sin, "cos" => cos, "tan" => tan, "asin" => asin,
    "acos" => acos, "atan" => atan, "sinh" => sinh, "cosh" => cosh, "tanh" => tanh, "asinh" => asinh,
    "acosh" => acosh, "atanh" => atanh, "deg2rad" => deg2rad, "rad2deg" => rad2deg, "floor" => floor,
    "ceil" => ceil, "round" => round, "trunc" => trunc, "isnan" => isnan, "isfinite" => isfinite,
    "isinf" => isinf, "not" => !)

const ELEMENTWISE_BINARY = Dict{String, Function}(
    "+" => +, "add" => +, "-" => -, "subtract" => -, "*" => *, "multiply" => *, "/" => /,
    "divide" => /, "^" => ^, "power" => ^, "min" => min, "minimum" => min, "max" => max,
    "maximum" => max, "hypot" => hypot, "atan2" => atan, "mod" => mod, "rem" => rem, "div" => div,
    "==" => ==, "!=" => !=, "<" => <, "<=" => <=, ">" => >, ">=" => >=, "&" => &, "|" => |, "xor" => xor)

# Associative operations, for Reduce (results do not depend on step sizes)
const ELEMENTWISE_ASSOCIATIVE = Set(["+", "add", "*", "multiply", "min", "minimum", "max", "maximum",
                                     "&", "|", "xor"])

"""
    register_elementwise!(name, f; binary=false, associative=false)

Make `f` available to `Unary` (or, `binary`, to `ColsBinary` and, if
`associative`, `Reduce`) under `name`.
"""
function register_elementwise!(name::String, f::Function; binary::Bool=false, associative::Bool=false)
    (binary ? ELEMENTWISE_BINARY : ELEMENTWISE_UNARY)[name] = f
    associative && push!(ELEMENTWISE_ASSOCIATIVE, name)
    return f
end

function elementwise_function(ctx, table::Dict{String, Function})
    name = String(required_param(ctx, "function"))
    haskey(table, name) || error("$(ctx.mod.descriptor.name): unknown function '$name' " *
                                 "(known: $(join(sort(collect(keys(table))), ", ")))")
    return table[name]
end

# Output element type of f on the input types (Float64 if not concrete)
result_type(f, types...) = (T = Base.promote_op(f, types...); isconcretetype(T) ? T : Float64)

unary_columns(ctx, t) = numeric_columns(ctx, t)

# The same columns, from a chunk of all the input's columns
chunk_columns(ctx, chunk) = param(ctx, "columns") === nothing ?
    [c for c in keys(chunk) if eltype(chunk[c]) <: Real] : as_symbols(param(ctx, "columns"))

binary_operands(ctx) = (as_symbols(required_param(ctx, "first")), as_symbols(required_param(ctx, "second")))

function binary_outputs(ctx)
    first, second = binary_operands(ctx)
    length(first) == length(second) || error("ColsBinary: 'first' and 'second' must have the same length")
    out = param(ctx, "cols_out")
    out = out === nothing ? first : as_symbols(out)
    length(out) == length(first) || error("ColsBinary: 'cols_out' must have one name per pair")
    return first, second, out
end

# Function barrier: the function is a runtime value
apply_unary(f, v) = f.(v)
apply_binary(f, a, b) = f.(a, b)

# LinearMap: the transformation matrix (k × m) from its table, once complete
function transformation_matrix(ctx)
    t = input_container(ctx, "transformation")
    cols = param(ctx, "transformation_columns")
    names = cols === nothing ? [n for n in column_names(t) if eltype(column(t, n)) <: Real] : as_symbols(cols)
    ids = row_ids(t)
    return reduce(hcat, [Float64.(t[ids, n]) for n in names]; init=zeros(length(ids), 0)), names
end

linear_columns(ctx) = (t = input_container(ctx, "vectors"); numeric_columns(ctx, t))

function register_progressive_elementwise!()
    P = PROGRESSIVE_PACKAGE

    define_map_module!(P, "Unary";
        schema=(ctx, t) -> (f = elementwise_function(ctx, ELEMENTWISE_UNARY);
                            [c => result_type(f, eltype(column(t, c))) for c in unary_columns(ctx, t)]),
        map=(chunk, ctx) -> (f = elementwise_function(ctx, ELEMENTWISE_UNARY);
                             cols = Tuple(chunk_columns(ctx, chunk));
                             NamedTuple{cols}(Tuple(apply_unary(f, chunk[c]) for c in cols))),
        parameters=[("function", String), ("columns", Vector{String})])

    define_map_module!(P, "ColsBinary";
        schema=function (ctx, t)
            f = elementwise_function(ctx, ELEMENTWISE_BINARY)
            first, second, out = binary_outputs(ctx)
            [o => result_type(f, eltype(column(t, a)), eltype(column(t, b))) for (a, b, o) in zip(first, second, out)]
        end,
        map=function (chunk, ctx)
            f = elementwise_function(ctx, ELEMENTWISE_BINARY)
            first, second, out = binary_outputs(ctx)
            NamedTuple{Tuple(out)}(Tuple(apply_binary(f, chunk[a], chunk[b]) for (a, b) in zip(first, second)))
        end,
        parameters=[("function", String), ("first", Vector{String}), ("second", Vector{String}),
                    ("cols_out", Vector{String})])

    define_fold_module!(P, "Reduce";
        init=(ctx, cols) -> ReduceAcc(reduce_function(ctx), Dict{Symbol, Any}(c => nothing for c in cols)),
        update=(acc, chunk, ctx) -> (foreach(c -> isempty(chunk[c]) ||
                                                 (acc.values[c] = combine_reduced(acc.f, acc.values[c], reduce(acc.f, chunk[c]))),
                                             keys(chunk)); acc),
        merge=(a, b) -> (foreach(c -> a.values[c] = combine_reduced(a.f, a.values[c], b.values[c]), keys(b.values)); a),
        result=(acc, ctx) -> Dict(c => v for (c, v) in acc.values if v !== nothing),
        parameters=[("function", String), ("columns", Vector{String})])

    define_map_module!(P, "LinearMap";
        input="vectors", extra_inputs=["transformation"],
        schema=(ctx, t) -> [n => Float64 for n in transformation_names(ctx)],
        ready=ctx -> (t = input_container(ctx, "transformation"); length(t) >= length(linear_columns(ctx))),
        map=function (chunk, ctx)
            M, names = transformation_matrix(ctx)
            k = length(linear_columns(ctx))
            size(M, 1) == k || error("LinearMap: the transformation has $(size(M, 1)) rows, expected $k (one per vector column)")
            X = reduce(hcat, [Float64.(chunk[c]) for c in linear_columns(ctx)])
            Y = X * M
            NamedTuple{Tuple(names)}(Tuple(Y[:, j] for j in eachindex(names)))
        end,
        parameters=[("columns", Vector{String}), ("transformation_columns", Vector{String})])
end

function reduce_function(ctx)
    name = String(required_param(ctx, "function"))
    name in ELEMENTWISE_ASSOCIATIVE || error("Reduce: '$name' is not a known associative function " *
                                             "(known: $(join(sort(collect(ELEMENTWISE_ASSOCIATIVE)), ", ")))")
    return ELEMENTWISE_BINARY[name]
end

struct ReduceAcc
    f::Function
    values::Dict{Symbol, Any}
end

combine_reduced(f, a, b) = a === nothing ? b : b === nothing ? a : f(a, b)

# The output columns' names: the transformation's (numeric) columns, known
# before its rows arrive
function transformation_names(ctx)
    t = input_container(ctx, "transformation")
    cols = param(ctx, "transformation_columns")
    return cols === nothing ? [n for n in column_names(t) if eltype(column(t, n)) <: Real] : as_symbols(cols)
end
