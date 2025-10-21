# VisTrailsJL Documentation Index

Welcome to the VisTrailsJL documentation! This index helps you find the right documentation for your needs.

## Quick Links

| Document | Description | Audience |
|----------|-------------|----------|
| [README.md](../README.md) | Getting started, features, examples | Everyone |
| [VT_FILE_FORMAT.md](VT_FILE_FORMAT.md) | .vt file format specification | Developers |
| [JSON_CONVERSION.md](JSON_CONVERSION.md) | JSON export/import guide | Users & Developers |
| [RENDERING.md](RENDERING.md) | SVG rendering system | Developers |
| [LOGGING.md](LOGGING.md) | Execution logging and provenance | Developers |
| [CONTEXT.md](CONTEXT.md) | Project context and background | Contributors |
| [SETUP.md](SETUP.md) | Installation and setup | New users |

## By Use Case

### I want to...

#### Use VisTrailsJL

- **Get started**: [README.md](../README.md) → Quick Start section
- **Install and configure**: [SETUP.md](SETUP.md)
- **Convert .vt to JSON**: [JSON_CONVERSION.md](JSON_CONVERSION.md)
- **Render workflows**: [RENDERING.md](RENDERING.md)

#### Understand VisTrails Files

- **Learn .vt file format**: [VT_FILE_FORMAT.md](VT_FILE_FORMAT.md)
- **Understand version control**: [VT_FILE_FORMAT.md](VT_FILE_FORMAT.md) → Actions section
- **See file examples**: [VT_FILE_FORMAT.md](VT_FILE_FORMAT.md) → Examples section

#### Develop with VisTrailsJL

- **Architecture overview**: [README.md](../README.md) → Architecture section
- **File format spec**: [VT_FILE_FORMAT.md](VT_FILE_FORMAT.md)
- **Rendering internals**: [RENDERING.md](RENDERING.md)
- **Execution logging**: [LOGGING.md](LOGGING.md)
- **Project context**: [CONTEXT.md](CONTEXT.md)

#### Contribute

- **Project background**: [CONTEXT.md](CONTEXT.md)
- **Development roadmap**: [README.md](../README.md) → Development Roadmap
- **Architecture**: [README.md](../README.md) → Architecture section

## Documentation Overview

### User Documentation

#### [README.md](../README.md)
Main entry point with:
- Quick start guide
- Feature overview
- Code examples (HTTPFile, JuliaSource, PythonSource)
- Compatibility matrix
- Development roadmap

#### [SETUP.md](SETUP.md)
Installation and configuration:
- Julia environment setup
- Dependencies
- Testing
- Troubleshooting

#### [JSON_CONVERSION.md](JSON_CONVERSION.md)
Complete guide to JSON export/import:
- Command-line tool usage
- Programmatic API
- Use cases (editing, version control, web integration)
- File format comparison
- Limitations and workarounds

### Developer Documentation

#### [VT_FILE_FORMAT.md](VT_FILE_FORMAT.md)
Complete .vt file specification:
- XML schema reference
- Action-based version control
- Modules, connections, ports
- Data encoding
- Reconstruction algorithm
- Real-world examples

#### [RENDERING.md](RENDERING.md)
SVG rendering system:
- Workflow visualization
- Version tree layout
- Lightweight rendering mode
- Module box sizing
- Connection routing

#### [LOGGING.md](LOGGING.md)
Execution logging and provenance:
- Machine information tracking
- Module execution records
- Workflow execution tracking
- Performance metrics
- Error logging
- Integration with interpreter

#### [CONTEXT.md](CONTEXT.md)
Project context:
- VisTrails overview
- Julia implementation rationale
- Design decisions
- Integration with VisFlow

## Features by Documentation

| Feature | Documented In | Section |
|---------|---------------|---------|
| Loading .vt files | README.md, VT_FILE_FORMAT.md | Reading section, File Structure |
| JSON export/import | JSON_CONVERSION.md | Complete guide |
| SVG rendering | README.md, RENDERING.md | SVG Rendering, Workflow Visualization |
| Action replay | VT_FILE_FORMAT.md, RENDERING.md | Actions section, Reconstruction |
| Module system | README.md, VT_FILE_FORMAT.md | Three Core Modules, Modules section |
| Version control | VT_FILE_FORMAT.md | Version Tree Structure |
| Execution logging | LOGGING.md | Complete guide |
| Python interop | README.md | PythonSource section |
| Julia execution | README.md | JuliaSource section |

## Code Examples

### Basic Usage
```julia
# Load and inspect a workflow
using VisTrailsJL
vt = load_vistrail("workflow.vt")
println("Versions: ", length(vt.actions))
```
**See:** [README.md](../README.md) → Reading and Rendering

### JSON Conversion
```bash
# Export to JSON
julia --project=. vt_json_convert.jl export workflow.vt
```
**See:** [JSON_CONVERSION.md](JSON_CONVERSION.md) → Command-Line Usage

### Workflow Creation
```julia
# Create a new pipeline
pipeline = Pipeline()
http = add_module!(pipeline, "org.vistrails.vistrails.basic", "HTTPFile")
```
**See:** [README.md](../README.md) → Example: HTTP Fetch + Julia Processing

### SVG Rendering
```julia
# Render workflow to SVG
svg = render_pipeline_svg(workflow)
write("workflow.svg", svg)
```
**See:** [RENDERING.md](RENDERING.md) → Usage section

## File Format References

### .vt Files (ZIP + XML)
- **Specification**: [VT_FILE_FORMAT.md](VT_FILE_FORMAT.md)
- **Container format**: ZIP archive with XML
- **Main file**: `vistrail` (XML)
- **Optional files**: `log`, `abstraction_*`, `thumbs/*.png`

### JSON Files
- **Specification**: [JSON_CONVERSION.md](JSON_CONVERSION.md) → JSON Structure
- **Format**: Pretty-printed JSON
- **Size**: 40-50x larger than compressed .vt
- **Advantages**: Human-readable, git-friendly, web-compatible

### SVG Files
- **Specification**: [RENDERING.md](RENDERING.md)
- **Workflows**: Module boxes with connections
- **Version trees**: Provenance visualization
- **Format**: Standard SVG 1.1

## API Reference

### Core Functions

**File I/O:**
- `load_vistrail(filename)` - Load .vt file
- `export_vt_to_json(vt_file, json_file)` - Export to JSON
- `import_vt_from_json(json_file, vt_file)` - Import from JSON

**Rendering:**
- `render_pipeline_svg(pipeline)` - Render workflow
- `render_version_tree_svg(vistrail)` - Render version tree

**Pipeline Manipulation:**
- `add_module!(pipeline, package, name)` - Add module
- `add_connection!(pipeline, src, src_port, dst, dst_port)` - Connect modules
- `set_parameter!(module, name, value)` - Set parameter

**See detailed API in:** [README.md](../README.md) and source code

## Version Information

| Component | Version | Schema Version | Notes |
|-----------|---------|----------------|-------|
| VisTrailsJL | 0.1.0 | N/A | Julia implementation |
| .vt format | - | 1.0.3 | Current Python VisTrails |
| JSON format | - | 2.0 | Custom JSON schema |

## Compatibility

**VisTrailsJL reads:**
- ✅ Python VisTrails .vt files (schema 1.0.0 - 1.0.3)
- ✅ Plain XML .vt files
- ✅ ZIP compressed .vt files
- ✅ Files with VTK/matplotlib modules (via lightweight rendering)

**VisTrailsJL writes:**
- ✅ JSON export of .vt files
- ✅ .vt files from JSON (uncompressed)
- ❌ Compressed .vt files (ZipFile.jl limitation)
- ❌ Native .vt creation (in development)

## Getting Help

### Troubleshooting

1. **Installation issues**: See [SETUP.md](SETUP.md) → Troubleshooting
2. **File loading errors**: Check [VT_FILE_FORMAT.md](VT_FILE_FORMAT.md) for format details
3. **JSON conversion issues**: See [JSON_CONVERSION.md](JSON_CONVERSION.md) → Limitations
4. **Rendering problems**: Check [RENDERING.md](RENDERING.md) → Known Issues

### Common Questions

**Q: Why is my restored .vt file larger?**
A: ZipFile.jl doesn't support compression. See [JSON_CONVERSION.md](JSON_CONVERSION.md) → Limitations.

**Q: How do I view version history?**
A: Use `render_version_tree_svg()` or inspect `vistrail.actions`. See [VT_FILE_FORMAT.md](VT_FILE_FORMAT.md) → Version Tree.

**Q: Can I edit workflows in JSON?**
A: Yes, but carefully. See [JSON_CONVERSION.md](JSON_CONVERSION.md) → Editing JSON Files.

**Q: What's the difference between actions and workflows?**
A: Actions are version control deltas, workflows are the actual pipelines. See [VT_FILE_FORMAT.md](VT_FILE_FORMAT.md) → Actions.

## Contributing

Want to contribute? See:
1. [README.md](../README.md) → Next Steps for Contributors
2. [CONTEXT.md](CONTEXT.md) → Project Background
3. Development roadmap in [README.md](../README.md)

## External Resources

- [VisTrails Website](https://www.vistrails.org/)
- [VisTrails GitHub](https://github.com/VisTrails/VisTrails)
- [VisTrails User Guide](https://www.vistrails.org/usersguide/)
- [Julia Language](https://julialang.org/)

## Document Status

| Document | Status | Last Updated | Completeness |
|----------|--------|--------------|--------------|
| README.md | ✅ Current | 2025-01-20 | Complete |
| VT_FILE_FORMAT.md | ✅ Current | 2025-01-20 | Complete |
| JSON_CONVERSION.md | ✅ Current | 2025-01-20 | Complete |
| RENDERING.md | ✅ Current | 2024 | Complete |
| LOGGING.md | ✅ Current | 2025-01-21 | Complete |
| CONTEXT.md | ✅ Current | 2024 | Complete |
| SETUP.md | ✅ Current | 2024 | Complete |

---

**Last updated:** 2025-01-20
**VisTrailsJL version:** 0.1.0
