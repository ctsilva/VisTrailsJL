"""Inputs of the dashboard experiments, from the January Arrow file of the
TaxiVis example (stratified order, identical to ProgressiVis' Parquet file):
the six dashboard columns as data/strat.npz (Python's in-memory source),
data/strat.parquet (file source of both), data/strat.arrow (Julia), and
the first 200 000 rows as data/strat_warmup.parquet (Julia's warm-up).

    .venv-std/bin/python prepare_data.py
"""
import os
import numpy as np
import pyarrow as pa
import pyarrow.feather as feather
import pyarrow.parquet as pq

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "examples", "taxivis", "data", "taxivis_2013_01_stratified.arrow")
COLUMNS = ["pickup_long", "pickup_lat", "dropoff_long", "dropoff_lat", "distance", "passengers"]
out = os.path.join(HERE, "data")
os.makedirs(out, exist_ok=True)
t = feather.read_table(SRC, columns=COLUMNS)
cols = {c: t[c].to_numpy() for c in COLUMNS}
np.savez(os.path.join(out, "strat.npz"), **cols)
pq.write_table(pa.table(cols), os.path.join(out, "strat.parquet"))
pq.write_table(pa.table({c: v[:200_000] for c, v in cols.items()}), os.path.join(out, "strat_warmup.parquet"))
# Non-nullable fields: Julia reads nullable ones as Union{Missing, T}
schema = pa.schema([pa.field(c, pa.from_numpy_dtype(v.dtype), nullable=False) for c, v in cols.items()])
# One record batch, as the TaxiVis file (Arrow.jl reads several as a ChainedVector)
n = len(cols["pickup_long"])
feather.write_feather(pa.table(cols, schema=schema), os.path.join(out, "strat.arrow"),
                      compression="uncompressed", chunksize=n)
print({k: (v.dtype.name, len(v)) for k, v in cols.items()})
