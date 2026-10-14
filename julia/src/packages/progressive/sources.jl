"""
Progressive sources: RandomTable, CSVLoader, ArrowLoader, ParquetLoader; and Sink
"""

using Random
using CSV
using Arrow

# RandomTable: `rows` rows of uniform Float64 values in `columns`

struct RandomTableModule end
execution_style(::Type{RandomTableModule}) = Progressive()
default_step_size(::Type{RandomTableModule}) = 100_000

mutable struct RandomTableState
    table::ProgressiveTable
    rng::Xoshiro
    columns::Vector{Symbol}
    remaining::Int
end

function init_state(::Type{RandomTableModule}, ctx::StepContext)
    columns = as_symbols(param(ctx, "columns", ["x", "y"]))
    table = set_output!(ctx, "result", ProgressiveTable((c => Float64 for c in columns)...))
    return RandomTableState(table, Xoshiro(as_int(param(ctx, "seed", 0))), columns,
                            as_int(param(ctx, "rows", 1_000_000)))
end

progress(s::RandomTableState) = (last_id(s.table), last_id(s.table) + s.remaining)

function step!(s::RandomTableState, ctx::StepContext, budget::Int)
    n = min(budget, s.remaining)
    # One value at a time, row by row, so the rows do not depend on step
    # sizes (filling an array draws a different, vectorized stream)
    columns = [Vector{Float64}(undef, n) for _ in s.columns]
    fill_rows!(columns, s.rng)
    append!(s.table, NamedTuple{Tuple(s.columns)}(Tuple(columns)))
    s.remaining -= n
    return StepResult(s.remaining == 0 ? :done : :ready, n)
end

# Row by row: columns[k][i] gets the ((i - 1) * ncolumns + k)-th draw
function fill_rows!(columns::Vector{Vector{Float64}}, rng)
    @inbounds for i in eachindex(first(columns)), c in columns
        c[i] = rand(rng)
    end
    return columns
end

# CSVLoader: reads `path` in chunks of lines

struct CSVLoaderModule end
execution_style(::Type{CSVLoaderModule}) = Progressive()
default_step_size(::Type{CSVLoaderModule}) = 50_000

mutable struct CSVLoaderState
    bytes_read::Int
    bytes_total::Int
    io::IO
    names::Vector{Symbol}         # all columns of the file
    types::Dict{Symbol, Type}     # of the selected columns
    selected::Vector{Symbol}
    table::ProgressiveTable
end

const CSV_TYPE_SAMPLE_ROWS = 1_000

function init_state(::Type{CSVLoaderModule}, ctx::StepContext)
    path = String(required_param(ctx, "path"))
    io = open(path)
    header = readline(io)
    names = Symbol.(strip.(split(header, ',')))

    # Infer column types from the first rows; integers are widened to
    # Float64, since later rows may hold decimals
    sample = IOBuffer()
    println(sample, header)
    mark(io)
    for _ in 1:CSV_TYPE_SAMPLE_ROWS
        eof(io) && break
        println(sample, readline(io))
    end
    reset(io)
    inferred = CSV.File(take!(sample))
    selected = param(ctx, "columns") === nothing ? names : as_symbols(param(ctx, "columns"))
    types = Dict{Symbol, Type}()
    for name in selected
        T = nonmissingtype(eltype(Tables.getcolumn(inferred, name)))
        T = T <: Integer ? Float64 : (T <: AbstractString || T === Union{} ? String : T)
        types[name] = Missing <: eltype(Tables.getcolumn(inferred, name)) ? Union{Missing, T} : T
    end

    table = set_output!(ctx, "result", ProgressiveTable((n => types[n] for n in selected)...))
    return CSVLoaderState(position(io), filesize(path), io, names, types, selected, table)
end

function step!(s::CSVLoaderState, ctx::StepContext, budget::Int)
    buffer = IOBuffer()
    n = 0
    while n < budget && !eof(s.io)
        line = readline(s.io)
        isempty(line) && continue
        println(buffer, line)
        n += 1
    end
    if n > 0
        rows = CSV.File(take!(buffer); header=s.names, select=s.selected,
                        types=Dict(k => nonmissingtype(v) for (k, v) in s.types))
        append!(s.table, rows)
    end
    s.bytes_read = position(s.io)
    return StepResult(eof(s.io) ? :done : :ready, n)
end

finish!(s::CSVLoaderState, ctx::StepContext) = close(s.io)
progress(s::CSVLoaderState) = (s.bytes_read, s.bytes_total)   # bytes

# ArrowLoader: streams the rows of an Arrow file (memory-mapped)

struct ArrowLoaderModule end
execution_style(::Type{ArrowLoaderModule}) = Progressive()
default_step_size(::Type{ArrowLoaderModule}) = 100_000

mutable struct ArrowLoaderState
    source::Vector{AbstractVector}   # the file's columns, memory-mapped
    names::Vector{Symbol}
    table::ProgressiveTable
    position::Int
    rows::Int
    throttle::Int                    # at most this many rows per step (0: no limit)
    rate::Float64                    # at most this many rows per second (0: no limit)
    started::Float64                 # time of the first step, for `rate`
end

function init_state(::Type{ArrowLoaderModule}, ctx::StepContext)
    file = Arrow.Table(String(required_param(ctx, "path")))
    names = param(ctx, "columns") === nothing ? collect(Symbol, Arrow.names(file)) :
            as_symbols(param(ctx, "columns"))
    source = AbstractVector[Tables.getcolumn(file, n) for n in names]
    table = set_output!(ctx, "result", ProgressiveTable((n => eltype(c) for (n, c) in zip(names, source))...))
    rows = isempty(source) ? 0 : length(first(source))
    return ArrowLoaderState(source, names, table, 0, rows, as_int(param(ctx, "throttle", 0)),
                            Float64(param(ctx, "rate", 0)), 0.0)
end

# Rows that `rate` allows now, in chunks of at least 50 ms worth of rows (so
# consumers see a few large steps per second, not many tiny ones). Until a
# chunk is due, the step waits (at most 20 ms) and loads nothing: a source has
# no input to wake it, and returning at once would spin.
const RATE_CHUNK_SECONDS = 0.05

function rate_allowance(s::ArrowLoaderState)
    s.rate > 0 || return typemax(Int)
    s.started == 0 && (s.started = time())
    chunk = min(max(1, floor(Int, s.rate * RATE_CHUNK_SECONDS)), s.rows - s.position)
    due = (s.position + chunk) / s.rate              # seconds after start
    wait = due - (time() - s.started)
    wait > 0 && sleep(min(wait, 0.02))
    allowed = floor(Int, s.rate * (time() - s.started)) - s.position
    return allowed >= chunk ? allowed : 0
end

function step!(s::ArrowLoaderState, ctx::StepContext, budget::Int)
    n = min(budget, s.rows - s.position, s.throttle > 0 ? s.throttle : typemax(Int), rate_allowance(s))
    r = s.position+1:s.position+n
    append!(s.table, NamedTuple{Tuple(s.names)}(Tuple(view(c, r) for c in s.source)))
    s.position += n
    return StepResult(s.position == s.rows ? :done : :ready, n)
end

progress(s::ArrowLoaderState) = (s.position, s.rows)

# ParquetLoader: streams the rows of a Parquet file, one row group decoded at a time

# Parquet2.jl is loaded on first use: loading it slows unrelated code (the
# taxi dashboard from Arrow by ~12%), so programs that read no Parquet do
# not pay for it. Its functions are called with `invokelatest`, being newer
# than the calling code.
const PARQUET2 = Base.PkgId(Base.UUID("98572fba-bba0-415d-956f-fa77e587d26d"), "Parquet2")
parquet2() = Base.require(PARQUET2)

struct ParquetLoaderModule end
execution_style(::Type{ParquetLoaderModule}) = Progressive()
default_step_size(::Type{ParquetLoaderModule}) = 100_000

mutable struct ParquetLoaderState
    dataset::Any                     # Parquet2.Dataset
    names::Vector{Symbol}
    types::Vector{Type}              # of the output columns
    table::ProgressiveTable
    group::Int                       # row groups decoded so far
    current::Vector{AbstractVector}  # the columns of the last one
    offset::Int                      # its rows already loaded
    position::Int
    rows::Int
end

# Column types: nullable floats become plain floats (null: NaN), as in
# ProgressiVis' tables; other nullable columns keep `missing`
function parquet_column_type(T::Type)
    S = nonmissingtype(T)
    return S <: AbstractFloat || S === T ? S : T
end

function open_parquet(path::String)
    P2 = parquet2()
    dataset = P2.Dataset(path)
    schema = Tables.schema(dataset)
    return dataset, collect(Symbol, schema.names), collect(Type, schema.types),
           sum(P2.ntablerows, P2.rowgroups(dataset); init=0)
end

function init_state(::Type{ParquetLoaderModule}, ctx::StepContext)
    parquet2()     # load first: code running when it loads cannot call it yet
    dataset, all_names, all_types, rows = Base.invokelatest(open_parquet, String(required_param(ctx, "path")))
    names = param(ctx, "columns") === nothing ? all_names : as_symbols(param(ctx, "columns"))
    types = Type[parquet_column_type(all_types[findfirst(==(n), all_names)]) for n in names]
    table = set_output!(ctx, "result", ProgressiveTable((n => T for (n, T) in zip(names, types))...))
    return ParquetLoaderState(dataset, names, types, table, 0, AbstractVector[], 0, 0, rows)
end

function read_row_group(dataset, group::Int, names, types)
    columns = Tables.columns(parquet2().rowgroups(dataset)[group])
    return AbstractVector[parquet_column(Tables.getcolumn(columns, n), T) for (n, T) in zip(names, types)]
end

# Parquet2 decodes ~90 M values/s (one thread), slower than consumers read
# them: decoding is the cost of this loader. Decoding the next row groups on
# other threads did not help (measured on the taxi dashboard)
function decode_row_group!(s::ParquetLoaderState)
    s.group += 1
    s.current = Base.invokelatest(read_row_group, s.dataset, s.group, s.names, s.types)
    s.offset = 0
end

parquet_column(v::AbstractVector, ::Type{T}) where {T <: AbstractFloat} =
    Missing <: eltype(v) ? T[x === missing ? T(NaN) : x for x in v] : convert(Vector{T}, v)
parquet_column(v::AbstractVector, ::Type{T}) where {T} = convert(Vector{T}, v)

function step!(s::ParquetLoaderState, ctx::StepContext, budget::Int)
    n = 0
    while n < budget && s.position < s.rows
        if isempty(s.current) || s.offset == length(first(s.current))
            decode_row_group!(s)
            continue
        end
        m = min(budget - n, length(first(s.current)) - s.offset)
        r = s.offset+1:s.offset+m
        append!(s.table, NamedTuple{Tuple(s.names)}(Tuple(view(c, r) for c in s.current)))
        s.offset += m
        s.position += m
        n += m
    end
    s.position == s.rows && (s.current = AbstractVector[])
    return StepResult(s.position == s.rows ? :done : :ready, n)
end

progress(s::ParquetLoaderState) = (s.position, s.rows)

# Variable: an input module whose value changes during a run (set_variable!)

struct VariableModule end
execution_style(::Type{VariableModule}) = Progressive()
is_input_module(::Type{VariableModule}) = true

struct VariableState end

function init_state(::Type{VariableModule}, ctx::StepContext)
    out = set_output!(ctx, "result", ProgressiveValue{Any}())
    v = param(ctx, "value")
    v === nothing || set!(out, v)
    return VariableState()
end

step!(::VariableState, ctx::StepContext, budget::Int) = StepResult(:blocked, 0)

# Its current value is not in its signature (only the initial one is), so its
# state must not be reused by later runs; downstream modules start over
is_cacheable(::Type{VariableModule}) = false

# Sink: consumes everything connected to `table`; outputs the number of rows

struct SinkModule end
execution_style(::Type{SinkModule}) = Progressive()
default_step_size(::Type{SinkModule}) = 1_000_000

mutable struct SinkState
    count::ProgressiveValue{Int}
    rows::Int
end

function init_state(::Type{SinkModule}, ctx::StepContext)
    return SinkState(set_output!(ctx, "count", ProgressiveValue{Int}(0)), 0)
end

function step!(s::SinkState, ctx::StepContext, budget::Int)
    items = 0
    for subs in values(ctx.subscriptions), sub in subs
        if sub isa TableSubscription
            created = next_created!(sub, budget)
            s.rows += length(created)
            items += length(created) + length(next_updated!(sub)) + length(next_deleted!(sub))
        elseif has_changes(sub)
            consume_all!(sub)
            items += 1
        end
    end
    items > 0 && set!(s.count, s.rows)
    return StepResult(input_has_changes(ctx) ? :ready : :blocked, items)
end

function register_progressive_sources!()
    register_module!(ModuleDescriptor(PROGRESSIVE_PACKAGE, "RandomTable", RandomTableModule,
        InputPort[], [OutputPort("result", ProgressiveTable)],
        Tuple{String, Type}[("columns", Vector{String}), ("rows", Int), ("seed", Int)]))
    register_module!(ModuleDescriptor(PROGRESSIVE_PACKAGE, "CSVLoader", CSVLoaderModule,
        InputPort[], [OutputPort("result", ProgressiveTable)],
        Tuple{String, Type}[("path", String), ("columns", Vector{String})]))
    register_module!(ModuleDescriptor(PROGRESSIVE_PACKAGE, "ArrowLoader", ArrowLoaderModule,
        InputPort[], [OutputPort("result", ProgressiveTable)],
        Tuple{String, Type}[("path", String), ("columns", Vector{String}), ("throttle", Int), ("rate", Float64)]))
    register_module!(ModuleDescriptor(PROGRESSIVE_PACKAGE, "ParquetLoader", ParquetLoaderModule,
        InputPort[], [OutputPort("result", ProgressiveTable)],
        Tuple{String, Type}[("path", String), ("columns", Vector{String})]))
    register_module!(ModuleDescriptor(PROGRESSIVE_PACKAGE, "Variable", VariableModule,
        InputPort[], [OutputPort("result", ProgressiveValue)],
        Tuple{String, Type}[("value", Any)]))
    register_module!(ModuleDescriptor(PROGRESSIVE_PACKAGE, "Sink", SinkModule,
        [InputPort("table", Any)], [OutputPort("count", ProgressiveValue)],
        Tuple{String, Type}[]))
end
