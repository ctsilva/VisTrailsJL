# Progressive TaxiVis on VisTrailsJL

A Julia port of the progressive TaxiVis built on ProgressiVis
(`progressivis-parallel/taxivis`), itself a simplified TaxiVis (Ferreira et
al., "Visual Exploration of Big Spatio-Temporal Urban Data: A Study of New
York City Taxi Trips", TVCG 2013). Same data, same queries, same page and
HTTP API; the dataflow is a VisTrailsJL `Pipeline` run by the
`ProgressiveEngine` (`docs/EXECUTION.md`). Up to three colored queries
select trips by pickup and dropoff region (rectangles or neighborhoods),
days of the week, hours of the day and attribute ranges; every view updates
while the 14.8 million trips of January 2013 stream in, and every
interaction restarts a progressive computation instead of blocking.

## Requirements

- The FOIL 2013 data preprocessed by TaxiVis, locally: a directory with
  `processed/2013_01.kdtrip` (default `~/data/FOIL2013`, or set `FOIL2013`).
  Nothing is downloaded.
- A web browser. The page uses no external libraries or map tiles.

## Running

From the repository root:

```sh
# once: write julia/examples/taxivis/data/taxivis_2013_01_stratified.arrow (874 MB)
julia --project=julia --threads=auto julia/examples/taxivis/prepare_data.jl

# start the dataflow and the local server
julia --project=julia --threads=auto julia/examples/taxivis/app.jl

# then open
open http://127.0.0.1:8767/
```

The server listens on 127.0.0.1 only; Ctrl-C stops it. At full speed the
month is loaded before the page opens; to watch it arrive, use
`--rate 250000` (about 1 minute). On 8 threads the
month loads in about 3 s and all summaries are complete about 10 s after
start (including compilation); a neighborhood/weekday/hour query over all
trips completes in about 4 s, with first results (backend latency) in about
0.25 s. Individual observations, not a benchmark.

Options of `app.jl`:

| Option | Default | Meaning |
| --- | --- | --- |
| `--workers N` | threads | `ProgressiveEngine` workers |
| `--port P` | 8767 | HTTP port |
| `--bins B` | 512 | map resolution (B x B) |
| `--rate R` | off | load at most R rows per second, to watch loading (250000: about 1 minute for the month) |
| `--throttle R` | off | at most R rows per loader step |
| `--rows N` | all | use the N-row file written by `prepare_data.jl --rows N` |

The page (`static/index.html`, `static/client.js`) is ProgressiVis' page,
unchanged; see its README for how to use it.

## Dataflow

```
ArrowLoader ─┬─ TripHistogram × 4 (all trips: pickup/dropoff maps, neighborhoods)
             └─ TripFilter_q ── TripHistogram_q × 9 (maps, 5 attributes, neighborhoods)
   Variable (view bounds) ──► map histograms
   Variable (constraints_q) ──► TripFilter_q                       for q = 1, 2, 3
```

39 modules: the loader, the view and three constraints `Variable`s, 3
filters, 8 map, 15 attribute and 8 neighborhood histograms.

- `ArrowLoader` (package `progressive`) appends the memory-mapped rows of
  the Arrow file to a `ProgressiveTable`, in stratified order, so every
  prefix is a sample spread over time and place.
- A query edit validates the request (`normalize_query`), then
  `set_variable!` sets the query's constraints `Variable`; this gives the
  filter and its histograms interactive priority.
- `TripFilter` (package `taxivis`) tests chunks of rows against all of a
  query's constraints and appends the ids of matching trips to its
  selection; when its constraints change, it empties the selection, bumps
  its `revision` output and rescans from the first trip.
- `TripHistogram` counts the values of its selection (read with `gather`)
  or of all trips, and after every step publishes an immutable `Summary`
  tagged with the query revision it counts; map histograms rebin when the
  view bounds change.
- The server (`server.jl`) reads summaries for `/state` and `/map.png`, and
  reports a query or the view as ready when every summary it needs carries
  the current revision.

## Files

| File | Purpose |
| --- | --- |
| `prepare_data.jl` | trips in stratified order to Arrow, same rows, order and columns as ProgressiVis' `prepare_data.py` |
| `regions.jl` | reads the neighborhoods; neighborhood of points by ray casting (same arithmetic as `regions.py`) |
| `data/neighborhoods.txt` | 132 NYC neighborhoods, from TaxiVis (Copyright (c) 2013-2015, New York University, BSD license) |
| `dataflow.jl` | query validation, `TripFilter` and `TripHistogram` modules, the pipeline |
| `server.jl` | application state, `/state` snapshot, map rendering (PNG), HTTP routes |
| `TaxiVis.jl` | the example as a module (`include` it, then `using .TaxiVis`) |
| `app.jl` | command-line entry point |
| `static/` | the page, from ProgressiVis |

Endpoints, request and response JSON are those of ProgressiVis' `app.py`:
`GET /`, `/client.js`, `/state`, `/map.png`, `/regions`, `/debug`,
`POST /query`, `POST /view`. Invalid requests return JSON errors with HTTP
400.

## Validation

The Arrow file matches ProgressiVis' Parquet file column by column
(SHA-256 of every column). Financial District pickups on weekend nights
(Sat and Sun, 22-2 h) count 11,658 trips in the app and in NumPy over the
Parquet file. Browser interaction has not been checked yet.

## Limits

- One month (January 2013), as in ProgressiVis.
- No automated tests for the example yet (the `ArrowLoader` and `gather`
  it relies on are tested in `test/progressive/`).
