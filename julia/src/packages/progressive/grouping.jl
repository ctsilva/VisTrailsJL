"""
Grouping, after ProgressiVis' `GroupBy` and `Aggregate`

- `GroupBy`: groups the rows by the value of `by` (a column, or a tuple of
  values for several columns). Its output `result` is a selection view of
  all rows, carrying the groups (`meta[:groups]`: key → row ids) for
  consumers that select groups;
- `Aggregate`: one row per group (the `by` columns, then one column per
  computation), appended when a group appears and updated in place as its
  rows arrive. `compute` lists `"column:function"` (functions `count`,
  `sum`, `mean`, `var`, `std`, `min`, `max`; `count` needs no column:
  `":count"`); output columns are named `column_function` (`count`).
  `by` comes from a `GroupBy` input, or the `by` parameter. Input updates
  and deletions recompute every group (as ProgressiVis resets).

ProgressiVis also groups by parts of datetime columns (`dt` chains); here a
map module can derive such a key column first.
"""

group_keys(ctx) = as_symbols(required_param(ctx, "by"))

# Keys of rows: the value (one column) or a tuple (several)
function row_keys(table::ProgressiveTable, by::Vector{Symbol}, ids::RowIds)
    length(by) == 1 && return table[ids, only(by)]
    cols = [table[ids, c] for c in by]
    return [Tuple(c[i] for c in cols) for i in eachindex(first(cols))]
end

# ---------------------------------------------------------------- GroupBy

struct Groups
    lock::ReentrantLock
    by::Vector{Symbol}
    rows::Dict{Any, Vector{Int}}     # key → row ids (in arrival order)
end

struct GroupByModule end
execution_style(::Type{GroupByModule}) = Progressive()
default_step_size(::Type{GroupByModule}) = 100_000

mutable struct GroupByState
    table::ProgressiveTable
    sub::TableSubscription
    view::ProgressiveTable
    groups::Groups
end

function init_state(::Type{GroupByModule}, ctx::StepContext)
    table = input_container(ctx, "table")
    table isa ProgressiveTable || error("GroupBy: input 'table' must be a table")
    view = set_output!(ctx, "result", selection_view(table))
    groups = Groups(ReentrantLock(), group_keys(ctx), Dict{Any, Vector{Int}}())
    view.meta[:groups] = groups
    return GroupByState(table, input_subscription(ctx, "table"), view, groups)
end

function add_to_groups!(g::Groups, keys, ids)
    for (k, id) in zip(keys, ids)
        push!(get!(Vector{Int}, g.rows, k), id)
    end
end

function remove_from_groups!(g::Groups, ids::RowIds)
    isempty(ids) && return
    for (k, rows) in g.rows
        filter!(id -> !(id in ids), rows)
    end
    filter!(kv -> !isempty(kv.second), g.rows)
end

function step!(s::GroupByState, ctx::StepContext, budget::Int)
    deleted = next_deleted!(s.sub)
    updated = next_updated!(s.sub, budget)
    created = next_created!(s.sub, max(0, budget - length(updated)))
    added = union(updated, created)
    keys = row_keys(s.table, s.groups.by, added)
    lock(s.groups.lock) do
        remove_from_groups!(s.groups, union(deleted, updated))
        add_to_groups!(s.groups, keys, collect(added))
    end
    deselect!(s.view, deleted)
    touch!(s.view, updated)
    select!(s.view, created)
    items = length(deleted) + length(updated) + length(created)
    items == 0 && return StepResult(:blocked, 0)
    return StepResult(has_changes(s.sub) ? :ready : :blocked, items)
end

consumed_rows(s::GroupByState) = lock(() -> setdiff(live_ids(s.table), s.sub.created), s.table.lock)
progress(s::GroupByState) = input_progress(s.table, s.sub)

# ---------------------------------------------------------------- Aggregate

const AGGREGATES = ("count", "sum", "mean", "var", "std", "min", "max")

# Running statistics of one group and column (moments merged as in Var)
mutable struct GroupStats
    n::Int
    mean::Float64
    m2::Float64
    sum::Float64
    min::Float64
    max::Float64
end
GroupStats() = GroupStats(0, 0.0, 0.0, 0.0, Inf, -Inf)

function add!(g::GroupStats, x::Real)
    v = Float64(x)
    g.n += 1
    delta = v - g.mean
    g.mean += delta / g.n
    g.m2 += delta * (v - g.mean)
    g.sum += v
    g.min = min(g.min, v)
    g.max = max(g.max, v)
    return g
end

function aggregate_value(g::GroupStats, f::String)
    f == "count" && return g.n
    f == "sum" && return g.sum
    f == "mean" && return g.n > 0 ? g.mean : NaN
    f == "var" && return g.n > 1 ? g.m2 / (g.n - 1) : NaN
    f == "std" && return g.n > 1 ? sqrt(g.m2 / (g.n - 1)) : NaN
    f == "min" && return g.min
    f == "max" && return g.max
    error("Aggregate: unknown function '$f'")
end

struct AggregateModule end
execution_style(::Type{AggregateModule}) = Progressive()
default_step_size(::Type{AggregateModule}) = 100_000

mutable struct AggregateState
    table::ProgressiveTable
    sub::TableSubscription
    by::Vector{Symbol}
    computations::Vector{Tuple{Symbol, String, Symbol}}   # (input column or :_, function, output column)
    out::ProgressiveTable
    group::Dict{Any, Int}                  # key → group number
    keys::Vector{Any}                      # group number → key
    stats::Vector{Vector{GroupStats}}      # per computation, per group
    row::Vector{Int}                       # group number → output row id (0: not yet)
end

function parse_computations(ctx)
    specs = something(param(ctx, "compute"), [":count"])
    out = Tuple{Symbol, String, Symbol}[]
    for spec in (specs isa AbstractVector ? specs : [specs])
        parts = split(String(spec), ':')
        length(parts) == 2 || error("Aggregate: compute entries are \"column:function\", got \"$spec\"")
        col, f = strip(parts[1]), strip(parts[2])
        f in AGGREGATES || error("Aggregate: unknown function '$f' (use one of $(join(AGGREGATES, ", ")))")
        isempty(col) && f != "count" && error("Aggregate: '$f' needs a column")
        push!(out, (isempty(col) ? :_ : Symbol(col), String(f), Symbol(isempty(col) ? f : "$(col)_$(f)")))
    end
    return out
end

function init_state(::Type{AggregateModule}, ctx::StepContext)
    table = input_container(ctx, "table")
    table isa ProgressiveTable || error("Aggregate: input 'table' must be a table")
    by = haskey(table.meta, :groups) && param(ctx, "by") === nothing ? table.meta[:groups].by : group_keys(ctx)
    computations = parse_computations(ctx)
    schema = Pair{Symbol, Type}[c => eltype(column(table, c)) for c in by]
    for (_, f, name) in computations
        push!(schema, name => (f == "count" ? Int : Float64))
    end
    out = set_output!(ctx, "result", ProgressiveTable(schema...))
    return AggregateState(table, input_subscription(ctx, "table"), by, computations, out,
                          Dict{Any, Int}(), Any[], [GroupStats[] for _ in computations], Int[])
end

function step!(s::AggregateState, ctx::StepContext, budget::Int)
    counts = pending(s.sub)
    if counts.updated > 0 || counts.deleted > 0
        # Recompute every group from all rows
        existing = row_ids(s.out)
        isempty(existing) || delete!(s.out, existing)
        empty!(s.group); empty!(s.keys); foreach(empty!, s.stats); empty!(s.row)
        reset!(s.sub)
    end
    created = next_created!(s.sub, budget)
    isempty(created) && return StepResult(:blocked, 0)
    groups, touched = group_numbers!(s, row_keys(s.table, s.by, created))
    for (j, (c, _, _)) in enumerate(s.computations)
        c == :_ ? count_rows!(s.stats[j], groups) : accumulate!(s.stats[j], groups, s.table[created, c])
    end
    write_groups!(s, touched)
    return StepResult(has_changes(s.sub) ? :ready : :blocked, length(created))
end

# Group number of each key, new groups created in order of appearance;
# keys are looked up in a typed table per step (few distinct keys), not
# one by one in the module's Dict{Any}
function group_numbers!(s::AggregateState, keys::AbstractVector{K}) where {K}
    seen = Dict{K, Int}()
    groups = Vector{Int}(undef, length(keys))
    touched = Int[]
    for (i, k) in enumerate(keys)
        g = get(seen, k, 0)
        if g == 0
            g = get(s.group, k, 0)
            if g == 0
                push!(s.keys, k)
                g = s.group[k] = length(s.keys)
                foreach(st -> push!(st, GroupStats()), s.stats)
                push!(s.row, 0)
            end
            seen[k] = g
            push!(touched, g)
        end
        groups[i] = g
    end
    return groups, touched
end

count_rows!(stats::Vector{GroupStats}, groups::Vector{Int}) = foreach(g -> stats[g].n += 1, groups)

function accumulate!(stats::Vector{GroupStats}, groups::Vector{Int}, values::AbstractVector)
    @inbounds for i in eachindex(groups, values)
        v = values[i]
        indexable(v) && add!(stats[groups[i]], v)
    end
end

# Append new groups (in order of appearance) and update the others in place
function write_groups!(s::AggregateState, touched::Vector{Int})
    new = Int[]
    for g in touched
        if s.row[g] == 0
            push!(new, g)
            continue
        end
        for (j, (_, f, name)) in enumerate(s.computations)
            v = aggregate_value(s.stats[j][g], f)
            isequal(s.out[s.row[g], name], v) || (s.out[s.row[g], name] = v)
        end
    end
    isempty(new) && return
    cols = Dict{Symbol, Any}()
    for (i, c) in enumerate(s.by)
        cols[c] = [length(s.by) == 1 ? s.keys[g] : s.keys[g][i] for g in new]
    end
    for (j, (_, f, name)) in enumerate(s.computations)
        cols[name] = [aggregate_value(s.stats[j][g], f) for g in new]
    end
    names = column_names(s.out)
    rows::UnitRange{Int} = append!(s.out, NamedTuple{Tuple(names)}(Tuple(cols[n] for n in names)))
    for (g, id) in zip(new, rows)
        s.row[g] = id
    end
end

consumed_rows(s::AggregateState) = lock(() -> setdiff(live_ids(s.table), s.sub.created), s.table.lock)
progress(s::AggregateState) = input_progress(s.table, s.sub)

function register_progressive_grouping!()
    P = PROGRESSIVE_PACKAGE
    register_module!(ModuleDescriptor(P, "GroupBy", GroupByModule,
        [InputPort("table", ProgressiveTable)], [OutputPort("result", ProgressiveTable)],
        Tuple{String, Type}[("by", Vector{String})]))
    register_module!(ModuleDescriptor(P, "Aggregate", AggregateModule,
        [InputPort("table", ProgressiveTable)], [OutputPort("result", ProgressiveTable)],
        Tuple{String, Type}[("by", Vector{String}), ("compute", Vector{String})]))
end
