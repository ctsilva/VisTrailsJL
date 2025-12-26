# VisFlow Web Integration

Documentation for integrating VisTrailsJL with the VisFlow web framework for browser-based workflow visualization.

## Overview

VisTrailsJL now provides a REST API backend that enables web-based visualization of VisTrails workflows through the VisFlow framework. This allows users to browse, view, and explore .vt files in a modern web interface.

## Architecture

The integration consists of three layers:

1. **VisTrailsJL Core** - Julia library for loading and rendering .vt files
2. **Genie.jl REST API** - HTTP server providing JSON and SVG endpoints
3. **VisFlow Frontend** - Vue.js web application for user interaction

## Quick Start

### 1. Start the Backend Server

```bash
cd /Users/csilva/src/VisTrails/julia/backend
./start.sh
```

Server will be available at: **http://localhost:8000**

### 2. Test the API

```bash
# Health check
curl http://localhost:8000/health

# List workflows
curl http://localhost:8000/api/workflows

# Get workflow SVG
curl http://localhost:8000/api/workflow/gcd/version/1/svg

# Get version tree SVG
curl http://localhost:8000/api/workflow/gcd/tree/svg
```

### 3. Access via VisFlow

With VisFlow dev server running (http://localhost:8080):

Navigate to: **http://localhost:8080/vistrails**

## API Endpoints

### Health Check

**GET /health**

Returns server status.

**Response:**
```json
{
  "status": "healthy",
  "service": "VisTrailsJL Backend",
  "version": "0.1.0"
}
```

### List Workflows

**GET /api/workflows**

Returns all .vt files in the examples directory.

**Response:**
```json
{
  "workflows": [
    {
      "id": "gcd",
      "name": "gcd",
      "path": "gcd.vt",
      "size": 12470,
      "modified": 1748320566854.8121
    }
  ],
  "count": 31
}
```

### Get Workflow Metadata

**GET /api/workflow/:id**

Returns metadata and latest pipeline for a workflow.

**Parameters:**
- `id` - Workflow name (without .vt extension)

**Example:** `/api/workflow/gcd`

**Response:**
```json
{
  "modules": [
    {
      "id": 1,
      "name": "PythonSource",
      "package": "org.vistrails.vistrails.basic",
      "x": 250.0,
      "y": 100.0,
      "inputs": [...],
      "outputs": [...]
    }
  ],
  "connections": [
    {
      "source_id": 1,
      "source_port": "value",
      "target_id": 2,
      "target_port": "a"
    }
  ],
  "version_id": 22
}
```

### Get Specific Workflow Version

**GET /api/workflow/:id/version/:version_id**

Returns a specific version of the workflow.

**Parameters:**
- `id` - Workflow name
- `version_id` - Version number (integer)

**Example:** `/api/workflow/gcd/version/1`

**Response:** Same format as workflow metadata

**Error Response (404):**
```json
{
  "error": "Version 999 could not be reconstructed"
}
```

### Get Workflow SVG

**GET /api/workflow/:id/svg**

Returns SVG visualization of the latest workflow version.

**Content-Type:** `image/svg+xml`

**Example:** `/api/workflow/gcd/svg`

### Get Specific Version SVG

**GET /api/workflow/:id/version/:version_id/svg**

Returns SVG visualization of a specific workflow version.

**Example:** `/api/workflow/gcd/version/1/svg`

### Get Version Tree

**GET /api/workflow/:id/versions**

Returns version history metadata.

**Example:** `/api/workflow/gcd/versions`

**Response:**
```json
{
  "versions": [
    {
      "id": 1,
      "parent": 0,
      "timestamp": "2024-01-15T10:30:00",
      "user": "user@example.com",
      "notes": "Initial version"
    }
  ],
  "tags": [
    {
      "name": "v1.0",
      "version_id": 22
    }
  ],
  "current_version": 22,
  "count": 22
}
```

### Get Version Tree SVG

**GET /api/workflow/:id/tree/svg**

Returns SVG visualization of the complete version tree.

**Content-Type:** `image/svg+xml`

**Example:** `/api/workflow/gcd/tree/svg`

## SVG Rendering Features

### Workflow SVG

The workflow SVG renderer provides:

- **Dynamic Module Sizing**: Box size based on longest label
- **Port Visualization**: Input ports on left, output ports on right
- **Connection Routing**: Bezier curves between modules
- **Lightweight Mode**: Renders without requiring module descriptors
- **Layout Preservation**: Uses original .vt file coordinates when available

### Version Tree SVG

The version tree renderer provides:

- **Hierarchical Layout**: Parent-child relationships visualized
- **Dynamic Sizing**: Ellipse size based on version count
- **Tag Labels**: Shows version tags
- **Bezier Connections**: Smooth lines between versions
- **Horizontal Spacing**: Prevents overlapping branches

## Backend Implementation

### Server Configuration

File: `backend/server.jl`

```julia
using Genie

ENV["GENIE_ENV"] = "dev"
ENV["PORT"] = get(ENV, "PORT", "8000")

Genie.config.run_as_server = true
Genie.config.server_host = "0.0.0.0"
Genie.config.server_port = 8000
Genie.config.websockets_server = false

include("routes.jl")
up()
```

### Route Definitions

File: `backend/routes.jl`

Routes are defined using Genie.jl's routing DSL:

```julia
route("/api/workflows", method = GET) do
    # Implementation
    json(result)
end
```

### VisTrailsJL Integration

Routes load and process .vt files using VisTrailsJL:

```julia
vistrail = VisTrailsJL.load_vistrail(vt_file, version=version_id)
pipeline = VisTrailsJL.get_pipeline(vistrail)
svg_content = VisTrailsJL.render_pipeline_svg(pipeline)
```

## Development

### Adding New Endpoints

1. Add route in `backend/routes.jl`:
```julia
route("/api/new-endpoint", method = GET) do
    # Implementation
    json(result)
end
```

2. Implement in VisTrailsJL if needed
3. Update documentation
4. Test with curl or browser

### Modifying SVG Rendering

SVG rendering code is in:
- `src/rendering/workflow_svg.jl` - Workflow visualization
- `src/rendering/version_tree_svg.jl` - Version tree visualization

### Testing

```bash
# Unit tests
julia --project=. test/runtests.jl

# Manual API testing
./backend/start.sh
curl http://localhost:8000/api/workflows
```

## VisFlow Integration

VisFlow connects to this backend through:

1. **Webpack Proxy** (development):
   - VisFlow dev server proxies `/api/*` to `http://localhost:8000/api/*`
   - Eliminates CORS issues

2. **Vue Component**:
   - `vistrails-viewer.vue` - UI component
   - Uses Axios for HTTP requests
   - Renders SVG inline in browser

3. **Routing**:
   - Accessible at `http://localhost:8080/vistrails`
   - Vue Router handles navigation

## CORS Considerations

### Development

CORS is handled by VisFlow's webpack proxy - no backend configuration needed.

### Production

For production deployment, you'll need to add CORS headers to the backend.

Option 1: Add middleware to Genie.jl (needs implementation)
Option 2: Use reverse proxy (nginx) to handle CORS
Option 3: Serve VisFlow from same domain as API

## Performance

### Caching

Consider adding caching for:
- Workflow list (changes rarely)
- SVG generation (expensive operation)
- Version metadata

### Optimization

For large .vt files:
- Lazy load version history
- Paginate workflow lists
- Stream SVG for very large workflows

## Monitoring

### Logs

Server outputs to stdout:
```
@info "Starting VisTrailsJL Backend Server..."
@info "Port: 8000"
@error "Error loading workflow" exception=(e, catch_backtrace())
```

### Health Checks

Use `/health` endpoint for monitoring:
```bash
curl http://localhost:8000/health
```

## Troubleshooting

### Port Already in Use

```bash
# Find process using port 8000
lsof -i :8000

# Kill it
kill -9 <PID>
```

### Julia Package Issues

```bash
cd /Users/csilva/src/VisTrails/julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### .vt File Not Found

Check that .vt files are in:
```
/Users/csilva/src/VisTrails/examples/
```

### SVG Rendering Errors

Check backend logs for:
- Version reconstruction failures
- Missing module descriptors
- Invalid .vt file format

## File Locations

### Backend Files
- `backend/server.jl` - Genie.jl server configuration
- `backend/routes.jl` - API route definitions
- `backend/start.sh` - Server startup script
- `backend/Project.toml` - Julia dependencies

### VisTrailsJL Files
- `src/rendering/workflow_svg.jl` - Workflow SVG generation
- `src/rendering/version_tree_svg.jl` - Version tree SVG generation
- `src/vistrail.jl` - Core .vt file loading

### Example Workflows
- `examples/*.vt` - Test .vt files (31 files)

## Related Documentation

- [VisFlow Integration Guide](/Users/csilva/github/visflow/docs/VISFLOW_VISTRAILS_INTEGRATION.md)
- [VisTrailsJL README](../README.md)
- [SVG Rendering Documentation](RENDERING.md)
- [Version Tree Demo](VERSION_TREE_DEMO_COMPLETE.md)
- [Genie.jl Documentation](https://genieframework.com/)
