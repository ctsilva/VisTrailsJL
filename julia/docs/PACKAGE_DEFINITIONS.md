# Package Definitions in Notebooks

Design for defining VisTrails packages using notebooks with nbdev-style directives.

## Current System (Julia Code)

### Current Package Structure

```
src/packages/basic/
├── init.jl                    # Package registration
├── HTTPFile.jl                # Module implementation
├── PythonSource.jl            # Module implementation
├── constants.jl               # Integer, Float, String, etc.
└── datastructures.jl          # Tuple, List, etc.
```

### Current Module Definition Pattern

**HTTPFile.jl**:
```julia
# 1. Define compute type
struct HTTPFileModule <: Module
end

# 2. Implement compute function
function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    url = mod.parameters["url"]
    response = HTTP.get(url)
    content = String(response.body)
    mod.outputs["file"] = content
    mod.uptodate = true
    return mod.outputs
end

# 3. Register module
function register_httpfile!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",  # package
        "HTTPFile",                        # name
        HTTPFileModule,                    # type
        InputPort[],                       # inputs
        [OutputPort("file", String)],      # outputs
        [("url", String)]                  # parameters
    )
    register_module!(descriptor)
end
```

### Issues with Current Approach

1. **Lots of boilerplate** - Every module needs struct + compute + register
2. **Hard to document** - Code and docs are separate
3. **Hard to test** - Tests are in separate files
4. **Not explorable** - Can't try modules interactively

## Proposed: Notebook-Based Packages

### Vision

Define packages in notebooks where:
- Each cell defines one module
- Directives specify module metadata
- Code is the compute function
- Documentation is literate (markdown cells)
- Tests are inline
- Can execute interactively

### Example: Basic Package in Notebook

**`packages/basic.ipynb`**:

```julia
# %% [markdown]
# # Basic Package
#
# Core modules for VisTrails workflows: HTTPFile, File, String, Integer, etc.
#
# **Package**: `org.vistrails.vistrails.basic`
# **Version**: 2.2.0

# %% Package metadata
#| package: org.vistrails.vistrails.basic
#| version: 2.2.0
#| description: Basic modules for workflows

# Package-level setup
using HTTP
using JSON

# %%% [markdown]
# ## HTTPFile Module
#
# Fetches content from an HTTP/HTTPS URL.
#
# **Inputs**: None
# **Outputs**:
# - `file::String` - Content fetched from URL
#
# **Parameters**:
# - `url::String` - The URL to fetch

# %%
#| module: HTTPFile
#| inputs: []
#| outputs:
#|   - file: String
#| parameters:
#|   - url: String

# Compute function
function compute_httpfile(mod::ModuleInstance)
    url = mod.parameters["url"]

    println("Fetching: ", url)

    response = HTTP.get(url)
    content = String(response.body)

    # Set output
    mod.outputs["file"] = content
    mod.uptodate = true
    mod.cache_state = :valid

    return mod.outputs
end

# %% Test HTTPFile
#| test

# Test the module interactively
test_mod = create_test_module(HTTPFileModule)
test_mod.parameters["url"] = "https://httpbin.org/json"
result = compute_httpfile(test_mod)
@assert haskey(result, "file")
@assert length(result["file"]) > 0
println("✓ HTTPFile test passed")

# %%% [markdown]
# ## Integer Module
#
# Constant integer value.

# %%
#| module: Integer
#| base: Constant
#| inputs:
#|   - value: Int
#| outputs:
#|   - value: Int
#| parameters: []

# Integer is a constant - no compute needed
# Just pass through the value

# %%% [markdown]
# ## JuliaSource Module
#
# Execute arbitrary Julia code with access to inputs/outputs.

# %%
#| module: JuliaSource
#| inputs: []  # Dynamic inputs
#| outputs:
#|   - self: Any
#| parameters:
#|   - source: String

function compute_juliasource(mod::ModuleInstance)
    source = mod.parameters["source"]

    # Create execution module
    code_module = Core.Module(Symbol("JuliaSourceExec_", mod.id))

    # Make inputs available
    for (name, value) in mod.inputs
        Core.eval(code_module, :($(Symbol(name)) = $value))
    end

    # Define helpers
    Core.eval(code_module, quote
        function get_input(name::String)
            return $(mod.inputs)[name]
        end

        local outputs = $(mod.outputs)
        function set_output(name::String, value)
            outputs[name] = value
        end
    end)

    # Execute user code
    parsed = Meta.parseall(source)
    result = Core.eval(code_module, parsed)

    mod.outputs["self"] = result
    mod.uptodate = true
    mod.cache_state = :valid

    return mod.outputs
end

# %% Test JuliaSource
#| test

test_mod = create_test_module(JuliaSourceModule)
test_mod.inputs["x"] = 5
test_mod.inputs["y"] = 10
test_mod.parameters["source"] = """
    result = x + y
    set_output("result", result)
"""
result = compute_juliasource(test_mod)
@assert result["result"] == 15
println("✓ JuliaSource test passed")
```

## Directive Specification for Packages

### Package-Level Directives

```julia
#| package: <package_identifier>
#| version: <semver>
#| description: <text>
#| author: <name>
#| dependencies: <pkg1>, <pkg2>, ...
```

Example:
```julia
#| package: org.vistrails.vistrails.basic
#| version: 2.2.0
#| description: Core modules for VisTrails
#| author: VisTrails Team
#| dependencies: HTTP, JSON
```

### Module-Level Directives

```julia
#| module: <ModuleName>
#| base: <BaseClass>            # Optional: Constant, Module (default: Module)
#| inputs:                      # List of input ports
#|   - <name>: <type>
#| outputs:                     # List of output ports
#|   - <name>: <type>
#| parameters:                  # List of parameters
#|   - <name>: <type>
#| description: <text>
#| abstract: true/false         # Is this an abstract module?
```

Example:
```julia
#| module: HTTPFile
#| inputs: []
#| outputs:
#|   - file: String
#| parameters:
#|   - url: String
#| description: Fetch content from HTTP/HTTPS URL
```

### Port Syntax

**Short form** (type only):
```julia
#| inputs:
#|   - data: String
#|   - threshold: Float64
```

**Long form** (with options):
```julia
#| inputs:
#|   - name: data
#|     type: String
#|     optional: false
#|   - name: threshold
#|     type: Float64
#|     optional: true
#|     default: 0.5
```

### Special Directives

```julia
#| test                         # Mark cell as test
#| example                      # Mark cell as example/demo
#| hide                         # Don't include in package export
```

## How It Works

### 1. Package Notebook Structure

```
packages/
├── basic.ipynb              # Basic package definition
├── julia.ipynb              # Julia package
├── pythoncalc.ipynb         # Python calculator
└── control_flow.ipynb       # Control flow modules
```

### 2. Parse Notebook → Package

```julia
"""
Parse a package notebook and register all modules.
"""
function load_package_from_notebook(notebook_path::String)
    nb = read_notebook(notebook_path)

    # Parse package metadata
    pkg_meta = parse_package_metadata(nb)

    package_name = pkg_meta["package"]
    println("Loading package: $package_name")

    # Parse each module cell
    for cell in nb.cells
        if cell.cell_type != "code"
            continue
        end

        directives = parse_cell_directives(cell.source)

        if !haskey(directives, "module")
            continue
        end

        # Create module descriptor
        module_name = directives["module"]
        inputs = parse_ports(get(directives, "inputs", []))
        outputs = parse_ports(get(directives, "outputs", []))
        parameters = parse_parameters(get(directives, "parameters", []))

        # Extract compute function from cell
        compute_func = extract_compute_function(cell.source)

        # Create module type dynamically
        module_type = create_module_type(module_name, compute_func)

        # Register
        descriptor = ModuleDescriptor(
            package_name,
            module_name,
            module_type,
            inputs,
            outputs,
            parameters
        )

        register_module!(descriptor)

        println("  ✓ Registered $module_name")
    end
end
```

### 3. Extract Compute Function

Two approaches:

**Approach A: Named function pattern**

Cell contains a function named `compute_<modulename>`:
```julia
#| module: HTTPFile

function compute_httpfile(mod::ModuleInstance)
    # Implementation
end
```

Parser extracts `compute_httpfile` and associates it with HTTPFile module.

**Approach B: Implicit compute**

Cell code IS the compute function:
```julia
#| module: HTTPFile

# This entire cell becomes the compute function body
url = mod.parameters["url"]
response = HTTP.get(url)
mod.outputs["file"] = String(response.body)
```

Parser wraps this in:
```julia
function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    # Cell code goes here
end
```

**Recommendation**: Use Approach A (named functions) for clarity.

### 4. Testing Inline

Test cells can be executed immediately:

```julia
#| test
#| module: HTTPFile

# Create test instance
mod = create_test_module("HTTPFile")
mod.parameters["url"] = "https://httpbin.org/json"

# Execute
result = compute_httpfile(mod)

# Assert
@assert haskey(result, "file")
@assert contains(result["file"], "slideshow")
println("✓ HTTPFile test passed")
```

When notebook runs, tests execute. When package is loaded, tests are skipped (unless running test suite).

## Comparison: Code vs Notebook

### Current (Julia Files)

**Pros**:
- Fast to load (compiled)
- IDE support (LSP, debugging)
- Traditional package structure

**Cons**:
- Boilerplate for each module
- Docs separate from code
- Tests in different files
- Can't try modules interactively

### Proposed (Notebooks)

**Pros**:
- Literate programming (docs + code)
- Inline testing
- Interactive development
- Examples embedded
- Easy to explore

**Cons**:
- Notebook overhead
- Need to "compile" to .jl files?
- Tool support varies

## Hybrid Approach (Recommended)

**Use notebooks for development, export to .jl files for production:**

1. **Develop in notebooks** (`packages/basic.ipynb`)
   - Write modules with directives
   - Test inline
   - Document thoroughly

2. **Export to Julia files** (`src/packages/basic/`)
   - Use nbdev-style export
   - Generate `init.jl`, `HTTPFile.jl`, etc.
   - Include in package distribution

3. **Round-trip support**
   - Changes to .jl files can be reflected back to notebook
   - Or: treat notebook as source of truth

### Export Command

```bash
# Export package notebook to Julia files
vt-package export packages/basic.ipynb -o src/packages/basic/

# Generate:
# - src/packages/basic/init.jl
# - src/packages/basic/HTTPFile.jl
# - src/packages/basic/JuliaSource.jl
# - etc.
```

### Example Exported File

From notebook cell:
```julia
#| module: HTTPFile
#| export

function compute_httpfile(mod::ModuleInstance)
    url = mod.parameters["url"]
    response = HTTP.get(url)
    mod.outputs["file"] = String(response.body)
    return mod.outputs
end
```

Exported to `src/packages/basic/HTTPFile.jl`:
```julia
"""
HTTPFile Module

Fetches content from an HTTP/HTTPS URL.
(Documentation extracted from notebook markdown)
"""

using HTTP

struct HTTPFileModule <: Module
end

function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    # Compute function from notebook
    url = mod.parameters["url"]
    response = HTTP.get(url)
    mod.outputs["file"] = String(response.body)
    return mod.outputs
end

function register_httpfile!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",
        "HTTPFile",
        HTTPFileModule,
        InputPort[],
        [OutputPort("file", String)],
        [("url", String)]
    )
    register_module!(descriptor)
end
```

## Alternative: Simpler Declarative Syntax

**Pure data approach** - modules as data structures:

```julia
#| module: HTTPFile
#| type: declarative

ModuleSpec(
    name = "HTTPFile",
    package = "org.vistrails.vistrails.basic",
    inputs = [],
    outputs = [("file", String)],
    parameters = [("url", String)],
    compute = function(mod)
        url = mod.parameters["url"]
        response = HTTP.get(url)
        mod.outputs["file"] = String(response.body)
    end
)
```

Even simpler:
```julia
@module HTTPFile begin
    @package "org.vistrails.vistrails.basic"
    @outputs file::String
    @parameters url::String

    @compute function(mod)
        url = mod.parameters["url"]
        response = HTTP.get(url)
        mod.outputs["file"] = String(response.body)
    end
end
```

But this brings back macros... Maybe not simpler after all.

## Decision: What's Best?

Let me propose **three tiers**:

### Tier 1: Simple Declarative Modules (YAML-like)

For simple modules that just transform data:

```julia
#| module: UpperCase
#| inputs:
#|   - text: String
#| outputs:
#|   - result: String
#| compute: |
#|   mod.outputs["result"] = uppercase(mod.inputs["text"])
```

Single-line compute, no function definition needed.

### Tier 2: Function-Based Modules (Most Common)

For modules with real logic:

```julia
#| module: HTTPFile
#| inputs: []
#| outputs:
#|   - file: String
#| parameters:
#|   - url: String

function compute_httpfile(mod::ModuleInstance)
    url = mod.parameters["url"]
    response = HTTP.get(url)
    mod.outputs["file"] = String(response.body)
    mod.uptodate = true
    return mod.outputs
end
```

### Tier 3: Full Control (Complex Modules)

For modules that need custom types, caching, etc:

```julia
#| module: VTKReader
#| export: full

# Full module definition with custom struct
struct VTKReaderModule <: Module
    # Custom fields
    vtk_pipeline::Any
end

function compute(mod::ModuleInstance, ::Type{VTKReaderModule})
    # Complex compute logic
    # Full access to VisTrails internals
end

function register_vtkreader!()
    # Custom registration
end
```

## Recommendation

**Start with Tier 2 (Function-Based)** for the MVP:

1. ✅ Clear separation of metadata (directives) and code (function)
2. ✅ Easy to understand (just functions)
3. ✅ Can export to .jl files cleanly
4. ✅ Testable inline
5. ✅ No macros needed

**Example package notebook**:

```julia
# Basic Package

#| package: org.vistrails.vistrails.basic
#| version: 2.2.0

# HTTPFile Module

#| module: HTTPFile
#| outputs:
#|   - file: String
#| parameters:
#|   - url: String

function compute_httpfile(mod::ModuleInstance)
    url = mod.parameters["url"]
    response = HTTP.get(url)
    mod.outputs["file"] = String(response.body)
    return mod.outputs
end

# Test

#| test
mod = test_module("HTTPFile", url="https://httpbin.org/json")
@assert compute_httpfile(mod)["file"] |> length > 0
```

Simple, clean, and it works!

## Next: Workflow Definitions

Once we nail package definitions, we can design workflow notebooks.

Key difference:
- **Package notebooks**: Define what modules CAN do (module definitions)
- **Workflow notebooks**: Define what modules WILL do (module instances + connections)

Should I design the workflow notebook format next?
