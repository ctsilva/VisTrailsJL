"""
Progressive sources: RandomTable, CSVLoader; and Sink
"""

using Random
using CSV

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
    values = Matrix{Float64}(undef, length(s.columns), n)
    for i in 1:n, k in eachindex(s.columns)
        values[k, i] = rand(s.rng)
    end
    append!(s.table, NamedTuple{Tuple(s.columns)}(Tuple(values[k, :] for k in eachindex(s.columns))))
    s.remaining -= n
    return StepResult(s.remaining == 0 ? :done : :ready, n)
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
    register_module!(ModuleDescriptor(PROGRESSIVE_PACKAGE, "Variable", VariableModule,
        InputPort[], [OutputPort("result", ProgressiveValue)],
        Tuple{String, Type}[("value", Any)]))
    register_module!(ModuleDescriptor(PROGRESSIVE_PACKAGE, "Sink", SinkModule,
        [InputPort("table", Any)], [OutputPort("count", ProgressiveValue)],
        Tuple{String, Type}[]))
end
