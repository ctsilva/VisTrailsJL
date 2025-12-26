# VisTrails Layout System Analysis

## Overview

VisTrails has two main layout systems:
1. **Workflow Layout** - for pipeline/DAG visualization
2. **Version Tree Layout** - for version history visualization

Both use pure geometric algorithms independent of rendering (Qt is only for display, not layout computation).

## 1. Workflow Layout (`workflow_layout.py`)

### Core Algorithm

**Purpose:** Layout a DAG (directed acyclic graph) of modules and connections as layers.

**Key Components:**

1. **Data Structures:**
   - `Vec2` - 2D vector (x, y) with arithmetic operations
   - `Module` - workflow node with:
     - `layout_pos: Vec2` - center position
     - `layout_dim: Vec2` - width/height dimensions
     - `layout_layer_number` - which horizontal layer (0, 1, 2...)
     - `layout_layer_index` - position within layer
   - `Port` - input/output port on a module with its own position
   - `Connection` - edge between two ports
   - `Layer` - horizontal stripe containing modules at same depth
   - `Page` - bounding box for entire layout

2. **Layout Algorithm Steps:**

   **Step 1: Compute Module Sizes** (`compute_module_sizes`)
   - Each module has 3 rows: input ports, label, output ports
   - Width depends on: max(ports width, text width)
   - Height is fixed based on number of rows
   - Port positions are relative to module center
   - **Input:** module_size_f function (gets width/height for module)
   - **Output:** Sets `layout_dim` and port positions for all modules

   **Step 2: Assign Modules to Layers** (`assign_modules_to_layers`)
   - Uses **topological sort** (DFS-based)
   - Layer 0: modules with no predecessors (source nodes)
   - Layer N: 1 + max(predecessor layers)
   - Adjusts free modules (those with flexible placement) closer to successors
   - **Algorithm:** DFSIterator for topological order
   - **Output:** Sets `layout_layer_number` for all modules

   **Alternative:** `assign_module_to_layers_no_gaps` - BFS-style, no empty layers

   **Step 3: Order Modules Within Layers** (`assign_module_permutation_to_each_layer`)
   - **Goal:** Minimize edge crossings between layers
   - **Method:** Barycentric heuristic (iterative improvement)
   - For each module, compute barycenter = average position of neighbors
   - Sort modules by barycenter value
   - Sweep down and up multiple times (up to 100 iterations)
   - **Option:** `preserve_order=True` - respect previous x positions
   - **Output:** Sets `layout_layer_index` for all modules

   **Step 4: Compute Final Positions** (`compute_layout`)
   - Place layers vertically with separation
   - Within each layer, spread modules horizontally
   - Center each layer
   - **Inputs:**
     - `layer_x_separation` - horizontal space between modules
     - `layer_y_separation` - vertical space between layers
   - **Output:**
     - Sets final `layout_pos` for all modules
     - Returns `Page` with bounding box

### Key Parameters

```python
# Default unit (in points, 1/72 inch)
Defaults.u = 10.0

# Typical usage:
layout = WorkflowLayout(
    pipeline,
    module_size_f,      # function: module -> (width, height)
    module_margin,      # tuple: (x_margin, y_margin)
    port_size,          # tuple: (width, height)
    port_interspace     # spacing between ports
)

layout.run_all(
    layer_x_separation=50,  # horizontal gap between modules
    layer_y_separation=50,  # vertical gap between layers
    preserve_order=False,   # respect previous positions?
    no_gaps=False          # use alternative layer assignment?
)
```

### Important Notes

1. **Coordinates:** Module positions are CENTER coordinates, not top-left
2. **Port positions:** Relative to module center
3. **Layout is independent of rendering** - just computes x,y positions
4. **Stored in .vt file:** `<location>` elements have x, y for each module
5. **Barycentric method:** Heuristic, not guaranteed optimal (NP-hard problem)

---

## 2. Version Tree Layout (`version_tree_layout.py`)

### Core Algorithm

**Purpose:** Layout version history as a tree (parent-child relationships).

**Key Components:**

1. **Node:** Each version (action) in the vistrail
2. **Edges:** Parent → child relationships (version lineage)
3. **Tags:** Special nodes with labels (named versions)

### Layout Algorithm

Uses `tree_layout.py` (general tree layout library):

1. **Build Tree:**
   - Root at version 0
   - Add tagged versions
   - Add all versions referenced in edges
   - Preserve edge order for consistent layout

2. **Compute Node Sizes:**
   - Width = text_width(label) + horizontal_margin
   - Height = text_height + vertical_margin
   - Minimum width for unlabeled nodes

3. **Tree Layout** (`TreeLayoutLW`):
   - Direction: TOP (root at top, children below)
   - Separations:
     - `min_horizontal_separation = 20` - between siblings
     - `min_vertical_separation = 50` - between parent/child
   - Algorithm: Walker's tree layout (classic CS algorithm)
     - Positions nodes to avoid overlap
     - Centers parents over children
     - Compacts tree to minimize width

4. **Output:**
   - `nodes` dict: version_id → NodeVistrailsTreeLayoutLW
   - Each node has: position (x, y), dimensions (width, height)
   - Bounding box for entire tree

### Key Parameters

```python
layout = VistrailsTreeLayoutLW(
    text_width_f,             # function: string -> width
    text_height,              # fixed height for text
    text_horizontal_margin,   # padding around text (x)
    text_vertical_margin      # padding around text (y)
)

layout.layout_from(vistrail, graph)
```

---

## 3. Rendering (Not in layout modules)

The layout modules **only compute positions**. Actual rendering is in:
- `vistrails/gui/pipeline_view.py` - renders workflows with Qt
- `vistrails/gui/version_view.py` - renders version trees with Qt

**Rendering pipeline:**
1. Layout computes positions (x, y) and dimensions (width, height)
2. Qt GraphicsScene/GraphicsItems draw:
   - Rectangles for modules
   - Text labels
   - Lines/curves for connections
   - Circles for ports

---

## 4. Storage in .vt Files

**Location data is stored in XML:**

```xml
<module id="3" name="PythonCalc" ...>
  <location id="5" x="-123.45" y="67.89" />
</module>
```

- X, Y are absolute coordinates
- Stored in action history (can replay layout changes)
- If missing, layout algorithm recomputes from scratch

---

## 5. Proposed Julia/SVG Implementation

### Architecture

```
julia/src/
├── layout/
│   ├── workflow_layout.jl      # Port of workflow_layout.py
│   ├── tree_layout.jl          # Port of tree_layout.py (Walker's algorithm)
│   ├── version_tree_layout.jl  # Port of version_tree_layout.py
│   └── types.jl                # Vec2, Module, Layer, etc.
├── rendering/
│   ├── svg_renderer.jl         # SVG generation
│   ├── workflow_svg.jl         # Render pipelines to SVG
│   └── version_tree_svg.jl     # Render version trees to SVG
```

### Key Design Decisions

1. **Separate Layout from Rendering:**
   - Layout: pure computation (x, y positions)
   - Rendering: SVG generation (can swap for other formats)

2. **Use Existing Positions When Available:**
   - Parse `<location>` elements from .vt files
   - Only run layout if positions missing or user requests relayout

3. **SVG Advantages:**
   - Vector graphics (scales perfectly)
   - Can embed in web pages
   - Can convert to PDF/PNG with external tools
   - Interactive (can add JavaScript for zoom/pan)
   - Text-based (easy to generate, diff, version control)

4. **Coordinate System:**
   - SVG uses top-left origin, y-down
   - Layout uses center origin, y-down
   - Need transformation: `svg_x = layout_x + page_width/2`

### Implementation Steps

**Phase 1: Core Layout (1-2 weeks)**
1. Port Vec2, Module, Connection, Port structs
2. Port DFS iterator and topological sort
3. Port layer assignment algorithm
4. Port barycentric ordering
5. Port final position computation
6. Unit tests comparing with Python output

**Phase 2: SVG Rendering (1 week)**
1. Create SVG document structure
2. Render modules as rectangles with rounded corners
3. Render text labels
4. Render ports as small circles
5. Render connections as Bezier curves
6. Add styling (colors, gradients, shadows)

**Phase 3: Version Tree (1 week)**
1. Port Walker's tree layout algorithm
2. Render version nodes as circles/boxes
3. Render edges as lines
4. Add tag labels
5. Highlight current version

**Phase 4: Polish (1 week)**
1. Add zoom/pan controls (JavaScript)
2. Add tooltips on hover
3. Color coding (module types, execution status)
4. Export options (SVG, PDF, PNG)
5. Interactive features (click to navigate)

### Example Usage

```julia
# Load vistrail
vt = load_vistrail("examples/gcd.vt")
pipeline = get_pipeline(vt, 100)

# Layout (if needed)
layout = WorkflowLayout(pipeline)
run_layout!(layout,
    layer_x_separation=50,
    layer_y_separation=50
)

# Render to SVG
svg = render_pipeline_svg(pipeline, layout,
    width=800,
    height=600,
    style=:modern  # or :classic, :compact
)

# Save
write("gcd_pipeline.svg", svg)
```

### SVG Structure

```svg
<svg width="800" height="600" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <style>
      .module { fill: #f0f0f0; stroke: #333; stroke-width: 2; }
      .port { fill: #4CAF50; }
      .connection { stroke: #666; stroke-width: 1.5; fill: none; }
    </style>
  </defs>

  <!-- Connections (drawn first, below modules) -->
  <path class="connection" d="M 100,200 C 150,200 150,250 200,250" />

  <!-- Modules -->
  <g class="module" transform="translate(100, 200)">
    <rect x="-40" y="-20" width="80" height="40" rx="5" />
    <text x="0" y="5" text-anchor="middle">PythonCalc</text>
    <circle class="port" cx="-30" cy="-20" r="3" />
    <circle class="port" cx="30" cy="20" r="3" />
  </g>
</svg>
```

---

## 6. Benefits of This Approach

1. **No Qt dependency** - works in headless environments
2. **Web-friendly** - can embed in Jupyter, Pluto, web apps
3. **Version control** - SVG diffs show layout changes
4. **Scriptable** - automate diagram generation
5. **Portable** - works anywhere Julia runs
6. **Reusable** - layout algorithm separate from rendering
7. **Extensible** - easy to add new renderers (PDF, PNG, HTML Canvas)

---

## 7. Testing Strategy

1. **Compare with Python:**
   - Parse same .vt file in both
   - Run layout algorithms
   - Compare (x, y) positions (should be identical)

2. **Visual Regression:**
   - Generate SVGs for test workflows
   - Store as golden files
   - Detect layout changes

3. **Round-trip:**
   - Load .vt → layout → save positions → load again
   - Positions should match

---

## Next Steps

1. ✅ Analyze Python layout code (DONE)
2. Create Julia type definitions (Vec2, Module, etc.)
3. Port topological sort and DFS
4. Port barycentric ordering
5. Port position computation
6. Test against Python
7. Create basic SVG renderer
8. Test on gcd.vt example
