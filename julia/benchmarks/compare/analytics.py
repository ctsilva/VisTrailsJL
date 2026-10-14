"""Tier-4 analytics modules in ProgressiVis, on the January taxi trips (data/strat.npz,
14.8 M rows, in memory through a Constant source) and on generated blobs.
Counterpart of analytics.jl; prints one JSON line per workload.

    PYTHONPATH=trees/head .venv-std/bin/python py_shim.py analytics.py [rows|0 [kmeans,ppca,scaler,blobs]]
"""
import json, os, sys, time
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROWS = int(sys.argv[1]) if len(sys.argv) > 1 and int(sys.argv[1]) > 0 else None
COLUMNS = ["pickup_long", "pickup_lat", "dropoff_long", "dropoff_lat", "distance", "passengers"]


def main():
    from progressivis import Scheduler, Constant, Sink, ConstDict, PDict
    from progressivis.core import aio
    from progressivis.table.api import PTable
    from progressivis.cluster.mb_k_means import MBKMeans
    from progressivis.stats.ppca import PPCA
    from progressivis.stats.scaling import MinMaxScaler
    from progressivis.stats.blobs_table import BlobsPTable

    d = np.load(os.path.join(HERE, "data", "strat.npz"))
    data = {c: (d[c][:ROWS] if ROWS else d[c]).astype("float64") for c in COLUMNS}
    n = len(data["pickup_long"])

    def timed(build):
        s = Scheduler()
        with s:
            out = build(s)
        t0 = time.perf_counter()
        aio.run(s.start())
        return time.perf_counter() - t0, out

    def source(s, columns=COLUMNS):
        return Constant(PTable(name=None, data={c: data[c] for c in columns}), scheduler=s)

    # k-means on the pickups, until the centers converge. A table of the two
    # columns: with a column hint, MBKMeans fails writing its centers
    # ("Adding new columns (...) via __setitem__ not implemented"). Not
    # greedy: a greedy MBKMeans keeps iterating after converging, and the
    # run never ends
    def kmeans(s, seed):
        km = MBKMeans(n_clusters=10, batch_size=1024, random_state=seed, is_greedy=False, scheduler=s)
        km.input.table = source(s, ["pickup_long", "pickup_lat"]).output.result
        sink = Sink(scheduler=s)
        sink.input.inp = km.output.result
        return km
    only = sys.argv[2].split(",") if len(sys.argv) > 2 else None
    want = lambda name: only is None or name in only
    if want("kmeans"):
        # Iterations to convergence depend on the seed (outliers): five seeds
        for seed in range(5):
            t, km = timed(lambda s: kmeans(s, seed))
            print(json.dumps({"workload": "MBKMeans k=10", "seed": seed, "rows": n, "seconds": t,
                              "iterations": km._cur_iter, "ms_per_iteration": 1000 * t / km._cur_iter,
                              "converged": km._has_converged}), flush=True)

    # Incremental PCA of the six columns, and the projection of every row
    def ppca(s, transform):
        p = PPCA(scheduler=s)
        p.params.n_components = 2
        p.input.table = source(s).output.result
        if transform:
            p.create_dependent_modules()
            sink = Sink(scheduler=s)
            sink.input.inp = p.dep.reduced.output.result
        else:
            sink = Sink(scheduler=s)
            sink.input.inp = p.output.result
        return p
    if want("ppca"):
        t, p = timed(lambda s: ppca(s, False))
        print(json.dumps({"workload": "PPCA (fit)", "rows": n, "seconds": t}), flush=True)
        t, p = timed(lambda s: ppca(s, True))
        print(json.dumps({"workload": "PPCA + PPCATransformer", "rows": n, "seconds": t,
                          "projected": len(p.dep.reduced.result)}), flush=True)

    # MinMaxScaler of the six columns, with its Min and Max. With a control
    # input: without one, the module fails ("slot 'control' not connected")
    def scaler(s):
        sc = MinMaxScaler(reset_threshold=10_000, scheduler=s)
        sc.create_dependent_modules(source(s))
        cst = ConstDict(pdict=PDict({"delta": -5, "ignore_max": 0}), scheduler=s)
        sc.input.control = cst.output.result
        sink = Sink(scheduler=s)
        sink.input.inp = sc.output.result
        return sc
    if want("scaler"):
        t, sc = timed(scaler)
        print(json.dumps({"workload": "MinMaxScaler (+ Min, Max)", "rows": n, "seconds": t,
                          "scaled": len(sc.result)}), flush=True)

    # Blobs: generate as many rows, 2 columns, 3 centers
    def blobs(s):
        b = BlobsPTable(columns=["x", "y"], rows=n, centers=[(0.0, 0.0), (6.0, 6.0), (-6.0, 6.0)], seed=1, scheduler=s)
        sink = Sink(scheduler=s)
        sink.input.inp = b.output.result
        return b
    if want("blobs"):
        t, b = timed(blobs)
        print(json.dumps({"workload": "Blobs", "rows": len(b.result), "seconds": t}), flush=True)


if __name__ == "__main__":
    main()
