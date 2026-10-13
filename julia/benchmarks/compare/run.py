"""
Preliminary Julia (VisTrailsJL) vs Python (ProgressiVis, parallel-scheduler)
comparison: a subset of the ProgressiVis paper's experiments, same machine,
same data. Results go to results/<name>/{e1,e3,e4}.jsonl.

    python3 run.py [--name NAME] [--repeats 3] [--only e1,e3,e4]

E1  taxi dashboard (January 2013, 14.8 M rows): in memory, with and without
    Var; from file (Python: Parquet, Julia: Arrow). Python: the paper's
    bench_one.py, CPython 3.14 std and free-threaded, W = 1, 2, 4 (W > 1 with
    helper threads). Julia: dashboard.jl, 1 thread (W = 1) and all cores
    (W = 1, 4). Fresh process per run; repeats in shuffled order.
E3  graph shapes, K = 4, 1 M rows (bench_parallel.py / shapes.jl), W = 1, 4;
    Julia on 1 thread and on all cores.
E4  one module over 20 M x 8 rows in memory (bench_data_parallel.py, widths
    1..cores / modules.jl, threads 1..cores), 2 workers.

Python runs need ./setup_python.sh and prepare_data.py first.
"""
import argparse, json, os, random, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
JULIA_PROJECT = os.path.abspath(os.path.join(HERE, "..", ".."))
TREE = os.path.join(HERE, "trees", "head")
CORES = os.cpu_count()


def python_env(interp):
    env = dict(os.environ, PYTHONPATH=TREE, BENCH_DATA=os.path.join(HERE, "data"),
               PROGRESSIVIS_FOIL2013=os.path.expanduser("~/data/FOIL2013"))
    env.pop("PYTHON_GIL", None)
    if interp == "ft":
        env["PYTHON_GIL"] = "0"
    return env


def python_cmd(interp, script, *args):
    return [os.path.join(HERE, f".venv-{interp}", "bin", "python"), os.path.join(HERE, "py_shim.py"),
            os.path.join(TREE, script), *args]


def julia_cmd(threads, script, *args):
    return ["julia", f"--project={JULIA_PROJECT}", f"--threads={threads}", os.path.join(HERE, script), *args]


def run(cmd, env=None, timeout=1800):
    t = time.time()
    p = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=timeout)
    lines = [json.loads(l.split("RESULT ", 1)[1]) for l in p.stdout.splitlines() if l.startswith("RESULT ")]
    if p.returncode != 0 or not lines:
        print("FAILED:", " ".join(cmd[-3:]), p.stderr[-1500:], file=sys.stderr)
    return lines, time.time() - t


def e1(out, repeats):
    configs = []
    for var in (False, True):
        for interp in ("std", "ft"):
            for w in (1, 2, 4):
                configs.append(("python", interp, {"source": "memory", "workers": w, "width": "budget", "var": var}))
        for threads, w in ((1, 1), (CORES, 1), (CORES, 4)):
            configs.append(("julia", threads, {"source": "memory", "workers": w, "var": var}))
    for interp in ("std", "ft"):
        for w in (1, 4):
            configs.append(("python", interp, {"source": "parquet", "workers": w, "width": "budget", "var": True}))
    for threads, w in ((1, 1), (CORES, 4)):
        configs.append(("julia", threads, {"source": "arrow", "workers": w, "var": True}))
    rng = random.Random(2026)
    with open(out, "a") as f:
        for r in range(repeats):
            order = configs[:]
            rng.shuffle(order)
            for i, (system, x, cfg) in enumerate(order):
                if system == "python":
                    lines, secs = run(python_cmd(x, "design/benchmarks/master_vs_branch/bench_one.py", json.dumps(cfg)),
                                      env=python_env(x))
                    tag = {"system": "python", "interp": x}
                else:
                    lines, secs = run(julia_cmd(x, "dashboard.jl", json.dumps(cfg)))
                    tag = {"system": "julia", "threads": x}
                for rec in lines:
                    rec.update(tag, repeat=r, process_s=secs, loadavg=os.getloadavg()[0])
                    f.write(json.dumps(rec) + "\n"); f.flush()
                print(f"E1 repeat {r} {i + 1}/{len(order)} {tag} {cfg} {secs:.1f}s", flush=True)


def e3(out, repeats):
    with open(out, "a") as f:
        for interp in ("std", "ft"):
            js = out + f".{interp}.json"
            _, secs = run(python_cmd(interp, "scripts/bench_parallel.py", "4", "1000000", "--repeats", str(repeats),
                                     "--skip-upper-bound", "--json", js), env=python_env(interp))
            if os.path.exists(js):
                for rec in json.load(open(js))["runs"]:
                    rec.update(system="python", interp=interp)
                    f.write(json.dumps(rec) + "\n")
            print(f"E3 python {interp} {secs:.1f}s", flush=True)
        for threads in (1, CORES):
            lines, secs = run(julia_cmd(threads, "shapes.jl", "4", "1000000", str(repeats)))
            for rec in lines:
                f.write(json.dumps(rec) + "\n")
            print(f"E3 julia threads={threads} {secs:.1f}s", flush=True)


def e4(out, repeats):
    widths = sorted({1, 2, 4, 8, CORES})
    with open(out, "a") as f:
        for interp in ("std", "ft"):
            js = out + f".{interp}.json"
            _, secs = run(python_cmd(interp, "scripts/bench_data_parallel.py", "--rows", "20000000", "--cols", "8",
                                     "--widths", ",".join(map(str, widths)), "--workers", "2",
                                     "--repeats", str(repeats), "--json", js), env=python_env(interp), timeout=3600)
            if os.path.exists(js):
                f.write(json.dumps({"system": "python", "interp": interp, "raw": json.load(open(js))}) + "\n")
            print(f"E4 python {interp} {secs:.1f}s", flush=True)
        for threads in widths:
            lines, secs = run(julia_cmd(threads, "modules.jl", "20000000", "8", str(repeats), "2"))
            for rec in lines:
                f.write(json.dumps(rec) + "\n")
            print(f"E4 julia threads={threads} {secs:.1f}s", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default=time.strftime("%Y-%m-%d"))
    ap.add_argument("--repeats", type=int, default=3)
    ap.add_argument("--only", default="e1,e3,e4")
    args = ap.parse_args()
    out = os.path.join(HERE, "results", args.name)
    os.makedirs(out, exist_ok=True)
    meta = {"machine": subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True,
                                      text=True).stdout.strip(), "cores": CORES,
            "progressivis_tree": os.path.realpath(TREE),
            "vistrailsjl": subprocess.run(["git", "-C", HERE, "rev-parse", "--short", "HEAD"], capture_output=True,
                                          text=True).stdout.strip(),
            "julia": subprocess.run(["julia", "--version"], capture_output=True, text=True).stdout.strip(),
            "started": time.strftime("%Y-%m-%d %H:%M:%S")}
    json.dump(meta, open(os.path.join(out, "meta.json"), "w"), indent=2)
    for exp in args.only.split(","):
        {"e1": e1, "e3": e3, "e4": e4}[exp](os.path.join(out, f"{exp}.jsonl"), args.repeats)


if __name__ == "__main__":
    main()
