# Layout Strategy for Julia Implementation

## Key Insight: Most Workflows Have Existing Layouts

**Important:** Workflows in .vt files already have layout information from when users created/edited them in the VisTrails GUI. We should **use these existing positions** rather than recompute them.

## Workflow Layout Priority

### Primary Strategy: Use Stored Positions

1. **Parse `<location>` elements from .vt files**
   ```xml
   <module id="3" name="PythonCalc" ...>
     <location id="5" x="-123.45" y="67.89" />
   </module>
   ```

2. **Render directly from stored positions**
   - No layout computation needed
   - Preserves user's original design
   - Faster rendering (no algorithm overhead)

3. **Only compute layout when:**
   - No location data in .vt file (rare)
   - User explicitly requests relayout
   - Programmatically generated workflows (no manual editing)

### Implementation Priority

**Phase 1: Read & Render Existing Layouts (HIGH PRIORITY)**
```julia
# This is what we need FIRST
positions = extract_module_positions(vt_file)
svg = render_pipeline_svg(pipeline, positions)
```

**Phase 2: Auto-Layout Algorithm (LOWER PRIORITY)**
```julia
# Only needed for edge cases or auto-generation
layout = compute_workflow_layout(pipeline)
svg = render_pipeline_svg(pipeline, layout.positions)
```

---

## Version Tree Layout Priority

### Version Trees DO Need Auto-Layout

**Important difference:** Version trees grow dynamically and are rarely manually positioned.

1. **Version history changes over time** - new versions added
2. **No stored positions** in .vt files for version tree
3. **Must compute layout** every time

### Implementation Priority

**Phase 1: Tree Layout Algorithm (HIGH PRIORITY for version trees)**
```julia
tree = build_version_tree(vistrail)
layout = compute_tree_layout(tree)
svg = render_version_tree_svg(tree, layout)
```

---

## Revised Implementation Plan

### Immediate Focus (Week 1-2):

1. **✅ Parse existing module positions from .vt files**
   - Location elements in XML
   - Handle missing locations gracefully

2. **✅ Basic SVG renderer for workflows**
   - Use stored positions
   - Render modules as rectangles
   - Render connections as curves
   - Add labels

3. **✅ Test on real .vt files** (like gcd.vt)
   - Verify positions are correct
   - Generate usable SVGs

### Medium Priority (Week 3-4):

4. **✅ Version tree layout algorithm**
   - Port Walker's algorithm
   - SVG renderer for trees
   - Test on vistrail history

### Lower Priority (Future):

5. **Workflow auto-layout** (for programmatic generation)
   - Only needed when creating workflows from scratch
   - Can defer until needed

---

## Checking for Existing Positions

The `.vt` file structure stores positions in two places:

### 1. In the `<workflow>` Element (Snapshot)

```xml
<workflow>
  <module cache="1" id="3" name="PythonCalc" ...>
    <location id="5" x="-123.45" y="67.89" />
  </module>
</workflow>
```

**This is the easiest to use** - already parsed when loading the workflow.

### 2. In Action History (Replay)

```xml
<action id="42">
  <add what="location" objectId="5" parentObjId="3" parentObjType="module">
    <location id="5" x="-123.45" y="67.89" />
  </add>
</action>
```

When using action replay, we need to track locations too.

---

## Current Status in Julia Implementation

Let me check what we're already parsing...

Looking at `action_replay.jl`:
- ✅ Tracks `builder.locations`
- ✅ Parses `<location>` elements
- ❌ **NOT applied to modules yet!**

Looking at `io.jl` (workflow element parsing):
- ❌ **NOT parsing locations from workflow element yet!**

## Implementation Tasks

### Task 1: Extract Positions from Workflow Element

```julia
# In parse_module() - src/db/services/io.jl
function parse_module(elem::EzXML.Node, pipeline::Pipeline)
    # ... existing code ...

    # Parse location if present
    loc_elem = findfirst(".//location", elem)
    if loc_elem !== nothing
        loc_attrs = attrs_dict(loc_elem)
        x = parse(Float64, get(loc_attrs, "x", "0"))
        y = parse(Float64, get(loc_attrs, "y", "0"))
        mod.layout_position = (x, y)  # Store position
    end

    return mod
end
```

### Task 2: Extract Positions from Action Replay

```julia
# In build_pipeline_from_state() - src/db/services/action_replay.jl
function build_pipeline_from_state(builder::PipelineBuilder)
    # ... after adding module ...

    # Apply location if available
    for (loc_id, loc_data) in builder.locations
        # Find which module this location belongs to
        for (mod_xml_id, mod_data) in builder.modules
            if loc_data["parent_id"] == mod_xml_id
                if haskey(module_id_map, mod_xml_id)
                    mod_id = module_id_map[mod_xml_id]
                    mod = pipeline.modules[mod_id]
                    x = parse(Float64, loc_data["x"])
                    y = parse(Float64, loc_data["y"])
                    mod.layout_position = (x, y)
                end
            end
        end
    end
end
```

### Task 3: Add Position Field to ModuleInstance

```julia
# In src/core/vistrail/module.jl
mutable struct ModuleInstance
    id::Int
    descriptor::ModuleDescriptor
    inputs::Dict{String, Any}
    outputs::Dict{String, Any}
    parameters::Dict{String, Any}
    layout_position::Union{Tuple{Float64, Float64}, Nothing}  # ADD THIS
    # ... rest of fields ...
end

# Update constructor
function ModuleInstance(id, descriptor)
    ModuleInstance(
        id, descriptor,
        Dict{String, Any}(),
        Dict{String, Any}(),
        Dict{String, Any}(),
        nothing,  # layout_position starts as nothing
        # ... rest ...
    )
end
```

### Task 4: Basic SVG Renderer

```julia
# src/rendering/svg_renderer.jl
function render_pipeline_svg(pipeline::Pipeline; width=800, height=600)
    io = IOBuffer()

    # SVG header
    println(io, """<?xml version="1.0" encoding="UTF-8"?>""")
    println(io, """<svg width="$width" height="$height" xmlns="http://www.w3.org/2000/svg">""")

    # Find bounding box from module positions
    positions = [m.layout_position for m in values(pipeline.modules) if m.layout_position !== nothing]

    if isempty(positions)
        @warn "No layout positions found - cannot render"
        println(io, "</svg>")
        return String(take!(io))
    end

    # Transform coordinates (center to top-left)
    min_x = minimum(p[1] for p in positions)
    max_x = maximum(p[1] for p in positions)
    min_y = minimum(p[2] for p in positions)
    max_y = maximum(p[2] for p in positions)

    # Add margins
    margin = 50
    scale_x = (width - 2*margin) / (max_x - min_x)
    scale_y = (height - 2*margin) / (max_y - min_y)
    scale = min(scale_x, scale_y)

    # Transform function
    to_svg(x, y) = (
        margin + (x - min_x) * scale,
        margin + (y - min_y) * scale
    )

    # Render connections first (below modules)
    for conn in pipeline.connections
        src_mod = conn.source
        dst_mod = conn.destination

        if src_mod.layout_position !== nothing && dst_mod.layout_position !== nothing
            x1, y1 = to_svg(src_mod.layout_position...)
            x2, y2 = to_svg(dst_mod.layout_position...)

            # Simple line (can upgrade to Bezier curve later)
            println(io, """  <line x1="$x1" y1="$y1" x2="$x2" y2="$y2" stroke="#666" stroke-width="2"/>""")
        end
    end

    # Render modules
    for (id, mod) in pipeline.modules
        if mod.layout_position === nothing
            continue
        end

        x, y = to_svg(mod.layout_position...)

        # Module as rectangle (centered)
        w, h = 100, 40
        rx, ry = x - w/2, y - h/2

        println(io, """  <g class="module">""")
        println(io, """    <rect x="$rx" y="$ry" width="$w" height="$h" fill="#f0f0f0" stroke="#333" stroke-width="2" rx="5"/>""")
        println(io, """    <text x="$x" y="$(y+5)" text-anchor="middle" font-size="12">$(mod.descriptor.name)</text>""")
        println(io, """  </g>""")
    end

    println(io, "</svg>")
    return String(take!(io))
end
```

---

## Summary

**Key Changes to Plan:**

1. ✅ **FIRST:** Parse existing positions from .vt files
2. ✅ **SECOND:** Simple SVG renderer using those positions
3. ✅ **THIRD:** Version tree layout (actually needs auto-layout)
4. ⏸️ **DEFER:** Workflow auto-layout (only for edge cases)

This is much more practical - we can get useful visualizations quickly without implementing complex layout algorithms!

**Shall I start with Task 1-4 above to get basic SVG rendering working with existing positions?**
