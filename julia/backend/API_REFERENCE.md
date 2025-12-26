# VisTrailsJL Backend API Reference

Complete API reference for the VisTrailsJL backend server.

## Starting the Server

```bash
cd julia/backend
./start.sh
```

Server starts at **http://localhost:8000**

## Demo Pages

- **Workflow Browser**: http://localhost:8000/demo
  - Browse .vt files
  - View version tree metadata
  - Display individual workflow versions
  - Shows SVG rendering and JSON data

- **Version Tree Viewer**: http://localhost:8000/tree-demo
  - Browse .vt files
  - Visualize complete version history as SVG tree
  - See version branches, tags, and lineage

## API Endpoints

### Health Check

**GET** `/health`

Returns server health status.

**Example:**
```bash
curl http://localhost:8000/health
```

**Response:**
```json
{
  "status": "healthy",
  "service": "VisTrailsJL Backend",
  "version": "0.1.0"
}
```

---

### List Workflows

**GET** `/api/workflows`

Returns list of all available .vt files in the examples directory.

**Example:**
```bash
curl http://localhost:8000/api/workflows | jq .
```

**Response:**
```json
{
  "workflows": [
    {
      "id": "gcd",
      "name": "gcd",
      "path": "gcd.vt",
      "size": 45123,
      "modified": 1729437281.0
    },
    {
      "id": "lung",
      "name": "lung",
      "path": "lung.vt",
      "size": 28941,
      "modified": 1729437281.0
    }
  ],
  "count": 2
}
```

---

### Get Workflow (Current Version, JSON)

**GET** `/api/workflow/:id`

Returns the current version of a workflow as JSON with modules and connections.

**Parameters:**
- `:id` - Workflow ID (filename without .vt extension)

**Example:**
```bash
curl http://localhost:8000/api/workflow/gcd | jq .
```

**Response:**
```json
{
  "modules": [
    {
      "id": 1,
      "name": "Integer",
      "package": "org.vistrails.vistrails.basic",
      "x": 250.0,
      "y": 100.0,
      "inputs": [],
      "outputs": [
        {
          "name": "value",
          "type": "Integer"
        }
      ]
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
  "version_id": 134
}
```

---

### Get Workflow (Current Version, SVG)

**GET** `/api/workflow/:id/svg`

Returns the current version of a workflow rendered as SVG.

**Parameters:**
- `:id` - Workflow ID

**Example:**
```bash
# Save to file
curl http://localhost:8000/api/workflow/gcd/svg > gcd.svg
open gcd.svg

# Or view directly in browser
open http://localhost:8000/api/workflow/gcd/svg
```

**Response:**
SVG XML content with workflow visualization:
- Rounded rectangle modules
- Square ports on module edges
- Bezier curve connections
- Module labels sized to fit text

**Features:**
- Dynamic module box sizing for long names
- Proper port positioning
- Automatic layout and scaling
- Professional styling

---

### Get Workflow Version (JSON)

**GET** `/api/workflow/:id/version/:version_id`

Returns a specific version of a workflow as JSON.

**Parameters:**
- `:id` - Workflow ID
- `:version_id` - Version number (integer)

**Example:**
```bash
curl http://localhost:8000/api/workflow/gcd/version/50 | jq .
```

**Response:**
Same format as current version endpoint, but for the specified version.

---

### Get Workflow Version (SVG)

**GET** `/api/workflow/:id/version/:version_id/svg`

Returns a specific version of a workflow rendered as SVG.

**Parameters:**
- `:id` - Workflow ID
- `:version_id` - Version number

**Example:**
```bash
curl http://localhost:8000/api/workflow/gcd/version/50/svg > gcd_v50.svg
open gcd_v50.svg
```

---

### Get Version Tree Metadata (JSON)

**GET** `/api/workflow/:id/versions`

Returns complete version history metadata including all versions, tags, and parent relationships.

**Parameters:**
- `:id` - Workflow ID

**Example:**
```bash
curl http://localhost:8000/api/workflow/gcd/versions | jq .
```

**Response:**
```json
{
  "versions": [
    {
      "id": 1,
      "parent": 0,
      "timestamp": "2024-01-15T10:30:00",
      "user": "john",
      "notes": "Initial version"
    },
    {
      "id": 2,
      "parent": 1,
      "timestamp": "2024-01-15T11:00:00",
      "user": "john",
      "notes": "Added colormap"
    }
  ],
  "tags": [
    {
      "name": "First colormap",
      "version_id": 36
    },
    {
      "name": "shifted 2",
      "version_id": 72
    }
  ],
  "current_version": 134,
  "count": 134
}
```

**Use Cases:**
- Display version history timeline
- Build version selection UI
- Show tagged versions
- Track workflow evolution

---

### Get Version Tree Visualization (SVG)

**GET** `/api/workflow/:id/tree/svg`

Returns the complete version tree rendered as an SVG visualization showing version history, branches, tags, and lineage.

**Parameters:**
- `:id` - Workflow ID

**Example:**
```bash
curl http://localhost:8000/api/workflow/gcd/tree/svg > gcd_tree.svg
open gcd_tree.svg

# Or view in browser
open http://localhost:8000/api/workflow/gcd/tree/svg
```

**Response:**
SVG XML content with version tree visualization.

**Visual Features:**
- **Ellipse nodes** for each version
- **Color coding**:
  - Light yellow: Regular versions
  - Golden: Tagged versions
  - Orange: Current version
- **Edge types**:
  - Solid lines: Direct parent-child relationships
  - Dashed lines: Collapsed linear sequences (terse graph)
- **Labels**: Tag names shown on tagged versions, version numbers on others
- **Dynamic sizing**: Ellipses expand to fit tag labels

**Use Cases:**
- Visualize workflow evolution
- Understand branching history
- Identify important tagged versions
- Embed in documentation or presentations

---

## Embedding in HTML

All SVG endpoints return properly formatted SVG that can be embedded directly:

### Using `<img>` tag:
```html
<img src="http://localhost:8000/api/workflow/gcd/svg"
     alt="GCD Workflow"
     style="max-width: 100%; height: auto;" />
```

### Using `<object>` tag (preserves SVG interactivity):
```html
<object data="http://localhost:8000/api/workflow/gcd/tree/svg"
        type="image/svg+xml"
        width="800"
        height="600">
  Version tree not supported
</object>
```

### Using `<iframe>`:
```html
<iframe src="http://localhost:8000/api/workflow/gcd/svg"
        width="100%"
        height="600"
        frameborder="0">
</iframe>
```

### Fetching and embedding with JavaScript:
```javascript
// Fetch SVG content
const response = await fetch('http://localhost:8000/api/workflow/gcd/svg');
const svgText = await response.text();

// Insert into page
document.getElementById('workflow-container').innerHTML = svgText;
```

---

## Error Handling

All endpoints return appropriate HTTP status codes:

- **200 OK**: Success
- **404 Not Found**: Workflow or version not found
- **500 Internal Server Error**: Server error

**Error Response Format:**
```json
{
  "error": "Workflow not found",
  "id": "nonexistent"
}
```

---

## CORS

CORS is enabled for all origins in development mode to support frontend development on different ports.

---

## Integration Guide

### For VisFlow Integration:

1. **List available workflows:**
   ```javascript
   const workflows = await fetch('http://localhost:8000/api/workflows').then(r => r.json());
   ```

2. **Display workflow SVG:**
   ```javascript
   const workflowId = 'gcd';
   const versionId = 50;

   // Use SVG directly (recommended)
   const svgUrl = `http://localhost:8000/api/workflow/${workflowId}/version/${versionId}/svg`;
   document.getElementById('workflow').innerHTML =
     `<img src="${svgUrl}" alt="Workflow ${versionId}" />`;
   ```

3. **Get workflow metadata:**
   ```javascript
   const metadata = await fetch(`http://localhost:8000/api/workflow/${workflowId}/versions`)
     .then(r => r.json());

   // Access versions and tags
   console.log(`Workflow has ${metadata.count} versions`);
   console.log(`Tagged versions:`, metadata.tags);
   ```

4. **Display version tree:**
   ```javascript
   const treeUrl = `http://localhost:8000/api/workflow/${workflowId}/tree/svg`;
   document.getElementById('tree').innerHTML =
     `<object data="${treeUrl}" type="image/svg+xml"></object>`;
   ```

---

## Recent Fixes and Improvements

### SVG Rendering Enhancements

1. **Workflow Module Boxes** ([workflow_svg.jl:231-235](../src/rendering/workflow_svg.jl#L231-L235))
   - Fixed dynamic sizing for long module names
   - Calculates text width in final scaled coordinates: `text_width / scale`
   - Modules like "vtkStructuredPointsReader" now display correctly
   - Boxes expand to fit labels without cutting off text

2. **Version Tree Ellipses** ([version_tree_svg.jl:272-276](../src/rendering/version_tree_svg.jl#L272-L276))
   - Fixed sizing for tag labels
   - Dynamic text width calculation: `length(label) * 7.0 + 20.0`
   - Uses maximum of computed node width or text width
   - Long tag names like "color and opacity" fit properly

### Version Tree Features

- **Terse graph rendering**: Collapses long linear version chains for cleaner visualization
- **Visual hierarchy**: Different colors for tagged, current, and regular versions
- **Smart labeling**: Shows tag names instead of version numbers when available
- **Clear relationships**: Solid lines for direct relationships, dashed for collapsed sequences

---

## Testing Examples

Complete testing workflow:

```bash
# 1. Start server
cd julia/backend
./start.sh

# 2. Wait for server to start
sleep 5

# 3. Test endpoints
curl http://localhost:8000/health

# 4. List workflows
curl http://localhost:8000/api/workflows | jq '.workflows[].name'

# 5. Get workflow (current version)
curl http://localhost:8000/api/workflow/gcd | jq '.modules | length'

# 6. Get workflow SVG
curl http://localhost:8000/api/workflow/gcd/svg > /tmp/gcd.svg
open /tmp/gcd.svg

# 7. Get specific version
curl http://localhost:8000/api/workflow/gcd/version/50 | jq '.version_id'

# 8. Get version metadata
curl http://localhost:8000/api/workflow/gcd/versions | jq '.count, .tags'

# 9. Get version tree SVG
curl http://localhost:8000/api/workflow/gcd/tree/svg > /tmp/gcd_tree.svg
open /tmp/gcd_tree.svg

# 10. Open demos
open http://localhost:8000/demo
open http://localhost:8000/tree-demo
```

---

## Performance Notes

- SVG rendering is done on-demand (not cached)
- Version reconstruction happens on-demand using action replay
- Large workflows (100+ modules) render in ~100-200ms
- Version trees with 100+ versions render in ~50-100ms
- No database required - reads directly from .vt files

---

## Troubleshooting

### Server won't start
```bash
# Check if port 8000 is in use
lsof -i :8000

# Kill existing processes
pkill -f "julia.*server.jl"

# Restart
cd julia/backend && ./start.sh
```

### SVG not rendering
- Check that the .vt file exists in `julia/examples/`
- Verify version ID exists: `curl http://localhost:8000/api/workflow/ID/versions | jq '.versions[].id'`
- Check server logs for errors

### CORS issues
- CORS is enabled by default in development mode
- For production, configure CORS in `server.jl`

---

## See Also

- [README.md](README.md) - Quick start guide
- [SVG_API_SUMMARY.md](SVG_API_SUMMARY.md) - SVG endpoint details
- [../docs/RENDERING.md](../docs/RENDERING.md) - Rendering implementation details
