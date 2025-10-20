# VisTrails Julia Reimplementation

A modern reimplementation of VisTrails in Julia, maintaining the same directory structure and architecture for compatibility while adding new capabilities.

## Goals

1. **Read original .vt files** - Full compatibility with Python VisTrails
2. **Execute workflows** - Support JuliaSource, PythonSource, and HTTPFile modules
3. **Maintain structure** - Same directory layout as Python version
4. **Extensibility** - Easy to add new packages and modules
5. **Interoperability** - Python and Julia modules can coexist

## Directory Structure

```
VisTrailsJL/
├── src/
│   ├── VisTrailsJL.jl           # Main module entry point
│   ├── core/
│   │   ├── db/
│   │   │   ├── io.jl            # Load/save operations
│   │   │   └── locator.jl       # File locators
│   │   ├── vistrail/
│   │   │   ├── vistrail.jl      # Main vistrail class
│   │   │   ├── pipeline.jl      # Pipeline/workflow
│   │   │   ├── module.jl        # Module base class
│   │   │   ├── connection.jl    # Connection class
│   │   │   ├── port.jl          # Port class
│   │   │   └── controller.jl    # Workflow controller
│   │   ├── interpreter/
│   │   │   ├── cached.jl        # Cached execution
│   │   │   └── default.jl       # Default interpreter
│   │   ├── modules/
│   │   │   ├── module_registry.jl  # Module registration
│   │   │   ├── basic_modules.jl    # Basic module types
│   │   │   └── vistrails_module.jl # Base module class
│   │   └── system.jl            # System utilities
│   ├── db/
│   │   ├── services/
│   │   │   ├── io.jl            # XML I/O
│   │   │   └── locator.jl       # Locator services
│   │   └── domain/
│   │       └── objects.jl       # DB domain models
│   └── packages/
│       ├── basic/
│       │   ├── init.jl          # Basic package initialization
│       │   ├── HTTPFile.jl      # HTTP file fetching
│       │   ├── File.jl          # File operations
│       │   ├── String.jl        # String operations
│       │   ├── Integer.jl       # Integer type
│       │   └── List.jl          # List operations
│       ├── pythoncalc/
│       │   └── PythonCalc.jl    # Python calculator (via PyCall)
│       ├── julia/
│       │   ├── init.jl          # Julia package initialization
│       │   └── JuliaSource.jl   # Execute Julia code
│       └── python/
│           ├── init.jl          # Python interop initialization
│           └── PythonSource.jl  # Execute Python code (via PyCall)
├── test/
│   ├── runtests.jl
│   └── test_modules.jl
├── examples/
│   └── julia/
│       ├── simple_calc.jl       # Simple Julia workflow
│       └── http_fetch.jl        # HTTP + processing
├── Project.toml                 # Julia package manifest
└── README.md
```

## Core Type Hierarchy

### Module System

```julia
# Abstract base types (matching Python structure)
abstract type ModuleDescriptor end
abstract type Port end
abstract type Connection end

# Core types
struct InputPort <: Port
    name::String
    type::Type
    optional::Bool
end

struct OutputPort <: Port
    name::String
    type::Type
end

# Base module (similar to vistrails_module.py)
abstract type Module end

mutable struct ModuleInstance <: Module
    id::Int
    descriptor::ModuleDescriptor
    inputs::Dict{String, Any}
    outputs::Dict{String, Any}
    parameters::Dict{String, Any}
    cache_state::Symbol  # :invalid, :valid, :computing
end
```

### Package Structure

```julia
# Package descriptor (similar to package.py)
struct Package
    identifier::String
    name::String
    version::String
    modules::Dict{String, Type{<:Module}}
    dependencies::Vector{String}
end

# Global module registry
const MODULE_REGISTRY = Dict{String, ModuleDescriptor}()
```

## Key Packages Implementation

### 1. Basic Package (org.vistrails.vistrails.basic)

```julia
# packages/basic/HTTPFile.jl

using HTTP

struct HTTPFile <: Module
    url::String
end

function compute(mod::HTTPFile)
    response = HTTP.get(mod.url)
    return Dict("file" => String(response.body))
end

# Module descriptor
function register_httpfile()
    register_module(
        "org.vistrails.vistrails.basic",
        "HTTPFile",
        HTTPFile,
        inputs = [],
        outputs = [OutputPort("file", String)],
        parameters = [("url", String)]
    )
end
```

### 2. Julia Package (org.vistrails.vistrails.julia)

```julia
# packages/julia/JuliaSource.jl

struct JuliaSource <: Module
    source::String
end

function compute(mod::JuliaSource)
    # Create a module to evaluate the code
    code_module = Module()

    # Define input/output functions
    Core.eval(code_module, :(
        # Inputs from ports
        function get_input(name::String)
            # Get from module inputs
        end

        # Outputs to ports
        function set_output(name::String, value)
            # Set module outputs
        end
    ))

    # Execute user code
    result = Core.eval(code_module, Meta.parse(mod.source))

    return Dict("self" => result)
end

# Module descriptor
function register_juliasource()
    register_module(
        "org.vistrails.vistrails.julia",
        "JuliaSource",
        JuliaSource,
        inputs = [],  # Dynamic based on code
        outputs = [OutputPort("self", Any)],
        parameters = [("source", String)]
    )
end
```

### 3. Python Package (org.vistrails.vistrails.python)

```julia
# packages/python/PythonSource.jl

using PyCall

struct PythonSource <: Module
    source::String
end

function compute(mod::PythonSource)
    # Use PyCall to execute Python code
    py"""
    exec($(mod.source))
    """

    # Get output from Python namespace
    result = py"locals().get('o', None)"

    return Dict("self" => result)
end

# Module descriptor
function register_pythonsource()
    register_module(
        "org.vistrails.vistrails.basic",  # Keep original package
        "PythonSource",
        PythonSource,
        inputs = [],  # Dynamic
        outputs = [OutputPort("self", Any)],
        parameters = [("source", String)]
    )
end
```

## Reading Original .vt Files

### XML Parser (db/services/io.jl)

```julia
using EzXML
using ZipFile

function load_vistrail_from_xml(xml_content::String)
    doc = parsexml(xml_content)
    root = EzXML.root(doc)

    # Parse vistrail structure
    vistrail = Vistrail()

    # Parse actions (versions)
    for action in findall("//action", root)
        parse_action!(vistrail, action)
    end

    # Parse modules
    for module in findall("//module", root)
        parse_module!(vistrail, module)
    end

    # Parse connections
    for conn in findall("//connection", root)
        parse_connection!(vistrail, conn)
    end

    return vistrail
end

function parse_module!(vistrail::Vistrail, xml_node::EzXML.Node)
    id = parse(Int, xml_node["id"])
    name = xml_node["name"]
    package = xml_node["package"]

    # Map Python package names to Julia equivalents
    julia_package = map_package_name(package)

    # Create module instance
    mod = create_module_instance(julia_package, name, id)

    # Parse parameters (functions in VisTrails terminology)
    for func in findall(".//function", xml_node)
        func_name = func["name"]
        params = parse_parameters(func)
        set_parameter!(mod, func_name, params)
    end

    add_module!(vistrail, id, mod)
end

function map_package_name(python_package::String)
    # Map Python packages to Julia equivalents
    mapping = Dict(
        "org.vistrails.vistrails.basic" => "org.vistrails.vistrails.basic",
        "org.vistrails.vistrails.pythoncalc" => "org.vistrails.vistrails.pythoncalc",
        # New Julia-native packages
        "org.vistrails.vistrails.julia" => "org.vistrails.vistrails.julia"
    )

    return get(mapping, python_package, python_package)
end
```

## Workflow Execution

### Interpreter (core/interpreter/default.jl)

```julia
struct Interpreter
    pipeline::Pipeline
    cache::Dict{Int, Any}
end

function execute_pipeline(pipeline::Pipeline)
    interp = Interpreter(pipeline, Dict())

    # Topological sort of modules
    sorted_modules = topological_sort(pipeline)

    # Execute in order
    for module_id in sorted_modules
        execute_module!(interp, module_id)
    end

    return interp.cache
end

function execute_module!(interp::Interpreter, module_id::Int)
    mod = get_module(interp.pipeline, module_id)

    # Check cache
    if haskey(interp.cache, module_id)
        return interp.cache[module_id]
    end

    # Get inputs from upstream modules
    inputs = collect_inputs(interp, module_id)

    # Set inputs on module
    for (port_name, value) in inputs
        set_input!(mod, port_name, value)
    end

    # Execute module
    outputs = compute(mod)

    # Cache results
    interp.cache[module_id] = outputs

    return outputs
end

function collect_inputs(interp::Interpreter, module_id::Int)
    inputs = Dict{String, Any}()

    # Find all connections where this module is the destination
    for conn in get_connections_to(interp.pipeline, module_id)
        # Get output from source module
        source_outputs = execute_module!(interp, conn.source_module_id)
        value = source_outputs[conn.source_port]

        # Set as input
        inputs[conn.dest_port] = value
    end

    return inputs
end
```

## Example Usage

### Creating a Workflow Programmatically

```julia
using VisTrailsJL

# Create a new pipeline
pipeline = Pipeline()

# Add HTTPFile module
http_mod = add_module!(pipeline, "org.vistrails.vistrails.basic", "HTTPFile")
set_parameter!(http_mod, "url", "https://example.com/data.json")

# Add JuliaSource module to process the data
julia_mod = add_module!(pipeline, "org.vistrails.vistrails.julia", "JuliaSource")
set_parameter!(julia_mod, "source", """
    data = get_input("file")
    parsed = JSON.parse(data)
    set_output("result", parsed)
""")

# Connect them
add_connection!(pipeline,
    http_mod, "file",
    julia_mod, "file"
)

# Execute
results = execute_pipeline(pipeline)
println(results)
```

### Loading an Existing .vt File

```julia
using VisTrailsJL

# Load original VisTrails file
vt = load_vistrail("examples/gcd.vt")

# Get latest workflow
workflow = get_pipeline(vt, vt.latest_version)

# Execute it (will use PyCall for PythonSource modules)
results = execute_pipeline(workflow)

# Access specific outputs
println(results)
```

## Package Registration

### Automatic Package Discovery

```julia
# src/core/modules/module_registry.jl

function initialize_packages!()
    # Register basic package
    include("../../packages/basic/init.jl")

    # Register Julia package
    include("../../packages/julia/init.jl")

    # Register Python package (if PyCall available)
    if @isdefined(PyCall)
        include("../../packages/python/init.jl")
    end
end

# packages/basic/init.jl
function __init__()
    register_httpfile()
    register_file()
    register_string()
    register_integer()
    register_list()
end

# packages/julia/init.jl
function __init__()
    register_juliasource()
end
```

## Project.toml

```toml
name = "VisTrailsJL"
uuid = "12345678-1234-1234-1234-123456789abc"
authors = ["Your Name <your.email@example.com>"]
version = "0.1.0"

[deps]
EzXML = "8f5d6c58-4d21-5cfd-889c-e3ad7ee6a615"
ZipFile = "a5390f91-8eb1-5f08-bee0-b1d1ffed6cea"
HTTP = "cd3eb016-35fb-5094-929b-558a96fad6f3"
JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
PyCall = "438e738f-606a-5dbb-bf0a-cddfbfd45ab0"  # Optional

[compat]
julia = "1.6"
EzXML = "1"
ZipFile = "0.10"
HTTP = "1"
JSON = "0.21"
PyCall = "1.92"
```

## Compatibility Matrix

| Feature | Python VisTrails | Julia VisTrails | Notes |
|---------|-----------------|-----------------|-------|
| Read .vt files | ✅ | ✅ | Full compatibility |
| PythonSource | ✅ | ✅ | Via PyCall |
| JuliaSource | ❌ | ✅ | New! |
| HTTPFile | ✅ | ✅ | Native Julia HTTP |
| VTK | ✅ | 🚧 | Via VTK.jl (future) |
| GUI | ✅ | 🚧 | Via Makie.jl (future) |
| Write .vt files | ✅ | ✅ | Same XML format |
| Caching | ✅ | ✅ | In-memory |
| Version control | ✅ | ✅ | Same structure |

## Migration Path

### Phase 1: Core (Current)
- ✅ XML parsing
- ✅ Module structure
- ✅ Basic execution
- ✅ Three core modules: HTTPFile, JuliaSource, PythonSource

### Phase 2: Compatibility
- 🚧 Full basic package
- 🚧 Control flow modules
- 🚧 More data types

### Phase 3: Extensions
- 🚧 Julia-native packages
- 🚧 Makie.jl for visualization
- 🚧 DataFrames.jl integration
- 🚧 Distributed computing

### Phase 4: GUI
- 🚧 Web-based GUI (Genie.jl)
- 🚧 Interactive workflow editor

## Next Steps

1. **Implement core types** (Module, Pipeline, Connection)
2. **XML parser** for .vt files
3. **Module registry** system
4. **Three initial modules**: HTTPFile, JuliaSource, PythonSource
5. **Basic interpreter** for workflow execution
6. **Test with existing .vt files**

Would you like me to start implementing any specific component?
