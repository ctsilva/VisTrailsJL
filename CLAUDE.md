# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About VisTrails

VisTrails is an open-source scientific workflow and provenance management system. It provides a visual programming interface for creating data analysis and visualization workflows with comprehensive history tracking and version control.

## Development Commands

### Running VisTrails
```bash
# GUI mode
python vistrails/run.py

# Console/batch mode
python vistrails/run.py --batch [options]

# Server mode  
python vistrails/vistrails_server.py --rpc-server localhost --rpc-port 8081
```

### Testing
```bash
# Run full test suite
python vistrails/tests/runtestsuite.py

# Run specific test modules
python vistrails/tests/runtestsuite.py module1 module2

# Run with debugging on failures
python vistrails/tests/runtestsuite.py -D

# Run example workflows
python vistrails/tests/runtestsuite.py -e

# Verbose output
python vistrails/tests/runtestsuite.py -V 2
```

### Documentation
```bash
# Build user guide (requires Sphinx)
cd doc/usersguide && make html

# Generate package documentation
python scripts/generate_pkg_doc.py
```

### Installation
```bash
# Install from source
python setup.py install

# Development install
pip install -e .
```

## Architecture Overview

### Core Components

**Module System** (`vistrails/core/modules/`): The heart of VisTrails' extensibility. Modules are computational units that can be connected to form workflows. Key files:
- `vistrails_module.py`: Base class for all modules
- `module_registry.py`: Manages module registration and discovery
- `package.py`: Package management and loading

**Workflow Engine** (`vistrails/core/vistrail/`): Manages workflow representation, execution, and provenance:
- `pipeline.py`: Workflow graph representation  
- `controller.py`: Workflow execution orchestration
- `action.py`: Change tracking for provenance

**Interpreter** (`vistrails/core/interpreter/`): Executes workflows with caching and dependency resolution:
- `cached.py`: Cached execution for performance
- `noncached.py`: Direct execution mode

**Package System** (`vistrails/packages/`): Modular architecture where functionality is organized into packages. Each package contains related modules (e.g., VTK for 3D visualization, matplotlib for plotting).

### Key Architectural Patterns

**Package-Based Modularity**: All functionality is organized into packages that can be independently developed and loaded. Packages register their modules with the central registry.

**Provenance-First Design**: Every workflow execution creates detailed provenance records tracking what was computed, when, and with what parameters.

**Version Control Integration**: Workflows are versioned, allowing branching, merging, and diff operations on computational pipelines.

**Lazy Evaluation**: The interpreter only computes modules whose outputs are needed, enabling efficient execution of large workflows.

## Package Development

When creating new packages:

1. Create directory in `vistrails/packages/[package_name]/`
2. Implement `__init__.py` with package initialization
3. Define modules inheriting from `Module` base class
4. Register modules in package initialization
5. Add package tests following existing patterns

## Dependencies

Core dependencies are in `requirements.txt`. Development dependencies in `dev-requirements.txt`. The system requires:
- PyQt4/5 for GUI
- VTK for 3D visualization
- matplotlib for plotting
- numpy/scipy for numerical computing

## Testing Strategy

Tests use Python's unittest framework. Test files are organized by package/module. Image comparison tests validate visualization outputs. The test runner can execute individual test modules or the full suite.

## Julia Implementation (VisTrailsJL)

A Julia reimplementation is under development in `julia/`. This provides a modern, notebook-based approach to scientific workflows.

### Completed Features (v0.1)
- ✅ Full .vt file loading (plain XML and ZIP formats)
- ✅ Action replay system for reconstructing workflows from history
- ✅ Lightweight rendering mode (renders workflows without requiring all packages)
- ✅ SVG rendering for workflows and version trees
- ✅ Module registry and package system
- ✅ Dynamic module box sizing based on labels
- ✅ Port positioning and connection routing
- ✅ Workflow execution with caching
- ✅ Execution logging (provenance tracking)
- ✅ JSON export/import for .vt files
- ✅ HTTP.jl backend API for workflow management
- ✅ Native Julia execution (JuliaSource module)
- ✅ Python interop (PythonSource via PyCall.jl)

### Successfully Tested Files
- `gcd.vt` - 22 modules, 31 connections, 134 versions (plain XML)
- `lung.vt` - 13 modules, 12 connections, 1843 versions (ZIP, VTK modules)
- `mta.vt` - 17 modules, 18 connections, 138 versions (ZIP)
- `plot.vt` - 10 modules, 10 connections, 43 versions (ZIP)

### Key Innovation: Lightweight Rendering
The Julia implementation can render workflows even when module packages (VTK, matplotlib, etc.) are not installed. It extracts layout and connection information from the action history without requiring module descriptors.

### Notebook-Based Workflow System (v0.2) - IMPLEMENTED

**Vision**: Define workflows and packages using Jupyter notebooks with nbdev-style directives, eliminating the need for a GUI while providing git-native version control.

**Status**: ✅ Core implementation complete and tested.

#### Implementation Files (`julia/src/notebook/`)

| File | Purpose |
|------|---------|
| `parser.jl` | Parse `.ipynb` files, extract `#\|` directives |
| `package_loader.jl` | Load packages from notebooks, register modules |
| `workflow_parser.jl` | Parse workflows, build pipelines, execute |
| `conversion.jl` | Convert between notebooks and code/.vt files |
| `init.jl` | Module initialization |

#### Running the Julia Implementation

```bash
cd julia

# Install dependencies
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Run notebook system tests
julia --project=. test/notebooks/test_notebook_system.jl

# Run conversion tests
julia --project=. test/notebooks/test_conversion.jl
```

#### Package Notebooks

Define module types with `#|` directives:

```julia
#| package-meta
#| identifier: org.vistrails.vistrails.mypackage
#| version: 1.0.0

#| module: AddOne
#| input_ports:
#|   - name: value
#|     signature: basic:Integer
#| output_ports:
#|   - name: result
#|     signature: basic:Integer

v = get_input("value")
set_output("result", v + 1)
```

#### Workflow Notebooks

Define module instances and connections:

```julia
#| workflow: my_computation

#| module-id: const1
#| module-type: basic:Integer
#| params:
#|   - value: 5

#| module-id: add
#| module-type: mypackage:AddOne
#| inputs:
#|   - value: const1.value

#| execute
```

#### API Usage

```julia
using VisTrailsJL

# Load and register a package from notebook
pkg = load_package_from_notebook("my_package.ipynb")
register_notebook_package!(pkg)

# Load and execute a workflow from notebook
workflow = parse_workflow_notebook("my_workflow.ipynb")
pipeline = build_pipeline_from_workflow(workflow)
results = execute_notebook_pipeline(pipeline)
```

#### Conversion Tools

```julia
# Export registered package to notebook
registered_package_to_notebook("org.vistrails.vistrails.basic", "basic.ipynb")

# Convert notebook to Julia code
save_package_code("my_package.ipynb", "my_package.jl")

# Convert .vt workflow to notebook
vistrail_workflow_to_notebook("examples/gcd.vt", 134; output_path="gcd.ipynb")
```

#### Design Documents (in `julia/docs/`)
- `PACKAGE_DEFINITIONS_V2.md` - Package notebook specification
- `WORKFLOW_DEFINITIONS.md` - Workflow notebook specification
- `DESIGN_VALIDATION.md` - Validation against real use cases

#### Remaining Work (v0.2+)

| Feature | Status |
|---------|--------|
| Directive parser | ✅ Complete |
| Package loading | ✅ Complete |
| Workflow parsing | ✅ Complete |
| Pipeline execution | ✅ Complete |
| Conversion tools | ✅ Complete |
| Diff engine | 🔲 Not started |
| Git history import | 🔲 Not started |

#### Benefits
- ✅ No GUI required for complete workflow system
- ✅ Git for version control (standard tools, GitHub PRs)
- ✅ Literate programming (documentation + code)
- ✅ Jupyter/Quarto/VSCode compatible
- ✅ Bidirectional conversion (.vt ↔ notebook ↔ code)

See [VisFlow-Lite](https://github.com/ctsilva/VisFlow-Lite) for the separate viewer project.

## Python 3 Migration Analysis

⚠️ **Status: Python 2.7 Only** - VisTrails currently requires Python 2.6/2.7 and cannot run on Python 3.

### Migration Complexity: **VERY HIGH**
- **999 Python files** in codebase
- **3-4 months** estimated full-time effort

### Major Blockers:
1. **PyQt4 → PyQt5/6** (Critical): GUI framework not available for Python 3
2. **String/Unicode handling**: 1,760 instances of `xrange`, `raw_input`, `basestring`, `unicode()`
3. **Dictionary iteration**: 887 instances of `.iteritems()`, `.iterkeys()`, `.itervalues()`
4. **Exception syntax**: 559 instances of old `except Exception, e:` format
5. **Dependencies**: `mysql-python`, VTK bindings need Python 3 equivalents

### Positive Factors:
- 714 files already use `from __future__ import division`
- No C extensions (pure Python)
- Comprehensive test suite exists
- Well-structured modular architecture

### Recommended Approach:
1. **Phase 1**: Automated conversion with 2to3 tool (2-4 weeks)
2. **Phase 2**: Dependencies and PyQt migration (2-3 weeks)
3. **Phase 3**: Manual fixes and semantic issues (4-6 weeks)
4. **Phase 4**: Testing and validation (2-4 weeks)