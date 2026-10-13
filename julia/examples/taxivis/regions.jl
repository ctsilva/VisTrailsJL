"""
NYC neighborhoods (from TaxiVis) and the neighborhood of a point.

`data/neighborhoods.txt` is TaxiVis's `data/neighborhoods.txt` (Copyright (c)
2013-2015, New York University; BSD license): a count, then for each region its
name, number of polygons, and for each polygon its number of vertices and
`lon lat` lines.

`locate` assigns points by ray casting after a bounding-box test per region,
with the same arithmetic as ProgressiVis' `taxivis/regions.py`, so both label
every trip identically. The last matching region wins.
"""

const REGIONS_PATH = joinpath(@__DIR__, "data", "neighborhoods.txt")

struct Region
    name::String
    polygons::Vector{Vector{NTuple{2, Float64}}}
    bbox::NTuple{4, Float64}       # x0, x1, y0, y1
    center::NTuple{2, Float64}     # mean vertex of the largest polygon
end

function load_regions(path::AbstractString=REGIONS_PATH)
    lines = split(read(path, String), '\n')
    i = 1
    n = parse(Int, lines[i]); i += 1
    regions = Region[]
    for _ in 1:n
        name = String(strip(lines[i])); i += 1
        npoly = parse(Int, lines[i]); i += 1
        polygons = Vector{NTuple{2, Float64}}[]
        for _ in 1:npoly
            nv = parse(Int, lines[i]); i += 1
            push!(polygons, [(parse(Float64, a), parse(Float64, b))
                             for (a, b) in (split(lines[i + k]) for k in 0:nv-1)])
            i += nv
        end
        xs = [p[1] for poly in polygons for p in poly]
        ys = [p[2] for poly in polygons for p in poly]
        biggest = polygons[argmax(length.(polygons))]
        center = (sum(first, biggest) / length(biggest), sum(last, biggest) / length(biggest))
        push!(regions, Region(name, polygons, (minimum(xs), maximum(xs), minimum(ys), maximum(ys)), center))
    end
    return regions
end

# Even-odd ray casting, as in regions.py (x < xint, crossings toggle)
function inside(region::Region, x::Float64, y::Float64)
    result = false
    for poly in region.polygons
        n = length(poly)
        for j in 1:n
            xa, ya = poly[j]
            xb, yb = poly[mod1(j + 1, n)]
            if (ya > y) != (yb > y)
                xint = xa + (y - ya) * (xb - xa) / (yb - ya)
                x < xint && (result = !result)
            end
        end
    end
    return result
end

"""
    locate(regions, lon, lat) -> Vector{Int16}

Neighborhood index (0-based, as in the trip files) of each point, -1 if none.
"""
function locate(regions::Vector{Region}, lon::AbstractVector, lat::AbstractVector)
    out = fill(Int16(-1), length(lon))
    Threads.@threads for i in eachindex(lon, lat)
        x, y = Float64(lon[i]), Float64(lat[i])
        for (k, r) in enumerate(regions)
            bx0, bx1, by0, by1 = r.bbox
            (bx0 <= x <= bx1 && by0 <= y <= by1) || continue
            inside(r, x, y) && (out[i] = Int16(k - 1))
        end
    end
    return out
end

"The regions as the page expects them from `GET /regions` (vertices rounded to 5 decimals)"
regions_json(regions::Vector{Region}) =
    [Dict("name" => r.name, "center" => collect(r.center), "bbox" => collect(r.bbox),
          "polygons" => [[[round(x, digits=5), round(y, digits=5)] for (x, y) in p] for p in r.polygons])
     for r in regions]
