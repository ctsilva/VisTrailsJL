"""
Progressive statistics, defined as folds (`define_fold_module!`)

Count, Min, Max, Mean and Var publish one value per column in a
`ProgressiveDict` (`columns` parameter: default, every numeric column).
Mean and Var use Chan et al.'s pairwise merge of (count, mean, M2), so a
chunk's statistics are computed in one pass and merged exactly.
Histogram1D and Histogram2D publish counts in a `ProgressiveValue`; values
outside [min, max] are not counted.
"""

# (count, mean, sum of squared deviations) of a chunk, and their merge
function moments(v::AbstractVector)
    n = length(v)
    n == 0 && return (0, 0.0, 0.0)
    m = sum(v) / n
    return (n, m, sum(x -> (x - m)^2, v))
end

function merge_moments(a, b)
    na, ma, sa = a
    nb, mb, sb = b
    n = na + nb
    n == 0 && return (0, 0.0, 0.0)
    delta = mb - ma
    return (n, ma + delta * nb / n, sa + sb + delta^2 * na * nb / n)
end

per_column(f, columns) = Dict{Symbol, Any}(c => f(c) for c in columns)

function histogram_bin(x, lo, hi, bins)
    (lo <= x <= hi) || return 0
    return x == hi ? bins : floor(Int, (x - lo) / (hi - lo) * bins) + 1
end

function register_progressive_statistics!()
    P = PROGRESSIVE_PACKAGE

    define_fold_module!(P, "Count";
        columns=(ctx, t) -> Symbol[first(column_names(t))],
        init=(ctx, cols) -> 0,
        update=(n, chunk, ctx) -> n + length(first(chunk)),
        result=(n, ctx) -> n,
        output=:value, output_type=Int)

    define_fold_module!(P, "Min";
        init=(ctx, cols) -> per_column(c -> Inf, cols),
        update=(acc, chunk, ctx) -> (foreach(c -> acc[c] = min(acc[c], minimum(chunk[c])), keys(chunk)); acc),
        result=(acc, ctx) -> acc,
        parameters=[("columns", Vector{String})])

    define_fold_module!(P, "Max";
        init=(ctx, cols) -> per_column(c -> -Inf, cols),
        update=(acc, chunk, ctx) -> (foreach(c -> acc[c] = max(acc[c], maximum(chunk[c])), keys(chunk)); acc),
        result=(acc, ctx) -> acc,
        parameters=[("columns", Vector{String})])

    moments_update = (acc, chunk, ctx) ->
        (foreach(c -> acc[c] = merge_moments(acc[c], moments(chunk[c])), keys(chunk)); acc)

    define_fold_module!(P, "Mean";
        init=(ctx, cols) -> per_column(c -> (0, 0.0, 0.0), cols),
        update=moments_update,
        result=(acc, ctx) -> Dict(c => m[2] for (c, m) in acc if m[1] > 0),
        parameters=[("columns", Vector{String})])

    define_fold_module!(P, "Var";
        init=(ctx, cols) -> per_column(c -> (0, 0.0, 0.0), cols),
        update=moments_update,
        result=(acc, ctx) -> Dict(c => m[3] / (m[1] - 1) for (c, m) in acc if m[1] > 1),
        parameters=[("columns", Vector{String})])

    define_fold_module!(P, "Histogram1D";
        columns=(ctx, t) -> [Symbol(required_param(ctx, "column"))],
        init=(ctx, cols) -> zeros(Int, as_int(param(ctx, "bins", 64))),
        update=function (counts, chunk, ctx)
            lo, hi = as_float(required_param(ctx, "min")), as_float(required_param(ctx, "max"))
            bins = length(counts)
            for x in first(chunk)
                b = histogram_bin(x, lo, hi, bins)
                b > 0 && (counts[b] += 1)
            end
            counts
        end,
        result=(counts, ctx) -> copy(counts),
        output=:value, output_type=Vector{Int},
        parameters=[("column", String), ("bins", Int), ("min", Float64), ("max", Float64)])

    define_fold_module!(P, "Histogram2D";
        columns=(ctx, t) -> Symbol.([required_param(ctx, "x_column"), required_param(ctx, "y_column")]),
        init=(ctx, cols) -> zeros(Int, as_int(param(ctx, "xbins", 64)), as_int(param(ctx, "ybins", 64))),
        update=function (counts, chunk, ctx)
            xlo, xhi = as_float(required_param(ctx, "xmin")), as_float(required_param(ctx, "xmax"))
            ylo, yhi = as_float(required_param(ctx, "ymin")), as_float(required_param(ctx, "ymax"))
            xs, ys = chunk[1], chunk[2]
            for i in eachindex(xs, ys)
                bx = histogram_bin(xs[i], xlo, xhi, size(counts, 1))
                by = histogram_bin(ys[i], ylo, yhi, size(counts, 2))
                (bx > 0 && by > 0) && (counts[bx, by] += 1)
            end
            counts
        end,
        result=(counts, ctx) -> copy(counts),
        output=:value, output_type=Matrix{Int},
        parameters=[("x_column", String), ("y_column", String), ("xbins", Int), ("ybins", Int),
                    ("xmin", Float64), ("xmax", Float64), ("ymin", Float64), ("ymax", Float64)])
end
