# Python to Julia Module Migration Guide

This guide explains how to convert Python VisTrails modules to Julia VisTrailsJL modules.

## Table of Contents
- [Feature Comparison](#feature-comparison)
- [Side-by-Side Examples](#side-by-side-examples)
- [Migration Steps](#migration-steps)
- [API Reference](#api-reference)
- [Common Patterns](#common-patterns)

---

## Feature Comparison

### Core Module Definition

| Feature | Python VisTrails | Julia Traditional | Julia Notebook | Status |
|---------|-----------------|-------------------|----------------|--------|
| **Base Class** | `class Divide(Module)` | `struct DivideModule <: Module` | N/A (directive-based) | ✅ |
| **Input Ports** | `_input_ports = [IPort(...)]` | `[InputPort(...)]` in descriptor | `#\| input_ports:` | ✅ |
| **Output Ports** | `_output_ports = [OPort(...)]` | `[OutputPort(...)]` in descriptor | `#\| output_ports:` | ✅ |
| **Port Signatures** | `signature='basic:Float'` | `InputPort("arg1", Float64)` | `signature: basic:Float` | ✅ |
| **Port Labels** | `label="dividend"` | `InputPort(..., label="dividend")` | `label: dividend` | ✅ |
| **Optional Ports** | Supported | `InputPort(..., optional=true)` | `optional: true` | ✅ |
| **compute() method** | `def compute(self)` | `compute(mod, ::Type{T})` | Code in cell | ✅ |
| **get_input()** | `self.get_input("arg1")` | `mod.inputs["arg1"]` | `get_input("arg1")` | ✅ |
| **set_output()** | `self.set_output("result", val)` | `mod.outputs["result"] = val` | `set_output("result", val)` | ✅ |
| **Error Handling** | `raise ModuleError(self, msg)` | `throw(ModuleError(mod, msg))` | `throw(ModuleError(msg))` | ✅ |
| **Registration** | Automatic (via class) | Manual `register_module!()` | Automatic (notebook) | ✅ |

---

## Side-by-Side Examples

### Example 1: Divide Module

#### Python Version
```python
class Divide(Module):
    """Divides two numbers."""

    _input_ports = [
        IPort(name='arg1',
              signature='basic:Float',
              label="dividend"),
        IPort(name='arg2',
              signature='basic:Float',
              label='divisor')
    ]

    _output_ports = [
        OPort(name='result',
              signature='basic:Float',
              label='quotient')
    ]

    def compute(self):
        arg1 = self.get_input("arg1")
        arg2 = self.get_input("arg2")

        if arg2 == 0.0:
            raise ModuleError(self, "Division by zero")

        self.set_output("result", arg1 / arg2)
```

#### Julia Traditional Version
```julia
"""
DivideModule <: Module

Divides two numbers.
"""
struct DivideModule <: Module
    # Module state (if needed)
end

function compute(mod::ModuleInstance, ::Type{DivideModule})
    # Get inputs
    arg1 = mod.inputs["arg1"]
    arg2 = mod.inputs["arg2"]

    # Check for division by zero
    if arg2 == 0.0
        throw(ModuleError(mod, "Division by zero"))
    end

    # Compute and set output
    result = arg1 / arg2
    mod.outputs["result"] = result

    return mod.outputs
end

function register_divide!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",      # package
        "Divide",                              # name
        DivideModule,                          # type
        [InputPort("arg1", Float64, label="dividend"),
         InputPort("arg2", Float64, label="divisor")],
        [OutputPort("result", Float64, label="quotient")],
        Tuple{String, Type}[]                  # parameters (none)
    )

    register_module!(descriptor)
end
```

#### Julia Notebook Version
```julia
#| module: Divide
#| input_ports:
#|   - name: arg1
#|     signature: basic:Float
#|     label: dividend
#|   - name: arg2
#|     signature: basic:Float
#|     label: divisor
#| output_ports:
#|   - name: result
#|     signature: basic:Float
#|     label: quotient

"""Divides two numbers."""

# Get inputs
arg1 = get_input("arg1")
arg2 = get_input("arg2")

# Check for division by zero
if arg2 == 0.0
    throw(ModuleError("Division by zero"))
end

# Compute and set output
set_output("result", arg1 / arg2)
```

---

## Migration Steps

### Step 1: Choose Your Approach

You have **three options** for migrating Python modules to Julia:

1. **Traditional Julia Modules** - Best for complex modules with significant state
2. **Notebook Modules** - Best for simple modules, prototyping, or literate programming
3. **Hybrid** - Use both approaches in the same package

### Step 2: Convert Port Definitions

#### Python → Julia Traditional
```python
# Python
_input_ports = [
    IPort(name='value', signature='basic:Float', optional=False),
    IPort(name='threshold', signature='basic:Float', optional=True)
]
```

```julia
# Julia Traditional
[
    InputPort("value", Float64, optional=false),
    InputPort("threshold", Float64, optional=true, default=0.0)
]
```

#### Python → Julia Notebook
```python
# Python
_input_ports = [IPort(name='value', signature='basic:Float')]
```

```julia
# Julia Notebook
#| input_ports:
#|   - name: value
#|     signature: basic:Float
```

### Step 3: Convert Type Signatures

| Python Signature | Julia Type | Julia Signature |
|------------------|------------|-----------------|
| `basic:Integer` | `Int` | `basic:Integer` |
| `basic:Float` | `Float64` | `basic:Float` |
| `basic:String` | `String` | `basic:String` |
| `basic:Boolean` | `Bool` | `basic:Boolean` |
| `basic:List` | `Vector` | `basic:List` |
| `basic:Dictionary` | `Dict` | `basic:Dictionary` |

### Step 4: Convert compute() Method

#### Pattern 1: Simple Input/Output
```python
# Python
def compute(self):
    x = self.get_input("x")
    y = self.get_input("y")
    self.set_output("result", x + y)
```

```julia
# Julia Traditional
function compute(mod::ModuleInstance, ::Type{MyModule})
    x = mod.inputs["x"]
    y = mod.inputs["y"]
    mod.outputs["result"] = x + y
    return mod.outputs
end
```

```julia
# Julia Notebook
x = get_input("x")
y = get_input("y")
set_output("result", x + y)
```

#### Pattern 2: Parameters
```python
# Python
def compute(self):
    url = self.get_input_from_port("url")  # parameter
    data = fetch(url)
    self.set_output("file", data)
```

```julia
# Julia Traditional
function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    url = mod.parameters["url"]
    data = HTTP.get(url)
    mod.outputs["file"] = String(data.body)
    return mod.outputs
end
```

```julia
# Julia Notebook
url = get_parameter("url")
data = HTTP.get(url)
set_output("file", String(data.body))
```

#### Pattern 3: Error Handling
```python
# Python
def compute(self):
    if condition:
        raise ModuleError(self, "Error message")
```

```julia
# Julia Traditional
function compute(mod::ModuleInstance, ::Type{MyModule})
    if condition
        throw(ModuleError(mod, "Error message"))
    end
    return mod.outputs
end
```

```julia
# Julia Notebook
if condition
    throw(ModuleError("Error message"))
end
```

### Step 5: Registration

#### Python (Automatic)
```python
# Python modules are automatically registered when the class is defined
```

#### Julia Traditional (Manual)
```julia
function register_mymodule!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.mypackage",
        "MyModule",
        MyModuleType,
        input_ports,
        output_ports,
        parameters
    )
    register_module!(descriptor)
end

# Call during package initialization
register_mymodule!()
```

#### Julia Notebook (Automatic)
```julia
# Automatically registered when notebook is loaded via:
pkg = load_package_from_notebook("my_package.ipynb")
register_notebook_package!(pkg)
```

---

## API Reference

### Module Base Class
```julia
# Python
class MyModule(Module):
    pass

# Julia Traditional
struct MyModule <: Module
    # fields (if needed)
end
```

### Port Definitions

#### InputPort
```julia
# Basic
InputPort(name::String, type::Type=Any)

# With options
InputPort(name::String, type::Type;
          optional::Bool=false,
          default=nothing,
          label::String="")
```

#### OutputPort
```julia
# Basic
OutputPort(name::String, type::Type=Any)

# With label
OutputPort(name::String, type::Type; label::String="")
```

### Module Instance API

```julia
# Get input (Julia Traditional)
value = mod.inputs["port_name"]

# Get input (Julia Notebook)
value = get_input("port_name")

# Check if input exists
has_input("port_name")  # Notebook only

# Set output (Julia Traditional)
mod.outputs["port_name"] = value

# Set output (Julia Notebook)
set_output("port_name", value)

# Get parameter (Julia Traditional)
param = mod.parameters["param_name"]

# Get parameter (Julia Notebook)
param = get_parameter("param_name")

# Check if parameter exists
has_parameter("param_name")  # Notebook only
```

### Error Handling

```julia
# Julia Traditional
throw(ModuleError(mod, "Error message"))

# Julia Notebook
throw(ModuleError("Error message"))

# Alternative: use standard Julia errors
error("Error message")
```

---

## Common Patterns

### Pattern 1: Simple Arithmetic Module

**Python:**
```python
class Add(Module):
    _input_ports = [IPort('a', 'basic:Float'),
                    IPort('b', 'basic:Float')]
    _output_ports = [OPort('sum', 'basic:Float')]

    def compute(self):
        self.set_output('sum',
                       self.get_input('a') + self.get_input('b'))
```

**Julia Notebook:**
```julia
#| module: Add
#| input_ports:
#|   - {name: a, signature: basic:Float}
#|   - {name: b, signature: basic:Float}
#| output_ports:
#|   - {name: sum, signature: basic:Float}

set_output("sum", get_input("a") + get_input("b"))
```

### Pattern 2: Module with Optional Input

**Python:**
```python
class Filter(Module):
    _input_ports = [
        IPort('data', 'basic:List'),
        IPort('threshold', 'basic:Float', optional=True)
    ]
    _output_ports = [OPort('filtered', 'basic:List')]

    def compute(self):
        data = self.get_input('data')
        threshold = self.get_input('threshold') if self.has_input('threshold') else 0.0
        filtered = [x for x in data if x > threshold]
        self.set_output('filtered', filtered)
```

**Julia Notebook:**
```julia
#| module: Filter
#| input_ports:
#|   - {name: data, signature: basic:List}
#|   - {name: threshold, signature: basic:Float, optional: true}
#| output_ports:
#|   - {name: filtered, signature: basic:List}

data = get_input("data")
threshold = has_input("threshold") ? get_input("threshold") : 0.0
filtered = filter(x -> x > threshold, data)
set_output("filtered", filtered)
```

### Pattern 3: Module with External Dependencies

**Python:**
```python
import numpy as np

class Statistics(Module):
    _input_ports = [IPort('array', 'basic:List')]
    _output_ports = [OPort('mean', 'basic:Float'),
                     OPort('std', 'basic:Float')]

    def compute(self):
        arr = np.array(self.get_input('array'))
        self.set_output('mean', float(np.mean(arr)))
        self.set_output('std', float(np.std(arr)))
```

**Julia Notebook:**
```julia
#| module: Statistics
#| input_ports:
#|   - {name: array, signature: basic:List}
#| output_ports:
#|   - {name: mean, signature: basic:Float}
#|   - {name: std, signature: basic:Float}

using Statistics

arr = get_input("array")
set_output("mean", mean(arr))
set_output("std", std(arr))
```

---

## Key Differences to Remember

### 1. Type Dispatch vs Inheritance
- **Python**: Uses inheritance (`class MyModule(Module)`)
- **Julia**: Uses type dispatch (`compute(mod, ::Type{MyModule})`)

### 2. Two Definition Styles
- **Python**: Only code-based modules
- **Julia**: Both code-based AND notebook-based modules

### 3. Explicit Return
- **Python**: No return needed from `compute()`
- **Julia Traditional**: Must return `mod.outputs`
- **Julia Notebook**: No return needed

### 4. Module State
- **Python**: Store state as instance variables (`self.x = value`)
- **Julia Traditional**: Store in struct fields or use module instance
- **Julia Notebook**: Use cell variables (accessible across cells)

---

## Migration Checklist

- [ ] Identify all Python modules in your package
- [ ] For each module:
  - [ ] Choose Traditional or Notebook approach
  - [ ] Convert port definitions
  - [ ] Convert type signatures
  - [ ] Convert compute() logic
  - [ ] Handle errors appropriately
  - [ ] Add registration code (if Traditional)
- [ ] Test module functionality
- [ ] Update package initialization
- [ ] Document any Julia-specific behaviors

---

## Getting Help

- **Documentation**: See `julia/docs/` for more guides
- **Examples**: Check `julia/src/packages/` for working modules
- **Issues**: Report bugs at https://github.com/ctsilva/VisTrailsJL

---

**Last Updated**: 2025-12-27
**VisTrailsJL Version**: v0.2
