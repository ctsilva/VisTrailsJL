"""
Helpers for defining progressive modules without the subscription API

- `define_fold_module!`: an accumulator over the rows of an input table
  (min, mean, histogram, ...). The update function sees contiguous chunks
  of column values; updates or deletions in the input reset the fold
  (re-read from scratch), the ProgressiVis default.
- `define_map_module!`: a chunk-wise transformation of an input table into
  an output table, row by row (projection, filter, derived columns). Output
  rows follow their input rows: input updates are re-mapped, input
  deletions delete the output rows.

Both register a module type in the registry, usable in pipelines and
workflow notebooks like any other module. Every parameter also gets an
optional input port of the same name: connecting a value (e.g. a
`Variable`) there drives the parameter live, and a change restarts the
module from all rows.
"""

# Module types are generated per (package, name); the functions live in specs
struct FoldModule{P, N} end
struct MapModule{P, N} end

execution_style(::Type{<:FoldModule}) = Progressive()
execution_style(::Type{<:MapModule}) = Progressive()
default_step_size(::Type{<:FoldModule}) = 100_000
default_step_size(::Type{<:MapModule}) = 10_000

struct FoldSpec
    input::String
    columns::Function    # (ctx, table) -> Vector{Symbol}
    init::Function       # (ctx, columns) -> accumulator
    update::Function     # (acc, chunk::NamedTuple, ctx) -> accumulator
    result::Function     # (acc, ctx) -> Dict (output=:dict) or value (output=:value)
    output::Symbol
    output_type::Type
    merge::Union{Function, Nothing}   # (acc, acc) -> acc, enables data parallelism
end

struct MapSpec
    input::String
    schema::Function     # (ctx, table) -> Vector{Pair{Symbol, Type}}
    map::Function        # (chunk::NamedTuple, ctx) -> NamedTuple of output columns (+ optional :_keep)
end

const FOLD_SPECS = Dict{Tuple{String, String}, FoldSpec}()
const MAP_SPECS = Dict{Tuple{String, String}, MapSpec}()

spec(::Type{FoldModule{P, N}}) where {P, N} = FOLD_SPECS[(String(P), String(N))]
spec(::Type{MapModule{P, N}}) where {P, N} = MAP_SPECS[(String(P), String(N))]

"""
    numeric_columns(ctx, table) -> Vector{Symbol}

The `columns` parameter if set, else every column with a `Real` element type.
"""
function numeric_columns(ctx::StepContext, table::ProgressiveTable)
    requested = param(ctx, "columns")
    requested !== nothing && return Symbol.(requested isa AbstractVector ? requested : [requested])
    return [n for n in column_names(table) if eltype(column(table, n)) <: Real]
end

"""
    define_fold_module!(package, name; init, update, result, output=:dict,
                        output_type=Dict{Symbol, Float64}, input="table",
                        columns=numeric_columns, parameters=[])

Register a progressive module that folds the rows of the table connected to
`input` into an accumulator:

- `init(ctx, columns)` → initial accumulator;
- `update(acc, chunk, ctx)` → new accumulator, where `chunk` is a
  `NamedTuple` of contiguous column views (one call per storage segment);
- `result(acc, ctx)` → the published result: a `Dict` written into the
  `ProgressiveDict` output `result` (`output=:dict`; only changed keys are
  reported), or a value set into the `ProgressiveValue` output `result`
  (`output=:value`, of type `output_type`).

`ctx` gives access to parameters (`param(ctx, "bins", 10)`).

With `merge(acc1, acc2)` → accumulator (combining the folds of two
consecutive pieces of rows, where `init` is the identity), the rows of a
step are folded in blocks of `FOLD_BLOCK_ROWS`, on several threads when
Julia has them, and merged in block order. Blocks do not depend on the
number of threads, so neither do the results.
"""
function define_fold_module!(package::String, name::String;
                             init::Function, update::Function, result::Function,
                             merge::Union{Function, Nothing}=nothing,
                             output::Symbol=:dict, output_type::Type=Dict{Symbol, Float64},
                             input::String="table", columns::Function=numeric_columns,
                             parameters::Vector=Tuple{String, Type}[])
    output in (:dict, :value) || throw(ArgumentError("output must be :dict or :value"))
    FOLD_SPECS[(package, name)] = FoldSpec(input, columns, init, update, result, output, output_type, merge)
    register_module!(ModuleDescriptor(package, name, FoldModule{Symbol(package), Symbol(name)},
        [InputPort(input, ProgressiveTable); control_ports(parameters)],
        [OutputPort("result", output == :dict ? ProgressiveDict : ProgressiveValue)],
        Tuple{String, Type}[(p[1], p[2]) for p in parameters]))
end

"""
    define_map_module!(package, name; map, schema=same_schema, input="table", parameters=[])

Register a progressive module that maps the rows of the table connected to
`input` into the output table `result`:

- `schema(ctx, table)` → output columns, as `[:name => Type, ...]`
  (default: the input's columns);
- `map(chunk, ctx)` → a `NamedTuple` of output column vectors, one row per
  input row of `chunk` (a `NamedTuple` of input column vectors). An extra
  `_keep` Boolean column drops the rows where it is false (a filter).
"""
function define_map_module!(package::String, name::String;
                            map::Function, schema::Function=same_schema,
                            input::String="table", parameters::Vector=Tuple{String, Type}[])
    MAP_SPECS[(package, name)] = MapSpec(input, schema, map)
    register_module!(ModuleDescriptor(package, name, MapModule{Symbol(package), Symbol(name)},
        [InputPort(input, ProgressiveTable); control_ports(parameters)], [OutputPort("result", ProgressiveTable)],
        Tuple{String, Type}[(p[1], p[2]) for p in parameters]))
end

# Optional input ports that drive parameters live
control_ports(parameters) = InputPort[InputPort(String(p[1]), Any; optional=true) for p in parameters]

"""
    take_control_changes!(ctx, main_input) -> Bool

Whether any input other than `main_input` (a control value) changed since
the last call; consumes those changes.
"""
function take_control_changes!(ctx::StepContext, main_input::String)
    changed = false
    for (port, subs) in ctx.subscriptions
        port == main_input && continue
        for sub in subs
            if has_changes(sub)
                consume_all!(sub)
                changed = true
            end
        end
    end
    return changed
end

same_schema(ctx, table::ProgressiveTable) = [n => eltype(column(table, n)) for n in column_names(table)]

# Fold state and step

mutable struct FoldState
    spec::FoldSpec
    table::ProgressiveTable
    sub::TableSubscription
    columns::Vector{Symbol}
    acc::Any
    output::Any
end

function init_state(T::Type{<:FoldModule}, ctx::StepContext)
    s = spec(T)
    table = input_container(ctx, s.input)
    table isa ProgressiveTable || error("$(ctx.mod.descriptor.name): input '$(s.input)' must be a table")
    columns = s.columns(ctx, table)
    output = s.output == :dict ? ProgressiveDict{Symbol, Any}() : ProgressiveValue{s.output_type}()
    set_output!(ctx, "result", output)
    return FoldState(s, table, input_subscription(ctx, s.input), columns, s.init(ctx, columns), output)
end

"""
    column_chunks(table, columns, ids::RowIds) -> iterator of NamedTuple

Contiguous chunks of column views covering `ids`, one per storage segment.
"""
function column_chunks(table::ProgressiveTable, columns::Vector{Symbol}, ids::RowIds)
    names = Tuple(columns)
    cols = [column(table, c) for c in columns]
    chunks = NamedTuple{names}[]
    for r in ranges(ids)
        views = [segment_views(c, r) for c in cols]
        isempty(views) && continue
        for k in eachindex(first(views))
            push!(chunks, NamedTuple{names}(Tuple(v[k] for v in views)))
        end
    end
    return chunks
end

function step!(s::FoldState, ctx::StepContext, budget::Int)
    counts = pending(s.sub)
    controls_changed = take_control_changes!(ctx, s.spec.input)
    if counts.updated > 0 || counts.deleted > 0 || controls_changed
        # Cannot update a fold incrementally: start over from all rows
        reset!(s.sub)
        controls_changed && (s.columns = s.spec.columns(ctx, s.table))
        s.acc = s.spec.init(ctx, s.columns)
    end

    ids = next_created!(s.sub, budget)
    isempty(ids) && return StepResult(:blocked, 0)
    chunks = column_chunks(s.table, s.columns, ids)
    if s.spec.merge === nothing
        for chunk in chunks
            s.acc = s.spec.update(s.acc, chunk, ctx)
        end
    else
        s.acc = fold_blocks(s, ctx, chunks)
    end
    publish_fold!(s, ctx)
    return StepResult(has_changes(s.sub) ? :ready : :blocked, length(ids))
end

"""
Rows per block for folds with a `merge` (data parallelism).
"""
const FOLD_BLOCK_ROWS = 16_384

# Split chunks (one per storage segment) into blocks of at most FOLD_BLOCK_ROWS rows
function fold_block_list(chunks)
    blocks = NamedTuple[]
    for chunk in chunks
        n = length(first(chunk))
        for lo in 1:FOLD_BLOCK_ROWS:n
            hi = min(n, lo + FOLD_BLOCK_ROWS - 1)
            push!(blocks, map(v -> view(v, lo:hi), chunk))
        end
    end
    return blocks
end

function fold_blocks(s::FoldState, ctx::StepContext, chunks)
    blocks = fold_block_list(chunks)
    fold_one(block) = s.spec.update(s.spec.init(ctx, s.columns), block, ctx)
    partials = if Threads.nthreads() > 1 && length(blocks) > 1 && !background_during_interaction(ctx)
        fetch.([Threads.@spawn fold_one(b) for b in blocks])
    else
        map(fold_one, blocks)
    end
    acc = s.acc
    for p in partials
        acc = s.spec.merge(acc, p)
    end
    return acc
end

function publish_fold!(s::FoldState, ctx::StepContext)
    r = s.spec.result(s.acc, ctx)
    if s.spec.output == :dict
        for (k, v) in r
            s.output[k] = v
        end
    else
        set!(s.output, r)
    end
end

"""
    consumed_rows(state) -> RowIds

Rows of the input a fold or map module has consumed so far (for tests and
progress reporting): the live rows not pending as created.
"""
consumed_rows(s::FoldState) =
    lock(() -> setdiff(live_ids(s.table), s.sub.created), s.table.lock)

# Map state and step

mutable struct MapState
    spec::MapSpec
    table::ProgressiveTable
    sub::TableSubscription
    out::ProgressiveTable
    out_columns::Vector{Symbol}
    out_id::Vector{Int}      # input row id → output row id (0: none); input ids are dense
end

function init_state(T::Type{<:MapModule}, ctx::StepContext)
    s = spec(T)
    table = input_container(ctx, s.input)
    table isa ProgressiveTable || error("$(ctx.mod.descriptor.name): input '$(s.input)' must be a table")
    schema = s.schema(ctx, table)
    out = ProgressiveTable(schema...)
    set_output!(ctx, "result", out)
    return MapState(s, table, input_subscription(ctx, s.input), out, [first(p) for p in schema], Int[])
end

output_row(s::MapState, id::Int) = id <= length(s.out_id) ? s.out_id[id] : 0

function step!(s::MapState, ctx::StepContext, budget::Int)
    if take_control_changes!(ctx, s.spec.input)
        # A parameter changed: remap every row from scratch
        existing = row_ids(s.out)
        isempty(existing) || delete!(s.out, existing)
        fill!(s.out_id, 0)
        reset!(s.sub)
    end
    deleted = next_deleted!(s.sub)
    for id in deleted
        out = output_row(s, id)
        if out != 0
            delete!(s.out, out)
            s.out_id[id] = 0
        end
    end

    updated = next_updated!(s.sub, budget)
    map_rows!(s, ctx, updated, false)
    created = next_created!(s.sub, max(0, budget - length(updated)))
    map_rows!(s, ctx, created, true)

    items = length(deleted) + length(updated) + length(created)
    items == 0 && return StepResult(:blocked, 0)
    return StepResult(has_changes(s.sub) ? :ready : :blocked, items)
end

consumed_rows(s::MapState) =
    lock(() -> setdiff(live_ids(s.table), s.sub.created), s.table.lock)

# Map rows `ids`; `fresh` rows were never mapped before (created), the
# others may have output rows to update or delete
function map_rows!(s::MapState, ctx::StepContext, ids::RowIds, fresh::Bool)
    isempty(ids) && return
    input_names = column_names(s.table)
    chunk = NamedTuple{Tuple(input_names)}(Tuple(s.table[ids, n] for n in input_names))
    mapped = s.spec.map(chunk, ctx)
    keep = haskey(mapped, :_keep) ? mapped[:_keep] : trues(length(ids))
    length(keep) == length(ids) || error("$(ctx.mod.descriptor.name): map returned $(length(keep)) rows for $(length(ids))")

    id_list = collect(ids)
    last(id_list) > length(s.out_id) && append!(s.out_id, zeros(Int, last(id_list) - length(s.out_id)))

    new_rows = if fresh
        findall(keep)
    else
        rows = Int[]
        for (i, id) in enumerate(id_list)
            existing = s.out_id[id]
            if keep[i]
                if existing == 0
                    push!(rows, i)
                else
                    for c in s.out_columns
                        s.out[existing, c] = mapped[c][i]
                    end
                end
            elseif existing != 0
                delete!(s.out, existing)
                s.out_id[id] = 0
            end
        end
        rows
    end

    if !isempty(new_rows)
        rows = NamedTuple{Tuple(s.out_columns)}(Tuple(mapped[c][new_rows] for c in s.out_columns))
        record_outputs!(s.out_id, id_list, new_rows, append!(s.out, rows))
    end
end

# Function barrier: `new_rows` comes from user code, of a type unknown here
function record_outputs!(out_id::Vector{Int}, id_list::Vector{Int}, new_rows::AbstractVector{<:Integer},
                         outputs::UnitRange{Int})
    for (i, out) in zip(new_rows, outputs)
        out_id[id_list[i]] = out
    end
end
