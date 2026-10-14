"""
Sample: a uniform random sample of `samples` rows of the input table, kept
up to date as rows arrive (reservoir sampling), after ProgressiVis' `Sample`

The output table `result` holds the sampled rows (same columns as the
input); when a new row enters the sample it replaces a row in place, so
consumers see updates. `select` holds the input row ids of the sample, in
output row order. Uses Li's Algorithm L, which jumps over the rows that do
not enter the sample: a step costs O(samples · log(rows / samples)), not
O(rows). Input updates of sampled rows are copied; input deletions restart
the sample from all rows (as ProgressiVis does). Reproducible with `seed`.
"""

struct SampleModule end
execution_style(::Type{SampleModule}) = Progressive()
default_step_size(::Type{SampleModule}) = 1_000_000

mutable struct SampleState
    table::ProgressiveTable
    sub::TableSubscription
    out::ProgressiveTable
    select::ProgressiveValue{Vector{Int}}
    k::Int
    seed::Int
    rng::Xoshiro
    seen::Int                 # input rows considered so far
    w::Float64                # Algorithm L's running weight
    next::Int                 # number of the next row to enter the sample
    ids::Vector{Int}          # input row id of each sampled row
    rows::Vector{Int}         # its output row id
end

function init_state(::Type{SampleModule}, ctx::StepContext)
    table = input_container(ctx, "table")
    table isa ProgressiveTable || error("Sample: input 'table' must be a table")
    out = set_output!(ctx, "result", ProgressiveTable(same_schema(ctx, table)...))
    select = set_output!(ctx, "select", ProgressiveValue{Vector{Int}}(Int[]))
    k = as_int(param(ctx, "samples", 50))
    k >= 1 || error("Sample: samples must be positive")
    seed = as_int(param(ctx, "seed", 42))
    return SampleState(table, input_subscription(ctx, "table"), out, select, k, seed, Xoshiro(seed),
                       0, 1.0, 0, Int[], Int[])
end

function restart!(s::SampleState)
    existing = row_ids(s.out)
    isempty(existing) || delete!(s.out, existing)
    reset!(s.sub)
    s.rng = Xoshiro(s.seed)
    s.seen, s.w, s.next = 0, 1.0, 0
    empty!(s.ids); empty!(s.rows)
end

# Algorithm L: the next row to enter a full reservoir
function advance!(s::SampleState)
    s.w *= exp(log(rand(s.rng)) / s.k)
    s.next += floor(Int, log(rand(s.rng)) / log1p(-s.w)) + 1
end

function step!(s::SampleState, ctx::StepContext, budget::Int)
    counts = pending(s.sub)
    if counts.deleted > 0 || take_control_changes!(ctx, "table")
        restart!(s)
    end
    names = column_names(s.table)
    changed = false

    # Updated input rows that are in the sample
    updated = next_updated!(s.sub)
    for (slot, id) in enumerate(s.ids)
        if id in updated
            foreach(c -> s.out[s.rows[slot], c] = s.table[id, c], names)
        end
    end

    created = collect(next_created!(s.sub, budget))
    n = length(created)
    # Fill the reservoir
    fill = min(n, s.k - length(s.ids))
    if fill > 0
        ids = RowIds(created[1:fill])
        rows = append!(s.out, NamedTuple{Tuple(names)}(Tuple(s.table[ids, c] for c in names)))
        append!(s.ids, created[1:fill]); append!(s.rows, rows)
        s.seen += fill
        changed = true
        if length(s.ids) == s.k
            s.next = s.k
            advance!(s)
        end
    end
    # Replace: rows s.next among those seen so far enter the sample
    while length(s.ids) == s.k && s.next <= s.seen + (n - fill)
        id = created[fill + s.next - s.seen]
        slot = rand(s.rng, 1:s.k)
        foreach(c -> s.out[s.rows[slot], c] = s.table[id, c], names)
        s.ids[slot] = id
        changed = true
        advance!(s)
    end
    s.seen += n - fill

    changed && set!(s.select, copy(s.ids))
    items = n + length(updated)
    items == 0 && return StepResult(:blocked, 0)
    return StepResult(has_changes(s.sub) ? :ready : :blocked, items)
end

consumed_rows(s::SampleState) = lock(() -> setdiff(live_ids(s.table), s.sub.created), s.table.lock)
progress(s::SampleState) = input_progress(s.table, s.sub)

function register_progressive_sampling!()
    register_module!(ModuleDescriptor(PROGRESSIVE_PACKAGE, "Sample", SampleModule,
        [InputPort("table", ProgressiveTable); control_ports([("samples", Int), ("seed", Int)])],
        [OutputPort("result", ProgressiveTable), OutputPort("select", ProgressiveValue)],
        Tuple{String, Type}[("samples", Int), ("seed", Int)]))
end
