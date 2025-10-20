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

## Julia Implementation (NEW!)

A Julia reimplementation is under development in `julia_starter/`. This provides:

### Completed Features
- ✅ Full .vt file loading (plain XML and ZIP formats)
- ✅ Action replay system for reconstructing workflows from history
- ✅ Lightweight rendering mode (renders workflows without requiring all packages)
- ✅ SVG rendering for workflows and version trees
- ✅ Module registry and package system
- ✅ Dynamic module box sizing based on labels
- ✅ Port positioning and connection routing

### Successfully Tested Files
- `gcd.vt` - 22 modules, 31 connections (plain XML)
- `lung.vt` - 13 modules, 12 connections (ZIP, VTK modules)
- `mta.vt` - 17 modules, 18 connections (138 version history)
- `plot.vt` - 10 modules, 10 connections (43 version history)

### Key Innovation: Lightweight Rendering
The Julia implementation can render workflows even when module packages (VTK, matplotlib, etc.) are not installed. It extracts layout and connection information from the action history without requiring module descriptors.

See `julia_starter/README.md` and `julia_starter/docs/RENDERING.md` for details.

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