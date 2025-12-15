# Package Definitions (Aligned with Python VisTrails)

Refined design for defining VisTrails packages using notebooks, following the canonical Python VisTrails package structure.

## Python VisTrails Package Structure (Reference)

### Package Files

```
vistrails/packages/mypackage/
├── __init__.py          # Package metadata
└── init.py              # Module definitions and registration
```

### __init__.py (Package Metadata)

```python
identifier = 'org.vistrails.vistrails.mypackage'
name = 'My Package'
version = '0.1.0'
```

### init.py (Module Definitions)

```python
from vistrails.core.modules.vistrails_module import Module

class MyModule(Module):
    """Module documentation"""

    _input_ports = [
        IPort(name='input1', signature='basic:Float'),
        IPort(name='input2', signature='basic:Integer', optional=True)
    ]

    _output_ports = [
        OPort(name='result', signature='basic:Float')
    ]

    def compute(self):
        val1 = self.get_input('input1')
        val2 = self.get_input('input2') if self.has_input('input2') else 0
        result = val1 + val2
        self.set_output('result', result)

# Register modules
_modules = [MyModule]
```

## Proposed: Notebook-Based Package Definition

### Single Notebook Per Package

**`packages/mypackage.ipynb`** contains:
1. Package metadata (equivalent to `__init__.py`)
2. Module definitions (equivalent to `init.py`)
3. Documentation
4. Tests
5. Examples

### Example: Complete Package Notebook

```julia
# %% [markdown]
# # My Package
#
# Custom modules for specialized workflows.

# %% Package metadata (equivalent to __init__.py)
#| package-meta
#| identifier: org.vistrails.vistrails.mypackage
#| name: My Package
#| version: 0.1.0
#| configuration:
#|   debug: false

# %% Package initialization
#| package-init

# Package-level imports and setup
using HTTP
using JSON

# %% [markdown]
# ## MyModule
#
# Description of what this module does.
#
# **Inputs**:
# - `input1::Float64` - First input value
# - `input2::Integer` (optional) - Second input value
#
# **Outputs**:
# - `result::Float64` - Computed result

# %% MyModule definition
#| module: MyModule
#| input_ports:
#|   - name: input1
#|     signature: basic:Float
#|   - name: input2
#|     signature: basic:Integer
#|     optional: true
#| output_ports:
#|   - name: result
#|     signature: basic:Float

# Compute function (equivalent to Python's compute() method)
function compute(self::ModuleInstance)
    val1 = get_input(self, "input1")
    val2 = has_input(self, "input2") ? get_input(self, "input2") : 0

    result = val1 + val2

    set_output(self, "result", result)
end

# %% Test MyModule
#| test

# Create test instance
mod = create_test_module("MyModule")
set_input!(mod, "input1", 5.0)
set_input!(mod, "input2", 3)

# Execute
compute(mod)

# Verify
@assert get_output(mod, "result") == 8.0
println("✓ MyModule test passed")

# %% [markdown]
# ## AnotherModule
#
# Another module in the same package...

# %% AnotherModule definition
#| module: AnotherModule
#| input_ports:
#|   - name: data
#|     signature: basic:String
#| output_ports:
#|   - name: processed
#|     signature: basic:String

function compute(self::ModuleInstance)
    data = get_input(self, "data")
    processed = uppercase(data)
    set_output(self, "processed", processed)
end
```

## Key Design Principles (Match Python VisTrails)

### 1. Module Base Class Pattern

Python:
```python
class MyModule(Module):
    def compute(self):
        # ...
```

Julia Notebook:
```julia
#| module: MyModule

function compute(self::ModuleInstance)
    # Same compute pattern as Python!
end
```

**Key**: Use same `self` convention and `compute()` method name.

### 2. Port Definitions Match Python

Python:
```python
_input_ports = [
    IPort(name='input1', signature='basic:Float'),
    IPort(name='input2', signature='basic:Integer', optional=True)
]
```

Julia Directive:
```julia
#| input_ports:
#|   - name: input1
#|     signature: basic:Float
#|   - name: input2
#|     signature: basic:Integer
#|     optional: true
```

**Exact same structure!** Just YAML instead of Python list.

### 3. Signature System

Use VisTrails signature format:
- `basic:Float` → Float from basic package
- `basic:Integer` → Integer from basic package
- `basic:String` → String from basic package
- `mypackage:MyModule` → Custom module type

Benefits:
- ✅ Compatible with Python VisTrails
- ✅ Clear type system
- ✅ Package namespacing

### 4. Port Options

Python supports:
```python
IPort(name='port',
      signature='basic:Float',
      optional=True,
      default=0.0,
      label='Nice Label',
      depth=1)  # List depth
```

Julia directive:
```julia
#| input_ports:
#|   - name: port
#|     signature: basic:Float
#|     optional: true
#|     default: 0.0
#|     label: Nice Label
#|     depth: 1
```

### 5. Configuration Objects

Python:
```python
configuration = ConfigurationObject(
    cache_dir=(None, str),
    debug=False
)
```

Julia directive:
```julia
#| configuration:
#|   cache_dir: /tmp/vistrails
#|   debug: false
```

## Complete Directive Specification

### Package Metadata Directive

```julia
#| package-meta
#| identifier: <org.domain.package>  # Required
#| name: <Display Name>              # Optional (defaults to identifier)
#| version: <semver>                 # Required
#| description: <text>               # Optional
#| author: <name>                    # Optional
#| configuration:                    # Optional
#|   key: value
```

### Package Initialization Directive

```julia
#| package-init

# Package-level setup code
# Imports, global variables, helper functions
```

### Module Definition Directive

```julia
#| module: <ModuleName>              # Required
#| base: Module                      # Optional (default: Module)
#| input_ports:                      # Optional (can be empty list)
#|   - name: <port_name>
#|     signature: <package:Type>
#|     optional: true/false          # Optional (default: false)
#|     default: <value>              # Optional
#|     label: <display text>         # Optional
#|     depth: <int>                  # Optional (for lists)
#| output_ports:                     # Optional (can be empty list)
#|   - name: <port_name>
#|     signature: <package:Type>
#|     label: <display text>         # Optional
#| description: <text>               # Optional (can use markdown cell instead)
```

### Test Directive

```julia
#| test
#| module: <ModuleName>              # Optional: which module this tests

# Test code
```

### Example Directive

```julia
#| example
#| module: <ModuleName>              # Optional: which module this demonstrates

# Example usage code
```

## Helper Functions (Match Python API)

### Port Access (Match Python self.get_input() etc.)

```julia
# Input
val = get_input(self, "port_name")
has = has_input(self, "port_name")
list_of_vals = get_input_list(self, "port_name")  # For depth > 0

# Output
set_output(self, "port_name", value)
```

### Module Inspection

```julia
# Check if input port exists and has value
if has_input(self, "optional_param")
    val = get_input(self, "optional_param")
else
    val = default_value
end
```

## Example: HTTPFile Module (Canonical)

```julia
# %% [markdown]
# # Basic Package
#
# Core modules for VisTrails workflows.

# %% Package metadata
#| package-meta
#| identifier: org.vistrails.vistrails.basic
#| name: Basic Modules
#| version: 2.2.0

# %% Package initialization
#| package-init

using HTTP

# %% [markdown]
# ## HTTPFile
#
# Fetches content from an HTTP/HTTPS URL.

# %% HTTPFile definition
#| module: HTTPFile
#| input_ports: []
#| output_ports:
#|   - name: file
#|     signature: basic:String
#|     label: File Content
#| parameters:
#|   - name: url
#|     signature: basic:String

function compute(self::ModuleInstance)
    url = get_parameter(self, "url")

    println("Fetching: ", url)

    response = HTTP.get(url)
    content = String(response.body)

    set_output(self, "file", content)
end

# %% Test HTTPFile
#| test
#| module: HTTPFile

mod = create_test_module("HTTPFile")
set_parameter!(mod, "url", "https://httpbin.org/json")

compute(mod)

content = get_output(mod, "file")
@assert length(content) > 0
@assert contains(content, "slideshow")
println("✓ HTTPFile test passed")
```

## Parameters vs Input Ports

**Important distinction** (from Python VisTrails):

### Input Ports
- Connected from other modules
- Dynamic values during execution
- Set via connections in workflow

```python
_input_ports = [IPort(name='data', signature='basic:String')]
```

### Parameters (Function Ports)
- Set by user in GUI/workflow definition
- Static configuration values
- Often appear as `Function` in workflow XML

Python uses `_input_ports` for both, but separates them semantically.

Julia directive proposal:
```julia
#| input_ports:        # Connected from other modules
#|   - name: data
#|     signature: basic:String
#| parameters:         # User-configurable values
#|   - name: url
#|     signature: basic:String
```

**However**, looking at Python code, parameters ARE input ports! They're just marked differently in the GUI.

**Revised approach**: Use `input_ports` for both, add `is_parameter` flag:

```julia
#| input_ports:
#|   - name: url
#|     signature: basic:String
#|     is_parameter: true        # User sets this (not connected)
#|   - name: data
#|     signature: basic:String
#|     is_parameter: false       # Connected from other module
```

Or simpler: keep the current distinction in directives for clarity, but translate to ports internally.

## Advanced: Dynamic Ports (PythonSource/JuliaSource)

Python PythonSource has dynamic ports - can accept any inputs/outputs.

```python
class PythonSource(Module):
    # No _input_ports defined - all dynamic!

    def compute(self):
        # Access any input by name
        val = self.get_input('any_name') if self.has_input('any_name') else None
        # Set any output
        self.set_output('any_output', result)
```

Julia directive:
```julia
#| module: JuliaSource
#| input_ports: dynamic     # Accept any inputs
#| output_ports: dynamic    # Can set any outputs
#| parameters:
#|   - name: source
#|     signature: basic:String

function compute(self::ModuleInstance)
    source = get_parameter(self, "source")

    # Execute source code
    # Code can access any input via get_input()
    # Code can set any output via set_output()
end
```

## Conversion: Notebook → Julia Package Files

### Generate __init__.py Equivalent

From:
```julia
#| package-meta
#| identifier: org.vistrails.vistrails.mypackage
#| name: My Package
#| version: 0.1.0
```

Generate `Package.toml`:
```toml
identifier = "org.vistrails.vistrails.mypackage"
name = "My Package"
version = "0.1.0"
```

Or just Julia code:
```julia
# src/packages/mypackage/metadata.jl
const PACKAGE_IDENTIFIER = "org.vistrails.vistrails.mypackage"
const PACKAGE_NAME = "My Package"
const PACKAGE_VERSION = v"0.1.0"
```

### Generate Module Files

From notebook cell:
```julia
#| module: MyModule
#| input_ports:
#|   - name: input1
#|     signature: basic:Float

function compute(self::ModuleInstance)
    val = get_input(self, "input1")
    set_output(self, "result", val * 2)
end
```

Generate `src/packages/mypackage/MyModule.jl`:
```julia
"""
MyModule

(Documentation from markdown cell above module definition)
"""

struct MyModuleType <: Module
end

function compute(self::ModuleInstance, ::Type{MyModuleType})
    val = get_input(self, "input1")
    set_output(self, "result", val * 2)
end

function register_mymodule!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.mypackage",
        "MyModule",
        MyModuleType,
        [InputPort("input1", Float64)],
        [OutputPort("result", Float64)],
        []
    )
    register_module!(descriptor)
end
```

## Benefits of This Approach

### 1. **Exact Python VisTrails Compatibility**

Same concepts:
- ✅ Module base class
- ✅ `compute()` method
- ✅ `get_input()` / `set_output()` API
- ✅ Port signatures (basic:Float, etc.)
- ✅ Package metadata structure
- ✅ Configuration objects

### 2. **Literate Package Development**

```markdown
# HTTPFile Module

This module fetches content from HTTP/HTTPS URLs using Julia's HTTP.jl library.

It's more efficient than Python's urllib because...
```

```julia
#| module: HTTPFile

function compute(self::ModuleInstance)
    # Implementation with inline comments
end
```

```julia
#| test

# Tests right here!
```

### 3. **Easy to Learn**

Python developer sees:
```python
class MyModule(Module):
    def compute(self):
        val = self.get_input('x')
        self.set_output('y', val * 2)
```

Julia notebook has:
```julia
#| module: MyModule

function compute(self::ModuleInstance)
    val = get_input(self, "x")
    set_output(self, "y", val * 2)
end
```

**Nearly identical!**

### 4. **Export to Traditional Package Structure**

Still generate `.jl` files for production:
```
src/packages/mypackage/
├── metadata.jl
├── init.jl
├── MyModule.jl
└── AnotherModule.jl
```

Best of both worlds!

## Recommendation

**Use this refined design** because:

1. ✅ **Faithful to Python VisTrails** - Same concepts, same API
2. ✅ **Clear separation** - Package metadata vs modules vs tests
3. ✅ **Professional** - Can export to standard Julia package structure
4. ✅ **Teachable** - Python VisTrails users will recognize everything

**Next step**: Design workflow notebooks (using instances of these modules)

Should I proceed with workflow notebook design?
