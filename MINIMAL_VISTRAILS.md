# Minimal VisTrails System

This document describes what a "minimal VisTrails" system would look like for **reading and inspecting .vt files without the GUI**.

## Overview

A minimal VisTrails system can:
- ✅ Load `.vt` (XML) files
- ✅ Inspect workflow structure (modules, connections, parameters)
- ✅ Read version history and tags
- ✅ Export workflow information to text
- ❌ No GUI (no PyQt4 required)
- ❌ No execution (no VTK or other visualization packages)
- ❌ No editing/saving

## Core Dependencies

### Absolutely Required

1. **Python 2.7** - VisTrails is Python 2 only
2. **XML Parser** - Built-in (`xml.etree.ElementTree` or `lxml`)
3. **Core VisTrails modules**:
   ```
   vistrails/core/db/          # Database layer for .vt files
   vistrails/core/vistrail/    # Core vistrail/pipeline classes
   vistrails/core/system.py    # System utilities
   vistrails/db/               # DB services and domain models
   ```

### Python Packages (minimal)

```
python-dateutil    # Date handling
```

That's it! No PyQt4, no VTK, no matplotlib, no scipy.

## File Structure (.vt files)

A `.vt` file is an **XML file** containing:

```xml
<vistrail>
  <actions>      <!-- Version history (git-like) -->
  <modules>      <!-- Workflow nodes -->
  <connections>  <!-- Edges between modules -->
  <parameters>   <!-- Module parameters -->
  <annotations>  <!-- Tags, notes, etc -->
</vistrail>
```

## Minimal Code Example

See [minimal_vistrails.py](minimal_vistrails.py) for a complete working example.

### Basic Usage

```python
from vistrails.core.db.locator import XMLFileLocator
from vistrails.core.db.io import load_vistrail

# Load a .vt file
locator = XMLFileLocator('workflow.vt')
(vistrail, abstractions, thumbnails, mashups) = load_vistrail(locator)

# Get latest version
latest_version = vistrail.get_latest_version()

# Get the pipeline (workflow)
pipeline = vistrail.getPipeline(latest_version)

# Inspect modules
for module in pipeline.module_list:
    print(f"{module.name} ({module.package})")
    for func in module.functions:
        print(f"  {func.name} = {func.params}")

# Inspect connections
for conn in pipeline.connection_list:
    src = pipeline.modules[conn.source.moduleId]
    dst = pipeline.modules[conn.destination.moduleId]
    print(f"{src.name} -> {dst.name}")
```

## Key Classes

### 1. **Vistrail** (`vistrails/core/vistrail/vistrail.py`)
The main container for a `.vt` file.

**Key methods:**
- `get_version_graph()` - Get all versions
- `get_latest_version()` - Get latest version ID
- `getPipeline(version_id)` - Get workflow for a version
- `get_tagMap()` - Get version tags

### 2. **Pipeline** (`vistrails/core/vistrail/pipeline.py`)
Represents a single workflow (DAG of modules).

**Key attributes:**
- `module_list` - List of modules (nodes)
- `connection_list` - List of connections (edges)
- `modules` - Dict of module_id -> module

### 3. **Module** (`vistrails/core/vistrail/module.py`)
A computational unit in the workflow.

**Key attributes:**
- `id` - Unique ID
- `name` - Module name (e.g., "PythonSource", "File")
- `package` - Package name (e.g., "org.vistrails.vistrails.basic")
- `functions` - List of parameters/settings

### 4. **Connection** (`vistrails/core/vistrail/connection.py`)
An edge connecting two modules.

**Key attributes:**
- `source` - Source port (moduleId, portName)
- `destination` - Destination port (moduleId, portName)

## What You Can Do

### 1. **Inspect Workflow Structure**

```bash
python minimal_vistrails.py workflow.vt
```

Output:
```
Total versions: 10
Tagged versions: 3
  - initial: version 1
  - final: version 10

Latest version: 10

Modules (15):
  - PythonSource (org.vistrails.vistrails.basic)
  - HTTPFile (org.vistrails.vistrails.basic)
  ...

Connections (12):
  - HTTPFile:self -> PythonSource:file
  ...
```

### 2. **Export to Text Format**

```bash
python minimal_vistrails.py workflow.vt --export output.txt
```

Creates a human-readable text representation.

### 3. **Analyze Version History**

```bash
python minimal_vistrails.py workflow.vt --tree
```

Shows the git-like version tree.

### 4. **Programmatic Access**

```python
# Load workflow
vistrail = load_vt_file('workflow.vt')

# Find all PythonSource modules
pipeline = vistrail.getPipeline(latest_version)
python_modules = [m for m in pipeline.module_list
                  if m.name == 'PythonSource']

# Extract Python code from them
for module in python_modules:
    for func in module.functions:
        if func.name == 'source':
            code = func.params[0].value
            print(code)
```

## Minimal Docker Image

For a minimal Docker setup (without GUI):

```dockerfile
FROM ubuntu:20.04
RUN apt-get update && apt-get install -y python2.7 python-pip
RUN pip install python-dateutil

COPY vistrails/ /vistrails/
WORKDIR /vistrails

CMD ["python2.7", "minimal_vistrails.py"]
```

**Size**: ~200MB (vs 2.18GB for full GUI version)

## Use Cases

### 1. **CI/CD Pipeline Validation**
```bash
# Validate workflow structure
python minimal_vistrails.py workflow.vt --export validation.txt
```

### 2. **Workflow Documentation**
```bash
# Generate documentation for all workflows
for file in *.vt; do
    python minimal_vistrails.py "$file" --export "docs/${file%.vt}.txt"
done
```

### 3. **Batch Analysis**
```python
# Analyze 1000 workflows
import glob
for vt_file in glob.glob('*.vt'):
    vistrail = load_vt_file(vt_file)
    pipeline = vistrail.getPipeline(vistrail.get_latest_version())
    print(f"{vt_file}: {len(pipeline.module_list)} modules")
```

### 4. **Workflow Migration**
```python
# Extract all PythonSource code for migration
for module in pipeline.module_list:
    if module.name == 'PythonSource':
        # Extract and convert to Python 3
        code = get_module_code(module)
        converted = convert_to_python3(code)
```

## Limitations of Minimal System

### Cannot Do:

1. **Execute workflows** - Requires interpreter + all packages (VTK, matplotlib, etc.)
2. **Display GUI** - No PyQt4
3. **Edit/Create workflows** - Read-only
4. **Render visualizations** - No VTK
5. **Interactive exploration** - Command-line only

### Can Do:

1. ✅ Load and parse `.vt` files
2. ✅ Inspect workflow structure
3. ✅ Read version history
4. ✅ Extract module parameters
5. ✅ Export to other formats
6. ✅ Validate workflow integrity
7. ✅ Generate documentation

## Files Needed (Minimal)

From the VisTrails codebase, you need:

```
vistrails/
├── core/
│   ├── db/
│   │   ├── io.py              # Load/save operations
│   │   └── locator.py         # File locators
│   ├── vistrail/
│   │   ├── vistrail.py        # Main vistrail class
│   │   ├── pipeline.py        # Pipeline/workflow
│   │   ├── module.py          # Module class
│   │   ├── connection.py      # Connection class
│   │   └── port.py            # Port class
│   ├── system.py              # System utilities
│   └── debug.py               # Debugging
├── db/
│   ├── services/
│   │   ├── io.py              # XML I/O
│   │   └── locator.py         # Locator services
│   └── domain/
│       └── *.py               # DB domain models
└── __init__.py
```

**Total**: ~50-100 Python files, ~5-10 MB

## Next Steps

1. **Try the minimal script**:
   ```bash
   python minimal_vistrails.py examples/terminator.vt
   ```

2. **Extend for your use case**:
   - Add JSON export
   - Add workflow diff
   - Add module search
   - Add validation rules

3. **Build a minimal Docker image**:
   ```bash
   docker build -f Dockerfile.minimal -t vistrails-minimal .
   ```

4. **Integrate with your tools**:
   - CI/CD pipelines
   - Documentation generators
   - Migration scripts

## Comparison: Full vs Minimal

| Feature | Full VisTrails | Minimal VisTrails |
|---------|---------------|-------------------|
| Load .vt files | ✅ | ✅ |
| Inspect structure | ✅ | ✅ |
| Execute workflows | ✅ | ❌ |
| GUI | ✅ | ❌ |
| Edit workflows | ✅ | ❌ |
| Visualizations | ✅ | ❌ |
| Docker image size | 2.18 GB | ~200 MB |
| Dependencies | 50+ packages | 1 package |
| Python version | 2.7 | 2.7 |
| Use case | Full workflow authoring | Inspection & analysis |

## Conclusion

A minimal VisTrails system is perfect for:
- 📊 Workflow analysis and reporting
- 🔍 Inspection and validation
- 📝 Documentation generation
- 🔄 Migration and conversion
- 🚀 Lightweight CI/CD integration

**Not suitable for**:
- Interactive workflow development
- Executing workflows
- Visualization rendering
