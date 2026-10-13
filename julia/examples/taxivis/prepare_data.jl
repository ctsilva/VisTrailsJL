"""
Write the 2013 FOIL trips to an Arrow file, for TaxiVis.

    julia --project=julia --threads=auto julia/examples/taxivis/prepare_data.jl [--rows N]
    julia --project=julia --threads=auto julia/examples/taxivis/prepare_data.jl --year [--months 1-12] [--rows N]

January (default):
Reads TaxiVis' preprocessed KD-tree file `processed/2013_01.kdtrip` from the
directory in `FOIL2013` (default `~/data/FOIL2013`); nothing is downloaded.
Same rows, order and columns as ProgressiVis' `taxivis/prepare_data.py`:

- pickup/dropoff long/lat (Float32), distance (miles), fare and tip (dollars),
  passengers, payment type;
- `hour`: hours since 2013-01-01 00:00 New York time; `duration`: minutes;
- `pickup_nbhd`, `dropoff_nbhd`: neighborhood index (`regions.jl`), -1 if none.

Stratified order: the KD-tree leaves (trips, sorted in space) in bit-reversed
order, so every prefix is a sample spread over time and place.

`--year`: all trips of the months (default the whole year, about 170 M) from
the raw `Tripdata_2013/trip_data_M.csv` and `Faredata_2013/trip_fare_M.csv`,
whose rows correspond one to one (checked: same pickup time). Same columns,
in a random order with a fixed seed, so every prefix is a simple random
sample (what TaxiVis' accuracy estimates assume). `hour` counts New York
wall-clock hours since 2013-01-01 00:00 (so `hour % 24` is the hour of day,
across daylight saving time). Missing coordinates become 0 (outside NYC),
missing numbers 0; passenger counts are clamped to 0-255.
"""

using Arrow
using CSV
using Dates
using Mmap
using Random

include(joinpath(@__DIR__, "regions.jl"))

const MONTH_START = 1357016400   # 2013-01-01 00:00 EST (UTC-5) as a UTC epoch
const NODE_BYTES = 12            # uint64 child_node, uint32 median_value (packed)
const TRIP_BYTES = 56            # TaxiVis' packed KdTrip record
const LEAF_SPAN = 1 + 1 + (TRIP_BYTES + 8) ÷ NODE_BYTES   # nodes per leaf
const TRIP_OFFSET = 8            # of the trip in its leaf node

data_dir() = get(ENV, "FOIL2013", joinpath(homedir(), "data", "FOIL2013"))
kdtrip_path(month=1) = joinpath(data_dir(), "processed", "2013_$(lpad(month, 2, '0')).kdtrip")
arrow_path(rows=nothing) = joinpath(@__DIR__, "data", "taxivis_2013_01_stratified" *
                                    (rows === nothing ? "" : "_$rows") * ".arrow")

# Little-endian loads at any byte offset (records are packed, not aligned)
@inline load_le(::Type{T}, raw::Vector{UInt8}, offset::Int) where {T} =
    ltoh(unsafe_load(Ptr{T}(pointer(raw, offset + 1))))

"""
    kdtrip_leaves(raw) -> Vector{Int}

Node index of every leaf (trip) of the KD-tree, in file order: an inner node's
left child follows it and its right child follows the left subtree's first
node (a single node, or a whole leaf), as in ProgressiVis' `read_kdtrip`.
"""
function kdtrip_leaves(raw::Vector{UInt8})
    child(i) = load_le(UInt64, raw, i * NODE_BYTES)
    leaves = Int[]
    frontier = [0]
    while !isempty(frontier)
        next = Int[]
        for node in frontier
            c = child(node)
            if c == 0
                push!(leaves, node)
            else
                left = Int(c)
                push!(next, left, left + (child(left) == 0 ? LEAF_SPAN : 1))
            end
        end
        frontier = next
    end
    return sort!(leaves)
end

"Indices 1..n sorted by the bit-reversal of their 0-based value (van der Corput)"
function bit_reversed_order(n::Int)
    bits = max(1, ndigits(n - 1; base=2))
    keys = [bitreverse(UInt64(i)) >> (64 - bits) for i in 0:n-1]
    return sortperm(keys)   # keys are distinct
end

function trip_columns(raw::Vector{UInt8}, leaves::Vector{Int})
    n = length(leaves)
    cols = (pickup_time=Vector{UInt32}(undef, n), dropoff_time=Vector{UInt32}(undef, n),
            pickup_long=Vector{Float32}(undef, n), pickup_lat=Vector{Float32}(undef, n),
            dropoff_long=Vector{Float32}(undef, n), dropoff_lat=Vector{Float32}(undef, n),
            distance=Vector{Float64}(undef, n), fare_amount=Vector{Float64}(undef, n),
            tip_amount=Vector{Float64}(undef, n), payment_type=Vector{UInt8}(undef, n),
            passengers=Vector{UInt8}(undef, n))
    Threads.@threads for i in 1:n
        o = leaves[i] * NODE_BYTES + TRIP_OFFSET
        cols.pickup_time[i] = load_le(UInt32, raw, o)
        cols.dropoff_time[i] = load_le(UInt32, raw, o + 4)
        cols.pickup_long[i] = load_le(Float32, raw, o + 8)
        cols.pickup_lat[i] = load_le(Float32, raw, o + 12)
        cols.dropoff_long[i] = load_le(Float32, raw, o + 16)
        cols.dropoff_lat[i] = load_le(Float32, raw, o + 20)
        # hundredths of a unit become units, as in foil2013.columns
        cols.distance[i] = load_le(UInt16, raw, o + 42) / 100.0
        cols.fare_amount[i] = load_le(UInt16, raw, o + 44) / 100.0
        cols.tip_amount[i] = load_le(UInt16, raw, o + 50) / 100.0
        cols.payment_type[i] = raw[o + 54 + 1]
        cols.passengers[i] = raw[o + 55 + 1]
    end
    return cols
end

function prepare(; rows::Union{Nothing, Int}=nothing, month::Int=1)
    t0 = time()
    path = kdtrip_path(month)
    isfile(path) || error("$path not found: set FOIL2013 to the FOIL 2013 data directory")
    raw = Mmap.mmap(path)
    leaves = kdtrip_leaves(raw)
    leaves = leaves[bit_reversed_order(length(leaves))]
    rows === nothing || (leaves = leaves[1:min(rows, end)])
    c = trip_columns(raw, leaves)
    println("  $(length(leaves)) trips read in $(round(time() - t0, digits=1)) s")

    pickup = Int64.(c.pickup_time)
    regions = load_regions()
    t1 = time()
    out = (pickup_long=c.pickup_long, pickup_lat=c.pickup_lat,
           dropoff_long=c.dropoff_long, dropoff_lat=c.dropoff_lat,
           distance=c.distance, fare_amount=c.fare_amount, tip_amount=c.tip_amount,
           passengers=c.passengers, payment_type=c.payment_type,
           hour=(pickup .- MONTH_START) ./ 3600.0,
           duration=(Int64.(c.dropoff_time) .- pickup) ./ 60.0,
           pickup_nbhd=locate(regions, c.pickup_long, c.pickup_lat),
           dropoff_nbhd=locate(regions, c.dropoff_long, c.dropoff_lat))
    println("  neighborhoods in $(round(time() - t1, digits=1)) s")

    target = arrow_path(rows)
    Arrow.write(target, out)
    println("$(length(leaves)) trips -> $target ($(round(filesize(target) / 1e6)) MB, " *
            "$(round(time() - t0, digits=1)) s)")
    return target
end

# ------------------------------------------------------------ year, from the CSVs

year_path(months, rows=nothing) =
    joinpath(@__DIR__, "data", "taxivis_2013" * (months == 1:12 ? "" : "_$(first(months))-$(last(months))") *
             "_random" * (rows === nothing ? "" : "_$rows") * ".arrow")

const PAYMENT_CODES = Dict("CSH" => 0x00, "DIS" => 0x01, "NOC" => 0x02, "CRD" => 0x03, "UNK" => 0x04)
const YEAR_START = DateTime(2013, 1, 1)
const STAMP = dateformat"yyyy-mm-dd HH:MM:SS"

orzero(::Type{T}, x) where {T} = ismissing(x) ? zero(T) : T(x)
hours_since_start(t::DateTime) = Dates.value(t - YEAR_START) / 3_600_000

"The columns of one month, from its trip and fare CSVs"
function month_columns(month::Int)
    trips = CSV.File(joinpath(data_dir(), "Tripdata_2013", "trip_data_$month.csv");
                     select=[6, 7, 8, 10, 11, 12, 13, 14], normalizenames=true,
                     types=Dict(6 => DateTime, 7 => DateTime, 8 => Int, 10 => Float64,
                                11 => Float32, 12 => Float32, 13 => Float32, 14 => Float32),
                     dateformat=STAMP, ntasks=Threads.nthreads())
    fares = CSV.File(joinpath(data_dir(), "Faredata_2013", "trip_fare_$month.csv");
                     select=[4, 5, 6, 9], normalizenames=true,
                     types=Dict(4 => DateTime, 5 => String, 6 => Float64, 9 => Float64),
                     dateformat=STAMP, ntasks=Threads.nthreads())
    n = length(trips)
    length(fares) == n || error("month $month: $n trips but $(length(fares)) fares")
    tp, tf = trips.pickup_datetime, fares.pickup_datetime
    mismatched = count(i -> !isequal(tp[i], tf[i]), 1:n)
    mismatched == 0 || error("month $month: $mismatched rows with different pickup times in trips and fares")
    drop = trips.dropoff_datetime
    return (pickup_long=orzero.(Float32, trips.pickup_longitude), pickup_lat=orzero.(Float32, trips.pickup_latitude),
            dropoff_long=orzero.(Float32, trips.dropoff_longitude), dropoff_lat=orzero.(Float32, trips.dropoff_latitude),
            distance=orzero.(Float64, trips.trip_distance),
            fare_amount=orzero.(Float64, fares.fare_amount), tip_amount=orzero.(Float64, fares.tip_amount),
            passengers=[UInt8(clamp(orzero(Int, p), 0, 255)) for p in trips.passenger_count],
            payment_type=[ismissing(p) ? 0x04 : get(PAYMENT_CODES, p, 0x04) for p in fares.payment_type],
            hour=hours_since_start.(tp),
            duration=[ismissing(d) ? 0.0 : Dates.value(d - t) / 60_000 for (t, d) in zip(tp, drop)])
end

function prepare_year(; months=1:12, rows::Union{Nothing, Int}=nothing, seed::Int=2013)
    t0 = time()
    names = nothing
    parts = map(months) do m
        t = time()
        c = month_columns(m)
        names = keys(c)
        println("  month $m: $(length(c.hour)) trips in $(round(time() - t, digits=1)) s")
        GC.gc()
        Dict{Symbol, AbstractVector}(pairs(c))
    end
    n = sum(p -> length(p[:hour]), parts)
    order = randperm(Xoshiro(seed), n)
    rows === nothing || (order = order[1:min(rows, n)])
    # one column at a time: concatenate, permute, free the months' copies
    # (peak: the data once plus two columns)
    cols = map(names) do name
        all = reduce(vcat, (pop!(p, name) for p in parts))
        permuted = all[order]
        all = nothing; GC.gc()
        permuted
    end
    out = NamedTuple{names}(cols)
    t1 = time()
    regions = load_regions()
    out = merge(out, (pickup_nbhd=locate(regions, out.pickup_long, out.pickup_lat),
                      dropoff_nbhd=locate(regions, out.dropoff_long, out.dropoff_lat)))
    println("  neighborhoods in $(round(time() - t1, digits=1)) s")
    target = year_path(months, rows)
    Arrow.write(target, out)
    println("$(length(order)) trips -> $target ($(round(filesize(target) / 1e6)) MB, " *
            "$(round(time() - t0, digits=1)) s)")
    return target
end

function months_option()
    i = findfirst(==("--months"), ARGS)
    i === nothing && return 1:12
    a, b = parse.(Int, split(ARGS[i + 1], '-'; limit=2) |> x -> length(x) == 1 ? [x[1], x[1]] : x)
    return a:b
end

if abspath(PROGRAM_FILE) == @__FILE__
    i = findfirst(==("--rows"), ARGS)
    rows = i === nothing ? nothing : parse(Int, ARGS[i + 1])
    "--year" in ARGS ? prepare_year(months=months_option(), rows=rows) : prepare(rows=rows)
end
