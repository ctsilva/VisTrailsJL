# VisTrailsJL Backend API

Genie.jl-based REST API for serving VisTrails workflows as JSON and SVG.

## Quick Start

```bash
cd backend

# Method 1: Use start script (recommended)
./start.sh

# Method 2: Manual start
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. server.jl
```

Server will start at http://localhost:8000

**Demo Pages:**
- Workflow Browser: http://localhost:8000/demo
- Version Tree Viewer: http://localhost:8000/tree-demo

## API Endpoints

### Health Check

```bash
GET /health
```

Response:
```json
{
  "status": "healthy",
  "service": "VisTrailsJL Backend",
  "version": "0.1.0"
}
```

### List Available Workflows

```bash
GET /api/workflows
```

Response:
```json
{
  "workflows": [
    {
      "id": "gcd",
      "name": "gcd",
      "path": "gcd.vt",
      "size": 12345,
      "modified": 1234567890.0
    }
  ],
  "count": 1
}
```

### Get Workflow as JSON (Latest Version)

```bash
GET /api/workflow/:id
```

Example:
```bash
curl http://localhost:8000/api/workflow/gcd
```

Response:
```json
{
  "modules": [
    {
      "id": 1,
      "name": "Integer",
      "package": "org.vistrails.vistrails.basic",
      "x": 100.0,
      "y": 50.0,
      "inputs": [],
      "outputs": [{"name": "value", "type": "Integer"}]
    }
  ],
  "connections": [
    {
      "source_id": 1,
      "source_port": "value",
      "target_id": 3,
      "target_port": "a"
    }
  ],
  "version_id": 100
}
```

### Get Workflow as SVG ⭐ NEW

```bash
GET /api/workflow/:id/svg
```

Example:
```bash
curl http://localhost:8000/api/workflow/gcd/svg > workflow.svg
# Or open in browser: http://localhost:8000/api/workflow/gcd/svg
```

Returns workflow rendered as SVG. This is the recommended way to display workflows - let the backend handle action replay and rendering!

### Get Specific Version as JSON

```bash
GET /api/workflow/:id/version/:version_id
```

Example:
```bash
curl http://localhost:8000/api/workflow/gcd/version/50
```

### Get Specific Version as SVG ⭐ NEW

```bash
GET /api/workflow/:id/version/:version_id/svg
```

Example:
```bash
curl http://localhost:8000/api/workflow/gcd/version/50/svg > workflow_v50.svg
```

### Get Version Tree (Metadata)

```bash
GET /api/workflow/:id/versions
```

Returns version tree metadata including all versions, tags, and parent relationships.

Response:
```json
{
  "versions": [
    {
      "id": 1,
      "parent": 0,
      "timestamp": "2024-01-01T00:00:00",
      "user": "user",
      "notes": "Initial version"
    }
  ],
  "tags": [
    {
      "name": "First colormap",
      "version_id": 36
    }
  ],
  "current_version": 134,
  "count": 134
}
```

### Get Version Tree as SVG ⭐ NEW

```bash
GET /api/workflow/:id/tree/svg
```

Returns the entire version tree rendered as an SVG visualization showing version history, branches, and tags.

Example:
```bash
curl http://localhost:8000/api/workflow/gcd/tree/svg > tree.svg
# Or open in browser: http://localhost:8000/api/workflow/gcd/tree/svg
```

Features:
- **Ellipse nodes** representing versions
- **Golden color** for tagged versions
- **Orange color** for current version
- **Dashed lines** for collapsed version chains
- **Tag labels** displayed on nodes

## Testing the API

```bash
# Health check
curl http://localhost:8000/health

# List workflows
curl http://localhost:8000/api/workflows | jq .

# Get GCD workflow (JSON)
curl http://localhost:8000/api/workflow/gcd | jq .

# Get GCD workflow (SVG)
curl http://localhost:8000/api/workflow/gcd/svg > gcd_workflow.svg
open gcd_workflow.svg  # macOS
# Or visit: http://localhost:8000/api/workflow/gcd/svg

# Get specific version (JSON)
curl http://localhost:8000/api/workflow/gcd/version/50 | jq .

# Get specific version (SVG)
curl http://localhost:8000/api/workflow/gcd/version/50/svg > gcd_v50.svg

# Get version tree (metadata)
curl http://localhost:8000/api/workflow/gcd/versions | jq .

# Get version tree (SVG visualization)
curl http://localhost:8000/api/workflow/gcd/tree/svg > gcd_tree.svg
open gcd_tree.svg
```

## JSON Format

The workflow JSON format matches the structure expected by VisFlow:

- **modules**: Array of module objects with id, name, package, position, and ports
- **connections**: Array of connection objects with source/target module IDs and port names
- **version_id**: Current version number

This format can be easily adapted to the VisFlow frontend format.

## Configuration

Environment variables:
- `PORT`: Server port (default: 8000)
- `GENIE_ENV`: Environment (dev/prod, default: dev)

## Development

To add new endpoints, edit `routes.jl`:

```julia
route("/api/my-endpoint") do
    json(Dict("data" => "value"))
end
```

## CORS

CORS is enabled for all origins in development mode to allow frontend development on different ports.

## Complete API Summary

| Endpoint | Method | Description | Output |
|----------|--------|-------------|--------|
| `/health` | GET | Health check | JSON |
| `/api/workflows` | GET | List all .vt files | JSON |
| `/api/workflow/:id` | GET | Get workflow (current version) | JSON |
| `/api/workflow/:id/svg` | GET | Get workflow as SVG | SVG |
| `/api/workflow/:id/version/:vid` | GET | Get specific version | JSON |
| `/api/workflow/:id/version/:vid/svg` | GET | Get specific version as SVG | SVG |
| `/api/workflow/:id/versions` | GET | Get version tree metadata | JSON |
| `/api/workflow/:id/tree/svg` | GET | Get version tree visualization | SVG |
| `/demo` | GET | Workflow browser demo | HTML |
| `/tree-demo` | GET | Version tree viewer demo | HTML |

## Recent Improvements

### SVG Rendering Fixes
- **Workflow module boxes**: Fixed dynamic sizing to accommodate long module names (e.g., "vtkStructuredPointsReader")
  - Calculates text width in final scaled coordinates: `text_width / scale`
  - Module boxes now properly expand to fit their labels

- **Version tree ellipses**: Fixed sizing for tag labels
  - Dynamically calculates text width: `length(label) * 7.0 + 20.0`
  - Ellipse width uses max of computed node width or text width
  - Long tag names like "color and opacity" now fit properly

### Version Tree Features
- Terse graph rendering (collapses long linear chains)
- Visual distinction for tagged, current, and regular versions
- Tag names displayed on nodes instead of version numbers
- Dashed lines indicate collapsed version sequences

## Integration with VisFlow

The API is designed for easy integration with VisFlow frontend:

1. **Embed workflows**: Use `/api/workflow/:id/svg` or `/api/workflow/:id/version/:vid/svg`
2. **Embed version trees**: Use `/api/workflow/:id/tree/svg`
3. **Get metadata**: Use JSON endpoints for programmatic access

All SVG endpoints return properly formatted SVG that can be directly embedded in HTML:
```html
<img src="http://localhost:8000/api/workflow/gcd/svg" />
<!-- or -->
<object data="http://localhost:8000/api/workflow/gcd/tree/svg" type="image/svg+xml"></object>
```
