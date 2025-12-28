# Matplotlib Example Files Analysis Report

## Executive Summary

Analyzed three matplotlib example .vt files to determine what modules are used and what functionality needs to be implemented in VisTrailsJL.

**Key Finding:** We are missing one critical module: `MplRectangleProperties`

---

## File 1: bar_ex1.vt

### Modules Used
- **PythonSource** (basic package) - ✅ Already implemented
- **MplBar** (matplotlib package) - ✅ Already implemented
- **MplFigure** (matplotlib package) - ✅ Already implemented
- **MplFigureOutput** (matplotlib package) - ✅ Already implemented
- **MplRectangleProperties** (matplotlib package) - ❌ **MISSING**

### Workflow Structure
```
PythonSource (generates data)
  ├─ outputs: height, left
  │
  ├─ height → MplBar.height
  └─ left → MplBar.left

MplBar
  └─ value → MplFigure.addPlot

MplFigure
  └─ self → MplFigureOutput.value
```

### PythonSource Code
```python
height = [2,5,7]
left = [3,5,4]
```

### Analysis
- Bar chart with 3 bars
- Uses `left` (x positions) and `height` (bar heights)
- The `MplRectangleProperties` module appears in action history but isn't actively used in current version
- **Status:** Mostly working, but missing MplRectangleProperties for complete compatibility

---

## File 2: hist_ex1.vt

### Modules Used
- **MplHist** (matplotlib package) - ✅ Already implemented
- **MplFigure** (matplotlib package) - ✅ Already implemented
- **MplFigureOutput** (matplotlib package) - ✅ Already implemented

### Workflow Structure
```
MplHist (x parameter set directly)
  └─ value → MplFigure.addPlot

MplFigure
  └─ self → MplFigureOutput.value
```

### Parameters
```python
MplHist.x = [1, 2, 3, 4, 3, 4, 2, 4, 5, 4, 5, 3, 5, 2, 4]
```

### Analysis
- Simple histogram of 15 data points
- Uses parameter (not input port) for data
- **Status:** ✅ Fully compatible - all modules implemented

---

## File 3: scatter.vt

### Modules Used
- **PythonSource** (basic package) - ✅ Already implemented
- **MplScatter** (matplotlib package) - ✅ Already implemented (but needs enhancement)
- **MplFigure** (matplotlib package) - ✅ Already implemented
- **MplFigureOutput** (matplotlib package) - ✅ Already implemented

### Workflow Structure
```
PythonSource (generates random data)
  ├─ outputs: X, Y, s
  │
  ├─ X → MplScatter.x
  ├─ Y → MplScatter.y
  └─ s → MplScatter.s

MplScatter
  └─ value → MplFigure.addPlot

MplFigure
  └─ self → MplFigureOutput.value
```

### PythonSource Code
```python
from math import pi
from numpy.random import rand

N = 30
X = 0.9 * rand(N)
Y = 0.9 * rand(N)
s = pi * (10 * rand(N))**2
```

### MplScatter Parameters
```
marker = o
norm = r  (note: this appears to be a typo - should be color?)
```

### Analysis
- Scatter plot with 30 random points
- Uses variable-sized markers (via `s` parameter - size in points²)
- **Issue:** Our current MplScatter doesn't support the `s` input port for marker sizes
- **Status:** ⚠️ Partially working - missing `s` (marker size) input port

---

## Summary: What We Have vs What We Need

### ✅ Already Implemented
1. **MplFigure** - Container for plots
2. **MplFigureOutput** - Save figure to file
3. **MplLinePlot** - Line plots
4. **MplScatter** - Scatter plots (basic version)
5. **MplBar** - Bar charts
6. **MplHist** - Histograms

### ❌ Missing / Needs Enhancement

#### 1. MplRectangleProperties (NEW MODULE NEEDED)
**Purpose:** Configure rectangle properties for bar charts and patches

**Input Ports (from Python VisTrails):**
- `bounds` (String, optional) - Set bounds: "l,b,w,h"
- `height` (Float, optional) - Rectangle height
- `width` (Float, optional) - Rectangle width
- `xy` (List, optional) - Left and bottom coords [x, y]
- `y` (Float, optional) - Bottom coordinate
- `x` (Float, optional) - Left coordinate

**Output Ports:**
- `value` (Function) - Returns configuration function

**Usage:** In bar_ex1.vt, this module appears in version history but isn't actively connected in the final workflow. It's used to configure rectangle appearance properties.

#### 2. MplScatter Enhancement (ENHANCEMENT NEEDED)
**Missing Port:**
- `s` (Float or Vector, optional) - Marker size in points²

**Current Implementation:**
- ✅ Has: x, y, marker, color, label
- ❌ Missing: s (size), c (color array), vmin, vmax, cmap, norm, edgecolors, linewidths, alpha

**Required for scatter.vt:**
- Add `s` input port to support variable marker sizes
- Type: `Union{Float64, Vector{Float64}}` (can be scalar or array)

---

## Implementation Recommendations

### Priority 1: Fix MplScatter
**File:** `/Users/csilva/github-ctsilva/VisTrailsJL/julia/src/packages/matplotlib/matplotlib.jl`

Add `s` input port to MplScatter:

```julia
function compute(self::ModuleInstance, ::Type{MplScatter})
    x = get(self.inputs, "x", nothing)
    y = get(self.inputs, "y", nothing)

    # Add size parameter
    s = haskey(self.inputs, "s") ? get(self.inputs, "s", nothing) : nothing
    marker_size = s !== nothing ? s : 20  # default size

    marker = haskey(self.inputs, "marker") ? get(self.inputs, "marker", nothing) : :circle
    color = haskey(self.inputs, "color") ? get(self.inputs, "color", nothing) : nothing
    label_text = haskey(self.inputs, "label") ? get(self.inputs, "label", nothing) : nothing

    plot_fn = function(figure)
        kwargs = Dict{Symbol, Any}(:marker => marker, :seriestype => :scatter)

        # Handle marker size (Plots.jl uses markersize, not s)
        if marker_size !== nothing
            # Note: matplotlib s is in points², Plots.jl markersize is different scale
            # May need to convert: sqrt(s/pi) to get radius
            if marker_size isa AbstractArray
                kwargs[:markersize] = marker_size
            else
                kwargs[:markersize] = marker_size
            end
        end

        if color !== nothing
            kwargs[:color] = color
        end
        if label_text !== nothing
            kwargs[:label] = label_text
        end

        Plots.plot!(figure, x, y; kwargs...)
    end

    self.outputs["value"] = plot_fn
    self.uptodate = true
    self.cache_state = :valid
    return self.outputs
end
```

Update module registration in `init.jl`:
```julia
function register_mplscatter!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.matplotlib",
        "MplScatter",
        MplScatter,
        [
            InputPort("x", Vector),
            InputPort("y", Vector),
            InputPort("s", Any, optional=true),  # Add this
            InputPort("marker", String, optional=true),
            InputPort("color", String, optional=true),
            InputPort("label", String, optional=true)
        ],
        [OutputPort("value", Function)],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)
end
```

### Priority 2: Implement MplRectangleProperties
**File:** `/Users/csilva/github-ctsilva/VisTrailsJL/julia/src/packages/matplotlib/matplotlib.jl`

Add new module:

```julia
struct MplRectangleProperties
end

function compute(self::ModuleInstance, ::Type{MplRectangleProperties})
    # Get rectangle properties
    bounds = haskey(self.inputs, "bounds") ? get(self.inputs, "bounds", nothing) : nothing
    height = haskey(self.inputs, "height") ? get(self.inputs, "height", nothing) : nothing
    width = haskey(self.inputs, "width") ? get(self.inputs, "width", nothing) : nothing
    xy = haskey(self.inputs, "xy") ? get(self.inputs, "xy", nothing) : nothing
    x = haskey(self.inputs, "x") ? get(self.inputs, "x", nothing) : nothing
    y = haskey(self.inputs, "y") ? get(self.inputs, "y", nothing) : nothing

    # Create configuration function
    config_fn = function(rect_params)
        # Apply rectangle properties to given parameters
        if bounds !== nothing
            # Parse "l,b,w,h" format
            parts = split(bounds, ",")
            if length(parts) == 4
                rect_params[:left] = parse(Float64, parts[1])
                rect_params[:bottom] = parse(Float64, parts[2])
                rect_params[:width] = parse(Float64, parts[3])
                rect_params[:height] = parse(Float64, parts[4])
            end
        end

        if height !== nothing
            rect_params[:height] = height
        end
        if width !== nothing
            rect_params[:width] = width
        end
        if xy !== nothing && length(xy) >= 2
            rect_params[:x] = xy[1]
            rect_params[:y] = xy[2]
        end
        if x !== nothing
            rect_params[:x] = x
        end
        if y !== nothing
            rect_params[:y] = y
        end

        return rect_params
    end

    self.outputs["value"] = config_fn
    self.uptodate = true
    self.cache_state = :valid
    return self.outputs
end
```

Register in `init.jl`:
```julia
function register_mplrectangleproperties!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.matplotlib",
        "MplRectangleProperties",
        MplRectangleProperties,
        [
            InputPort("bounds", String, optional=true),
            InputPort("height", Float64, optional=true),
            InputPort("width", Float64, optional=true),
            InputPort("xy", Vector, optional=true),
            InputPort("x", Float64, optional=true),
            InputPort("y", Float64, optional=true)
        ],
        [OutputPort("value", Function)],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)
end
```

Add to package initialization:
```julia
function initialize_matplotlib_package!()
    @info "Initializing matplotlib package..."

    register_mplfigure!()
    register_mplfigureoutput!()
    register_mpllineplot!()
    register_mplscatter!()
    register_mplbar!()
    register_mplhist!()
    register_mplrectangleproperties!()  # Add this

    @info "  ✓ Matplotlib package initialized"
    @info "  Registered modules: MplFigure, MplFigureOutput, MplLinePlot, MplScatter, MplBar, MplHist, MplRectangleProperties"
end
```

---

## Testing Plan

1. **Test hist_ex1.vt** - Should work immediately (no changes needed)
2. **Test scatter.vt** - Test after adding `s` parameter to MplScatter
3. **Test bar_ex1.vt** - Test after implementing MplRectangleProperties

---

## Notes

- The `norm = r` parameter in scatter.vt appears to be either a typo or refers to a normalization function. In Python matplotlib, `norm` is a normalization instance, not a string. This might need investigation.
- MplFigureOutput currently saves to a hardcoded filename. Consider adding parameters for output path, format, width, height.
- All three examples use the pattern: Plot Module → MplFigure → MplFigureOutput, which matches our current architecture.
