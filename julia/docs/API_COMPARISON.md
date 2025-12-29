# API Comparison: VisTrailsJL vs Python VisTrails

This document compares the Julia implementation of the VisTrails API with the original Python VisTrails API defined in `vistrails/core/api.py`.

## Overview

The Julia API was designed to be compatible with the Python VisTrails API style, making it familiar to existing VisTrails users while taking advantage of Julia's features.

## API Entry Points

### ✅ Implemented

| Function | Python | Julia | Notes |
|----------|--------|-------|-------|
| `load_vistrail(path)` | ✅ | ✅ | Returns wrapper type |
| `load_pipeline(path)` | ✅ | ✅ (as `load_workflow`) | Notebook-based in Julia |
| `load_package(identifier)` | ✅ | ✅ | Julia also supports notebook packages |

### ❌ Not Yet Implemented

| Function | Python | Julia | Notes |
|----------|--------|-------|-------|
| `ipython_mode(use_notebook)` | ✅ | ❌ | Julia has Pluto/IJulia instead |
| `run_vistrail(...)` | ✅ | ❌ | Can be added if needed |
| `output_mode(...)` | ✅ | ❌ | Different output model in Julia |

## Vistrail Class

### ✅ Implemented

| Method/Property | Python | Julia | Notes |
|-----------------|--------|-------|-------|
| `get_pipeline(version)` | ✅ | ✅ | Via `vistrail.vistrail.pipelines[ver]` |
| `select_version(version)` | ✅ | ✅ | `select_version!(wrapper, ver)` |
| `select_latest_version()` | ✅ | ✅ | `select_latest_version!(wrapper)` |
| `current_pipeline` | ✅ property | ✅ field | |
| `current_version` | ✅ property | ✅ via `.vistrail.current_version` |
| `execute(*args, **kwargs)` | ✅ | ✅ | Parameter injection supported |
| `changed` | ✅ property | ❌ | Not tracked yet |

### ❌ Not Yet Implemented

| Method/Property | Python | Julia | Notes |
|-----------------|--------|-------|-------|
| `set_tag(version, tag)` | ✅ | ❌ | Tags loaded but not settable |
| `tag(tag)` | ✅ | ❌ | Convenience for set_tag |
| `__repr__()` | ✅ | ✅ | Custom show() implemented |
| `_repr_html_()` | ✅ | ❌ | SVG rendering exists separately |

### 🔄 Differences

**Python**: Uses `VistrailController` internally
**Julia**: Direct `Vistrail` struct manipulation

**Python**: Tag-based version selection supported
**Julia**: Numeric version IDs only (tags loaded but not used for selection yet)

**Python**: Dynamic pipeline reconstruction on version switch
**Julia**: Requires XML root for reconstruction (limitation documented)

## Pipeline Class

### ✅ Implemented

| Method/Property | Python | Julia | Notes |
|-----------------|--------|-------|-------|
| `execute(*args, **kwargs)` | ✅ | ✅ | Parameter injection supported |
| `get_module(module_id)` | ✅ | ✅ | By ID or name |
| `get_input(name)` | ✅ | ✅ | `get_input(pipeline, name)` |
| `get_output(name)` | ✅ | ✅ (different API) | Via get_module |
| `modules` | ✅ property | ✅ via `.pipeline.modules` | |
| `inputs` | ✅ property | ❌ | Can iterate modules manually |
| `outputs` | ✅ property | ❌ | Can iterate modules manually |

### 🔄 Differences

**Python**: `execute(module == value, kwarg=val)` syntax
**Julia**: `execute(pipeline; kwarg=val)` - simpler keyword-only approach

**Python**: `ModuleValuePair` for `module == value` expressions
**Julia**: Direct keyword argument passing

**Python**: Automatic input/output port discovery via properties
**Julia**: Manual iteration over modules

## ExecutionResults Class

### ✅ Implemented

| Method/Property | Python | Julia | Notes |
|-----------------|--------|-------|-------|
| `output_port(name)` | ✅ | ✅ | `output_port(result, name)` |
| `module_output(module)` | ✅ | ✅ | `module_output(result, id, port)` |
| `__repr__()` | ✅ | ✅ | Custom show() implemented |

### 🔄 Differences

**Python**: `module_output(module)` returns all ports
**Julia**: `module_output(result, id, port)` returns specific port value

**Python**: Access via `resultobj._objects[module_id].outputPorts`
**Julia**: Access via `result.cache[module_id][port_name]`

## Module Class

### ❌ Not Yet Implemented

The Python API has a `Module` class that wraps module descriptors and allows:
- `module == value` syntax for input binding
- Module metadata access
- Dynamic module type classes

**Julia Alternative**: Direct module descriptor and instance manipulation

## Package Class

### ✅ Implemented (Different Approach)

| Feature | Python | Julia |
|---------|--------|-------|
| Package loading | `load_package(identifier)` | `load_package(path)` for notebooks |
| Module access | `pkg.namespace.ModuleName` or `pkg['namespace\|ModuleName']` | Module registry lookup |
| Module classes | Dynamic `ModuleClass` creation | Static descriptors |

### 🔄 Differences

**Python**: Package as namespace with dot/bracket notation
**Julia**: Package registration + registry lookup

**Python**: Packages identified by reverse-DNS identifier
**Julia**: Packages can be notebooks with `#|` directives

## Additional Julia Features

### ✨ Features Not in Python

1. **Notebook-Based Workflows**: Define workflows in `.ipynb` files with `#|` directives
2. **Notebook-Based Packages**: Define custom packages in notebooks
3. **Incremental Output Saving**: Save execution results back to notebooks
4. **Image Output Support**: Automatic PNG embedding for Plot objects
5. **Module Introspection**: `describe_module(type)` shows ports and parameters
6. **Native Julia Execution**: JuliaSource modules execute natively (no PyCall overhead)

## API Usage Comparison

### Python VisTrails

```python
import vistrails as vt

# Load and execute
vistrail = vt.load_vistrail('example.vt')
vistrail.select_latest_version()
result = vistrail.execute(input_a=5, input_b=10)
value = result.output_port('result')

# Module access
pkg = vt.load_package('org.vistrails.vistrails.matplotlib')
module_class = pkg.MplFigure
```

### Julia VisTrailsJL

```julia
using VisTrailsJL

# Load and execute
vt = load_vistrail("example.vt")
select_latest_version!(vt)
result = execute(vt, input_a=5, input_b=10)
value = output_port(result, "result")

# Module introspection
describe_module("matplotlib:MplFigure")

# Notebook workflow
workflow = load_workflow("workflow.ipynb")
result = execute(workflow, save_outputs=true)
```

## Summary

### API Compatibility: ~75%

**Strong Compatibility:**
- ✅ Core workflow execution
- ✅ Version navigation
- ✅ Output extraction
- ✅ Package loading

**Partial Compatibility:**
- 🔄 Tag-based version selection (tags loaded, not used)
- 🔄 Module/input binding syntax (simplified in Julia)
- 🔄 Package namespace access (registry-based instead)

**Missing:**
- ❌ IPython integration (different ecosystem)
- ❌ Tag setting/modification
- ❌ Module == value syntax
- ❌ Vistrail modification methods
- ❌ Changed/dirty tracking

**Julia Advantages:**
- ✨ Notebook-first workflow system
- ✨ Native Julia execution
- ✨ Type safety and performance
- ✨ Git-native version control (via notebooks)
- ✨ Literate programming support

## Recommendations

### For Python VisTrails Users

The Julia API should feel familiar for:
- Loading and executing .vt files
- Navigating versions
- Extracting outputs

New features to explore:
- Notebook-based workflow definitions
- Custom package creation in notebooks
- Native Julia module execution

### For New Users

Start with the notebook-based approach:
1. Define packages in `.ipynb` files
2. Define workflows in `.ipynb` files
3. Use `#|` directives for metadata
4. Execute and save results incrementally

Use the API for:
- Programmatic execution
- Batch processing
- Integration with existing .vt files

## Future Work

To increase Python API compatibility:

1. **Tag Management**: Implement `set_tag()` and tag-based version selection
2. **Module Binding Syntax**: Add `Module == value` syntax support
3. **Changed Tracking**: Track vistrail modifications
4. **Vistrail Modification**: Add methods to modify workflows programmatically
5. **Package Namespace**: Add dot/bracket notation for package module access
6. **Pipeline Properties**: Add `inputs` and `outputs` properties
7. **Module Class**: Wrap module descriptors for better ergonomics

These additions would bring compatibility to ~95% while preserving Julia's unique advantages.
