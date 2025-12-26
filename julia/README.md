## VisTrailsJL - Julia Reimplementation of VisTrails

A modern Julia implementation of the VisTrails workflow management system, maintaining compatibility with original Python VisTrails .vt files while providing native Julia execution.

### Goals

1. **Read existing .vt files** - Full compatibility with Python VisTrails workflows
2. **Execute workflows** - Support Julia and Python code execution
3. **Same architecture** - Mirror Python directory structure for easy comparison
4. **Extensibility** - Easy to add new packages and modules
5. **Performance** - Leverage Julia's speed for computational workflows

### Quick Start

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()

using VisTrailsJL

# Load an existing .vt file
vt = load_vistrail("../examples/gcd.vt")

# Get the latest workflow
workflow = get_pipeline(vt)

# Execute it
results = execute_pipeline(workflow)
```

### Current Implementation Status

#### Core ✅
- [x] Port system (InputPort, OutputPort)
- [x] Connection system
- [x] Module base types
- [x] Pipeline/Workflow structure
- [x] Vistrail (version control)
- [x] XML parser for .vt files (plain XML and ZIP formats)
- [x] Module registry
- [x] Action replay system
- [x] SVG rendering (workflows and version trees)
- [x] Execution logging (provenance tracking)
- [ ] Full interpreter with caching

#### Packages

**Basic Package (org.vistrails.vistrails.basic)**
- [x] HTTPFile - Fetch files from URLs
- [ ] File - Read local files
- [ ] String - String operations
- [ ] Integer - Integer type
- [ ] List - List operations

**Julia Package (org.vistrails.vistrails.julia)** ⭐ NEW!
- [x] JuliaSource - Execute Julia code in workflows

**Python Package (org.vistrails.vistrails.basic & pythoncalc)** ✅
- [x] PythonSource - Execute Python code (via PyCall.jl)
- [x] PythonCalc - Python calculator with operators (+, -, *, /)

### Architecture

The directory structure mirrors Python VisTrails:

```
julia/
├── Project.toml
├── src/
│   ├── VisTrailsJL.jl              # Main module ✅
│   ├── core/
│   │   ├── vistrail/
│   │   │   ├── port.jl              ✅ Complete
│   │   │   ├── connection.jl        ✅ Complete
│   │   │   ├── module.jl            ✅ Complete
│   │   │   ├── pipeline.jl          ✅ Complete
│   │   │   └── vistrail.jl          ✅ Complete
│   │   ├── interpreter/
│   │   │   └── default.jl           ✅ Complete
│   │   ├── modules/
│   │   │   └── module_registry.jl   ✅ Complete
│   │   ├── log/
│   │   │   ├── machine.jl           ✅ Complete
│   │   │   ├── module_exec.jl       ✅ Complete
│   │   │   ├── workflow_exec.jl     ✅ Complete
│   │   │   └── log.jl               ✅ Complete
│   │   └── db/
│   │       └── io.jl                ✅ Complete
│   ├── db/
│   │   └── services/
│   │       ├── io.jl                ✅ Complete (XML + ZIP)
│   │       ├── json_io.jl           ✅ Complete (JSON export/import)
│   │       ├── action_replay.jl     ✅ Complete
│   │       └── locator.jl           ✅ Complete
│   ├── rendering/
│   │   ├── workflow_svg.jl          ✅ Complete
│   │   ├── version_tree_svg.jl      ✅ Complete
│   │   ├── version_tree_layout.jl   ✅ Complete
│   │   ├── tree_layout.jl           ✅ Complete
│   │   └── terse_graph.jl           ✅ Complete
│   └── packages/
│       ├── basic/                   ✅ Complete
│       ├── julia/                   ✅ Complete
│       ├── pythoncalc/              ✅ Complete
│       └── control_flow/            ✅ Complete
└── test/
    └── runtests.jl
```

### Three Core Modules

#### 1. HTTPFile (Basic Package)

Fetch content from HTTP/HTTPS URLs.

```julia
# In a workflow
http_mod = add_module!(pipeline, "org.vistrails.vistrails.basic", "HTTPFile")
set_parameter!(http_mod, "url", "https://example.com/data.json")
```

**Python VisTrails equivalent:**
```xml
<module id="1" name="HTTPFile" package="org.vistrails.vistrails.basic">
  <function name="url">
    <parameter val="https://example.com/data.json"/>
  </function>
</module>
```

#### 2. JuliaSource (Julia Package) ⭐ NEW!

Execute arbitrary Julia code in workflows.

```julia
julia_mod = add_module!(pipeline, "org.vistrails.vistrails.julia", "JuliaSource")
set_parameter!(julia_mod, "source", """
    # Access inputs
    data = get_input("data")

    # Process
    result = process(data)

    # Set outputs
    set_output("result", result)
""")
```

**Features:**
- Access to input ports via `get_input(name)`
- Set output ports via `set_output(name, value)`
- Full Julia language support
- Inputs available as variables

#### 3. PythonSource (Basic Package)

Execute Python code for compatibility with original VisTrails.

```julia
py_mod = add_module!(pipeline, "org.vistrails.vistrails.basic", "PythonSource")
set_parameter!(py_mod, "source", """
a = self.get_input('a')
b = self.get_input('b')
o = a + b
self.set_output('o', o)
""")
```

**Uses PyCall.jl** for Python interop.

### Example: HTTP Fetch + Julia Processing

```julia
using VisTrailsJL

# Create pipeline
pipeline = Pipeline()

# Add HTTPFile to fetch data
http = add_module!(pipeline, "org.vistrails.vistrails.basic", "HTTPFile")
set_parameter!(http, "url", "https://api.github.com/repos/julia/julia")

# Add JuliaSource to process JSON
julia_proc = add_module!(pipeline, "org.vistrails.vistrails.julia", "JuliaSource")
set_parameter!(julia_proc, "source", """
    using JSON

    # Get the fetched data
    json_str = get_input("file")

    # Parse JSON
    data = JSON.parse(json_str)

    # Extract info
    result = Dict(
        "name" => data["name"],
        "stars" => data["stargazers_count"],
        "language" => data["language"]
    )

    # Output
    set_output("info", result)
""")

# Connect them
add_connection!(pipeline, http, "file", julia_proc, "file")

# Execute
results = execute_pipeline(pipeline)
println(results)
```

### Reading and Rendering .vt Files

```julia
# Load a Python VisTrails file (supports both plain XML and ZIP formats)
vt = load_vistrail("path/to/workflow.vt")

# Inspect
println("Current version: ", vt.current_version)
println("Total actions: ", length(vt.actions))

# Render version tree to SVG
tree_svg = render_version_tree_svg(vt, width=1200, height=800)
write("version_tree.svg", tree_svg)

# Get the current workflow
workflow = vt.pipelines[vt.current_version]

# Render workflow to SVG
workflow_svg = render_pipeline_svg(workflow, width=2000, height=1600)
write("workflow.svg", workflow_svg)

# Execute (will use JuliaSource for new modules, PythonSource via PyCall for old ones)
results = execute_pipeline(workflow)
```

### JSON Export/Import ⭐ NEW!

Convert .vt files to human-readable JSON for easier editing, version control, and web integration.

**Command-line tool:**
```bash
# Export .vt to JSON
julia --project=. vt_json_convert.jl export ../examples/gcd.vt

# Import JSON back to .vt
julia --project=. vt_json_convert.jl import gcd.json -o gcd_restored.vt

# Validate JSON
julia --project=. vt_json_convert.jl validate gcd.json

# Export full bundle (with logs, thumbnails)
julia --project=. vt_json_convert.jl export ../examples/lung.vt --bundle --thumbnails
```

**Programmatic usage:**
```julia
include("src/db/services/json_io.jl")

# Export to JSON
export_vt_to_json("../examples/gcd.vt", json_filename="gcd.json", pretty=true)

# Import from JSON
import_vt_from_json("gcd.json", vt_filename="gcd_restored.vt")

# Validate
is_valid, error = validate_json_vistrail("gcd.json")
```

**Use cases:**
- 📝 Human-readable workflow inspection
- 🔍 Git-friendly diffs (line-by-line changes)
- 🌐 Web integration (standard JSON format)
- 🔧 Easier editing and debugging
- 🤖 API interoperability

See [docs/JSON_CONVERSION.md](docs/JSON_CONVERSION.md) for details.

**Note:** Restored .vt files are larger than originals due to ZipFile.jl limitation (no compression support). Content is identical.

### Execution Logging ⭐ NEW!

Track workflow execution with comprehensive provenance records, similar to Python VisTrails.

**Features:**
- 📊 Module execution timing and caching
- 🖥️ Machine information (OS, architecture, RAM)
- ❌ Error tracking with stack traces
- ⏱️ Workflow duration metrics
- 📈 Success/failure statistics

**Usage:**
```julia
include("src/core/interpreter/default.jl")

# Execute with logging (enabled by default)
cache, workflow_exec = execute_pipeline(pipeline)

# View execution summary
if workflow_exec !== nothing
    println("Duration: ", duration(workflow_exec))
    println("Failed modules: ", length(failed_modules(workflow_exec)))
    println("Cached modules: ", length(cached_modules(workflow_exec)))

    # Detailed module execution info
    for mod_exec in workflow_exec.module_execs
        status = mod_exec.completed == 1 ? "✓" : "✗"
        cached = mod_exec.cached ? " [CACHED]" : ""
        println("$status $(mod_exec.module_name)$cached: $(duration(mod_exec))")
    end
end

# Use Log container for multiple executions
log = Log(vistrail_id="my_vistrail")
add_workflow_exec!(log, workflow_exec)
print_summary(log)  # Formatted summary with statistics
```

See [docs/LOGGING.md](docs/LOGGING.md) for complete documentation.

#### SVG Rendering Features

The Julia implementation includes full SVG rendering capabilities:

- **Version Tree Visualization**: Renders the complete provenance tree with:
  - Tagged versions highlighted and labeled
  - Terse mode (skips untagged nodes with single child/parent)
  - Horizontal tree layout with proper spacing

- **Workflow/Pipeline Visualization**: Renders workflow DAGs with:
  - Dynamic module box sizing based on label width
  - Ports positioned inside boxes (inputs: top-left, outputs: bottom-right)
  - Bezier curve connections between ports
  - Support for modules without registered descriptors (VTK, etc.)
  - XML character escaping for special characters in labels

**Example: Render any .vt file**
```julia
using VisTrailsJL

vt = load_vistrail("../examples/mta.vt")

# Render version tree
tree_svg = render_version_tree_svg(vt)
write("mta_tree.svg", tree_svg)

# Find and render largest workflow
largest_version = argmax(v -> length(vt.pipelines[v].modules), keys(vt.pipelines))
pipeline = vt.pipelines[largest_version]
workflow_svg = render_pipeline_svg(pipeline)
write("mta_workflow.svg", workflow_svg)
```

### Compatibility with Python VisTrails

| Feature | Python | Julia | Notes |
|---------|--------|-------|-------|
| Read .vt (XML) | ✅ | ✅ | Plain XML files |
| Read .vt (ZIP) | ✅ | ✅ | Compressed archives |
| JSON export/import | ❌ | ✅ | Human-readable .vt format |
| Action replay | ✅ | ✅ | Full reconstruction from history |
| Lightweight rendering | ❌ | ✅ | Render without module descriptors |
| SVG rendering | ❌ | ✅ | Version trees and workflows |
| PythonSource | ✅ | ✅ | Via PyCall.jl |
| PythonCalc | ✅ | ✅ | Via PyCall.jl |
| JuliaSource | ❌ | ✅ | NEW! Native Julia execution |
| HTTPFile | ✅ | ✅ | Native Julia HTTP |
| GUI | ✅ | 🔮 | Future: Makie.jl or web-based |
| Caching | ✅ | 🚧 | In progress |

### Development Roadmap

#### Phase 1: Core Functionality ✅ COMPLETE
- [x] Define core types (Port, Connection, Module)
- [x] Implement HTTPFile
- [x] Implement JuliaSource
- [x] Complete Pipeline type
- [x] Complete Vistrail type
- [x] XML parser (plain XML and ZIP)
- [x] Module registry
- [x] Action replay system
- [x] SVG rendering (version trees and workflows)
- [x] Lightweight rendering mode (no module descriptors needed)

#### Phase 2: Compatibility ✅ COMPLETE
- [x] PythonSource via PyCall
- [x] PythonCalc via PyCall
- [x] Read Python .vt files (XML and ZIP)
- [x] Execute mixed Julia/Python workflows
- [x] JSON export/import for .vt files
- [x] Render workflows without all packages installed
- [ ] Write .vt files (XML generation)

#### Phase 3: Extended Packages
- [ ] DataFrames integration
- [ ] Plots.jl/Makie.jl for visualization
- [ ] Distributed computing support
- [ ] More basic modules (File, String, etc.)
- [ ] VTK package bindings

#### Phase 4: GUI
- [ ] Web-based workflow editor (Genie.jl)
- [ ] Interactive execution
- [ ] Live workflow visualization

### Successfully Tested .vt Files

The Julia implementation has been tested and can render the following Python VisTrails files:

| File | Format | Modules | Connections | Version History |
|------|--------|---------|-------------|-----------------|
| gcd.vt | XML | 22 | 31 | 134 versions |
| lung.vt | ZIP | 13 | 12 | 1843 versions |
| mta.vt | ZIP | 17 | 18 | 138 versions |
| plot.vt | ZIP | 10 | 10 | 43 versions |

All files successfully render both version trees and workflow diagrams, including workflows with VTK and other unregistered modules.

### Next Steps for Contributors

1. **Implement Full Interpreter**
   - Execute workflows with caching
   - Handle module dependencies
   - Error recovery and debugging

2. **Add More Basic Modules**
   - File I/O modules
   - String manipulation
   - List/Dict operations
   - Mathematical functions

3. **PythonSource Integration**
   - Implement via PyCall.jl
   - Python environment management
   - Mixed Julia/Python workflows

4. **Write .vt Files**
   - Serialize Vistrails to XML
   - Create ZIP archives
   - Maintain compatibility with Python VisTrails

5. **Performance Optimization**
   - Optimize action replay for large histories
   - Cache parsed XML
   - Parallel workflow execution

### Contributing

See [JULIA_ARCHITECTURE.md](../JULIA_ARCHITECTURE.md) for detailed design.

### License

Same as VisTrails (BSD-style, see main VisTrails LICENSE)
