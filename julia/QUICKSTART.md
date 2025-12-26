# VisTrailsJL Quick Start

Render any VisTrails .vt file (even without having all packages installed!)

## Installation

```bash
cd julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## Render a Workflow

```julia
using VisTrailsJL

# Load any .vt file (works with both XML and ZIP formats)
vt = load_vistrail("../examples/mta.vt")

# Render version tree
tree_svg = render_version_tree_svg(vt, width=1200, height=800)
write("version_tree.svg", tree_svg)

# Render workflow
pipeline = vt.pipelines[vt.current_version]
workflow_svg = render_pipeline_svg(pipeline, width=2000, height=1600)
write("workflow.svg", workflow_svg)
```

## Command Line Usage

Render any .vt file:

```bash
julia --project=. test_vistrail.jl ../examples/lung.vt
```

This generates:
- `lung_tree.svg` - Version history tree
- `lung_workflow.svg` - Largest workflow in the file

## Features

✅ Works with plain XML and ZIP .vt files  
✅ Renders workflows without needing VTK, matplotlib, etc.  
✅ Dynamic module sizing based on labels  
✅ Proper port positioning and connections  
✅ Version tree visualization with tagged versions  

## Tested Files

All example files in `../examples/` work:
- gcd.vt (control flow)
- lung.vt (VTK visualization)
- mta.vt (table data)
- plot.vt (matplotlib)
- brain_vistrail.vt (large VTK workflow)
- And 20+ more!

## Documentation

- [README.md](README.md) - Full documentation
- [docs/RENDERING.md](docs/RENDERING.md) - Rendering system details
- [docs/PORT_DEFINITIONS.md](docs/PORT_DEFINITIONS.md) - Module port specifications

## Key Innovation

Unlike Python VisTrails, the Julia implementation can **render workflows without having all packages installed**. It uses a lightweight action replay mode that extracts layout and connection information from the version history without requiring module descriptors.

This means you can visualize VTK workflows without installing VTK, matplotlib workflows without matplotlib, etc.
