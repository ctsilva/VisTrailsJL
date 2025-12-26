# SVG Rendering System

The Julia VisTrails implementation includes a complete SVG rendering system for visualizing workflows and version trees.

## Features

### Version Tree Rendering

Renders the complete provenance history as a horizontal tree diagram:

```julia
using VisTrailsJL

vt = load_vistrail("examples/mta.vt")
svg = render_version_tree_svg(vt, width=1200, height=800)
write("version_tree.svg", svg)
```

**Features:**
- Tagged versions are highlighted with colored nodes
- Version labels displayed for tagged versions
- Terse mode: skips intermediate untagged nodes with single parent/child
- Horizontal layout with proper edge routing
- Automatic layout and spacing

### Workflow/Pipeline Rendering

Renders workflow DAGs with modules, ports, and connections:

```julia
using VisTrailsJL

vt = load_vistrail("examples/lung.vt")
pipeline = vt.pipelines[vt.current_version]
svg = render_pipeline_svg(pipeline, 
                          width=2000, 
                          height=1600,
                          module_width=120.0,
                          module_height=60.0,
                          port_size=6.0,
                          margin=80.0)
write("workflow.svg", svg)
```

**Features:**
- Dynamic module box sizing based on text label width
- Ports rendered inside boxes:
  - Input ports: top-left corner, left-to-right
  - Output ports: bottom-right corner, right-to-left
- Bezier curve connections from output ports to input ports
- XML character escaping (e.g., `<`, `>`, `&`)
- Module labels from `__desc__` annotation or module name
- Automatic scaling to fit canvas

## Lightweight Rendering Mode

A key innovation in the Julia implementation is the ability to render workflows **without having module descriptors registered**. This allows rendering of VTK, matplotlib, and other package workflows without installing those packages.

### How It Works

When action replay fails due to missing modules, the system falls back to **lightweight mode**:

1. Parses action history to extract module information
2. Creates placeholder `ModuleDescriptor` objects
3. Infers port specifications from connections
4. Extracts layout positions from actions
5. Renders the workflow with all visual information

```julia
# This works even if VTK is not installed!
vt = load_vistrail("examples/lung.vt")  # Contains VTK modules
pipeline = vt.pipelines[vt.current_version]
svg = render_pipeline_svg(pipeline)  # Renders successfully
```

**Implementation:** See `build_pipeline_from_state_lightweight()` in `src/db/services/action_replay.jl`

## Architecture

### Key Files

- `src/rendering/workflow_svg.jl` - Pipeline/workflow SVG generation
- `src/rendering/version_tree_svg.jl` - Version tree visualization  
- `src/rendering/version_tree_layout.jl` - Tree layout algorithm
- `src/db/services/action_replay.jl` - Action replay with lightweight mode

### Rendering Pipeline

#### Workflow Rendering Flow

```
Pipeline object
    ↓
Calculate module sizes (based on labels)
    ↓
Transform positions to SVG coordinates
    ↓
Render modules with ports
    ↓
Render connections between ports
    ↓
SVG output
```

#### Version Tree Rendering Flow

```
Vistrail object
    ↓
Build action graph
    ↓
Extract tagged versions
    ↓
Apply terse mode (optional)
    ↓
LayeredLayout algorithm
    ↓
Route edges
    ↓
SVG output
```

## Technical Details

### Module Sizing

Modules are sized dynamically based on their labels:

```julia
function calculate_module_size(label::String, min_width::Float64=80.0, min_height::Float64=60.0)
    text_width = estimate_text_width(label)
    width = max(min_width, text_width + 40.0)  # 40px padding
    height = min_height
    return (width, height)
end
```

Text width estimation assumes Arial 14px bold font with ~0.6× character width multiplier.

### Port Positioning

Ports are positioned **inside** module boxes with edge padding:

```julia
function compute_port_position(module_center, module_size, port_type, port_index, num_ports, port_size, scale)
    # Input ports: top-left, going left to right
    if port_type == :input
        start_x = cx - w/2 + edge_padding + ps/2
        port_x = start_x + (port_index - 1) * port_spacing
        port_y = cy - h/2 + edge_padding + ps/2
    # Output ports: bottom-right, going right to left  
    else
        start_x = cx + w/2 - edge_padding - ps/2
        port_x = start_x - (port_index - 1) * port_spacing
        port_y = cy + h/2 - edge_padding - ps/2
    end
    return (port_x, port_y)
end
```

### Connection Rendering

Connections use cubic Bezier curves with vertical control points:

```julia
# Control points create smooth vertical curve
vertical_distance = abs(dst_port_y - src_port_y)
control_offset = vertical_distance * 0.4

control1_x = src_port_x
control1_y = src_port_y + control_offset
control2_x = dst_port_x  
control2_y = dst_port_y - control_offset

# SVG path
path = "M $src_port_x,$src_port_y C $control1_x,$control1_y $control2_x,$control2_y $dst_port_x,$dst_port_y"
```

### Coordinate Systems

**VisTrails coordinates:**
- Origin at workflow center
- Negative Y is up
- Arbitrary units

**SVG coordinates:**
- Origin at top-left
- Positive Y is down  
- Pixels

**Transformation:**
```julia
function to_svg(x, y)
    svg_x = margin + (x - min_x) * scale
    svg_y = margin + (max_y - y) * scale  # Flip Y-axis
    return (svg_x, svg_y)
end
```

### Port Specifications

The system handles two types of port information:

1. **Static ports** - Defined in `ModuleDescriptor` (e.g., `InputPort`, `OutputPort`)
2. **Instance ports** - Specified in workflow XML via `<portSpec>` elements (e.g., `Tuple`, `Untuple`)

Rendering always prefers instance-specific ports when available:

```julia
function get_input_port_specs(mod::ModuleInstance)
    if !isempty(mod.port_specs)
        # Use instance-specific ports from XML
        input_specs = filter(ps -> ps.port_type == :input, mod.port_specs)
        sort!(input_specs, by = ps -> ps.sort_key)
        return [(ps.name, ps.sort_key) for ps in input_specs]
    end
    # Fallback to descriptor ports
    return [(p.name, i) for (i, p) in enumerate(mod.descriptor.input_ports)]
end
```

## XML Character Escaping

Module labels may contain XML special characters (e.g., comparison operators). All text is escaped:

```julia
function escape_xml(s::String)
    s = replace(s, "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    s = replace(s, "\"" => "&quot;")
    s = replace(s, "'" => "&apos;")
    return s
end
```

Example: Module labeled `. < .` renders as `<text>. &lt; .</text>`

## CSS Styling

SVG elements use CSS classes for consistent styling:

```css
.module {
    fill: #f5f5f5;
    stroke: #333;
    stroke-width: 2;
}

.module-text {
    font-family: Arial, sans-serif;
    font-size: 14px;
    font-weight: bold;
    fill: #333;
}

.port {
    fill: #666;
    stroke: #333;
    stroke-width: 1;
}

.connection {
    stroke: #000;
    stroke-width: 2;
    fill: none;
}
```

## Testing

All rendering code has been tested with real VisTrails files:

- **gcd.vt** - Plain XML format, control flow modules
- **lung.vt** - ZIP format, VTK modules (unregistered)
- **mta.vt** - Complex workflow with table operations
- **plot.vt** - Matplotlib visualization workflow

Run the test script:
```bash
julia --project=. test_vistrail.jl ../examples/mta.vt
```

This generates:
- `mta_tree.svg` - Version history tree
- `mta_workflow.svg` - Largest workflow diagram

## Future Enhancements

Potential improvements to the rendering system:

1. **Interactive SVG** - Add JavaScript for pan/zoom, node selection
2. **Export formats** - PDF, PNG via external tools
3. **Custom styling** - User-configurable colors and fonts
4. **Hierarchical layout** - Group related modules
5. **Subworkflow expansion** - Inline subworkflow rendering
6. **Execution state** - Highlight cached/executed modules
7. **Port labels** - Show port names on hover
8. **Connection labels** - Show data types flowing through connections

## References

- Python VisTrails rendering: `vistrails/gui/pipeline_view.py`
- Layout algorithm based on: Sugiyama et al., "Methods for Visual Understanding of Hierarchical System Structures"
- SVG specification: https://www.w3.org/TR/SVG2/
