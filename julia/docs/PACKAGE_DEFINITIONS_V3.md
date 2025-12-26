# Package Definitions in Notebooks (v3 - Type-Dispatched)

**Revised design using full type-dispatched compute functions for better debugging and execution.**

## Key Revision

Use **executable, type-dispatched code** in notebooks:

```julia
#| module: HTTPFile

struct HTTPFileModule <: Module end

function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    url = mod.parameters["url"]
    response = HTTP.get(url)
    mod.outputs["file"] = String(response.body)
    mod.uptodate = true
    mod.cache_state = :valid
    return mod.outputs
end
```

**Why this is better**:
- ✅ **Directly executable** - Copy/paste into REPL works
- ✅ **Debuggable** - Can use Julia debugger on actual code
- ✅ **Testable** - Can test immediately in notebook cells
- ✅ **Transparent** - No hidden wrapping, what you see is what runs
- ✅ **Idiomatic Julia** - Uses multiple dispatch properly

## Complete Package Notebook Example

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

# Package-level setup (optional)
using HTTP
using JSON

# %% [markdown]
# ## HTTPFile Module
#
# Fetches content from an HTTP/HTTPS URL.
#
# **Parameters**:
# - `url::String` - The URL to fetch
#
# **Outputs**:
# - `file::String` - Content fetched from URL

# %% HTTPFile definition
#| module: HTTPFile
#| output_ports:
#|   - name: file
#|     signature: basic:String
#| parameters:
#|   - name: url
#|     signature: basic:String

# Define module type
struct HTTPFileModule <: Module end

# Define compute function
function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    # Get parameter
    url = mod.parameters["url"]

    println("Fetching: ", url)

    # Fetch content
    response = HTTP.get(url)
    content = String(response.body)

    # Set output
    mod.outputs["file"] = content

    # Mark as complete
    mod.uptodate = true
    mod.cache_state = :valid

    return mod.outputs
end

# %% Test HTTPFile
#| test
#| module: HTTPFile

# Create test instance
mod = ModuleInstance(1, ModuleDescriptor(
    "org.vistrails.vistrails.basic",
    "HTTPFile",
    HTTPFileModule,
    InputPort[],
    [OutputPort("file", String)],
    [("url", String)]
))

# Set parameter
mod.parameters["url"] = "https://httpbin.org/json"

# Execute
result = compute(mod, HTTPFileModule)

# Verify
@assert haskey(result, "file")
@assert length(result["file"]) > 0
println("✓ HTTPFile test passed")

# %% [markdown]
# ## JuliaSource Module
#
# Executes arbitrary Julia code with access to inputs/outputs.

# %% JuliaSource definition
#| module: JuliaSource
#| output_ports:
#|   - name: self
#|     signature: basic:Any
#| parameters:
#|   - name: source
#|     signature: basic:String

struct JuliaSourceModule <: Module end

function compute(mod::ModuleInstance, ::Type{JuliaSourceModule})
    # Get source code
    source = mod.parameters["source"]

    # Create execution module
    code_module = Core.Module(Symbol("JuliaSourceExec_", mod.id))

    # Make inputs available as variables
    for (name, value) in mod.inputs
        Core.eval(code_module, :($(Symbol(name)) = $value))
    end

    # Define helper functions
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

    # Set default output
    mod.outputs["self"] = result

    mod.uptodate = true
    mod.cache_state = :valid

    return mod.outputs
end

# %% Test JuliaSource
#| test
#| module: JuliaSource

mod = ModuleInstance(2, ModuleDescriptor(
    "org.vistrails.vistrails.julia",
    "JuliaSource",
    JuliaSourceModule,
    InputPort[],
    [OutputPort("self", Any)],
    [("source", String)]
))

mod.inputs["x"] = 5
mod.inputs["y"] = 10
mod.parameters["source"] = """
    result = x + y
    set_output("result", result)
"""

result = compute(mod, JuliaSourceModule)

@assert result["result"] == 15
println("✓ JuliaSource test passed")
```

## Debugging in Notebooks

### Interactive Testing

Run cells sequentially to test modules:

```julia
# Cell 1: Define module
#| module: HTTPFile

struct HTTPFileModule <: Module end

function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    url = mod.parameters["url"]
    response = HTTP.get(url)
    mod.outputs["file"] = String(response.body)
    return mod.outputs
end

# Cell 2: Create test instance and run
mod = ModuleInstance(1, test_descriptor)
mod.parameters["url"] = "https://httpbin.org/json"

# Cell 3: Execute (can step through with debugger)
using Debugger
@enter compute(mod, HTTPFileModule)

# Or just run
result = compute(mod, HTTPFileModule)
println(result["file"])
```

### Using Julia Debugger

```julia
using Debugger

# Set breakpoint in compute function
@bp

# Execute
result = compute(mod, HTTPFileModule)

# Debugger will stop at breakpoint, can inspect variables:
# - url
# - response
# - content
```

### Profiling

```julia
using Profile

# Profile the compute function
@profile compute(mod, HTTPFileModule)

# View results
Profile.print()
```

### Unit Testing

```julia
using Test

@testset "HTTPFile Module" begin
    mod = create_test_instance(HTTPFileModule)
    mod.parameters["url"] = "https://httpbin.org/json"

    result = compute(mod, HTTPFileModule)

    @test haskey(result, "file")
    @test length(result["file"]) > 0
    @test occursin("slideshow", result["file"])
end
```

## Directive Specification (Simplified)

### Package Metadata

```julia
#| package-meta
#| identifier: <org.domain.package>
#| name: <Display Name>
#| version: <semver>
```

### Module Definition

```julia
#| module: <ModuleName>
#| output_ports:                    # Optional
#|   - name: <port_name>
#|     signature: <package:Type>
#|   - name: <port_name>
#|     signature: <package:Type>
#| input_ports:                     # Optional
#|   - name: <port_name>
#|     signature: <package:Type>
#|     optional: true/false
#| parameters:                      # Optional
#|   - name: <param_name>
#|     signature: <package:Type>

# Then the actual Julia code:
struct <ModuleName>Module <: Module end

function compute(mod::ModuleInstance, ::Type{<ModuleName>Module})
    # Implementation
end
```

### Test Directive

```julia
#| test
#| module: <ModuleName>

# Test code
```

## Parser Implementation

### Extracting Module Definition

```julia
function parse_module_cell(cell)
    directives = parse_cell_directives(cell.source)

    if !haskey(directives, "module")
        return nothing
    end

    module_name = directives["module"]

    # Extract code after directives
    code = extract_code_without_directives(cell.source)

    # Parse the code to find struct and compute function
    struct_def = extract_struct_definition(code, module_name)
    compute_func = extract_compute_function(code, module_name)

    # Verify they exist
    if struct_def === nothing
        error("Module $(module_name) must define struct $(module_name)Module <: Module")
    end

    if compute_func === nothing
        error("Module $(module_name) must define compute(mod, ::Type{$(module_name)Module})")
    end

    # Parse ports from directives
    input_ports = parse_port_list(get(directives, "input_ports", []))
    output_ports = parse_port_list(get(directives, "output_ports", []))
    parameters = parse_parameter_list(get(directives, "parameters", []))

    return ModuleDefinition(
        name = module_name,
        struct_def = struct_def,
        compute_func = compute_func,
        input_ports = input_ports,
        output_ports = output_ports,
        parameters = parameters,
        full_code = code
    )
end
```

### Loading Package from Notebook

```julia
function load_package_from_notebook(notebook_path::String)
    nb = read_notebook(notebook_path)

    # Parse package metadata
    pkg_meta = parse_package_metadata(nb)
    package_id = pkg_meta["identifier"]

    println("Loading package: $package_id")

    # Process each module cell
    for cell in nb.cells
        if cell.cell_type != "code"
            continue
        end

        module_def = parse_module_cell(cell)

        if module_def === nothing
            continue
        end

        # Evaluate the code in current module
        # This defines the struct and compute function
        eval(Meta.parse(module_def.full_code))

        # Get the module type
        module_type = eval(Symbol("$(module_def.name)Module"))

        # Create descriptor
        descriptor = ModuleDescriptor(
            package_id,
            module_def.name,
            module_type,
            module_def.input_ports,
            module_def.output_ports,
            module_def.parameters
        )

        # Register
        register_module!(descriptor)

        println("  ✓ Registered $(module_def.name)")
    end
end
```

## Code Execution Flow

### When Loading Package Notebook

1. **Parse directives** → Extract module name, ports, parameters
2. **Extract code** → Get struct definition and compute function
3. **Evaluate code** → `eval()` the struct and function definitions
4. **Register module** → Create ModuleDescriptor and register

### When Executing Workflow

1. **Module needs execution** → Interpreter calls `compute(mod, ModuleType)`
2. **Multiple dispatch** → Julia finds the right compute function
3. **Function executes** → Same code that was in notebook
4. **Results cached** → Outputs stored in cache

## Advantages for Debugging

### 1. Copy-Paste to REPL

Can copy cell directly to REPL:

```julia
julia> struct HTTPFileModule <: Module end

julia> function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
           url = mod.parameters["url"]
           response = HTTP.get(url)
           mod.outputs["file"] = String(response.body)
           return mod.outputs
       end

julia> # Now test it
       mod = create_test_module(HTTPFileModule)
       mod.parameters["url"] = "https://httpbin.org/json"
       compute(mod, HTTPFileModule)
```

### 2. Step Through with Debugger

```julia
using Debugger

@enter compute(mod, HTTPFileModule)

# Debugger shows:
# 1| function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
# 2|     url = mod.parameters["url"]  ← step here
# 3|     response = HTTP.get(url)     ← step here
# 4|     mod.outputs["file"] = String(response.body)
# 5|     return mod.outputs
# 6| end
```

### 3. Inspect Variables

In notebook, can add inspection cells:

```julia
# Cell 1: Module definition
#| module: HTTPFile

struct HTTPFileModule <: Module end
function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    url = mod.parameters["url"]
    response = HTTP.get(url)
    mod.outputs["file"] = String(response.body)
    return mod.outputs
end

# Cell 2: Test and inspect
mod = create_test_module(HTTPFileModule)
mod.parameters["url"] = "https://httpbin.org/json"
result = compute(mod, HTTPFileModule)

# Cell 3: Inspect intermediate values
println("URL: ", mod.parameters["url"])
println("Output length: ", length(result["file"]))
println("First 100 chars: ", result["file"][1:min(100, end)])
```

### 4. Profile Performance

```julia
using BenchmarkTools

# Benchmark the compute function
@btime compute($mod, HTTPFileModule)

# Output: 245.2 ms (1234 allocations: 56.7 KiB)
```

## Comparison: Named vs Type-Dispatched

| Aspect | Named (`compute_httpfile`) | Type-Dispatched (`compute(mod, ::Type{T})`) |
|--------|---------------------------|---------------------------------------------|
| **Executable in REPL** | ⚠️ Needs wrapper | ✅ **Works directly** |
| **Debuggable** | ⚠️ Debug wrapper | ✅ **Debug actual code** |
| **Testable** | ⚠️ Need to know wrapper | ✅ **Test directly** |
| **Idiomatic Julia** | ❌ Named functions | ✅ **Multiple dispatch** |
| **Simple syntax** | ✅ Easy to write | ⚠️ Need type annotation |
| **No name clashes** | ✅ Unique names | ✅ **Dispatch handles it** |
| **Transparent** | ❌ Hidden wrapper | ✅ **What you see runs** |

**Type-dispatched wins on most important criteria!**

## Migration Path

### Current .jl Files → Notebook

Current code:
```julia
# src/packages/basic/HTTPFile.jl

struct HTTPFileModule <: Module end

function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    url = mod.parameters["url"]
    response = HTTP.get(url)
    mod.outputs["file"] = String(response.body)
    mod.uptodate = true
    mod.cache_state = :valid
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

Becomes notebook cell:
```julia
#| module: HTTPFile
#| output_ports:
#|   - name: file
#|     signature: basic:String
#| parameters:
#|   - name: url
#|     signature: basic:String

struct HTTPFileModule <: Module end

function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    url = mod.parameters["url"]
    response = HTTP.get(url)
    mod.outputs["file"] = String(response.body)
    mod.uptodate = true
    mod.cache_state = :valid
    return mod.outputs
end
```

**Just add directives and remove registration function!**

### Notebook → .jl Files

Can export back to original format:
```julia
export_package_to_jl("packages/basic.ipynb", "src/packages/basic/")
```

Generates traditional .jl files with registration functions.

## Updated Documentation

This replaces `PACKAGE_DEFINITIONS_V2.md` with type-dispatched approach.

Key changes:
- ✅ Use `struct <Name>Module <: Module end`
- ✅ Use `function compute(mod, ::Type{<Name>Module})`
- ✅ Code is directly executable
- ✅ No hidden wrapping
- ✅ Better for debugging and testing

## Decision

**Use full type-dispatched approach for v0.2**

Reasons:
1. ✅ **Executable code** - Can run directly in REPL
2. ✅ **Debuggable** - Can step through actual code
3. ✅ **Transparent** - What you write is what runs
4. ✅ **Idiomatic Julia** - Uses type system properly
5. ✅ **Easy migration** - Current code → notebook is trivial

The slightly more complex syntax (type annotation) is **worth it** for the debugging and transparency benefits.
