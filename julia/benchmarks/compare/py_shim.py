"""Run one of ProgressiVis' benchmark scripts unchanged on macOS: provides
os.sched_getaffinity (Linux only) and reports ru_maxrss in KiB as on Linux.

    python py_shim.py SCRIPT ARGS...
"""
import os, resource, runpy, sys

if not hasattr(os, "sched_getaffinity"):
    os.sched_getaffinity = lambda pid: set(range(os.cpu_count()))
if sys.platform == "darwin":  # ru_maxrss is in bytes on macOS, KiB on Linux
    _getrusage = resource.getrusage

    class _Usage:
        def __init__(self, u):
            self._u = u

        def __getattr__(self, name):
            v = getattr(self._u, name)
            return v / 1024 if name == "ru_maxrss" else v

    resource.getrusage = lambda who: _Usage(_getrusage(who))
script = sys.argv[1]
sys.argv = sys.argv[1:]
sys.path.insert(0, os.path.dirname(os.path.abspath(script)))
runpy.run_path(script, run_name="__main__")
