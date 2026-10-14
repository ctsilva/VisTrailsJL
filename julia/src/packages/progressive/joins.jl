"""
Joins and routing, after ProgressiVis' `Join`, `JoinById`/`Merge` and
`Switch`

- `Join`: many-to-one join of the `related` table (foreign key
  `related_on`) with the `primary` table (unique key `primary_on`; `on`
  sets both). Output: one row per related row, its columns (`related_columns`,
  default all) then the primary row's (`primary_columns`, default all but
  the key; `suffix` on name clashes). `how="inner"`: a related row waits
  until its key arrives in the primary table (rows whose key never comes
  are left out); `how="outer"`: it is output at once with `missing` primary
  values, filled in (an update) when its key arrives. Primary updates or
  deletions recompute the join (as ProgressiVis resets); related ones are
  re-joined row by row. Duplicate primary keys are an error.
- `JoinById`: rows present (by row id) in every table on `table`, with the
  columns of all (a clashing name gets `_k`, k the input's position);
  ProgressiVis' `Merge` (inner, on the index). Row ids match across views
  of one table (queries, `Switch`, `GroupBy`), not across tables made
  independently.
- `Switch`: the input's rows go to `result` while `condition` is true, to
  `result_else` while it is false (both selection views); nothing until it
  is set. Changing it moves the rows.

Unlike ProgressiVis' (views with computed columns), `Join` and `JoinById`
copy values into a new table.
"""

# Row id → output row id, in a vector (row ids are dense; 0: none)
struct IdMap
    v::Vector{Int}
end
IdMap() = IdMap(Int[])
Base.haskey(m::IdMap, id::Integer) = id <= length(m.v) && m.v[id] != 0
Base.getindex(m::IdMap, id::Integer) = m.v[id]
function Base.setindex!(m::IdMap, x::Integer, id::Integer)
    id > length(m.v) && append!(m.v, zeros(Int, max(id - length(m.v), length(m.v))))
    m.v[id] = x
end
Base.delete!(m::IdMap, id::Integer) = (haskey(m, id) && (m.v[id] = 0); m)
Base.empty!(m::IdMap) = (empty!(m.v); m)

# ---------------------------------------------------------------- Join

struct JoinModule end
execution_style(::Type{JoinModule}) = Progressive()
default_step_size(::Type{JoinModule}) = 100_000

mutable struct JoinState
    primary::ProgressiveTable
    related::ProgressiveTable
    psub::TableSubscription
    rsub::TableSubscription
    primary_on::Vector{Symbol}
    related_on::Vector{Symbol}
    related_columns::Vector{Symbol}
    primary_columns::Vector{Symbol}
    out_names::Vector{Symbol}            # related columns, then primary columns (renamed)
    outer::Bool
    out::ProgressiveTable
    key_row::Dict{Any, Int}              # primary key → primary row id
    out_row::IdMap                       # related row id → output row id
    waiting::Dict{Any, Vector{Int}}      # key not (yet) in primary → related row ids
end

function join_keys(ctx)
    on = param(ctx, "on")
    pon, ron = param(ctx, "primary_on"), param(ctx, "related_on")
    on === nothing || return as_symbols(on), as_symbols(on)
    (pon === nothing || ron === nothing) && error("Join: set 'on', or both 'primary_on' and 'related_on'")
    p, r = as_symbols(pon), as_symbols(ron)
    length(p) == length(r) || error("Join: 'primary_on' and 'related_on' must have the same length")
    return p, r
end

function init_state(::Type{JoinModule}, ctx::StepContext)
    primary, related = input_container(ctx, "primary"), input_container(ctx, "related")
    (primary isa ProgressiveTable && related isa ProgressiveTable) || error("Join: 'primary' and 'related' must be tables")
    pon, ron = join_keys(ctx)
    rcols = param(ctx, "related_columns") === nothing ? column_names(related) : as_symbols(param(ctx, "related_columns"))
    pcols = param(ctx, "primary_columns") === nothing ? [c for c in column_names(primary) if !(c in pon)] :
            as_symbols(param(ctx, "primary_columns"))
    suffix = String(param(ctx, "suffix", "_primary"))
    renamed = [c in rcols ? Symbol(string(c), suffix) : c for c in pcols]
    allunique([rcols; renamed]) || error("Join: output column names clash: $([rcols; renamed])")
    how = String(param(ctx, "how", "inner"))
    how in ("inner", "outer") || error("Join: how must be \"inner\" or \"outer\"")
    outer = how == "outer"
    schema = Pair{Symbol, Type}[c => eltype(column(related, c)) for c in rcols]
    for (c, n) in zip(pcols, renamed)
        T = eltype(column(primary, c))
        push!(schema, n => (outer ? Union{Missing, T} : T))
    end
    out = set_output!(ctx, "result", ProgressiveTable(schema...))
    return JoinState(primary, related, input_subscription(ctx, "primary"), input_subscription(ctx, "related"),
                     pon, ron, rcols, pcols, [rcols; renamed], outer, out,
                     Dict{Any, Int}(), IdMap(), Dict{Any, Vector{Int}}())
end

table_keys(t::ProgressiveTable, on::Vector{Symbol}, ids::RowIds) = row_keys(t, on, ids)

function step!(s::JoinState, ctx::StepContext, budget::Int)
    p = pending(s.psub)
    if p.updated > 0 || p.deleted > 0
        # The primary table changed: recompute the join
        existing = row_ids(s.out)
        isempty(existing) || delete!(s.out, existing)
        empty!(s.key_row); empty!(s.out_row); empty!(s.waiting)
        reset!(s.psub); reset!(s.rsub)
    end
    items = 0

    # New primary rows: their keys, and the related rows waiting for them
    pcreated = next_created!(s.psub)
    if !isempty(pcreated)
        items += length(pcreated)
        arrived = Int[]
        for (k, id) in zip(table_keys(s.primary, s.primary_on, pcreated), pcreated)
            haskey(s.key_row, k) && error("Join: duplicate key $(repr(k)) in the primary table")
            s.key_row[k] = id
            haskey(s.waiting, k) && append!(arrived, pop!(s.waiting, k))
        end
        if !isempty(arrived)
            sort!(arrived)
            if s.outer      # already output, with missing values: fill them in
                ids = rowids_sorted(arrived)
                keys = table_keys(s.related, s.related_on, ids)
                for (rid, k) in zip(arrived, keys)
                    for (c, n) in zip(s.primary_columns, s.out_names[length(s.related_columns)+1:end])
                        s.out[s.out_row[rid], n] = s.primary[s.key_row[k], c]
                    end
                end
            else
                emit_joined!(s, rowids_sorted(arrived))
            end
        end
    end

    # Related rows: deleted, updated (re-joined), created
    rdeleted = next_deleted!(s.rsub)
    rupdated = next_updated!(s.rsub, budget)
    gone = union(rdeleted, rupdated)
    if !isempty(gone)
        drop = RowIds([s.out_row[id] for id in gone if haskey(s.out_row, id)])
        isempty(drop) || delete!(s.out, drop)
        foreach(id -> delete!(s.out_row, id), gone)
        for (k, rows) in s.waiting
            filter!(id -> !(id in gone), rows)
        end
        filter!(kv -> !isempty(kv.second), s.waiting)
    end
    rcreated = union(rupdated, next_created!(s.rsub, max(0, budget - length(rupdated))))
    isempty(rcreated) || emit_joined!(s, rcreated)
    items += length(rdeleted) + length(rcreated)
    items == 0 && return StepResult(:blocked, 0)
    return StepResult(has_changes(s.psub) || has_changes(s.rsub) ? :ready : :blocked, items)
end

# Output related rows `ids` (inner: those whose key is known; the others wait)
function emit_joined!(s::JoinState, ids::RowIds)
    list = collect(ids)
    keys = table_keys(s.related, s.related_on, ids)
    pids::Vector{Int} = primary_rows(s.key_row, keys)   # 0: key not (yet) in the primary table
    for i in eachindex(pids)
        pids[i] == 0 && push!(get!(Vector{Int}, s.waiting, keys[i]), list[i])
    end
    emit = s.outer ? trues(length(list)) : pids .> 0
    any(emit) || return
    rows = rowids_sorted(list[emit])
    cols = Any[s.related[rows, c] for c in s.related_columns]
    epids = pids[emit]
    for c in s.primary_columns
        push!(cols, primary_values(column(s.primary, c), epids, s.outer))
    end
    out_ids::UnitRange{Int} = append!(s.out, NamedTuple{Tuple(s.out_names)}(Tuple(cols)))
    for (rid, oid) in zip(list[emit], out_ids)
        s.out_row[rid] = oid
    end
end

# Primary row of each key, through a typed table of this step's keys
function primary_rows(key_row::Dict{Any, Int}, keys::AbstractVector{K}) where {K}
    seen = Dict{K, Int}()
    return [get!(() -> get(key_row, k, 0), seen, k) for k in keys]
end

# A primary column's values at rows `pids` (0: missing, outer joins only)
function primary_values(col::AbstractVector{T}, pids::Vector{Int}, outer::Bool) where {T}
    outer || return gather(col, pids)
    v = Vector{Union{Missing, T}}(missing, length(pids))
    hit = findall(>(0), pids)
    v[hit] = gather(col, pids[hit])
    return v
end

progress(s::JoinState) = input_progress(s.related, s.rsub)

# ---------------------------------------------------------------- JoinById

struct JoinByIdModule end
execution_style(::Type{JoinByIdModule}) = Progressive()
default_step_size(::Type{JoinByIdModule}) = 100_000

mutable struct JoinByIdState
    inputs::Vector{ProgressiveTable}
    subs::Vector{TableSubscription}
    columns::Vector{Vector{Pair{Symbol, Symbol}}}   # per input: its column => output column
    out::ProgressiveTable
    out_row::IdMap                                   # row id → output row id
end

function init_state(::Type{JoinByIdModule}, ctx::StepContext)
    inputs = get(ctx.inputs, "table", Any[])
    (length(inputs) >= 2 && all(t -> t isa ProgressiveTable, inputs)) ||
        error("JoinById: connect at least two tables to 'table'")
    counts = Dict{Symbol, Int}()
    foreach(t -> foreach(c -> counts[c] = get(counts, c, 0) + 1, column_names(t)), inputs)
    columns = [[c => (counts[c] > 1 ? Symbol(string(c), "_", k) : c) for c in column_names(t)]
               for (k, t) in enumerate(inputs)]
    schema = [n => eltype(column(t, c)) for (t, cols) in zip(inputs, columns) for (c, n) in cols]
    out = set_output!(ctx, "result", ProgressiveTable(schema...))
    return JoinByIdState(ProgressiveTable[inputs...], TableSubscription[ctx.subscriptions["table"]...],
                         columns, out, IdMap())
end

function step!(s::JoinByIdState, ctx::StepContext, budget::Int)
    items = 0
    candidates = RowIds()
    for (k, (t, sub)) in enumerate(zip(s.inputs, s.subs))
        deleted = next_deleted!(sub)
        drop = RowIds([s.out_row[id] for id in deleted if haskey(s.out_row, id)])
        isempty(drop) || delete!(s.out, drop)
        foreach(id -> delete!(s.out_row, id), deleted)
        for id in next_updated!(sub)
            haskey(s.out_row, id) || continue
            foreach(((c, n),) -> s.out[s.out_row[id], n] = t[id, c], s.columns[k])
        end
        created = next_created!(sub, budget)
        union!(candidates, created)
        items += length(deleted) + length(created)
    end
    # Rows now in every input and not output yet
    live = [row_ids(t) for t in s.inputs]
    ready = [id for id in candidates if !haskey(s.out_row, id) && all(l -> id in l, live)]
    if !isempty(ready)
        ids = rowids_sorted(ready)
        cols = Any[t[ids, c] for (t, cols) in zip(s.inputs, s.columns) for (c, _) in cols]
        names = [n for cols in s.columns for (_, n) in cols]
        out_ids::UnitRange{Int} = append!(s.out, NamedTuple{Tuple(names)}(Tuple(cols)))
        for (id, oid) in zip(ready, out_ids)
            s.out_row[id] = oid
        end
    end
    items == 0 && return StepResult(:blocked, 0)
    return StepResult(any(has_changes, s.subs) ? :ready : :blocked, items)
end

# ---------------------------------------------------------------- Switch

struct SwitchModule end
execution_style(::Type{SwitchModule}) = Progressive()

mutable struct SwitchState
    table::ProgressiveTable
    sub::TableSubscription
    result::ProgressiveTable
    result_else::ProgressiveTable
    condition::Union{Nothing, Bool}
end

function init_state(::Type{SwitchModule}, ctx::StepContext)
    table = input_container(ctx, "table")
    table isa ProgressiveTable || error("Switch: input 'table' must be a table")
    return SwitchState(table, input_subscription(ctx, "table"),
                       set_output!(ctx, "result", selection_view(table)),
                       set_output!(ctx, "result_else", selection_view(table)), nothing)
end

switch_condition(ctx) = (c = param(ctx, "condition"); c === nothing ? nothing : Bool(c))

# Nothing to do until the condition is set
ready_to_step(s::SwitchState, ctx::StepContext) = switch_condition(ctx) !== nothing

function step!(s::SwitchState, ctx::StepContext, budget::Int)
    take_control_changes!(ctx, "table")
    condition = switch_condition(ctx)
    condition === nothing && return StepResult(:blocked, 0)
    target, other = condition ? (s.result, s.result_else) : (s.result_else, s.result)
    items = 0
    if condition !== s.condition
        # Move the rows routed so far
        moved = row_ids(other)
        deselect!(other, moved)
        select!(target, moved)
        s.condition = condition
        items += max(1, length(moved))
    end
    deleted = next_deleted!(s.sub)
    updated = next_updated!(s.sub, budget)
    created = next_created!(s.sub, max(0, budget - length(updated)))
    deselect!(target, deleted)
    touch!(target, updated)
    select!(target, created)
    items += length(deleted) + length(updated) + length(created)
    items == 0 && return StepResult(:blocked, 0)
    return StepResult(has_changes(s.sub) ? :ready : :blocked, items)
end

consumed_rows(s::SwitchState) = lock(() -> setdiff(live_ids(s.table), s.sub.created), s.table.lock)

function register_progressive_joins!()
    P = PROGRESSIVE_PACKAGE
    join_params = [("on", Vector{String}), ("primary_on", Vector{String}), ("related_on", Vector{String}),
                   ("how", String), ("primary_columns", Vector{String}), ("related_columns", Vector{String}),
                   ("suffix", String)]
    register_module!(ModuleDescriptor(P, "Join", JoinModule,
        [InputPort("primary", ProgressiveTable), InputPort("related", ProgressiveTable)],
        [OutputPort("result", ProgressiveTable)], Tuple{String, Type}[join_params...]))
    register_module!(ModuleDescriptor(P, "JoinById", JoinByIdModule,
        [InputPort("table", ProgressiveTable)], [OutputPort("result", ProgressiveTable)], Tuple{String, Type}[]))
    register_module!(ModuleDescriptor(P, "Switch", SwitchModule,
        [InputPort("table", ProgressiveTable); control_ports([("condition", Bool)])],
        [OutputPort("result", ProgressiveTable), OutputPort("result_else", ProgressiveTable)],
        Tuple{String, Type}[("condition", Bool)]))
end
