"""
Tests for selection views and the index and query modules ported from
ProgressiVis (tier 2): BinningIndex, RangeQuery, RangeQuery2D, SimpleFilter,
CategoricalQuery, Intersection, Percentiles

Queries are checked against brute force on the rows they consumed: after
every step, under random step sizes, with bounds changed during the run,
with input updates and deletions, and in the one-shot engine.
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Test
using Random
using Tables

const VT = VisTrailsJL
const P = "org.vistrails.progressive"
const T = "org.vistrails.test.indexes"

function node!(p, name, sources...; port="table", package=P, params...)
    m = add_module!(p, package, name)
    for (k, v) in params
        set_parameter!(m, String(k), v)
    end
    for s in sources
        add_connection!(p, s, "result", m, port)
    end
    return m
end

result_of(run, m, port="result") = (c = run.outputs[m.id][port]; c isa ProgressiveValue ? current_value(c) :
                                    c isa ProgressiveDict ? snapshot(c) : Tables.columntable(c))
selected(run, m) = collect(row_ids(run.outputs[m.id]["result"]))

# A source serving a fixed table in steps (segments of 4 096 rows)
const TABLES = Dict{String, Any}()
struct FixedTableModule end
VT.execution_style(::Type{FixedTableModule}) = VT.Progressive()
VT.default_step_size(::Type{FixedTableModule}) = 5_000
mutable struct FixedTableState
    data::Any
    table::ProgressiveTable
    position::Int
end
function VT.init_state(::Type{FixedTableModule}, ctx::VT.StepContext)
    data = TABLES[VT.param(ctx, "key")]
    t = VT.set_output!(ctx, "result", ProgressiveTable((n => eltype(v) for (n, v) in pairs(data))...; segment_size=4_096))
    return FixedTableState(data, t, 0)
end
function VT.step!(s::FixedTableState, ctx::VT.StepContext, budget::Int)
    n = min(budget, length(first(s.data)) - s.position)
    append!(s.table, map(v -> v[s.position+1:s.position+n], s.data))
    s.position += n
    return VT.StepResult(s.position == length(first(s.data)) ? :done : :ready, n)
end

# A source that appends, then updates and deletes rows, then appends more
struct MutatorModule end
VT.execution_style(::Type{MutatorModule}) = VT.Progressive()
mutable struct MutatorState
    table::ProgressiveTable
    phase::Int
end
VT.init_state(::Type{MutatorModule}, ctx) =
    MutatorState(VT.set_output!(ctx, "result", ProgressiveTable(:x => Float64, :y => Float64)), 0)
function VT.step!(s::MutatorState, ctx, budget)
    s.phase += 1
    t = s.table
    if s.phase == 1
        append!(t, (x=collect(1.0:200.0), y=collect(200.0:-1.0:1.0)))
    elseif s.phase == 2
        t[10, :x] = 150.5          # moves into the query range
        t[120, :x] = 5.0           # moves out of it
    elseif s.phase == 3
        delete!(t, VT.RowIds(140:160))
    else
        append!(t, (x=[130.0, 300.0], y=[1.0, 2.0]))
        return VT.StepResult(:done, 1)
    end
    return VT.StepResult(:ready, 1)
end

for (name, type) in (("FixedTable", FixedTableModule), ("Mutator", MutatorModule))
    VT.register_module!(VT.ModuleDescriptor(T, name, type, VT.InputPort[],
        [VT.OutputPort("result", ProgressiveTable)], Tuple{String, Type}[("key", String)]))
end

source!(p, key) = node!(p, "FixedTable"; package=T, key=key)

# Integer-valued x (many values exactly on bin edges with tol = 1), y in [0, 1),
# a category, and some NaN
function data_table(n; seed=2)
    rng = Xoshiro(seed)
    x = Float64.(rand(rng, -50:150, n))
    x[rand(rng, 1:n, n ÷ 100)] .= NaN
    return (x=x, y=rand(rng, n), cat=rand(rng, ["a", "b", "c", "d"], n))
end

brute(data, ids, pred) = [i for i in ids if pred(i)]
in_range(v, lo, hi) = !isnan(v) && lo <= v < hi

# The checks of each module on the rows it consumed (`consumed`: its input's ids)
struct QueryChecker <: ExecutionObserver
    checks::Dict{Int, Function}      # module id → (run, consumed) -> Bool
    counts::Dict{Int, Int}
    failures::Vector{String}
end
QueryChecker(checks) = QueryChecker(checks, Dict{Int, Int}(), String[])
function VT.on_module_step(c::QueryChecker, run, mod, result, seconds)
    haskey(c.checks, mod.id) || return
    state = run.engine_state.modules[mod.id].state
    consumed = collect(VT.consumed_rows(state))
    c.counts[mod.id] = get(c.counts, mod.id, 0) + 1
    c.checks[mod.id](run, consumed) || push!(c.failures, "$(mod.descriptor.name) after $(length(consumed)) rows")
end

@testset "Indexes and queries (tier 2)" begin
    @testset "RowIds set operations" begin
        rng = Xoshiro(1)
        rset(n, p) = Set(i for i in 1:n if rand(rng) < p)
        separate(s) = all(last(s.ranges[i]) + 1 < first(s.ranges[i+1]) for i in 1:length(s.ranges)-1)
        for _ in 1:300
            a, b = rset(200, rand(rng)), rset(200, rand(rng))
            A, B = RowIds(collect(a)), RowIds(collect(b))
            @test Set(collect(union(A, B))) == union(a, b) && separate(union(A, B))
            @test Set(collect(setdiff(A, B))) == setdiff(a, b) && separate(setdiff(A, B))
            @test Set(collect(intersect(A, B))) == intersect(a, b)
        end
    end

    @testset "Selection views" begin
        rng = Xoshiro(2)
        rset(p) = Set(i for i in 1:300 if rand(rng) < p)
        for _ in 1:100
            base = ProgressiveTable((x=collect(1.0:300.0),))
            v = selection_view(base)
            sub = VT.subscribe!(v)
            seen, truth = Set{Int}(), Set{Int}()
            for _ in 1:30
                s = rset(rand(rng) * 0.3)
                r = rand(rng)
                if r < 0.4
                    select!(v, RowIds(collect(s))); union!(truth, s)
                elseif r < 0.7
                    deselect!(v, RowIds(collect(s))); setdiff!(truth, s)
                else
                    set_selection!(v, RowIds(collect(s))); truth = copy(s)
                end
                @test Set(collect(row_ids(v))) == truth && length(v) == length(truth)
                if rand(rng) < 0.5     # the consumer reads every change
                    d, c = collect(VT.next_deleted!(sub)), collect(VT.next_created!(sub))
                    u = collect(VT.next_updated!(sub))
                    @test isempty(intersect(Set(c), seen)) && issubset(Set(d), seen) && issubset(Set(u), seen)
                    setdiff!(seen, d); union!(seen, c)
                    @test seen == truth
                end
            end
        end
        base = ProgressiveTable((x=collect(1.0:10.0),))
        v = selection_view(base)
        select!(v, RowIds([2, 5, 7]))
        @test Tables.columntable(v) == (x=[2.0, 5.0, 7.0],)       # values from the base
        @test_throws ArgumentError append!(v, (x=[1.0],))
        @test_throws ArgumentError select!(v, RowIds([11]))       # not in the base
    end

    TABLES["data"] = data_table(40_000)
    data = TABLES["data"]
    ids_all = 1:length(data.x)

    @testset "BinningIndex: every indexable row in one bin, bounds" begin
        for (tol, threshold) in ((1.0, 10_000), (-1.0, 10_000), (-5.0, 100_000))   # last: fewer rows than the threshold
            p = Pipeline()
            src = source!(p, "data")
            ix = node!(p, "BinningIndex", src; columns=["x", "y"], tol=tol, init_threshold=threshold)
            run = run!(ProgressiveEngine(step_size=id -> 3_000), p)
            index = run.outputs[ix.id]["result"].meta[:index]
            for c in (:x, :y)
                b = index.bins[c]
                all_ids = sort(reduce(vcat, values(b.bins)))
                @test all_ids == [i for i in ids_all if !isnan(data[c][i])]
                @test all(VT.bin_number(b, data[c][id]) == k for (k, bin) in b.bins for id in bin)
                @test b.numbers == sort(collect(keys(b.bins))) && all(!isempty, values(b.bins))
            end
            @test index.bins[:x].width == (tol > 0 ? tol : index.bins[:x].width)
            finite = filter(!isnan, data.x)
            @test result_of(run, ix, "min")[:x] == minimum(finite) && result_of(run, ix, "max")[:x] == maximum(finite)
            @test selected(run, ix) == collect(ids_all)
        end
    end

    # source → BinningIndex(x, y) → RangeQuery, RangeQuery2D, SimpleFilters, Percentiles;
    # source → CategoricalQuery; Intersection(RangeQuery, CategoricalQuery); counts downstream
    function query_pipeline(; tol=1.0, lower=-10.0, upper=40.0)
        p = Pipeline()
        src = source!(p, "data")
        ix = node!(p, "BinningIndex", src; columns=["x", "y"], tol=tol, init_threshold=5_000)
        lo, hi = node!(p, "Variable"; value=lower), node!(p, "Variable"; value=upper)
        rq = node!(p, "RangeQuery", ix; port="index", column="x")
        add_connection!(p, lo, "result", rq, "lower")
        add_connection!(p, hi, "result", rq, "upper")
        m = (src=src, ix=ix, lo=lo, hi=hi, rq=rq,
             rq2=node!(p, "RangeQuery2D", ix; port="index", x_column="x", y_column="y",
                       x_lower=0.0, x_upper=100.0, y_lower=0.25, y_upper=0.5),
             f_lt=node!(p, "SimpleFilter", ix; port="index", column="x", op="<", value=20.0),
             f_le=node!(p, "SimpleFilter", ix; port="index", column="x", op="<=", value=20.0),
             f_gt=node!(p, "SimpleFilter", ix; port="index", column="x", op=">", value=20.0),
             f_ge=node!(p, "SimpleFilter", ix; port="index", column="x", op=">=", value=20.0),
             f_eq=node!(p, "SimpleFilter", ix; port="index", column="x", op="==", value=20.0),
             cat=node!(p, "CategoricalQuery", src; column="cat", choice=["a", "c"]),
             pct=node!(p, "Percentiles", ix; port="index", column="x", percentiles=[0.0, 10.0, 50.0, 99.0, 100.0]))
        both = node!(p, "Intersection", m.rq, m.cat)
        m = merge(m, (both=both, count=node!(p, "Count", rq), hist=node!(p, "Histogram1D", rq; column="y", bins=10,
                      min=0.0, max=1.0), both_count=node!(p, "Count", both)))
        return p, m
    end

    preds(lower, upper) = Dict(
        :rq => i -> in_range(data.x[i], lower, upper),
        :rq2 => i -> in_range(data.x[i], 0.0, 100.0) && 0.25 <= data.y[i] < 0.5,
        :f_lt => i -> data.x[i] < 20, :f_le => i -> data.x[i] <= 20, :f_gt => i -> data.x[i] > 20,
        :f_ge => i -> data.x[i] >= 20, :f_eq => i -> data.x[i] == 20,
        :cat => i -> data.cat[i] in ("a", "c"))
    lower_pct(v, p) = (s = sort(filter(!isnan, v)); s[1 + floor(Int, p / 100 * (length(s) - 1))])

    function check_final(run, m, lower, upper)
        pr = preds(lower, upper)
        for k in keys(pr)
            @test selected(run, m[k]) == brute(data, ids_all, pr[k])
        end
        both = brute(data, ids_all, i -> pr[:rq](i) && pr[:cat](i))
        @test selected(run, m.both) == both
        @test result_of(run, m.both_count) == length(both)
        @test result_of(run, m.count) == count(pr[:rq], ids_all)
        ys = data.y[brute(data, ids_all, pr[:rq])]
        @test result_of(run, m.hist) == [count(y -> (b - 1) / 10 <= y < b / 10 || (b == 10 && y == 1.0), ys) for b in 1:10]
        @test result_of(run, m.pct) == Dict{Any, Any}(p => lower_pct(data.x, p) for p in (0.0, 10.0, 50.0, 99.0, 100.0))
        @test Tables.columntable(run.outputs[m.rq.id]["result"]).y == ys    # values through the view
    end

    @testset "Queries after every step, under random step sizes" begin
        rng = Xoshiro(3)
        p, m = query_pipeline()
        pr = preds(-10.0, 40.0)
        checks = Dict{Int, Function}(m[k].id => ((run, consumed) -> selected(run, m[k]) == brute(data, consumed, pr[k]))
                                     for k in keys(pr))
        checker = QueryChecker(checks)
        run = run!(ProgressiveEngine(step_size=id -> rand(rng, 1:6_000)), p; observers=[checker])
        @test isempty(checker.failures)
        @test all(get(checker.counts, m[k].id, 0) >= 3 for k in keys(pr))
        check_final(run, m, -10.0, 40.0)
    end

    @testset "Final results whatever the step sizes, bin widths and workers" begin
        for (step, tol, workers) in ((40_000, 1.0, 1), (777, -1.0, 1), (5_000, 7.3, 4))
            p, m = query_pipeline(tol=tol)
            run = run!(ProgressiveEngine(step_size=id -> step, workers=workers), p)
            check_final(run, m, -10.0, 40.0)
        end
    end

    @testset "Bounds changed during the run: re-queried from the index" begin
        p, m = query_pipeline()
        pr = start!(ProgressiveEngine(step_size=id -> 2_000), p)
        sleep(0.05)
        set_variable!(pr, m.lo, 25.0)
        sleep(0.02)
        set_variable!(pr, m.hi, 120.5)
        close_inputs!(pr)
        run = wait(pr)
        check_final(run, m, 25.0, 120.5)
        # NaN or missing bounds: unbounded
        p, m = query_pipeline(lower=NaN)
        check_final(run!(ProgressiveEngine(), p), m, -Inf, 40.0)
    end

    @testset "Input updates and deletions" begin
        p = Pipeline()
        src = node!(p, "Mutator"; package=T)
        ix = node!(p, "BinningIndex", src; column="x", tol=10.0, init_threshold=10)
        rq = node!(p, "RangeQuery", ix; port="index", column="x", lower=100.0, upper=160.0)
        pct = node!(p, "Percentiles", ix; port="index", column="x", percentiles=[50.0])
        counter = node!(p, "Count", rq)
        run = run!(ProgressiveEngine(step_size=id -> 50), p)
        t = run.outputs[src.id]["result"]
        live = collect(row_ids(t))
        x = Dict(i => t[i, :x] for i in live)
        expected = [i for i in live if 100 <= x[i] < 160]
        @test selected(run, rq) == expected
        @test 10 in expected && !(120 in expected) && isempty(intersect(expected, 140:160))
        @test result_of(run, counter) == length(expected)
        @test result_of(run, pct)[50.0] == sort([x[i] for i in live])[1 + floor(Int, 0.5 * (length(live) - 1))]
        index = run.outputs[ix.id]["result"].meta[:index].bins[:x]
        @test sort(reduce(vcat, values(index.bins))) == live
    end

    @testset "One-shot engine: queries scan the rows" begin
        p = Pipeline()
        src = source!(p, "data")
        ix = node!(p, "BinningIndex", src; column="x", tol=1.0)
        rq = node!(p, "RangeQuery", ix; port="index", column="x", lower=-10.0, upper=40.0)
        cat = node!(p, "CategoricalQuery", src; column="cat", choice=["b"])
        pct = node!(p, "Percentiles", ix; port="index", column="x", percentiles=[50.0])
        progressive = run!(ProgressiveEngine(), p)
        oneshot = run!(OneShotEngine(), p)
        for m in (rq, cat, pct)
            @test isequal(result_of(oneshot, m), result_of(progressive, m))     # NaN in x
        end
    end
end
