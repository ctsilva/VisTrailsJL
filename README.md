# VisTrailsJL

**A modern Julia implementation of VisTrails with full provenance tracking and workflow management**

This repository contains both the original Python VisTrails codebase (for reference and compatibility testing) and a complete Julia reimplementation (VisTrailsJL) with enhanced performance and native Julia module support.

## What is VisTrails?

VisTrails is an open-source scientific workflow and provenance management system that provides:
- Visual programming interface for data analysis workflows
- Comprehensive history tracking and version control
- Action-based provenance with branching/merging
- Workflow replay and diff capabilities
- 20+ years of research from the University of Utah

## What is VisTrailsJL?

VisTrailsJL is a complete Julia reimplementation that:
- ✅ **Reads existing .vt files** - Full compatibility with Python VisTrails workflows
- ✅ **Notebook-based workflows** - Define workflows in Jupyter notebooks with `#|` directives
- ✅ **Executes workflows** - Supports Julia modules and Python code via PyCall.jl
- ✅ **Maintains provenance** - Action-based versioning with replay capability
- ✅ **Renders workflows** - SVG output for workflows and version trees
- ✅ **Git-native version control** - Standard git tools replace custom versioning
- ⚡ **Enhanced performance** - Leverages Julia's speed for computational workflows

## Repository Structure

```
.
├── vistrails/              # Original Python VisTrails (v2.2)
│   ├── core/              # Core system (modules, pipeline, interpreter)
│   ├── packages/          # Built-in packages (VTK, matplotlib, etc.)
│   └── gui/               # PyQt GUI
│
├── julia/          # VisTrailsJL - Julia implementation
│   ├── src/
│   │   ├── core/          # Core system (matching Python structure)
│   │   ├── packages/      # Julia packages (basic, julia, python)
│   │   ├── db/            # .vt file parsing and serialization
│   │   └── rendering/     # SVG workflow visualization
│   ├── docs/              # Implementation guides and analysis
│   ├── examples/          # Example workflows and tests
│   └── README.md          # VisTrailsJL documentation
│
└── examples/              # Example .vt workflow files
    ├── gcd.vt            # Simple GCD computation
    ├── lung.vt           # VTK volume rendering
    └── mta.vt            # MTA subway analysis
```

## Quick Start - VisTrailsJL

### Installation

```bash
cd julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Notebook-Based Workflows (Recommended)

Define workflows in Jupyter notebooks using `#|` directives:

**Package Notebook** (`my_package.ipynb`):
```julia
#| package-meta
#| identifier: org.example.mypackage
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

**Workflow Notebook** (`my_workflow.ipynb`):
```julia
#| workflow: my_computation

#| module-id: input
#| module-type: basic:Integer
#| params:
#|   - value: 5

#| module-id: process
#| module-type: mypackage:AddOne
#| inputs:
#|   - value: input.value

#| execute
```

**Execute from Julia**:
```julia
using VisTrailsJL

# Load and register package
pkg = load_package_from_notebook("my_package.ipynb")
register_notebook_package!(pkg)

# Execute workflow
workflow = parse_workflow_notebook("my_workflow.ipynb")
pipeline = build_pipeline_from_workflow(workflow)
results = execute_notebook_pipeline(pipeline)
```

### Load Existing .vt Files

```julia
using VisTrailsJL

# Load an existing .vt file
vt = load_vistrail("../examples/gcd.vt")

# Get the latest workflow version
workflow = get_pipeline(vt)

# Render workflow as SVG
render_pipeline_svg(workflow, "workflow.svg")

# Convert to notebook format
vistrail_workflow_to_notebook("../examples/gcd.vt", 134; output_path="gcd.ipynb")
```

## Implementation Status

### ✅ Complete (100%)

All core functionality is implemented and tested:

**Core System:**
- Port system (InputPort, OutputPort)
- Connection validation and management
- Module base types and registry
- Pipeline/Workflow structure
- Vistrail version control
- Action system (add, delete, change operations)
- Action replay from .vt files
- XML parser (plain XML and ZIP formats)
- SVG rendering (workflows and version trees)

**Packages:**
- **Basic Package**: String, Integer, Float, Boolean, List, HTTPFile
- **Julia Package**: JuliaSource, JuliaCalc (execute Julia code)
- **Python Package**: PythonSource, PythonCalc (via PyCall.jl)

**Notebook System (v0.2):**
- Directive parser for `#|` notebook annotations
- Package loading from notebooks
- Workflow parsing and execution
- Bidirectional conversion (.vt ↔ notebook ↔ code)

**Advanced Features:**
- Lightweight rendering (render workflows without loading packages)
- XML character escaping for special characters
- Dynamic module sizing in SVG output
- Bezier curve connections with proper port anchoring

### 🚧 Future Enhancements

- Diff engine (notebook diffs → VisTrails actions)
- Git history import (commits → version tree)
- VTK package for 3D visualization
- Matplotlib package for plotting

## Documentation

Comprehensive documentation is available in [`julia/docs/`](julia/docs/):

- **[README.md](julia/README.md)** - VisTrailsJL overview
- **[QUICKSTART.md](julia/QUICKSTART.md)** - Getting started guide
- **[IMPLEMENTATION_STATUS.md](julia/docs/IMPLEMENTATION_STATUS.md)** - Feature comparison with Python
- **[COMPLETION_SUMMARY.md](julia/docs/COMPLETION_SUMMARY.md)** - Implementation verification
- **[API_REQUIREMENTS.md](julia/docs/API_REQUIREMENTS.md)** - REST API design for web editor
- **[VISFLOW_INTEGRATION_ANALYSIS.md](julia/docs/VISFLOW_INTEGRATION_ANALYSIS.md)** - Web editor integration plan
- **[CURIO_VS_VISFLOW_COMPARISON.md](julia/docs/CURIO_VS_VISFLOW_COMPARISON.md)** - Frontend technology comparison

## Python VisTrails (Reference)

The original Python implementation is included for reference and compatibility testing.

### Running Python VisTrails

```bash
# GUI mode
python vistrails/run.py

# Console/batch mode
python vistrails/run.py --batch [options]

# Run tests
python vistrails/tests/runtestsuite.py
```

See [CLAUDE.md](CLAUDE.md) for detailed Python VisTrails documentation.

## Project Goals

1. **Preserve VisTrails' Research** - 20 years of provenance research shouldn't be lost to Python 2 obsolescence
2. **Modern Performance** - Julia's JIT compilation for scientific computing workflows
3. **Maintain Compatibility** - Read/write existing .vt files for seamless migration
4. **Git-Native Versioning** - Use standard git for version control instead of custom system
5. **Notebook-Based Workflows** - Define workflows in Jupyter notebooks, no GUI required
6. **Extensibility** - Easy package development in Julia

## Migration from Python VisTrails

VisTrailsJL can read and execute existing .vt files created by Python VisTrails:

```julia
# Load Python-created workflow
vt = load_vistrail("my_workflow.vt")

# Replay to any version
pipeline = replay_to_version(vt, version_id)

# Execute with Julia interpreter
results = execute_pipeline(pipeline)

# Save back to .vt format (future feature)
save_vistrail(vt, "my_workflow_modified.vt")
```

## Why Julia?

- **Performance**: Julia's JIT compilation rivals C/Fortran for numerical computing
- **Interoperability**: Call Python libraries via PyCall.jl, C/Fortran code directly
- **Modern Language**: Multiple dispatch, metaprogramming, first-class functions
- **Scientific Computing**: Rich ecosystem (Plots.jl, DataFrames.jl, DifferentialEquations.jl)
- **Active Development**: Python 2 is dead, PyQt4 is obsolete, Julia is thriving

## Contributing

This is a research project by Claudio Silva (@ctsilva). Contributions welcome!

### Development Setup

```bash
# Clone repository
git clone https://github.com/ctsilva/VisTrailsJL.git
cd VisTrailsJL

# Setup Julia environment
cd julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Run tests
julia --project=. -e 'using Test; include("test/runtests.jl")'
```

## License

- **Python VisTrails**: BSD 3-Clause (original license preserved)
- **VisTrailsJL**: BSD 3-Clause (compatible with original)

## Citation

If you use VisTrailsJL in your research, please cite:

```bibtex
@inproceedings{vistrails2006,
  title={VisTrails: visualization meets data management},
  author={Callahan, Steven P and and Freire, Juliana and Scheidegger, Carlos E and Silva, Cl{\'a}udio T and Vo, Huy T},
  booktitle={Proceedings of the 2006 ACM SIGMOD International Conference on Management of Data},
  pages={745--747},
  year={2006},
  organization={ACM},
  doi={10.1145/1142473.1142574}
}

@software{vistrailsjl2025,
  title={VisTrailsJL: A Julia Implementation of VisTrails},
  author={Silva, Claudio T},
  year={2025},
  url={https://github.com/ctsilva/VisTrailsJL}
}
```

## Acknowledgments

- Original VisTrails team at University of Utah
- Julia community for excellent scientific computing ecosystem
- VisFlow and Curio projects for workflow editor inspiration

## Contact

- **Author**: Claudio Silva
- **GitHub**: [@ctsilva](https://github.com/ctsilva)
- **Original VisTrails**: https://github.com/VisTrails/VisTrails

---

**Status**: Active development (Core v0.1 + notebook system v0.2 complete)
