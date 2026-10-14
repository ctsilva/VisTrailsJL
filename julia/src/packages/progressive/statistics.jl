"""
Progressive statistics, defined as folds (`define_fold_module!`)

Count, Min, Max, Mean and Var publish one value per column in a
`ProgressiveDict` (`columns` parameter: default, every numeric column).
Mean and Var use Chan et al.'s pairwise merge of (count, mean, M2), so a
chunk's statistics are computed in one pass and merged exactly.
Histogram1D and Histogram2D publish counts in a `ProgressiveValue`; values
outside [min, max] are not counted.

After ProgressiVis' `stats` modules, also folds:

- `Quantiles`: KLL sketches (kll.jl) per column; publishes the `quantiles`
  of each column (approximate, rank error ~1.65/k);
- `KLLSketch`: one column's sketch: min, max, quantiles and a histogram
  (`binning`) of approximate fractions;
- `Histogram1DCategorical`: counts of each value of a column (any type);
- `Distinct`: the distinct values of each column, or `nothing` once there
  are more than `threshold`;
- `Corr`: Pearson correlations (or covariances) of every pair of columns,
  by a pairwise merge of co-moments;
- `IdxMin`, `IdxMax`: per column, the row id and value of the minimum
  (maximum); ties go to the first row, NaN is skipped.
"""

include("kll.jl")

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

# Merge two per-column accumulators with `op`
merge_columns(op) = (a, b) -> (foreach(c -> a[c] = op(a[c], b[c]), keys(b)); a)

function histogram_bin(x, lo, hi, bins)
    (lo <= x <= hi) || return 0
    return x == hi ? bins : floor(Int, (x - lo) / (hi - lo) * bins) + 1
end

# Counting loops behind a function barrier: the bounds come from parameters
# (untyped), and the loops must be compiled for concrete types
function count_bins!(counts::Vector{Int}, xs::AbstractVector, lo::Float64, hi::Float64)
    bins = length(counts)
    @inbounds for x in xs
        b = histogram_bin(x, lo, hi, bins)
        b > 0 && (counts[b] += 1)
    end
    return counts
end

function count_bins!(counts::Matrix{Int}, xs::AbstractVector, ys::AbstractVector,
                     xlo::Float64, xhi::Float64, ylo::Float64, yhi::Float64)
    nx, ny = size(counts)
    @inbounds for i in eachindex(xs, ys)
        bx = histogram_bin(xs[i], xlo, xhi, nx)
        by = histogram_bin(ys[i], ylo, yhi, ny)
        (bx > 0 && by > 0) && (counts[bx, by] += 1)
    end
    return counts
end

function register_progressive_statistics!()
    P = PROGRESSIVE_PACKAGE

    define_fold_module!(P, "Count";
        columns=(ctx, t) -> Symbol[first(column_names(t))],
        init=(ctx, cols) -> 0,
        update=(n, chunk, ctx) -> n + length(first(chunk)),
        merge=+,
        result=(n, ctx) -> n,
        output=:value, output_type=Int)

    define_fold_module!(P, "Min";
        init=(ctx, cols) -> per_column(c -> Inf, cols),
        update=(acc, chunk, ctx) -> (foreach(c -> acc[c] = min(acc[c], minimum(chunk[c])), keys(chunk)); acc),
        merge=merge_columns(min),
        result=(acc, ctx) -> acc,
        parameters=[("columns", Vector{String})])

    define_fold_module!(P, "Max";
        init=(ctx, cols) -> per_column(c -> -Inf, cols),
        update=(acc, chunk, ctx) -> (foreach(c -> acc[c] = max(acc[c], maximum(chunk[c])), keys(chunk)); acc),
        merge=merge_columns(max),
        result=(acc, ctx) -> acc,
        parameters=[("columns", Vector{String})])

    moments_update = (acc, chunk, ctx) ->
        (foreach(c -> acc[c] = merge_moments(acc[c], moments(chunk[c])), keys(chunk)); acc)

    define_fold_module!(P, "Mean";
        init=(ctx, cols) -> per_column(c -> (0, 0.0, 0.0), cols),
        update=moments_update,
        merge=merge_columns(merge_moments),
        result=(acc, ctx) -> Dict(c => m[2] for (c, m) in acc if m[1] > 0),
        parameters=[("columns", Vector{String})])

    define_fold_module!(P, "Var";
        init=(ctx, cols) -> per_column(c -> (0, 0.0, 0.0), cols),
        update=moments_update,
        merge=merge_columns(merge_moments),
        result=(acc, ctx) -> Dict(c => m[3] / (m[1] - 1) for (c, m) in acc if m[1] > 1),
        parameters=[("columns", Vector{String})])

    define_fold_module!(P, "Histogram1D";
        columns=(ctx, t) -> [Symbol(required_param(ctx, "column"))],
        init=(ctx, cols) -> zeros(Int, as_int(param(ctx, "bins", 64))),
        update=(counts, chunk, ctx) ->
            count_bins!(counts, first(chunk), as_float(required_param(ctx, "min")), as_float(required_param(ctx, "max"))),
        merge=(a, b) -> (a .+= b),
        result=(counts, ctx) -> copy(counts),
        output=:value, output_type=Vector{Int},
        parameters=[("column", String), ("bins", Int), ("min", Float64), ("max", Float64)])

    define_fold_module!(P, "Histogram2D";
        columns=(ctx, t) -> Symbol.([required_param(ctx, "x_column"), required_param(ctx, "y_column")]),
        init=(ctx, cols) -> zeros(Int, as_int(param(ctx, "xbins", 64)), as_int(param(ctx, "ybins", 64))),
        update=(counts, chunk, ctx) ->
            count_bins!(counts, chunk[1], chunk[2],
                        as_float(required_param(ctx, "xmin")), as_float(required_param(ctx, "xmax")),
                        as_float(required_param(ctx, "ymin")), as_float(required_param(ctx, "ymax"))),
        merge=(a, b) -> (a .+= b),
        result=(counts, ctx) -> copy(counts),
        output=:value, output_type=Matrix{Int},
        parameters=[("x_column", String), ("y_column", String), ("xbins", Int), ("ybins", Int),
                    ("xmin", Float64), ("xmax", Float64), ("ymin", Float64), ("ymax", Float64)])

    define_fold_module!(P, "Quantiles";
        init=(ctx, cols) -> per_column(c -> KLL(as_int(param(ctx, "k", 200))), cols),
        update=(acc, chunk, ctx) -> (foreach(c -> kll_update!(acc[c], chunk[c]), keys(chunk)); acc),
        merge=merge_columns(kll_merge!),
        result=(acc, ctx) -> Dict(c => kll_quantiles(sk, quantile_list(ctx)) for (c, sk) in acc),
        parameters=[("columns", Vector{String}), ("quantiles", Vector{Float64}), ("k", Int)])

    define_fold_module!(P, "KLLSketch";
        columns=(ctx, t) -> [Symbol(required_param(ctx, "column"))],
        init=(ctx, cols) -> KLL(as_int(param(ctx, "k", 200))),
        update=(sk, chunk, ctx) -> kll_update!(sk, first(chunk)),
        merge=kll_merge!,
        result=kll_summary,
        parameters=[("column", String), ("quantiles", Vector{Float64}), ("binning", Int), ("k", Int)])

    define_fold_module!(P, "Histogram1DCategorical";
        columns=(ctx, t) -> [Symbol(required_param(ctx, "column"))],
        init=(ctx, cols) -> Dict{Any, Int}(),
        update=(counts, chunk, ctx) -> count_values!(counts, first(chunk)),
        merge=(a, b) -> mergewith!(+, a, b),
        result=(counts, ctx) -> counts,
        key_type=Any,
        parameters=[("column", String)])

    define_fold_module!(P, "Distinct";
        columns=(ctx, t) -> param(ctx, "columns") === nothing ? column_names(t) : as_symbols(param(ctx, "columns")),
        init=(ctx, cols) -> per_column(c -> Set{Any}(), cols),
        update=(acc, chunk, ctx) -> (foreach(c -> acc[c] = add_distinct(acc[c], chunk[c], distinct_threshold(ctx)), keys(chunk)); acc),
        merge=(a, b) -> (foreach(c -> a[c] = add_distinct(a[c], b[c], typemax(Int)), keys(b)); a),
        result=(acc, ctx) -> Dict(c => cap_distinct(v, distinct_threshold(ctx)) for (c, v) in acc),
        parameters=[("columns", Vector{String}), ("threshold", Int)])

    define_fold_module!(P, "Corr";
        init=(ctx, cols) -> CoMoments(cols),
        update=(acc, chunk, ctx) -> merge_comoments!(acc, CoMoments(chunk)),
        merge=merge_comoments!,
        result=correlations,
        key_type=Tuple{Symbol, Symbol},
        parameters=[("columns", Vector{String}), ("mode", String)])

    for (name, better) in (("IdxMin", <), ("IdxMax", >))
        define_fold_module!(P, name;
            init=(ctx, cols) -> per_column(c -> (id=0, value=NaN), cols),
            update=(acc, chunk, ctx) -> (foreach(c -> acc[c] = extreme_row(acc[c], chunk[c], chunk._id, better),
                                                 filter(!=(:_id), keys(chunk))); acc),
            merge=merge_columns((a, b) -> better_row(a, b, better)),
            result=(acc, ctx) -> Dict(c => r for (c, r) in acc if r.id > 0),
            row_ids=true,
            parameters=[("columns", Vector{String})])
    end
end

# Quantiles, KLLSketch

quantile_list(ctx) = Float64.(something(param(ctx, "quantiles"), [0.25, 0.5, 0.75]))

function kll_summary(sk::KLL, ctx)
    r = Dict{Symbol, Any}(:n => sk.n, :min => sk.n > 0 ? sk.min : NaN, :max => sk.n > 0 ? sk.max : NaN,
                          :quantiles => kll_quantiles(sk, quantile_list(ctx)))
    bins = param(ctx, "binning")
    if bins !== nothing && sk.n > 0
        edges = collect(range(sk.min, sk.max; length=as_int(bins) + 1))
        r[:splits] = edges
        r[:pmf] = kll_pmf(sk, edges)
    end
    return r
end

# Histogram1DCategorical

function count_values!(counts::Dict{Any, Int}, values::AbstractVector)
    for v in values
        counts[v] = get(counts, v, 0) + 1
    end
    return counts
end

# Distinct: a set, or nothing once over the threshold (for good)

distinct_threshold(ctx) = as_int(param(ctx, "threshold", 56))

function add_distinct(set, values, threshold)
    set === nothing && return nothing
    values === nothing && return nothing
    for v in values
        push!(set, v)
        length(set) > threshold && return nothing
    end
    return set
end

cap_distinct(set, threshold) = set === nothing || length(set) > threshold ? nothing : copy(set)

# Corr: counts, means and co-moments sum((x - mean x)(y - mean y)) of
# columns, merged pairwise (Chan et al., as for Var)

mutable struct CoMoments
    columns::Vector{Symbol}
    n::Int
    mean::Vector{Float64}
    C::Matrix{Float64}
end

CoMoments(cols::Vector{Symbol}) = CoMoments(cols, 0, zeros(length(cols)), zeros(length(cols), length(cols)))

function CoMoments(chunk::NamedTuple)
    cols = collect(Symbol, keys(chunk))
    data = [Float64.(chunk[c]) for c in cols]
    n = isempty(data) ? 0 : length(first(data))
    n == 0 && return CoMoments(cols)
    mean = [sum(v) / n for v in data]
    centered = [v .- m for (v, m) in zip(data, mean)]
    k = length(cols)
    C = zeros(k, k)
    for i in 1:k, j in i:k
        C[i, j] = C[j, i] = sum(centered[i] .* centered[j])
    end
    return CoMoments(cols, n, mean, C)
end

function merge_comoments!(a::CoMoments, b::CoMoments)
    b.n == 0 && return a
    if a.n == 0
        a.n, a.mean, a.C = b.n, copy(b.mean), copy(b.C)
        return a
    end
    n = a.n + b.n
    delta = b.mean .- a.mean
    a.C .+= b.C .+ (delta * delta') .* (a.n * b.n / n)
    a.mean .+= delta .* (b.n / n)
    a.n = n
    return a
end

function correlations(acc::CoMoments, ctx)
    mode = String(param(ctx, "mode", "Pearson"))
    mode in ("Pearson", "CovarianceOnly") || error("Corr: mode must be \"Pearson\" or \"CovarianceOnly\"")
    acc.n < 2 && return Dict{Tuple{Symbol, Symbol}, Float64}()
    cov = acc.C ./ (acc.n - 1)
    r = Dict{Tuple{Symbol, Symbol}, Float64}()
    for (i, a) in enumerate(acc.columns), (j, b) in enumerate(acc.columns)
        r[(a, b)] = mode == "CovarianceOnly" ? cov[i, j] : cov[i, j] / sqrt(cov[i, i] * cov[j, j])
    end
    return r
end

# IdxMin, IdxMax: the first row with the best value; `better` is < or >

better_row(a, b, better) = a.id == 0 ? b : b.id == 0 ? a :
    better(b.value, a.value) || (b.value == a.value && b.id < a.id) ? b : a

function extreme_row(best, values::AbstractVector, ids::AbstractVector{Int}, better)
    bi, bv = 0, NaN
    @inbounds for i in eachindex(values, ids)
        v = values[i]
        isnan(v) && continue
        if bi == 0 || better(v, bv)
            bi, bv = ids[i], Float64(v)
        end
    end
    return better_row(best, (id=bi, value=bv), better)
end
