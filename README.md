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
- ✅ **Executes workflows** - Supports Julia modules and Python code via PyCall.jl
- ✅ **Maintains provenance** - Action-based versioning with replay capability
- ✅ **Renders workflows** - SVG output for workflows and version trees
- ✅ **Matches architecture** - Mirrors Python structure for easy comparison
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

```julia
# Navigate to julia directory
cd julia

# Activate the project
using Pkg
Pkg.activate(".")
Pkg.instantiate()

using VisTrailsJL
```

### Load and Execute a Workflow

```julia
# Load an existing .vt file
vt = load_vistrail("../examples/gcd.vt")

# Get the latest workflow version
workflow = get_pipeline(vt)

# Execute it
results = execute_pipeline(workflow)

# Render workflow as SVG
render_pipeline_svg(workflow, "workflow.svg")

# Render version tree
render_version_tree_svg(vt, "versions.svg")
```

### Create a New Workflow

```julia
using VisTrailsJL

# Create a new pipeline
pipeline = Pipeline()

# Add modules
mod1 = add_module(pipeline, "org.vistrails.vistrails.basic", "Integer")
mod2 = add_module(pipeline, "org.vistrails.vistrails.basic", "Integer")
mod3 = add_module(pipeline, "org.vistrails.vistrails.basic", "Add")

# Connect modules
connect_modules(pipeline, mod1, "value", mod3, "input1")
connect_modules(pipeline, mod2, "value", mod3, "input2")

# Execute
results = execute_pipeline(pipeline)
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

**Advanced Features:**
- Lightweight rendering (render workflows without loading packages)
- XML character escaping for special characters
- Dynamic module sizing in SVG output
- Bezier curve connections with proper port anchoring

### 🚧 Future Enhancements

- Full interpreter with caching (currently direct execution)
- VTK package for 3D visualization
- Matplotlib package for plotting
- Web-based workflow editor (in progress - see [docs/](julia/docs/))

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
4. **Web-Based UI** - Replace PyQt4 with modern web interface (React/Vue)
5. **Extensibility** - Easy package development in Julia

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
@article{vistrails2006,
  title={VisTrails: enabling interactive multiple-view visualizations},
  author={Callahan, Steven P and Freire, Juliana and Santos, Emanuele and Scheidegger, Carlos E and Silva, Claudio T and Vo, Huy T},
  journal={IEEE Visualization},
  year={2006}
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

**Status**: ✅ Production-ready (Core functionality complete, web UI in development)
