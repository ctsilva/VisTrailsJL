"""
Write the January 2013 FOIL trips in stratified order to an Arrow file, for TaxiVis.

    julia --project=julia --threads=auto julia/examples/taxivis/prepare_data.jl [--rows N]

Reads TaxiVis' preprocessed KD-tree file `processed/2013_01.kdtrip` from the
directory in `FOIL2013` (default `~/data/FOIL2013`); nothing is downloaded.
Same rows, order and columns as ProgressiVis' `taxivis/prepare_data.py`:

- pickup/dropoff long/lat (Float32), distance (miles), fare and tip (dollars),
  passengers, payment type;
- `hour`: hours since 2013-01-01 00:00 New York time; `duration`: minutes;
- `pickup_nbhd`, `dropoff_nbhd`: neighborhood index (`regions.jl`), -1 if none.

Stratified order: the KD-tree leaves (trips, sorted in space) in bit-reversed
order, so every prefix is a sample spread over time and place.
"""

using Arrow
using Mmap

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

if abspath(PROGRAM_FILE) == @__FILE__
    i = findfirst(==("--rows"), ARGS)
    prepare(rows=i === nothing ? nothing : parse(Int, ARGS[i + 1]))
end
