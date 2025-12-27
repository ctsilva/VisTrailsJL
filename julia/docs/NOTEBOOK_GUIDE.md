# VisTrailsJL Notebook System User Guide

**Version 0.2** - Notebook-Based Workflow System

## Table of Contents

1. [Introduction](#introduction)
2. [Quick Start](#quick-start)
3. [Workflow Notebooks](#workflow-notebooks)
4. [Package Notebooks](#package-notebooks)
5. [Built-in Modules](#built-in-modules)
6. [Examples](#examples)
7. [API Reference](#api-reference)

---

## Introduction

VisTrailsJL v0.2 introduces a **notebook-based workflow system** that lets you define and execute scientific workflows directly in Jupyter notebooks using simple `#|` directives.

### Why Notebooks?

- **No GUI required** - Define workflows as code
- **Git-native** - Version control with standard git tools
- **Literate programming** - Mix documentation, code, and workflows
- **Jupyter/VSCode compatible** - Use your favorite editor
- **Reproducible** - Workflows are self-contained and executable

### Key Concepts

- **Workflows** = Directed graphs of modules connected by data flow
- **Modules** = Computational units with inputs, outputs, and parameters
- **Packages** = Collections of related modules
- **Directives** = Special `#|` comments that define workflow structure

---

## Quick Start

### 1. Create a Simple Workflow

Create a file `my_workflow.ipynb`:

```json
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": ["# My First Workflow"]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "#| workflow: my_first_workflow\\n",
    "#| version: 1"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "#| module-id: number\\n",
    "#| module-type: basic:Integer\\n",
    "#| params:\\n",
    "#|   - value: 42"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "#| module-id: print\\n",
    "#| module-type: basic:StandardOutput\\n",
    "#| inputs:\\n",
    "#|   - value: number.value"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": ["#| execute"]
  }
 ]
}
```

### 2. Run the Workflow

```julia
using VisTrailsJL

# Parse and execute
workflow = parse_workflow_notebook("my_workflow.ipynb")
pipeline, id_to_module = build_pipeline_from_workflow(workflow)
cache, outputs = execute_notebook_pipeline(pipeline, workflow; id_to_module=id_to_module)
```

Output:
```
42
```

---

## Workflow Notebooks

### Basic Structure

Every workflow notebook has three parts:

1. **Workflow declaration** - Defines the workflow name and version
2. **Module definitions** - Defines each module instance
3. **Execution directive** (optional) - Tells VisTrailsJL to execute automatically

### Workflow Declaration

```julia
#| workflow: my_workflow_name
#| version: 1
```

- **workflow**: Unique identifier for this workflow
- **version**: Integer version number (for tracking changes)

### Module Definitions

Each module requires:

```julia
#| module-id: unique_id
#| module-type: package:ModuleName
#| inputs: (optional)
#|   - port_name: source_module.port_name
#| params: (optional)
#|   - param_name: value
```

**Example:**

```julia
#| module-id: add_one
#| module-type: julia:JuliaSource
#| inputs:
#|   - x: input_value.value

x = get_input("x")
result = x + 1
set_output("self", result)
```

### Connections

Connections are defined in the `inputs:` section using the syntax:

```
source_module_id.output_port_name
```

**Example:**
```julia
#| inputs:
#|   - data: fetch_module.file
#|   - threshold: threshold_param.value
```

### Parameters

Parameters are set in the `params:` section:

```julia
#| params:
#|   - url: "https://api.example.com/data"
#|   - max_retries: 3
#|   - enable_cache: true
```

### Execution Directive

Add this to automatically execute the workflow when loaded:

```julia
#| execute
```

---

## Package Notebooks

You can define custom modules in package notebooks.

### Package Structure

```julia
#| package-meta
#| identifier: my.custom.package
#| version: 1.0.0

#| module: MyModule
#| input_ports:
#|   - name: input_data
#|     signature: basic:List
#| output_ports:
#|   - name: result
#|     signature: basic:Float

# Module computation code
data = get_input("input_data")
result = sum(data) / length(data)  # Calculate mean
set_output("result", result)
```

### Package Components

1. **Package Metadata**
   ```julia
   #| package-meta
   #| identifier: org.example.mypackage
   #| version: 1.0.0
   ```

2. **Module Definitions**
   ```julia
   #| module: ModuleName
   #| input_ports:
   #|   - name: port_name
   #|     signature: type_signature
   #| output_ports:
   #|   - name: port_name
   #|     signature: type_signature
   #| parameters: (optional)
   #|   - name: param_name
   #|     signature: type_signature
   ```

3. **Compute Code**
   - Use `get_input(name)` to read inputs
   - Use `get_parameter(name)` to read parameters
   - Use `set_output(name, value)` to write outputs

### Loading Custom Packages

```julia
# Load package from notebook
pkg = load_package_from_notebook("my_package.ipynb")

# Register it
register_notebook_package!(pkg)

# Now modules are available as "mypackage:ModuleName"
```

---

## Built-in Modules

VisTrailsJL includes several built-in packages:

### Basic Package (`basic:`)

**Constants:**
- `Integer` - Integer constant
- `Float` - Floating point constant
- `String` - String constant
- `Boolean` - Boolean constant

**Data Structures:**
- `List` - Create a list from inputs
- `Tuple` - Create a tuple
- `Untuple` - Extract elements from tuple

**I/O:**
- `StandardOutput` - Print to console
- `HTTPFile` - Fetch data from URL

**Math:**
- `Round` - Round floating point numbers

### Julia Package (`julia:`)

**JuliaSource** - Execute arbitrary Julia code
```julia
#| module-id: calc
#| module-type: julia:JuliaSource
#| inputs:
#|   - x: input.value

# Your Julia code here
result = x^2 + 2*x + 1
set_output("self", result)
```

### Control Flow Package (`control_flow:`)

**Boolean Operations:**
- `And` - Logical AND over a list
- `Or` - Logical OR over a list
- `Not` - Logical NOT

**Vector Operations:**
- `Sum` - Sum all elements in a list
- `Dot` - Dot product of two vectors
- `Cross` - Cross product of 3D vectors
- `ElementwiseProduct` - Element-wise multiplication

**Conditionals (simplified):**
- `If` - Conditional execution (basic implementation)
- `While` - Loop construct (basic implementation)

### Python Package (`pythoncalc:`)

**PythonCalc** - Execute Python expressions
```julia
#| module-id: py_calc
#| module-type: pythoncalc:PythonCalc
#| inputs:
#|   - value1: input1.value
#|   - value2: input2.value
#| params:
#|   - op: "+"
```

---

## Examples

### Example 1: Data Analysis

See [`examples/data_analysis_workflow.ipynb`](../examples/data_analysis_workflow.ipynb)

Demonstrates:
- Generating sample data
- Using built-in Sum module
- Custom JuliaSource for calculations
- Formatting and displaying results

### Example 2: HTTP Data Fetching

See [`examples/http_fetch_workflow.ipynb`](../examples/http_fetch_workflow.ipynb)

Demonstrates:
- Fetching JSON from web APIs
- Parsing JSON in JuliaSource
- Data extraction and formatting
- Real-world API integration

### Example 3: Vector Operations

See [`test/notebooks/test_vector_ops.jl`](../test/notebooks/test_vector_ops.jl)

Demonstrates:
- Sum, Dot, Cross products
- Element-wise operations
- Vector mathematics

### Example 4: Branching Workflows

See [`test/notebooks/test_branching.ipynb`](../test/notebooks/test_branching.ipynb)

Demonstrates:
- Conditional execution paths
- Using If module
- Multiple output connections

---

## API Reference

### Parsing Functions

#### `parse_workflow_notebook(path::String) -> NotebookWorkflow`

Parse a workflow notebook and extract workflow definition.

**Returns:** `NotebookWorkflow` struct containing:
- `name::String` - Workflow name
- `version::Int` - Version number
- `modules::Vector{NotebookModule}` - Module definitions
- `execute::Bool` - Whether to auto-execute

#### `parse_notebook(path::String) -> Vector{Cell}`

Parse notebook and extract all cells with directives.

### Building Functions

#### `build_pipeline_from_workflow(workflow::NotebookWorkflow) -> (Pipeline, Dict{String, ModuleInstance})`

Build an executable pipeline from workflow definition.

**Returns:**
- `Pipeline` - The constructed pipeline
- `id_to_module` - Mapping from notebook IDs to module instances

### Execution Functions

#### `execute_notebook_pipeline(pipeline::Pipeline, workflow::NotebookWorkflow; id_to_module=nothing, enable_logging::Bool=false) -> (Dict, Dict)`

Execute a pipeline with notebook-defined modules.

**Returns:**
- `cache` - Full execution cache (all module outputs)
- `workflow_outputs` - Named outputs from workflow

### Package Functions

#### `load_package_from_notebook(path::String) -> NotebookPackage`

Load a package definition from a notebook.

#### `register_notebook_package!(pkg::NotebookPackage)`

Register a package and all its modules in the global registry.

### Helper Functions

#### `get_input(name::String)`

In module compute code: get value from input port.

#### `get_parameter(name::String)`

In module compute code: get parameter value.

#### `set_output(name::String, value)`

In module compute code: set output port value.

#### `has_input(name::String) -> Bool`

Check if input port has a value (useful for optional inputs).

#### `has_parameter(name::String) -> Bool`

Check if parameter is set.

---

## Rendering Workflows to SVG

VisTrailsJL can render notebook workflows to SVG format for visualization and documentation.

### Basic Rendering

```julia
# Load and build workflow
workflow = parse_workflow_notebook("my_workflow.ipynb")
pipeline, _ = build_pipeline_from_workflow(workflow)

# Render to SVG (automatic layout using Graphviz)
svg = render_pipeline_svg(pipeline, width=1200, height=800)

# Save to file
write("workflow.svg", svg)
```

### Automatic Layout

Notebook workflows don't have visual layout positions by default. VisTrailsJL uses **Graphviz** to automatically compute hierarchical layouts:

```julia
# Explicit auto-layout
auto_layout_pipeline!(pipeline, algorithm="dot")

# Or use render_pipeline_svg (auto-layout by default)
svg = render_pipeline_svg(pipeline)  # Automatically uses Graphviz
```

### Layout Algorithms

Choose different Graphviz layout algorithms:

```julia
# Hierarchical (best for workflows/DAGs)
auto_layout_pipeline!(pipeline, algorithm="dot")

# Force-directed
auto_layout_pipeline!(pipeline, algorithm="fdp")

# Circular
auto_layout_pipeline!(pipeline, algorithm="circo")
```

### Disable Auto-Layout

If you want to control layout manually:

```julia
svg = render_pipeline_svg(pipeline, auto_layout=false)
```

---

## Tips and Best Practices

### 1. Organize Your Workflows

Use markdown cells to document each step:

```markdown
## Step 1: Load Data

This step fetches data from the remote API...
```

### 2. Modular Packages

Keep related modules together in package notebooks:

```
packages/
  ├── statistics.ipynb    # Statistical modules
  ├── visualization.ipynb # Plotting modules
  └── io.ipynb           # I/O modules
```

### 3. Version Control with Git

Workflow notebooks are git-friendly:

```bash
git add my_workflow.ipynb
git commit -m "Add data cleaning step"
```

### 4. Testing Workflows

Create test workflows for your packages:

```julia
#| workflow: test_my_module
#| version: 1

# ... test modules ...

#| execute
```

### 5. Debugging

Enable logging to see execution details:

```julia
cache, outputs = execute_notebook_pipeline(
    pipeline, workflow;
    id_to_module=id_to_module,
    enable_logging=true
)
```

---

## Troubleshooting

### Common Issues

**Problem:** "Module not found in registry"

**Solution:** Check that:
1. Package identifier is correct
2. Module name is spelled correctly
3. Package is registered before use
4. Short name mapping is unique

**Problem:** "Connection reference not found"

**Solution:** Verify:
1. Source module ID exists
2. Source port name is correct
3. Module is defined before being referenced

**Problem:** "Missing required input"

**Solution:** Ensure all required inputs are connected in the `inputs:` section.

---

## Next Steps

- See [examples/](../examples/) for more workflow examples
- Read [DESIGN_VALIDATION.md](DESIGN_VALIDATION.md) for system architecture
- Check [TEST_README.md](../test/README.md) for running tests
- Explore [packages/](../src/packages/) for built-in module implementations

---

*For questions or issues, please file an issue at: https://github.com/VisTrails/VisTrails/issues*
