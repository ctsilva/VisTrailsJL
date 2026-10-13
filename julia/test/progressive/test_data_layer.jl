"""
Tests for the progressive data layer (Phase 3a of docs/PROGRESSIVE_EXECUTION_PLAN.md)

Run with several threads: julia --project=. --threads=4 test/progressive/test_data_layer.jl
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Test
using Random
using Tables

const VT = VisTrailsJL

# Is the RowIds representation canonical: sorted, non-empty, non-adjacent ranges?
canonical(s::RowIds) = all(!isempty, ranges(s)) &&
    all(last(ranges(s)[i]) + 1 < first(ranges(s)[i + 1]) for i in 1:length(ranges(s)) - 1)

random_range(rng, maxid) = (a = rand(rng, 1:maxid); a:min(maxid, a + rand(rng, 0:5)))

@testset "Progressive data layer" begin
    @testset "RowIds against a Set oracle" begin
        rng = MersenneTwister(1)
        for trial in 1:200
            s, oracle = RowIds(), Set{Int}()
            for step in 1:60
                op = rand(rng, 1:5)
                if op == 1
                    r = random_range(rng, 80); add!(s, r); union!(oracle, r)
                elseif op == 2
                    i = rand(rng, 1:80); add!(s, i); push!(oracle, i)
                elseif op == 3
                    r = random_range(rng, 80); remove!(s, r); setdiff!(oracle, r)
                elseif op == 4
                    other = RowIds(rand(rng, 1:80, 5))
                    if rand(rng, Bool)
                        union!(s, other); union!(oracle, other)
                    else
                        setdiff!(s, other); setdiff!(oracle, other)
                    end
                else
                    n = rand(rng, 0:10)
                    taken = take_first!(s, n)
                    expected = first(sort!(collect(oracle)), n)
                    @test collect(taken) == expected
                    setdiff!(oracle, expected)
                end
                @test canonical(s)
                @test collect(s) == sort!(collect(oracle))
                @test length(s) == length(oracle)
            end
            probe = rand(rng, 0:81)
            @test (probe in s) == (probe in oracle)
        end
        a, b = RowIds([1, 2, 3, 10]), RowIds([2, 10, 11])
        @test collect(intersect(a, b)) == [2, 10]
        @test collect(union(a, b)) == [1, 2, 3, 10, 11]
        @test collect(setdiff(a, b)) == [1, 3]
    end

    @testset "Table basics" begin
        t = ProgressiveTable(:x => Float64, :name => String; segment_size=3)
        @test isempty(t) && last_id(t) == 0
        @test append!(t, (x=[1.0, 2.0], name=["a", "b"])) == 1:2
        @test push!(t, (x=3.0, name="c")) == 3
        @test append!(t, (x=Float64[], name=String[])) == 4:3
        @test length(t) == 3 && last_id(t) == 3
        @test t[2, :name] == "b"
        @test collect(t[:x]) == [1.0, 2.0, 3.0]
        @test column_names(t) == [:x, :name]

        # Values are converted to the column type; wrong lengths are refused
        append!(t, (x=[4], name=["d"]))
        @test t[4, :x] === 4.0
        @test_throws DimensionMismatch append!(t, (x=[1.0, 2.0], name=["e"]))
        @test_throws KeyError t[1, :missing]

        t[1, :x] = 10.0
        @test t[1, :x] == 10.0
        delete!(t, 2)
        @test collect(row_ids(t)) == [1, 3, 4] && length(t) == 3
        @test_throws ArgumentError t[2, :x] = 0.0
        @test_throws ArgumentError delete!(t, 2)
        @test_throws ArgumentError delete!(t, 9)

        # Tables.jl: a snapshot of the live rows
        @test Tables.istable(t)
        @test Tables.columntable(t) == (x=[10.0, 3.0, 4.0], name=["a", "c", "d"])
        @test Tables.schema(t).names == (:x, :name)
        u = ProgressiveTable((a=[1, 2, 3], b=["p", "q", "r"]))
        @test Tables.columntable(u) == (a=[1, 2, 3], b=["p", "q", "r"])
        @test eltype(column(u, :a)) == Int
    end

    @testset "Segments never move" begin
        t = ProgressiveTable(:v => Int; segment_size=4)
        append!(t, (v=collect(1:6),))
        col = column(t, :v)
        first_segment = VT.segment(col, 1)
        for k in 1:100
            append!(t, (v=collect(1:k),))
        end
        @test VT.segment(col, 1) === first_segment
        @test first_segment[1:4] == [1, 2, 3, 4]
        @test length(col) == last_id(t)

        # Bulk reads: contiguous views across segment boundaries
        for r in [1:last_id(t), 3:9, 4:5, 5:5, 2:1, 17:40]
            views = segment_views(col, r)
            @test all(v -> length(v) <= 4, views)
            @test reduce(vcat, collect.(views); init=Int[]) == col[r]
        end
        @test_throws BoundsError segment_views(col, 1:last_id(t)+1)

        # Values at arbitrary ids, across segments
        ids = [last_id(t), 1, 5, 4, 5, 17]
        @test gather(col, ids) == col[ids]
        @test gather(col, Int[]) == Int[]
        @test_throws BoundsError gather(col, [0])
        @test_throws BoundsError gather(col, [last_id(t) + 1])
    end

    @testset "Subscriptions" begin
        t = ProgressiveTable(:v => Int)
        append!(t, (v=[1, 2, 3],))
        early = subscribe!(t)
        @test pending(early) == (created=3, updated=0, deleted=0)  # existing rows count as created

        append!(t, (v=[4, 5],))
        late = subscribe!(t)
        @test collect(next_created!(early, 2)) == [1, 2]            # bounded, smallest first
        @test collect(next_created!(early)) == [3, 4, 5]
        @test !has_changes(early)
        @test pending(late).created == 5                             # independent pace

        t[1, :v] = 100      # read by `early`: an update
        t[5, :v] = 500      # read by `early`: an update
        @test collect(next_updated!(early)) == [1, 5]
        @test pending(late) == (created=5, updated=0, deleted=0)    # unread rows: still created

        delete!(t, 2:3)
        @test collect(next_deleted!(early)) == [2, 3]
        @test pending(late) == (created=3, updated=0, deleted=0)    # never saw them: nothing to report

        reset!(early)
        @test collect(next_created!(early)) == [1, 4, 5]

        unsubscribe!(late)
        append!(t, (v=[6],))
        @test pending(late).created == 3
        @test pending(early).created == 1
    end

    @testset "A consumer mirroring the table through its changes" begin
        # Random appends, updates and deletions interleaved with random
        # bounded reads: applying the changes read keeps an exact copy.
        rng = MersenneTwister(3)
        for trial in 1:100
            t = ProgressiveTable(:v => Int; segment_size=rand(rng, 1:8))
            append!(t, (v=rand(rng, 1:100, rand(rng, 0:5)),))
            sub = subscribe!(t)
            mirror = Dict{Int, Int}()

            function consume!(n)
                for id in next_deleted!(sub, n)
                    @test haskey(mirror, id)
                    delete!(mirror, id)
                end
                for id in next_updated!(sub, n)
                    @test haskey(mirror, id)
                    mirror[id] = t[id, :v]
                end
                for id in next_created!(sub, n)
                    @test !haskey(mirror, id)
                    mirror[id] = t[id, :v]
                end
            end

            for step in 1:40
                live = collect(row_ids(t))
                op = rand(rng, 1:4)
                if op == 1
                    append!(t, (v=rand(rng, 1:100, rand(rng, 1:6)),))
                elseif op == 2 && !isempty(live)
                    t[rand(rng, live), :v] = rand(rng, 1:100)
                elseif op == 3 && !isempty(live)
                    delete!(t, RowIds(unique(rand(rng, live, rand(rng, 1:3)))))
                else
                    consume!(rand(rng, 1:4))
                end
            end
            consume!(typemax(Int))
            @test !has_changes(sub)
            @test mirror == Dict(id => t[id, :v] for id in row_ids(t))
        end
    end

    @testset "Concurrent producer and consumer" begin
        # The producer appends rows whose value is a function of their id while
        # a consumer on another thread reads them: every row is seen exactly
        # once, published values are complete, and no read sees a moved segment.
        n_rows = 200_000
        t = ProgressiveTable(:id2 => Int, :square => Float64; segment_size=1000)
        sub = subscribe!(t)

        producer = Threads.@spawn begin
            id = 0
            while id < n_rows
                k = min(rand(1:500), n_rows - id)
                ids = id+1:id+k
                append!(t, (id2=2 .* ids, square=Float64.(ids) .^ 2))
                id += k
            end
        end

        consumer = Threads.@spawn begin
            seen, bad = 0, 0
            while seen < n_rows
                batch = next_created!(sub, 777)
                if isempty(batch)
                    yield()
                    continue
                end
                for id in batch
                    seen += 1
                    (t[id, :id2] == 2id && t[id, :square] == Float64(id)^2) || (bad += 1)
                end
            end
            (seen, bad)
        end

        wait(producer)
        seen, bad = fetch(consumer)
        @test seen == n_rows
        @test bad == 0
        @test !has_changes(sub)
    end

    @testset "ProgressiveDict" begin
        d = ProgressiveDict{Symbol, Float64}(:min => 1.0)
        sub = subscribe!(d)
        @test take_changes!(sub).created == Set([:min])

        d[:min] = 1      # equal value: not a change
        @test !has_changes(sub)
        d[:min] = 0.5
        d[:max] = 9.0
        changes = take_changes!(sub)
        @test changes.updated == Set([:min]) && changes.created == Set([:max])
        @test !has_changes(sub)

        d[:tmp] = 1.0
        delete!(d, :tmp)                       # created then deleted, unread: nothing
        delete!(d, :max)                       # read: deleted
        changes = take_changes!(sub)
        @test isempty(changes.created) && changes.deleted == Set([:max])

        @test d[:min] == 0.5 && length(d) == 1 && haskey(d, :min)
        @test snapshot(d) == Dict(:min => 0.5)
        reset!(sub)
        @test take_changes!(sub).created == Set([:min])

        inferred = ProgressiveDict("a" => 1, "b" => 2)
        @test inferred isa ProgressiveDict{String, Int}
    end

    @testset "ProgressiveValue" begin
        pv = ProgressiveValue{Vector{Int}}()
        sub = subscribe!(pv)
        @test !has_value(pv) && !has_changes(sub)
        @test_throws ErrorException current_value(pv)

        set!(pv, [1, 2])
        @test has_changes(sub)
        @test take_value!(sub) == [1, 2]
        @test !has_changes(sub)

        set!(pv, [1, 2])                       # replacement is always a change
        @test has_changes(sub)
        @test current_value(pv) == [1, 2]

        late = subscribe!(ProgressiveValue(42))
        @test has_changes(late) && take_value!(late) == 42
    end
end
