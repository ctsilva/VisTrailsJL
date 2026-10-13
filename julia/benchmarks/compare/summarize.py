"""
Median tables of a comparison run, as Markdown.

    python3 summarize.py results/NAME > results/NAME/summary.md
"""
import json, os, sys
from collections import defaultdict
from statistics import median

d = sys.argv[1]
meta = json.load(open(os.path.join(d, "meta.json")))


def load(name):
    p = os.path.join(d, name)
    return [json.loads(l) for l in open(p)] if os.path.exists(p) else []


def fmt(x, digits=3):
    return "–" if x is None else f"{x:.{digits}f}"


print(f"# Julia vs Python, preliminary ({meta['started']})\n")
print(f"{meta['machine']}, {meta['cores']} cores; ProgressiVis tree `{os.path.basename(meta['progressivis_tree'])}`; "
      f"VisTrailsJL `{meta['vistrailsjl']}`; {meta['julia']}. Medians of the repeats.\n")

# ---------------------------------------------------------------- E1
rows = load("e1.jsonl")
if rows:
    groups = defaultdict(list)
    for r in rows:
        who = f"Python {r['interp']}" if r["system"] == "python" else f"Julia {r['threads']} thr"
        groups[(r["source"], r.get("var", True), who, r["workers"])].append(r)
    print("## E1: taxi dashboard (January 2013, 14.8 M rows)\n")
    print("Wall time of the run (s), time to the first pickup heatmap (ms), heatmap updates, histogram resets, "
          "peak memory (MB), all runs exact. Julia: after a warm-up run (compilation not included; "
          "see the cold column, a first run on 200 000 rows).\n")
    print("| Source | Var | System | W | wall (s) | first map (ms) | updates | resets | MB | exact | Julia cold (s) |")
    print("| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |")
    for key in sorted(groups, key=lambda k: (k[0] != "memory", k[1], k[2], k[3])):
        g = groups[key]
        src, var, who, w = key
        wall = median(r["wall"] for r in g)
        first = [r["first_heatmap"] for r in g if r.get("first_heatmap") is not None]
        cold = [r["warmup_s"] for r in g if r.get("warmup_s")]
        print(f"| {src} | {'yes' if var else 'no'} | {who} | {w} | {fmt(wall)} | "
              f"{fmt(median(first) * 1000, 1) if first else '–'} | {median(r['heatmap_updates'] for r in g):.0f} | "
              f"{median(r['resets'] for r in g):.0f} | {median(r['maxrss_mb'] for r in g):.0f} | "
              f"{all(r['ok'] for r in g)} ({len(g)}) | {fmt(median(cold), 1) if cold else ''} |")
    print()

# ---------------------------------------------------------------- E3
rows = load("e3.jsonl")
if rows:
    groups = defaultdict(list)
    for r in rows:
        who = f"Python {r['interp']}" if r["system"] == "python" else f"Julia {r['threads']} thr"
        groups[(r["shape"], who, r["workers"])].append(r)
    print("## E3: graph shapes (K = 4, 1 M rows)\n")
    print("| Shape | System | W=1 wall (s) | W=4 wall (s) | W=4 speedup | W=4 first result (ms) |")
    print("| --- | --- | ---: | ---: | ---: | ---: |")
    for shape in ("pipelines", "fanout", "uneven", "narrow"):
        for who in sorted({k[1] for k in groups if k[0] == shape}):
            w1 = median(r["wall_s"] for r in groups[(shape, who, 1)]) if (shape, who, 1) in groups else None
            w4g = groups.get((shape, who, 4), [])
            w4 = median(r["wall_s"] for r in w4g) if w4g else None
            first = [r["first_result_s"] for r in w4g if r.get("first_result_s") is not None]
            print(f"| {shape} | {who} | {fmt(w1)} | {fmt(w4)} | {fmt(w1 / w4, 2) if w1 and w4 else '–'}x | "
                  f"{fmt(median(first) * 1000, 1) if first else '–'} |")
    print()

# ---------------------------------------------------------------- E4
rows = load("e4.jsonl")
if rows:
    table = defaultdict(dict)   # (scenario, who) -> width -> (median, ok)
    for r in rows:
        if r["system"] == "python":
            for scenario, results in r["raw"]["results"].items():
                for x in results:
                    table[(scenario, f"Python {r['interp']}")][x["width"]] = (x["median_s"], x["correct"])
    jl = defaultdict(list)
    for r in rows:
        if r["system"] == "julia":
            jl[(r["scenario"], r["threads"])].append(r)
    for (scenario, threads), g in jl.items():
        table[(scenario, "Julia")][threads] = (median(r["wall"] for r in g), all(r["ok"] for r in g))
    widths = sorted({w for v in table.values() for w in v})
    print("## E4: one module, 20 M x 8 Float64 in memory (2 workers)\n")
    print("Wall time (s) by data width: Python's forced step width, Julia's thread count; "
          "speedup is width 1 over the best.\n")
    print("| Module | System | " + " | ".join(f"w={w}" for w in widths) + " | best speedup | exact |")
    print("| --- | --- | " + " | ".join("---:" for _ in widths) + " | ---: | --- |")
    for scenario in ("var", "minmax", "hist1d", "hist2d"):
        for who in ("Python std", "Python ft", "Julia"):
            v = table.get((scenario, who))
            if not v:
                continue
            cells = [fmt(v[w][0]) if w in v else "–" for w in widths]
            best = min(t for t, _ in v.values())
            print(f"| {scenario} | {who} | " + " | ".join(cells) +
                  f" | {fmt(v[min(v)][0] / best, 2)}x | {all(ok for _, ok in v.values())} |")
    print()
