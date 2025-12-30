# Backend Status & Enhancement Plan

## Current Backend Implementation

VisTrailsJL has **two backend implementations**:

### 1. HTTP.jl Backend ([`julia/backend/http_server.jl`](../backend/http_server.jl)) ✅ Recommended
- Lightweight, fast HTTP server
- Pure Julia implementation
- 293 lines, well-structured
- CORS enabled

### 2. Genie.jl Backend ([`julia/backend/server.jl`](../backend/server.jl) + [`routes.jl`](../backend/routes.jl))
- Full-featured web framework
- More dependencies
- Similar functionality to HTTP.jl version

## Implemented API Endpoints

### ✅ Workflow Management
| Endpoint | Method | Description | Status |
|----------|--------|-------------|--------|
| `/health` | GET | Health check | ✅ Working |
| `/api/workflows` | GET | List all workflows | ✅ Working |
| `/api/workflow/:id` | GET | Get workflow metadata | ✅ Working |
| `/api/workflow/:id/json` | GET | Get current pipeline as JSON | ✅ Working |
| `/api/workflow/:id/version/:vid/json` | GET | Get specific version as JSON | ✅ Working |

### ✅ Visualization
| Endpoint | Method | Description | Status |
|----------|--------|-------------|--------|
| `/api/workflow/:id/tree/svg` | GET | Version tree SVG | ✅ Working |
| `/api/workflow/:id/version/:vid/svg` | GET | Pipeline SVG for version | ✅ Working |

### ✅ Version Management
| Endpoint | Method | Description | Status |
|----------|--------|-------------|--------|
| `/api/workflow/:id/versions` | GET | List all versions (Genie only) | ✅ Working |

## Features Working

✅ **Read Operations:**
- Load .vt files
- Parse version trees
- Reconstruct specific versions
- Render SVG visualizations
- Export to JSON

✅ **Data Serialization:**
- Pipeline → JSON with modules, connections
- Includes module positions (if available)
- Port definitions with types
- Parameters and annotations

✅ **CORS Support:**
- Enabled for frontend development
- Allows cross-origin requests

## Missing / Needs Enhancement

### ❌ Write Operations (Critical for Git Integration)

**Not Implemented:**
- ❌ Create new workflows
- ❌ Modify existing workflows (add/remove modules)
- ❌ Create new versions
- ❌ Save changes to .vt files
- ❌ Execute workflows via API
- ❌ Get execution results

**What's Needed for Git Integration:**
```
POST /api/workflow                    # Create new workflow
PUT /api/workflow/:id                 # Update workflow metadata
POST /api/workflow/:id/version        # Create new version
PUT /api/workflow/:id/version/:vid    # Update version
POST /api/workflow/:id/execute        # Execute workflow
GET /api/workflow/:id/execution/:eid  # Get execution results
```

### ❌ Notebook Workflow Support

**Not Implemented:**
- ❌ Load notebook workflows (.ipynb)
- ❌ Execute notebook pipelines
- ❌ Save notebook outputs
- ❌ Notebook → .vt conversion
- ❌ .vt → Notebook conversion

**What's Needed:**
```
GET /api/notebook/:id                 # Get notebook workflow
POST /api/notebook/:id/execute        # Execute notebook
GET /api/notebook/:id/outputs         # Get saved outputs
POST /api/workflow/:id/to-notebook    # Convert .vt to notebook
POST /api/notebook/:id/to-vt          # Convert notebook to .vt
```

### ❌ Package Management

**Not Implemented:**
- ❌ List available packages
- ❌ Load package notebooks
- ❌ Get module descriptors
- ❌ Module introspection API

**What's Needed:**
```
GET /api/packages                     # List packages
GET /api/package/:id                  # Get package info
GET /api/package/:id/modules          # List modules in package
GET /api/module/:package/:name        # Get module descriptor
```

### ❌ Authentication & Authorization

**Not Implemented:**
- ❌ User authentication
- ❌ Access control
- ❌ API keys
- ❌ Rate limiting

### ❌ Git Integration (Key for Version Control)

**Not Implemented:**
- ❌ Git repository initialization
- ❌ Commit workflow changes
- ❌ Pull workflow history
- ❌ Push to remote
- ❌ Branch management
- ❌ Diff between versions

**What's Needed:**
```
POST /api/git/init                    # Initialize git repo
POST /api/git/commit                  # Commit changes
GET /api/git/log                      # Get commit history
GET /api/git/diff/:v1/:v2            # Diff between versions
POST /api/git/push                    # Push to remote
GET /api/git/branches                 # List branches
```

### 🔄 Partial Implementation

**Database/Storage:**
- Currently: Reads from `examples/` directory only
- Needed: Proper storage backend (filesystem, database, or git)

**Error Handling:**
- Currently: Basic try/catch
- Needed: Structured error responses, validation

**Testing:**
- Currently: No backend tests
- Needed: Integration tests, API tests

## Enhancement Priority

### Phase 1: Execution Support (High Priority) 🔥
Enable running workflows via API:

1. **Execute Endpoint**
   ```julia
   POST /api/workflow/:id/execute
   Body: { "parameters": {"in_a": 5, "in_b": 3}, "version": 37 }
   Response: { "execution_id": "uuid", "status": "running" }
   ```

2. **Execution Results**
   ```julia
   GET /api/execution/:id
   Response: { "status": "completed", "outputs": {...}, "logs": [...] }
   ```

3. **Execution History**
   ```julia
   GET /api/workflow/:id/executions
   Response: [{ "id": "uuid", "timestamp": ..., "status": ... }]
   ```

### Phase 2: Write Operations (High Priority) 🔥
Enable workflow modification:

1. **Create Workflow**
   ```julia
   POST /api/workflow
   Body: { "name": "new_workflow", "modules": [...], "connections": [...] }
   ```

2. **Modify Workflow**
   ```julia
   PUT /api/workflow/:id/version/:vid
   Body: { "add_modules": [...], "remove_modules": [...], "add_connections": [...] }
   ```

3. **Save to File**
   ```julia
   POST /api/workflow/:id/save
   Response: { "path": "workflows/my_workflow.vt", "version": 38 }
   ```

### Phase 3: Git Integration (Critical for Vision) 🎯
Enable git-native version control:

1. **Git Backend**
   - Use LibGit2.jl for git operations
   - Commit workflow changes automatically
   - Import git history as VisTrails version tree

2. **Diff Engine**
   - Compare pipeline JSON between versions
   - Generate VisTrails actions from diffs
   - Support three-way merge

3. **GitHub Integration**
   - OAuth authentication
   - Push/pull from GitHub
   - Pull request workflow

### Phase 4: Notebook Support (Medium Priority)
Enable notebook workflows:

1. **Notebook Execution**
   - Execute `#|` directive workflows
   - Save outputs back to notebook
   - Image embedding

2. **Conversion API**
   - .vt ↔ notebook bidirectional
   - Preserve all metadata

### Phase 5: Package Management (Low Priority)
Enable package discovery:

1. **Package Registry**
   - List installed packages
   - Module introspection
   - Package documentation

2. **Dynamic Loading**
   - Load packages on demand
   - Hot reload for development

## Recommended Implementation Order

### Week 1-2: Execution Support
```julia
# Priority endpoints
POST /api/workflow/:id/execute
GET /api/execution/:id
GET /api/execution/:id/outputs
```

**Why first?**: Enables interactive workflows, validates the pipeline execution system

### Week 3-4: Write Operations
```julia
# Priority endpoints
POST /api/workflow
POST /api/workflow/:id/version
PUT /api/workflow/:id/module
DELETE /api/workflow/:id/module/:mid
```

**Why second?**: Enables workflow creation/modification, necessary for git integration

### Week 5-6: Git Integration (Phase 1)
```julia
# Priority endpoints
POST /api/git/commit
GET /api/git/log
GET /api/git/diff/:v1/:v2
```

**Why third?**: Core value proposition - git-native version control

### Week 7-8: Notebook Support
```julia
# Priority endpoints
POST /api/notebook/:id/execute
POST /api/workflow/:id/to-notebook
```

**Why fourth?**: Alternative workflow creation method

## Technical Recommendations

### Use HTTP.jl Backend
- Lighter weight than Genie
- Sufficient for API needs
- Easier to maintain

### Add WebSocket Support
For real-time execution updates:
```julia
WS /api/workflow/:id/execute/stream
→ {"type": "log", "message": "Module 1 executing..."}
→ {"type": "output", "module_id": 1, "port": "value", "data": 42}
→ {"type": "complete", "execution_id": "uuid"}
```

### Use JSON Schema Validation
- Validate request bodies
- Generate API documentation
- Client SDKs

### Add Metrics/Logging
- Prometheus metrics
- Structured logging
- Performance monitoring

## Current Usage

Start the backend:
```bash
cd julia
julia --project=. backend/http_server.jl
```

Test endpoints:
```bash
curl http://localhost:8000/health
curl http://localhost:8000/api/workflows
curl http://localhost:8000/api/workflow/gcd/json
```

## Summary

**What Works:** ✅
- Read-only API for .vt files
- Version tree visualization
- Pipeline JSON export
- SVG rendering

**What's Needed:** ❌
- Execution API (critical)
- Write operations (critical)
- Git integration (strategic)
- Notebook support (nice-to-have)

**Recommendation:**
Focus on **execution support first**, then **write operations**, then **git integration**. This provides immediate value while building toward the git-native vision.

The backend foundation is solid - it just needs these write/execute capabilities to become a complete workflow management system!
