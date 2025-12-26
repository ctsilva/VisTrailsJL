# VisTrails GUI Rendering Analysis

Analysis of VisTrails Python GUI code for implementing SVG rendering in Julia.

Date: 2025-10-19
Source files analyzed:
- `vistrails/gui/pipeline_view.py` - Module and workflow rendering
- `vistrails/gui/version_view.py` - Version tree rendering
- `vistrails/gui/theme.py` - Visual styling constants
- `vistrails/core/layout/` - Layout algorithms

---

## Part 1: Module and Workflow Rendering

### Module Visual Style (`QGraphicsModuleItem`)

**Location:** `pipeline_view.py:1085`

#### Basic Shape
- **Base shape:** Rounded rectangle (or custom polygon from "fringe")
- **Dimensions:** Dynamic based on content
  - Label text width + margins
  - Port count determines minimum width
  - Height includes: label + description + edit widgets

#### Visual States
```python
# Normal module
modulePen = CurrentTheme.MODULE_PEN          # Default border
moduleBrush = CurrentTheme.MODULE_BRUSH      # Default fill

# Selected
modulePen = CurrentTheme.MODULE_SELECTED_PEN
labelPen = CurrentTheme.MODULE_LABEL_SELECTED_PEN

# Ghosted (search/filtered out)
modulePen = CurrentTheme.GHOSTED_MODULE_PEN
moduleBrush = CurrentTheme.GHOSTED_MODULE_BRUSH

# Invalid (missing package/error)
modulePen = CurrentTheme.INVALID_MODULE_PEN
moduleBrush = CurrentTheme.INVALID_MODULE_BRUSH

# Breakpoint
modulePen = CurrentTheme.BREAKPOINT_MODULE_PEN
moduleBrush = CurrentTheme.BREAKPOINT_MODULE_BRUSH

# Abstraction (subworkflow)
modulePen = CurrentTheme.ABSTRACTION_PEN

# Group
modulePen = CurrentTheme.GROUP_PEN
```

#### Custom Styling
- **Custom color:** Modules can have custom brush colors from module registry
- **Custom shape ("fringe"):** Modules can have custom outlines
  - Left and right fringes define polygon points
  - Example: triangular modules, curved edges, etc.

#### Module Layout Components
```python
paddedRect = QtCore.QRectF()    # Overall bounding box
labelRect = QtCore.QRectF()     # Label text area
descRect = QtCore.QRectF()      # Description text area
editRect = QtCore.QRectF()      # Inline edit widgets area
abstRect = QtCore.QRectF()      # "!" indicator for abstractions
```

#### Margins and Spacing
```python
MODULE_LABEL_MARGIN = [left, top, right, bottom]  # Around label
MODULE_EDIT_MARGIN = [left, top, right, bottom]   # Around edit widgets
MODULE_PORT_MARGIN = [left, top, right, bottom]   # Port region margins
MODULE_PORT_SPACE = horizontal_spacing_between_ports
PORT_WIDTH, PORT_HEIGHT = dimensions
```

### Port Visual Style (`QAbstractGraphicsPortItem`)

**Location:** `pipeline_view.py:100`

#### Port Shapes
Multiple port shape types available:
1. **Rectangle** (`QGraphicsPortRectItem`) - Default
2. **Triangle** (`QGraphicsPortTriangleItem`) - With rotation angle
3. **Diamond** (`QGraphicsPortDiamondItem`)
4. **Ellipse/Circle** (`QGraphicsPortEllipseItem`)
5. **Custom Polygon** (`QGraphicsPortPolygonItem`) - From point list

#### Port States
```python
# Connected vs unconnected
_connected = count_of_connections

# Optional ports
optional = True/False  # Affects visibility

# Required connection state
_min_conns, _max_conns  # Min/max connections allowed

# Invalid port
invalid = True  # Missing type, registry error
```

#### Port Positioning
- **Input ports:** Top edge, left-aligned, spaced horizontally
- **Output ports:** Bottom edge, right-aligned, spaced horizontally
- Port positions calculated in `setupModule()` based on port count

### Connection Visual Style (`QGraphicsConnectionItem`)

**Connections are Bezier curves** connecting ports with control points for smooth curves.

---

## Part 2: Version Tree Rendering

### Version Node Visual Style (`QGraphicsVersionItem`)

**Location:** `version_view.py:397`

#### Basic Shape
- **Shape:** Ellipse (not circle - can be wider than tall)
- **Size:** Dynamic based on label text
  - Width adapts to label length
  - `VERSION_LABEL_MARGIN` padding around text

#### Visual States
```python
# Normal version
versionPen = CurrentTheme.VERSION_PEN
versionBrush = CurrentTheme.VERSION_USER_BRUSH  # or VERSION_OTHER_BRUSH

# Selected
versionPen = CurrentTheme.VERSION_SELECTED_PEN

# Ghosted (filtered by search)
versionPen = CurrentTheme.GHOSTED_VERSION_PEN
versionBrush = CurrentTheme.GHOSTED_VERSION_USER_BRUSH

# Custom color
# Can have RGB custom color from annotations
```

#### Color Saturation by Rank
**Important:** Versions are colored by **recency rank** to show temporal ordering
```python
def update_color(isThisUs, new_rank, new_max_rank, ...):
    sat = float(new_rank+1) / new_max_rank
    (h, s, v, a) = brush.color().getHsvF()
    newHsv = (h, s*sat, v+(1.0-v)*(1-sat), a)
```
- Newer versions: **Higher saturation** (more vivid)
- Older versions: **Lower saturation** (more faded)
- Separate rank scales for current user vs other users

#### Labels
- **Tagged versions:** Show tag name
- **Untagged versions:** Show version description (if present)
- **Version ID:** Always stored in `version.id`

### Link/Edge Visual Style (`QGraphicsLinkItem`)

**Location:** `version_view.py:72`

#### Basic Shape
- **Shape:** Polygon (arrow-like connector)
- **Direction:** From parent to child version
- **Rendering:** Lines connecting ellipse edges

#### Visual States
```python
linkPen = CurrentTheme.LINK_PEN  # Normal
# Ghosted when both connected versions are ghosted
ghosted = (source.ghosted and target.ghosted)
```

---

## Part 3: Version Tree Filtering Logic

### Terse Graph Generation

**Key insight:** VisTrails uses a "terse graph" that **hides linear chain versions**

**Location:** `vistrails/core/vistrail/controller.py` (referenced in version_view.py:938)

#### What Gets Shown in Version Tree
1. **Root version** (version 0)
2. **All tagged versions** - Always visible
3. **Branch points** - Versions with multiple children
4. **Merge points** - Versions with multiple parents (rare)
5. **Leaf versions** - Latest versions in each branch
6. **Current version** - Always visible

#### What Gets Hidden
- **Linear chain versions** between branch/tag points
  - If version N has exactly one parent and one child
  - And is not tagged
  - And is not current version
  - Then it's **collapsed** into edge between parent and grandchild

#### Edge Annotations
Edges in terse graph carry information:
- `expand` - Can this edge be expanded to show hidden versions?
- `collapse` - Can this edge be collapsed to hide versions?

### Search/Filter Implementation

**Location:** `version_view.py:843` (`adjust_version_colors`)

```python
if controller.search and nodeId!=0:
    action = am[nodeId]
    # Match version against search query
    ghosted = not controller.search.match(controller, action)
else:
    ghosted = False
```

Versions that don't match search are "ghosted" (grayed out) but still rendered.

---

## Part 4: Layout Details

### Version Tree Layout

**Algorithm:** TreeLayoutLW (Linear Walker - Buchheim-Junger-Leipert)
**Location:** `vistrails/core/layout/version_tree_layout.py`

#### Key Parameters
```python
min_horizontal_separation = 20    # Between siblings
min_vertical_separation = 50      # Between levels
vertical_alignment = TOP          # Node alignment in level band
```

#### Text Width Calculation
```python
text_width_f = function(text) -> width_in_pixels
text_height = 20.0
text_horizontal_margin = 10.0
text_vertical_margin = 5.0
```

Node width = `text_width(label) + text_horizontal_margin`

### Workflow Layout

**Algorithm:** Layer-based DAG layout with barycentric heuristic
**Location:** `vistrails/core/layout/workflow_layout.py`

#### Key Steps
1. **Topological sort** to determine layer assignments
2. **Barycentric heuristic** to minimize edge crossings
  - Iteratively reorder nodes within layers
  - Position based on average position of neighbors
3. **Coordinate computation** from layer assignments

#### Existing Layouts
**Critical:** Most workflows have **user-created layouts** stored in .vt files
- `<location x="..." y="..."/>` elements in XML
- Should be **preferred** over auto-layout
- Only use auto-layout for programmatically-created pipelines

---

## Part 5: Theme Constants

### Typical Values (from CurrentTheme)

```python
# Modules
MODULE_FONT = QtGui.QFont('Arial', 14)
MODULE_PEN = QtGui.QPen(QtCore.Qt.black, 2)
MODULE_BRUSH = QtGui.QBrush(QtGui.QColor(192, 192, 192))  # Light gray
MODULE_SELECTED_PEN = QtGui.QPen(QtGui.QColor(255, 140, 0), 3)  # Orange

# Ports
PORT_RECT = QtCore.QRectF(-3.75, -3.75, 7.5, 7.5)  # Centered square
PORT_WIDTH = 7.5
PORT_HEIGHT = 7.5

# Versions
VERSION_PEN = QtGui.QPen(QtCore.Qt.black, 2)
VERSION_USER_BRUSH = QtGui.QBrush(QtGui.QColor(100, 150, 200))  # Blue
VERSION_OTHER_BRUSH = QtGui.QBrush(QtGui.QColor(200, 150, 100))  # Brown

# Connections/Links
LINK_PEN = QtGui.QPen(QtCore.Qt.black, 2)
```

---

## Part 6: Implementation Strategy for Julia/SVG

### Phase 1: Core Visual Styles
1. Translate theme constants to SVG CSS classes
2. Implement module rendering with rounded rectangles
3. Implement port rendering (rectangles, triangles, circles)
4. Implement Bezier curve connections

### Phase 2: Version Tree Improvements
1. **Implement terse graph generation**
   - Filter linear chain versions
   - Keep only: tagged, branching, leaves, current
2. **Implement saturation-based coloring**
   - Rank versions by time
   - Apply HSV saturation scaling
3. **Add proper ellipse sizing**
   - Measure text width
   - Adapt ellipse dimensions

### Phase 3: Advanced Features
1. Custom module shapes (fringe polygons)
2. Custom module colors
3. Search/filter ghosting
4. Inline parameter widgets
5. Breakpoint indicators

### Phase 4: Workflow Layout
1. Use existing layouts from .vt files (already implemented)
2. Implement DAG auto-layout for programmatic workflows
3. Barycentric crossing minimization

---

## Key Takeaways for Julia Implementation

### What's Working Well
✅ Layout algorithms translated (TreeLayoutLW)
✅ Basic SVG rendering functional
✅ Reading existing module positions from .vt files

### What Needs Improvement

#### Version Tree
❌ **Terse graph not implemented** - Showing ALL 134 versions instead of ~10-20
❌ **Saturation coloring missing** - All versions same color
❌ **Ellipse sizing** - Currently fixed size, should adapt to labels
❌ **Edge expand/collapse** - Not showing which edges hide versions

#### Visual Fidelity
❌ **Rounded rectangles** for modules - Currently using rectangles
❌ **Port shapes** - Only squares, need triangles/diamonds/circles
❌ **Bezier connections** - Implemented but could match VisTrails curves better
❌ **Theme colors** - Should match VisTrails color palette exactly

#### Priority Implementation Order
1. **Terse graph generation** (biggest impact on usability)
2. **Saturation coloring** (helps understand version age)
3. **Rounded rectangles** for modules (visual polish)
4. **Proper ellipse sizing** (better version tree layout)
5. **Port shapes** (visual polish)
6. **Custom colors/shapes** (advanced feature)

---

## Example: Terse Graph Algorithm (Pseudocode)

```julia
function generate_terse_graph(vistrail)
    graph = Dict{Int, Vector{Int}}()  # version_id -> children
    visible_versions = Set{Int}()

    # Always include
    push!(visible_versions, 0)  # root
    push!(visible_versions, vistrail.current_version)  # current

    # Include all tagged versions
    for tag in vistrail.tags
        push!(visible_versions, tag.version_id)
    end

    # Build parent-child relationships
    for (id, action) in vistrail.actions
        parent = action.prev_id === nothing ? 0 : action.prev_id
        if !haskey(graph, parent)
            graph[parent] = Int[]
        end
        push!(graph[parent], id)
    end

    # Include branch points (multiple children)
    for (parent, children) in graph
        if length(children) > 1
            push!(visible_versions, parent)
            for child in children
                push!(visible_versions, child)
            end
        end
    end

    # Include leaf nodes (no children)
    all_children = Set(vcat(values(graph)...))
    for id in keys(vistrail.actions)
        if !(id in all_children)
            push!(visible_versions, id)
        end
    end

    # Build terse graph edges (skipping hidden versions)
    terse_edges = Dict{Int, Vector{Tuple{Int, Bool}}}()
    for v in visible_versions
        terse_edges[v] = []
        # Find next visible descendant(s)
        for child in get(graph, v, [])
            next_visible = find_next_visible(child, graph, visible_versions)
            push!(terse_edges[v], (next_visible, has_hidden_between(v, next_visible)))
        end
    end

    return (visible_versions, terse_edges)
end
```

---

## Conclusion

The VisTrails GUI code provides a sophisticated rendering system with:
- Multiple visual states for modules and versions
- Dynamic sizing based on content
- Filtering/search with ghosting
- Temporal color coding via saturation
- Terse graph generation for readability

The Julia/SVG implementation should prioritize:
1. **Terse graph** for version trees (critical for usability)
2. **Visual fidelity** to match VisTrails look
3. **Existing layouts** where available
4. **Progressive enhancement** - basic first, then advanced features
