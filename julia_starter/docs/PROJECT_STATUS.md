# VisTrailsJL Project Status

**Last Updated**: 2024-12-12

## Current Status: Design Phase Complete ✅

We have a **validated, approved design** for a notebook-based VisTrails system. Ready to begin implementation.

## What We've Accomplished

### Phase 1: Foundation (v0.1) - COMPLETE ✅

Built a solid Julia implementation of core VisTrails functionality:

**Core Architecture**:
- ✅ Full .vt file loading (XML and ZIP formats)
- ✅ Action replay system (reconstruct workflows from version history)
- ✅ Module registry and package system
- ✅ Pipeline execution engine with caching
- ✅ Provenance tracking (execution logging)

**Rendering System**:
- ✅ SVG rendering for workflows
- ✅ SVG rendering for version trees
- ✅ Lightweight rendering (no package dependencies needed)
- ✅ Dynamic module sizing and port positioning

**API and Interop**:
- ✅ HTTP.jl backend server (REST API)
- ✅ JSON export/import for .vt files
- ✅ Native Julia execution (JuliaSource module)
- ✅ Python interop (PythonSource via PyCall.jl)

**Packages Implemented**:
- ✅ basic (HTTPFile, constants, data structures, I/O)
- ✅ julia (JuliaSource)
- ✅ pythoncalc (PythonCalc)
- ✅ control_flow (If, While, And, Or, Not)

**Testing**:
- ✅ Successfully loads and renders real VisTrails files (gcd.vt, lung.vt, mta.vt, plot.vt)
- ✅ Handles workflows with 1000+ versions
- ✅ Renders workflows without installing VTK or other packages

### Phase 2: Design (v0.2) - COMPLETE ✅

**Problem**: Building a GUI is time-consuming (8-11 weeks) and doesn't leverage modern collaborative workflows.

**Solution**: Notebook-based system with git-native version control.

**Design Documents Created**:

1. **[PACKAGE_DEFINITIONS_V2.md](PACKAGE_DEFINITIONS_V2.md)** (35 KB)
   - How to define VisTrails packages in Jupyter notebooks
   - Uses nbdev-style directives (`#| module: HTTPFile`)
   - Function-based compute definitions
   - Compatible with Python VisTrails concepts
   - Validated against official VisTrails docs

2. **[WORKFLOW_DEFINITIONS.md](WORKFLOW_DEFINITIONS.md)** (51 KB)
   - How to define workflows in Jupyter notebooks
   - Module instances with `#| module-id: fetch_data`
   - Connection syntax: `#| inputs: data: fetch_data.file`
   - Execution model: register then `#| execute`
   - Git commits → VisTrails actions

3. **[DESIGN_VALIDATION.md](DESIGN_VALIDATION.md)** (38 KB)
   - Tested design against 10 real-world scenarios
   - Validated conversion of existing .vt files
   - Tested dynamic ports, control flow, large workflows
   - Confirmed round-trip compatibility
   - No critical issues found!

4. **[NBDEV_WORKFLOWS.md](NBDEV_WORKFLOWS.md)** (41 KB)
   - Initial exploration of nbdev approach
   - Comparison of directives vs macros
   - Benefits analysis

5. **[V1_ROADMAP.md](V1_ROADMAP.md)** (52 KB)
   - Original GUI-based roadmap (deferred)
   - Detailed feature breakdown and timeline
   - Preserved for reference

**Key Design Decisions Made**:

1. ✅ **Directives over macros** - Use comments (`#|`), not Julia macros
2. ✅ **Register-then-execute** - Cells define modules, `#| execute` runs workflow
3. ✅ **Git-native versioning** - Commits are versions, diffs are actions
4. ✅ **Infer dynamic ports** - Inputs from connections, outputs from code
5. ✅ **Module identity by ID** - Not cell position (allows reordering)
6. ✅ **Jupyter/Quarto first** - Skip Pluto.jl initially (reactive model conflict)

## What We're Building (v0.2)

### Vision

A complete workflow system using **notebooks instead of GUI**:

- **Package notebooks** define module types (like Python `__init__.py` + `init.py`)
- **Workflow notebooks** define module instances and connections
- **Git** provides version control (commits → versions, branches → tree branches)
- **Jupyter/Quarto** for editing and execution
- **Round-trip** conversion to .vt files (Python VisTrails compatibility)

### Example: Package Definition

```julia
# %% Package metadata
#| package-meta
#| identifier: org.vistrails.vistrails.basic
#| version: 2.2.0

# %% HTTPFile module
#| module: HTTPFile
#| output_ports:
#|   - name: file
#|     signature: basic:String
#| parameters:
#|   - name: url
#|     signature: basic:String

function compute(self::ModuleInstance)
    url = get_parameter(self, "url")
    response = HTTP.get(url)
    set_output(self, "file", String(response.body))
end
```

### Example: Workflow Definition

```julia
# %% Fetch COVID data
#| module-id: fetch_data
#| module-type: basic:HTTPFile
#| params:
#|   url: "https://api.covid19api.com/summary"

# %% Process data
#| module-id: analyze
#| module-type: julia:JuliaSource
#| inputs:
#|   raw_data: fetch_data.file

using JSON
data = JSON.parse(get_input("raw_data"))
top_10 = sort(data["Countries"], by=c->c["TotalConfirmed"], rev=true)[1:10]
set_output("top_countries", top_10)

# %% Execute
#| execute
display(analyze.top_countries)
```

### Git Integration

```bash
# Initial workflow
git commit -m "Initial COVID analysis"
# → VisTrails version 1

# Modify workflow
git commit -m "Change data source to v2 API"
# → VisTrails version 2 (action: change_parameter)

# Branch for experiment
git checkout -b experiment
git commit -m "Try different visualization"
# → Version tree branch

# Merge back
git merge experiment
# → Merge node in version tree
```

**Git log IS the version tree!**

## Why This Approach?

### Advantages Over GUI

| Aspect | Notebook System | GUI System |
|--------|----------------|------------|
| Development time | **6-9 weeks** | 8-11 weeks |
| Version control | **Git (native)** | Custom integration |
| Collaboration | **GitHub (PRs, reviews)** | Need custom tools |
| Documentation | **Built-in (literate)** | Separate |
| Reproducibility | **Git commit = state** | Need export |
| Learning curve | **Familiar (notebooks)** | New interface |
| Offline work | **Fully offline** | Need server |
| Tools | **Standard (Jupyter)** | Custom UI |

### Compatibility with Python VisTrails

✅ Same concepts:
- Module base class
- `compute()` method
- `get_input()` / `set_output()` API
- Port signatures (`basic:Float`)
- Package structure
- Action/operation model

✅ Round-trip:
- Load .vt files
- Convert to notebook
- Edit in notebook
- Export back to .vt
- Open in Python VisTrails

## Implementation Plan

### Phase 1: Package Notebook Parser (2 weeks)

**Goal**: Parse package notebooks and register modules

**Tasks**:
1. Implement directive parser (regex-based)
2. Handle YAML-style nested parameters
3. Extract compute functions from cells
4. Build ModuleDescriptor from directives
5. Register modules in registry
6. Unit tests

**Deliverables**:
- `src/notebook/directives.jl` - Parse `#|` directives
- `src/notebook/package_parser.jl` - Package notebook → modules
- `load_package_from_notebook()` function
- Test suite

### Phase 2: Workflow Notebook Parser (2 weeks)

**Goal**: Parse workflow notebooks and build pipelines

**Tasks**:
1. Parse workflow metadata directives
2. Parse module instance directives
3. Extract connections from `#| inputs:`
4. Build Pipeline from parsed modules
5. Handle dynamic ports (JuliaSource)
6. Validation (cycles, missing connections)

**Deliverables**:
- `src/notebook/workflow_parser.jl` - Workflow notebook → Pipeline
- `build_workflow_from_notebook()` function
- Connection inference
- Test suite

### Phase 3: Diff Engine (2 weeks)

**Goal**: Convert notebook diffs to VisTrails actions

**Tasks**:
1. Compare two notebook files (diff by module-id)
2. Generate operations (add/delete/modify module/connection)
3. LibGit2 integration for git diffs
4. Build Action from operations
5. Handle edge cases (reordering, whitespace)

**Deliverables**:
- `src/notebook/diff.jl` - Diff engine
- `diff_notebooks()` function
- `git_diff_to_actions()` function
- Test with real git commits

### Phase 4: Execution Engine (1 week)

**Goal**: Execute workflows from notebooks

**Tasks**:
1. Implement `#| execute` directive handling
2. Hook into existing interpreter
3. Make results available as variables
4. Error handling and display
5. Support `#| execute-from` for partial execution

**Deliverables**:
- `src/notebook/executor.jl` - Execution from notebook
- `execute_notebook()` function
- Output capture
- CLI tool: `vt-notebook execute`

### Phase 5: Conversion Tools (2 weeks)

**Goal**: Bidirectional .vt ↔ notebook conversion

**Tasks**:
1. .vt → notebook conversion
2. Notebook → .vt conversion
3. Preserve all metadata
4. Round-trip testing (load, convert, convert back)
5. CLI tools

**Deliverables**:
- `vistrail_to_notebook()` function
- `notebook_to_vt()` function
- CLI: `vt-notebook export/import`
- Round-trip tests with real .vt files

### Phase 6: Git Integration (1 week)

**Goal**: Import git history as version tree

**Tasks**:
1. Parse git log for notebook file
2. For each commit, extract directives
3. Generate actions from commit diffs
4. Build Vistrail with version tree
5. Import git tags as VisTrails tags

**Deliverables**:
- `import_git_history()` function
- Git tag synchronization
- Documentation and examples

### Phase 7: Documentation and Examples (1 week)

**Goal**: Make system usable

**Tasks**:
1. User guide (how to define packages/workflows)
2. API documentation
3. Example package notebooks
4. Example workflow notebooks
5. Tutorial: Convert existing .vt to notebook

**Deliverables**:
- User guide
- 3+ example package notebooks
- 5+ example workflow notebooks
- Video tutorial (optional)

**Total**: 11 weeks (2.5 months)

Slightly longer than original estimate (9 weeks) but includes more comprehensive documentation and examples.

## Success Criteria

✅ **v0.2 is successful if**:

1. Can define packages in notebooks and load them
2. Can define workflows in notebooks and execute them
3. Git commits on workflow notebooks generate correct VisTrails actions
4. Can convert existing .vt files to notebooks
5. Can convert notebooks back to .vt files (round-trip)
6. Converted .vt files load in Python VisTrails
7. Git history imports as version tree with correct structure
8. Documentation and examples are complete
9. Works with Jupyter and Quarto
10. All tests pass (package parser, workflow parser, diff engine, execution, conversion)

## After v0.2

### v0.3: Enhanced Features (Optional)

- Quarto templates for publication-ready reports
- Subworkflow support (notebook → module)
- Parameter exploration (sweep values)
- Improved error messages
- Performance optimization

### v0.4: GUI Integration (Optional)

- Web-based workflow viewer (read-only)
- Visual diff viewer (compare versions)
- Interactive version tree
- Module palette
- Could still use VisFlow or build custom

**Note**: GUI becomes optional since notebook system is complete!

## Current Development Environment

### Repository Structure

```
VisTrailsJL/
├── CLAUDE.md                    # Claude Code guidance (updated!)
├── README.md                    # Project overview
├── vistrails/                   # Original Python VisTrails
├── examples/                    # Example .vt files
│   ├── gcd.vt
│   ├── lung.vt
│   ├── mta.vt
│   └── plot.vt
└── julia_starter/              # Julia implementation
    ├── Project.toml
    ├── README.md
    ├── src/
    │   ├── VisTrailsJL.jl
    │   ├── core/               # Core data structures
    │   ├── db/                 # Persistence and I/O
    │   ├── rendering/          # SVG generation
    │   ├── packages/           # Module packages
    │   └── notebook/           # 🆕 Notebook system (to implement)
    ├── backend/                # HTTP server
    ├── docs/                   # Documentation
    │   ├── PACKAGE_DEFINITIONS_V2.md    # 🆕 Package design
    │   ├── WORKFLOW_DEFINITIONS.md      # 🆕 Workflow design
    │   ├── DESIGN_VALIDATION.md         # 🆕 Design validation
    │   ├── NBDEV_WORKFLOWS.md           # 🆕 nbdev exploration
    │   ├── V1_ROADMAP.md               # 🆕 GUI roadmap (deferred)
    │   ├── PROJECT_STATUS.md           # 🆕 This file
    │   ├── RENDERING.md
    │   ├── LOGGING.md
    │   └── ...
    └── test/                   # Tests
```

### Dependencies

**Current**:
- Julia 1.9+
- HTTP.jl (backend API)
- JSON3.jl (JSON handling)
- LightXML.jl (XML parsing)
- ZipFile.jl (.vt ZIP archives)
- PyCall.jl (Python interop)

**New (for v0.2)**:
- IJulia.jl (Jupyter notebook interface)
- LibGit2 (git integration)
- YAML.jl (directive parsing)

### How to Run (Currently)

```julia
# Start Julia REPL
julia --project=julia_starter

# Load package
using VisTrailsJL

# Load existing .vt file
vt = load_vistrail("examples/gcd.vt")

# Render version tree
tree_svg = render_version_tree_svg(vt)
write("gcd_tree.svg", tree_svg)

# Get workflow
workflow = vt.pipelines[vt.current_version]

# Render workflow
workflow_svg = render_pipeline_svg(workflow)
write("gcd_workflow.svg", workflow_svg)

# Execute workflow
cache, log = execute_pipeline(workflow)
```

**After v0.2** (planned):

```julia
# Load package from notebook
load_package_from_notebook("packages/basic.ipynb")

# Build workflow from notebook
workflow = build_workflow_from_notebook("workflows/covid_analysis.ipynb")

# Execute
execute_notebook("workflows/covid_analysis.ipynb")

# Convert .vt to notebook
vistrail_to_notebook("examples/gcd.vt", "workflows/gcd.ipynb")

# Convert notebook to .vt (with git history)
notebook_to_vistrail("workflows/gcd.ipynb", "gcd_new.vt", import_git_history=true)
```

## Questions?

Refer to design documents for details:
- Package definitions: `julia_starter/docs/PACKAGE_DEFINITIONS_V2.md`
- Workflow definitions: `julia_starter/docs/WORKFLOW_DEFINITIONS.md`
- Design validation: `julia_starter/docs/DESIGN_VALIDATION.md`

See `CLAUDE.md` for general project context and architecture.

## Next Action

**Ready to begin Phase 1: Package Notebook Parser**

First task: Implement directive parser (`src/notebook/directives.jl`)
