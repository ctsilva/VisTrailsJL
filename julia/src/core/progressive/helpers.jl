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
    key_type::Type       # of the result dict's keys (output=:dict)
    row_ids::Bool        # chunks carry the row ids they cover (`_id`)
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
                        columns=numeric_columns, parameters=[], key_type=Symbol,
                        row_ids=false)

Register a progressive module that folds the rows of the table connected to
`input` into an accumulator:

- `init(ctx, columns)` → initial accumulator;
- `update(acc, chunk, ctx)` → new accumulator, where `chunk` is a
  `NamedTuple` of contiguous column views (one call per storage segment);
- `result(acc, ctx)` → the published result: a `Dict` written into the
  `ProgressiveDict{key_type, Any}` output `result` (`output=:dict`; only
  changed keys are reported, so return new objects, not mutated ones), or a
  value set into the `ProgressiveValue` output `result`
  (`output=:value`, of type `output_type`).

`ctx` gives access to parameters (`param(ctx, "bins", 10)`). With
`row_ids=true`, each chunk also has a field `_id`: the row ids of its rows
(a range).

With `merge(acc1, acc2)` → accumulator (combining the folds of two
consecutive pieces of rows, where `init` is the identity), the rows of a
step are split into blocks of `FOLD_BLOCK_ROWS`, the blocks into at most
`FOLD_GROUPS` groups of consecutive blocks; each group is folded into its
own accumulator (on several threads when Julia has them), and the groups
are merged in order. Neither depends on the number of threads, so neither
do the results; a step creates at most `FOLD_GROUPS` accumulators, however
many rows it has (accumulators can be large: a 512² histogram is 2 MB).
"""
function define_fold_module!(package::String, name::String;
                             init::Function, update::Function, result::Function,
                             merge::Union{Function, Nothing}=nothing,
                             output::Symbol=:dict, output_type::Type=Dict{Symbol, Float64},
                             input::String="table", columns::Function=numeric_columns,
                             parameters::Vector=Tuple{String, Type}[], key_type::Type=Symbol,
                             row_ids::Bool=false)
    output in (:dict, :value) || throw(ArgumentError("output must be :dict or :value"))
    FOLD_SPECS[(package, name)] = FoldSpec(input, columns, init, update, result, output, output_type, merge,
                                           key_type, row_ids)
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
    output = s.output == :dict ? ProgressiveDict{s.key_type, Any}() : ProgressiveValue{s.output_type}()
    set_output!(ctx, "result", output)
    return FoldState(s, table, input_subscription(ctx, s.input), columns, s.init(ctx, columns), output)
end

"""
    column_chunks(table, columns, ids::RowIds; row_ids=false) -> iterator of NamedTuple

Contiguous chunks of column views covering `ids`, one per storage segment
(scattered ids: one chunk of gathered values); with `row_ids`, each chunk
also has the field `_id`, the ids of its rows.
"""
function column_chunks(table::ProgressiveTable, columns::Vector{Symbol}, ids::RowIds; row_ids::Bool=false)
    names = row_ids ? (Tuple(columns)..., :_id) : Tuple(columns)
    cols = [column(table, c) for c in columns]
    if is_fragmented(ids)
        # Scattered rows (a selection): gather them into one dense chunk
        list = collect(ids)
        values = Any[gather(c, list) for c in cols]
        row_ids && push!(values, list)
        return [NamedTuple{names}(Tuple(values))]
    end
    chunks = NamedTuple{names}[]
    for r in ranges(ids)
        views = [segment_views(c, r) for c in cols]
        if row_ids
            views = Any[views...]
            # The segment boundaries of r (the same for every column)
            seg = isempty(cols) ? typemax(Int) : first(cols).segment_size
            pieces = UnitRange{Int}[]
            i = first(r)
            while i <= last(r)
                n = min(last(r) - i + 1, seg - (i - 1) % seg)
                push!(pieces, i:i+n-1)
                i += n
            end
            push!(views, pieces)
        end
        isempty(views) && continue
        for k in eachindex(first(views))
            push!(chunks, NamedTuple{names}(Tuple(v[k] for v in views)))
        end
    end
    return chunks
end

# Connected parameter inputs that have no value yet (e.g. bounds still being computed)
controls_waiting(ctx::StepContext, main_input::String) =
    any(c isa ProgressiveValue && !has_value(c) for (port, cs) in ctx.inputs if port != main_input for c in cs)

# A parameter driven by an input waits for its first value
ready_to_step(s::FoldState, ctx::StepContext) = !controls_waiting(ctx, s.spec.input)

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
    chunks = column_chunks(s.table, s.columns, ids; row_ids=s.spec.row_ids)
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

"""
Most groups of blocks (accumulators) per step of a fold with a `merge`.
"""
const FOLD_GROUPS = 16

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
    n = length(blocks)
    g = min(n, FOLD_GROUPS)
    groups = [blocks[cld((k - 1) * n, g) + 1:cld(k * n, g)] for k in 1:g]
    fold_group(group) = foldl((acc, block) -> s.spec.update(acc, block, ctx), group; init=s.spec.init(ctx, s.columns))
    partials = if Threads.nthreads() > 1 && length(groups) > 1 && !background_during_interaction(ctx)
        fetch.([Threads.@spawn fold_group(g) for g in groups])
    else
        map(fold_group, groups)
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

# Progress: rows consumed of the rows available so far
function input_progress(table::ProgressiveTable, sub::TableSubscription)
    lock(table.lock) do
        available = last_id(table) - length(table.deleted)
        (available - length(sub.created), available)
    end
end

progress(s::FoldState) = input_progress(s.table, s.sub)
progress(s::MapState) = input_progress(s.table, s.sub)
