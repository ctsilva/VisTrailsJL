# Python VisTrails API Examples Analysis

Based on the Python VisTrails API code (`vistrails/core/api.py`) and the iPython notebook mentioned in the codebase, here are the example workflows that would typically be used to demonstrate the API:

## Example Files (Referenced but not included in repo)

### 1. **simplemath.vt**
**Purpose**: Demonstrates basic arithmetic operations with InputPort and OutputPort modules

**Likely Contents**:
- **Input Ports**:
  - `in_a` - First input number
  - `in_b` - Second input number
- **Modules**:
  - PythonCalc modules for operations (multiplication, addition)
  - Integer/Float constants
- **Output Ports**:
  - `out_times` - Result of a × b
  - `out_plus` - Result of a + b
- **Use Case**: Shows parameter injection via `execute(in_a=2, in_b=4)`

**API Usage**:
```python
vistrail = vt.load_vistrail('simplemath.vt')
pipeline = vistrail.current_pipeline
result = pipeline.execute(in_a=2, in_b=4)
print(result.output_port('out_times'))  # 8
print(result.output_port('out_plus'))   # 6
```

### 2. **outputs.vt**
**Purpose**: Demonstrates error handling and OutputPort modules

**Likely Contents**:
- **Modules**:
  - String constant
  - OutputPort module
  - Possibly intentional error module
- **Output Ports**:
  - `msg` - String message output
- **Versions**:
  - Version 1: Has errors (for demonstrating error handling)
  - Later version: Works correctly
- **Use Case**: Shows ExecutionErrors exception handling

**API Usage**:
```python
outputs = vt.load_vistrail('outputs.vt')
outputs.select_version(1)
try:
    result = outputs.execute()
except vt.ExecutionErrors:
    print("Execution failed as expected")

outputs.select_latest_version()
result = outputs.execute()
print(result.output_port('msg'))
```

### 3. **imagemagick.vt**
**Purpose**: Demonstrates image manipulation workflows

**Likely Contents**:
- **Modules**:
  - ImageMagick read module
  - ImageMagick blur filter
  - ImageMagick edge detection
  - File output modules
- **Versions/Tags**:
  - `read` - Just read an image
  - `blur` - Apply blur filter
  - `edges` - Edge detection
- **Output Ports**:
  - `result` - Processed image file
- **Use Case**: Shows version navigation and IPython notebook image display

**API Usage**:
```python
im = vt.load_vistrail('imagemagick.vt')
im.select_version('read')
result = im.execute()
result.output_port('result')  # Displays in notebook

im.select_version('blur')
result = im.execute()  # Blurred image

im.select_version('edges')
result = im.execute()  # Edge-detected image
```

### 4. **brain_output.xml**
**Purpose**: Demonstrates VTK 3D visualization output

**Likely Contents**:
- **Modules**:
  - VTK data reader
  - VTK renderer
  - vtkRendererOutput module
- **Use Case**: Shows 3D visualization rendering to IPython notebook

**API Usage**:
```python
render = vt.load_vistrail('brain_output.xml')
render.select_latest_version()
render.execute()  # Renders 3D brain visualization inline
```

### 5. **out_html.xml**
**Purpose**: Demonstrates HTML/rich text output

**Likely Contents**:
- **Modules**:
  - String processing
  - RichTextOutput module
- **Use Case**: Shows HTML rendering in IPython notebook

**API Usage**:
```python
richtext = vt.load_vistrail('out_html.xml')
richtext.select_latest_version()
richtext.execute()  # Displays formatted HTML
```

### 6. **table.xml**
**Purpose**: Demonstrates tabular data output

**Likely Contents**:
- **Modules**:
  - CSV/data reading
  - Table formatting
  - TableOutput module
- **Use Case**: Shows table rendering in IPython notebook

**API Usage**:
```python
tbl = vt.load_vistrail('table.xml')
tbl.select_latest_version()
tbl.execute()  # Displays formatted table
```

## Julia Equivalents in VisTrailsJL

Since these exact files don't exist in our repository, here are the Julia equivalents we DO have:

### Existing Julia Examples

1. **gcd.vt** (in `examples/`) - Similar to simplemath.vt
   - Basic arithmetic and control flow
   - 134 versions demonstrating version tree

2. **lineplot_ex3.vt** (in `examples/matplotlib/`) - Similar to imagemagick.vt
   - Matplotlib plotting
   - Demonstrates visualization workflows

3. **data_analysis.ipynb** (in `julia/examples/workflows/`) - Notebook workflow
   - CSV parsing, filtering, statistics
   - Custom package usage
   - OutputPort demonstration

4. **julia_api_demo.ipynb** (in `julia/examples/api/`) - API demonstration
   - Shows how to use the Julia API
   - Equivalent to ipython-notebook.ipynb

### What We Can Do

To create proper API examples for Julia, we could:

1. **Create simplemath.vt equivalent**: Simple arithmetic workflow for testing parameter injection
2. **Create visualization examples**: Using matplotlib or Plots.jl
3. **Create output examples**: Demonstrating different output types (text, images, tables)
4. **Port existing .vt files**: Convert Python examples to Julia notebook format

### Differences

**Python VisTrails Output Modes**:
- IPython notebook integration via `vt.ipython_mode(True)`
- Specialized output modules: RichTextOutput, TableOutput, vtkRendererOutput, MplFigureOutput

**Julia VisTrailsJL Approach**:
- Native Jupyter notebook support
- Automatic image embedding (PNG for plots)
- Markdown cells for rich text
- DataFrames for tables
- No special output modules needed - Julia's ecosystem handles this

## Recommendation

Since the original Python example files aren't in the repository, we should:

1. Use our existing examples (gcd.vt, matplotlib examples, notebook workflows)
2. Create a comprehensive set of Julia-native examples
3. Document the differences between Python and Julia output handling
4. Show how Julia's ecosystem features replace specialized VisTrails output modules

The Julia approach is actually **simpler** - instead of specialized output modules, we use:
- Plots.jl for visualization (auto-embedded as PNG)
- Markdown for rich text (native to notebooks)
- DataFrames.jl for tables (native display)
- Native Julia types for everything else
