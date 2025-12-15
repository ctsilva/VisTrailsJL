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

A Julia reimplementation is under development in `julia_starter/`. This provides a modern, notebook-based approach to scientific workflows.

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

### Current Focus: Notebook-Based Workflow System (v0.2)

**Vision**: Define workflows and packages using Jupyter notebooks with nbdev-style directives, eliminating the need for a GUI while providing git-native version control.

**Design Documents** (in `julia_starter/docs/`):
- `PACKAGE_DEFINITIONS_V2.md` - How to define VisTrails packages in notebooks
- `WORKFLOW_DEFINITIONS.md` - How to define workflows in notebooks
- `DESIGN_VALIDATION.md` - Validation of notebook-based approach against real use cases

**Key Concepts**:

1. **Package Notebooks** - Define module types with directives:
   ```julia
   #| package-meta
   #| identifier: org.vistrails.vistrails.mypackage
   #| version: 1.0.0

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

2. **Workflow Notebooks** - Define module instances and connections:
   ```julia
   #| workflow: covid_analysis
   #| version: 1

   #| module-id: fetch_data
   #| module-type: basic:HTTPFile
   #| params:
   #|   url: "https://api.covid19api.com/summary"

   #| module-id: process
   #| module-type: julia:JuliaSource
   #| inputs:
   #|   data: fetch_data.file

   using JSON
   data = JSON.parse(get_input("data"))
   # ... processing logic ...
   set_output("result", processed_data)

   #| execute
   ```

3. **Git-Native Version Control**:
   - Git commits → VisTrails actions
   - Git diffs → Module operations (add/delete/modify)
   - Git history → Version tree
   - Git branches → Version tree branches
   - Git tags → VisTrails tags

4. **Literate Workflows**:
   - Mix documentation (markdown), workflow definition (directives), and code
   - Executable notebooks (run to execute workflow)
   - Quarto integration for publication-ready reports

5. **Backward Compatible**:
   - Round-trip conversion: .vt ↔ notebook
   - Same concepts as Python VisTrails (Module, Port, compute(), etc.)
   - Port signature system: `basic:Float`, `basic:String`
   - Compatible with existing .vt files

**Status**: Design validated and approved. Ready for implementation.

**Next Steps**:
1. Implement directive parser for package notebooks
2. Implement directive parser for workflow notebooks
3. Build diff engine (notebook diffs → VisTrails actions)
4. Implement execution from notebooks
5. Build conversion tools (.vt ↔ notebook)
6. Git history importer (commits → version tree)

**Benefits**:
- ✅ No GUI required for complete workflow system
- ✅ Git for version control (standard tools, GitHub PRs)
- ✅ Literate programming (documentation + code)
- ✅ Jupyter/Quarto/VSCode compatible
- ✅ Faster development (6-9 weeks vs 8-11 weeks for GUI)
- ✅ More collaborative (GitHub workflow)

See `julia_starter/docs/V1_ROADMAP.md` for original GUI-based roadmap (deferred in favor of notebook approach).

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