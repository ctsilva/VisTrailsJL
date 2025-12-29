# VisTrailsJL Backend API Endpoints

Complete reference for all HTTP API endpoints available in the VisTrailsJL backend.

**Base URL**: `http://localhost:8000` (default)

---

## Health & Status

### GET /health
Health check endpoint.

**Response**:
```json
{
  "status": "healthy",
  "service": "VisTrailsJL Backend",
  "version": "0.1.0"
}
```

---

## Workflow List & Metadata

### GET /api/workflows
List all available workflows.

**Response**:
```json
{
  "workflows": [
    {
      "id": "gcd",
      "name": "gcd",
      "path": "gcd.vt",
      "size": 123456,
      "modified": 1234567890.0
    }
  ],
  "count": 1
}
```

---

## Workflow Data (Read-Only)

### GET /api/workflow/:id
Get workflow data as JSON (latest version).

**Parameters**:
- `id` - Workflow ID (e.g., "gcd", "lung", "mta")

**Response**:
```json
{
  "modules": [
    {
      "id": 1,
      "name": "Integer",
      "package": "org.vistrails.vistrails.basic",
      "x": 100.0,
      "y": 100.0,
      "inputs": [{"name": "value", "type": "Int64"}],
      "outputs": [{"name": "value", "type": "Int64"}]
    }
  ],
  "connections": [
    {
      "source_id": 1,
      "source_port": "value",
      "target_id": 2,
      "target_port": "value1"
    }
  ],
  "version_id": 134
}
```

**Example**:
```bash
curl http://localhost:8000/api/workflow/gcd
```

---

### GET /api/workflow/:id/version/:version_id
Get specific version of workflow as JSON.

**Parameters**:
- `id` - Workflow ID
- `version_id` - Version number (integer)

**Response**: Same format as GET /api/workflow/:id

**Example**:
```bash
curl http://localhost:8000/api/workflow/gcd/version/100
```

---

### GET /api/workflow/:id/svg
Get workflow rendered as SVG (latest version).

**Parameters**:
- `id` - Workflow ID

**Response**: SVG image (Content-Type: image/svg+xml)

**Example**:
```bash
curl http://localhost:8000/api/workflow/gcd/svg > workflow.svg
```

---

### GET /api/workflow/:id/version/:version_id/svg
Get specific version rendered as SVG.

**Parameters**:
- `id` - Workflow ID
- `version_id` - Version number

**Response**: SVG image

**Example**:
```bash
curl http://localhost:8000/api/workflow/gcd/version/100/svg > workflow.svg
```

---

## Version Tree

### GET /api/workflow/:id/versions
Get version tree data as JSON.

**Parameters**:
- `id` - Workflow ID

**Response**:
```json
{
  "versions": [
    {
      "id": 1,
      "parent": 0,
      "timestamp": "2024-01-15T10:30:00",
      "user": "alice",
      "notes": "Initial version"
    }
  ],
  "tags": [
    {
      "name": "stable",
      "version_id": 100
    }
  ],
  "current_version": 134,
  "count": 134
}
```

**Example**:
```bash
curl http://localhost:8000/api/workflow/gcd/versions
```

---

### GET /api/workflow/:id/tree/svg
Get version tree rendered as SVG.

**Parameters**:
- `id` - Workflow ID

**Response**: SVG image

**Example**:
```bash
curl http://localhost:8000/api/workflow/gcd/tree/svg > tree.svg
```

---

## Workflow Editing (Write Operations)

### GET /api/workflow/:id/state
Get current editing state for a workflow.

**Parameters**:
- `id` - Workflow ID

**Response**:
```json
{
  "workflow_id": "gcd",
  "current_version": 134,
  "modified": true,
  "last_saved": "2024-01-15T10:30:00",
  "module_count": 22,
  "connection_count": 31,
  "modules": [
    {
      "id": 1,
      "name": "Integer",
      "package": "org.vistrails.vistrails.basic",
      "position": {"x": 100.0, "y": 100.0},
      "parameters": {"value": 42}
    }
  ],
  "connections": [
    {
      "id": 1,
      "source_module_id": 1,
      "source_port": "value",
      "dest_module_id": 2,
      "dest_port": "value1"
    }
  ]
}
```

**Example**:
```bash
curl http://localhost:8000/api/workflow/gcd/state
```

---

### POST /api/workflow/:id/module
Add a new module to the workflow.

**Parameters**:
- `id` - Workflow ID

**Request Body**:
```json
{
  "type": "basic:Integer",
  "position": {
    "x": 100.0,
    "y": 100.0
  },
  "parameters": {
    "value": 42
  }
}
```

**Module Types** (format: `package:name` or `package::name`):
- `basic:Integer`, `basic:Float`, `basic:String`, `basic:Boolean`
- `basic:HTTPFile`, `basic:PythonSource`
- `basic:InputPort`, `basic:OutputPort`, `basic:StandardOutput`
- `basic:Tuple`, `basic:Untuple`, `basic:List`, `basic:Round`
- `julia:JuliaSource`
- `pythoncalc:PythonCalc`
- `control_flow:If`, `control_flow:While`, `control_flow:And`, `control_flow:Or`, `control_flow:Not`
- `control_flow:Sum`, `control_flow:Cross`, `control_flow:Dot`, `control_flow:ElementwiseProduct`
- `matplotlib:MplFigure`, `matplotlib:MplFigureOutput`, `matplotlib:MplLinePlot`
- `matplotlib:MplScatter`, `matplotlib:MplBar`, `matplotlib:MplHist`

**Response**:
```json
{
  "module_id": 1,
  "descriptor": {
    "name": "Integer",
    "package": "org.vistrails.vistrails.basic",
    "input_ports": [],
    "output_ports": [
      {"name": "value", "type": "Int64"}
    ]
  },
  "position": {"x": 100.0, "y": 100.0},
  "parameters": {"value": 42}
}
```

**Example**:
```bash
curl -X POST http://localhost:8000/api/workflow/gcd/module \
  -H "Content-Type: application/json" \
  -d '{
    "type": "basic:Integer",
    "position": {"x": 100, "y": 100},
    "parameters": {"value": 42}
  }'
```

---

### PATCH /api/workflow/:id/module/:module_id/position
Update a module's position on the canvas.

**Parameters**:
- `id` - Workflow ID
- `module_id` - Module ID (integer)

**Request Body**:
```json
{
  "x": 150.0,
  "y": 120.0
}
```

**Response**:
```json
{
  "success": true,
  "module_id": 1,
  "position": {"x": 150.0, "y": 120.0}
}
```

**Example**:
```bash
curl -X PATCH http://localhost:8000/api/workflow/gcd/module/1/position \
  -H "Content-Type: application/json" \
  -d '{"x": 150, "y": 120}'
```

---

### PATCH /api/workflow/:id/module/:module_id/parameters
Update a module's parameters.

**Parameters**:
- `id` - Workflow ID
- `module_id` - Module ID (integer)

**Request Body**:
```json
{
  "value": 100,
  "other_param": "some value"
}
```

**Response**:
```json
{
  "success": true,
  "module_id": 1,
  "parameters": {
    "value": 100,
    "other_param": "some value"
  }
}
```

**Example**:
```bash
curl -X PATCH http://localhost:8000/api/workflow/gcd/module/1/parameters \
  -H "Content-Type: application/json" \
  -d '{"value": 100}'
```

---

### DELETE /api/workflow/:id/module/:module_id
Delete a module from the workflow.

**Parameters**:
- `id` - Workflow ID
- `module_id` - Module ID (integer)

**Response**:
```json
{
  "success": true,
  "module_id": 1,
  "removed_connections": [1, 2, 3]
}
```

**Note**: All connections to/from the deleted module are automatically removed (cascade delete).

**Example**:
```bash
curl -X DELETE http://localhost:8000/api/workflow/gcd/module/1
```

---

### POST /api/workflow/:id/connection
Add a connection between two modules.

**Parameters**:
- `id` - Workflow ID

**Request Body**:
```json
{
  "source_module_id": 1,
  "source_port": "value",
  "dest_module_id": 2,
  "dest_port": "value1"
}
```

**Response**:
```json
{
  "connection_id": 1,
  "source_module_id": 1,
  "source_port": "value",
  "dest_module_id": 2,
  "dest_port": "value1"
}
```

**Type Validation**: The backend validates that the source port type is compatible with the destination port type:
- Exact type match (Int64 → Int64)
- Numeric conversions (Int64 → Float64)
- String types (String → String)
- Subtype relationships
- Universal `Any` type

**Error Response** (on type mismatch):
```json
{
  "error": "Type mismatch: Cannot connect String to Int64"
}
```

**Example**:
```bash
curl -X POST http://localhost:8000/api/workflow/gcd/connection \
  -H "Content-Type: application/json" \
  -d '{
    "source_module_id": 1,
    "source_port": "value",
    "dest_module_id": 2,
    "dest_port": "value1"
  }'
```

---

### DELETE /api/workflow/:id/connection/:connection_id
Delete a connection.

**Parameters**:
- `id` - Workflow ID
- `connection_id` - Connection ID (integer)

**Response**:
```json
{
  "success": true,
  "connection_id": 1
}
```

**Example**:
```bash
curl -X DELETE http://localhost:8000/api/workflow/gcd/connection/1
```

---

## HTML Demo Pages

### GET /
Main index page.

**Response**: HTML page (if public/index.html exists)

---

### GET /demo
Workflow visualization demo page.

**Response**: HTML page with workflow viewer

---

### GET /tree-demo
Version tree visualization demo page.

**Response**: HTML page with version tree viewer

---

## Error Responses

All endpoints may return error responses in this format:

```json
{
  "error": "Error message here"
}
```

**Common HTTP Status Codes**:
- `200 OK` - Successful request
- `404 Not Found` - Workflow/version/module not found
- `500 Internal Server Error` - Server-side error

---

## Complete Endpoint Summary

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| GET | `/` | Main page |
| GET | `/demo` | Workflow demo page |
| GET | `/tree-demo` | Version tree demo page |
| GET | `/api/workflows` | List all workflows |
| GET | `/api/workflow/:id` | Get workflow JSON (latest) |
| GET | `/api/workflow/:id/version/:version_id` | Get workflow JSON (specific version) |
| GET | `/api/workflow/:id/svg` | Get workflow SVG (latest) |
| GET | `/api/workflow/:id/version/:version_id/svg` | Get workflow SVG (specific version) |
| GET | `/api/workflow/:id/versions` | Get version tree data |
| GET | `/api/workflow/:id/tree/svg` | Get version tree SVG |
| GET | `/api/workflow/:id/state` | Get editing state |
| POST | `/api/workflow/:id/module` | Add module |
| PATCH | `/api/workflow/:id/module/:module_id/position` | Update module position |
| PATCH | `/api/workflow/:id/module/:module_id/parameters` | Update module parameters |
| DELETE | `/api/workflow/:id/module/:module_id` | Delete module |
| POST | `/api/workflow/:id/connection` | Add connection |
| DELETE | `/api/workflow/:id/connection/:connection_id` | Delete connection |

**Total**: 17 endpoints (10 read-only + 7 write operations)

---

## Starting the Server

```bash
cd julia/backend
julia --project=.. server.jl

# Server starts on http://localhost:8000
```

---

## Testing with curl

```bash
# Health check
curl http://localhost:8000/health

# List workflows
curl http://localhost:8000/api/workflows

# Get workflow
curl http://localhost:8000/api/workflow/gcd

# Get as SVG
curl http://localhost:8000/api/workflow/gcd/svg > workflow.svg

# Add module
curl -X POST http://localhost:8000/api/workflow/gcd/module \
  -H "Content-Type: application/json" \
  -d '{"type":"basic:Integer","position":{"x":100,"y":100},"parameters":{"value":42}}'

# Move module
curl -X PATCH http://localhost:8000/api/workflow/gcd/module/1/position \
  -H "Content-Type: application/json" \
  -d '{"x":150,"y":120}'

# Add connection
curl -X POST http://localhost:8000/api/workflow/gcd/connection \
  -H "Content-Type: application/json" \
  -d '{"source_module_id":1,"source_port":"value","dest_module_id":2,"dest_port":"value1"}'

# Get state
curl http://localhost:8000/api/workflow/gcd/state
```

---

## Notes

- All editing operations maintain in-memory sessions
- Sessions are created automatically on first access
- Type validation is performed for all connections
- Module and connection IDs are auto-generated
- Deleting modules cascades to remove connected connections
- Modified workflows are tracked with `modified: true` flag
- Saving back to `.vt` files is not yet implemented (coming soon)
