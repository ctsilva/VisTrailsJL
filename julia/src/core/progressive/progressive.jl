"""
Progressive data layer (Phase 3a of docs/PROGRESSIVE_EXECUTION_PLAN.md)

Change-tracked containers that progressive modules produce and consume:
`ProgressiveTable` (growing columnar table), `ProgressiveDict` (small keyed
results) and `ProgressiveValue` (any replaceable value), with per-consumer
subscriptions to their changes.
"""

include("ids.jl")
include("subscriptions.jl")
include("table.jl")
include("dict.jl")
include("engine.jl")
include("helpers.jl")
include("provenance.jl")
