# VisTrailsJL → VisFlow Integration POC ✅

## What We Built

A complete proof-of-concept showing that VisTrailsJL workflows can be fetched from a backend API and displayed in a web interface (VisFlow).

### Components

1. **Fixed Backend API** (`backend/routes.jl`)
   - Corrected field names to match actual VisTrailsJL structs
   - `Pipeline`: uses `modules`, `connections` (no `module_positions`)
   - `Connection`: uses `source_port`, `dest_port` (not `*_name`)
   - `Vistrail`: uses `actions` (not `action_map`)

2. **Demo Web Interface** (`backend/public/vistrails-demo.html`)
   - Lists all 31 available workflows from `/api/workflows`
   - Loads workflow JSON from `/api/workflow/:id`
   - Displays workflow SVG from `/api/workflow/:id/svg`
   - Shows VisFlow mapping format

### API Endpoints (Working!)

```bash
# Health check
curl http://localhost:8000/health

# List all workflows
curl http://localhost:8000/api/workflows

# Get workflow JSON
curl http://localhost:8000/api/workflow/gcd | jq .

# Get workflow SVG
curl http://localhost:8000/api/workflow/gcd/svg

# Demo interface
open http://localhost:8000/demo
```

### Example Workflow JSON

```json
{
  "modules": [
    {
      "name": "StandardOutput",
      "id": 2,
      "x": 400.0,
      "y": 100.0,
      "package": "org.vistrails.vistrails.basic",
      "inputs": [],
      "outputs": []
    },
    {
      "name": "While",
      "id": 1,
      "x": 250.0,
      "y": 200.0,
      "package": "org.vistrails.vistrails.control_flow",
      "inputs": [],
      "outputs": []
    }
  ],
  "connections": [
    {
      "source_id": 1,
      "target_id": 2,
      "target_port": "value",
      "source_port": "Result"
    }
  ],
  "version_id": 134
}
```

### VisFlow Mapping Format

The demo shows how to map VisTrailsJL format to VisFlow's expected format:

```javascript
{
  nodes: vistrailsData.modules.map(mod => ({
    id: mod.id.toString(),
    type: mod.name,
    label: mod.name,
    package: mod.package,
    x: mod.x,
    y: mod.y,
    inputs: mod.inputs,
    outputs: mod.outputs
  })),
  edges: vistrailsData.connections.map((conn, idx) => ({
    id: `edge-${idx}`,
    source: conn.source_id.toString(),
    sourcePort: conn.source_port,
    target: conn.target_id.toString(),
    targetPort: conn.target_port
  })),
  metadata: {
    source: 'VisTrailsJL',
    version_id: vistrailsData.version_id
  }
}
```

## Running the Demo

```bash
# Start the backend
cd /Users/csilva/src/VisTrails/julia/backend
./start.sh

# Open the demo in your browser
open http://localhost:8000/demo
```

## Next Steps for VisFlow Integration

1. **Fork VisFlow Repository**
   ```bash
   cd /Users/csilva/github
   # Already exists at /Users/csilva/github/visflow
   ```

2. **Add VisTrailsJL Data Source**
   - Create a new component in `visflow/client/src/components/vistrails-source/`
   - Use the mapping function from the demo
   - Fetch from `http://localhost:8000/api/workflow/:id`

3. **Render in VisFlow Canvas**
   - Convert VisTrailsJL modules → VisFlow nodes
   - Convert VisTrailsJL connections → VisFlow edges
   - Use existing VisFlow rendering engine

4. **Test with Multiple Workflows**
   - gcd.vt (2 modules, 1 connection)
   - lung.vt (13 modules, 12 connections)
   - plot.vt (10 modules, 10 connections)
   - All 31 example workflows available!

## Key Achievements

✅ Backend API serving VisTrails workflows as JSON
✅ 31 example workflows available
✅ Both JSON and SVG rendering
✅ Demo interface showing feasibility
✅ Clear mapping to VisFlow format documented
✅ CORS enabled for frontend development

## Architecture

```
VisFlow Frontend
     ↓ fetch()
http://localhost:8000/api/workflow/:id
     ↓
Genie.jl Backend
     ↓
VisTrailsJL (Julia)
     ↓
.vt Files (31 examples)
```

## Files Modified

- `backend/routes.jl` - Fixed field names to match VisTrailsJL structs
- `backend/public/vistrails-demo.html` - Created demo interface

## Result

**The proof-of-concept is complete!** We can successfully:
- Load VisTrails workflows from the Julia backend
- Convert them to JSON format
- Display them in a web interface
- Map them to VisFlow's format

The next step is to create an actual VisFlow component that uses this API.
