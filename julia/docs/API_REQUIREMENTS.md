# VisTrails Web API Requirements

Comprehensive analysis of VisTrails functionality from user guide documentation to determine REST API endpoints needed for a web-based editor.

## Analysis Source
Based on `/Users/csilva/src/VisTrails/doc/usersguide/` documentation files.

## Core VisTrails Concepts

### 1. Vistrail (Version-Controlled Workflow Collection)
- A vistrail is a `.vt` file containing:
  - Multiple workflow versions
  - Version tree (DAG of versions)
  - Action history (changes between versions)
  - Tags and annotations
  - User information
  - Execution provenance

### 2. Pipeline/Workflow
- Computational graph with:
  - Modules (nodes)
  - Connections (edges)
  - Parameters
  - Layout positions

### 3. Versions
- Each edit creates a new version
- Versions form a tree structure
- Can branch and merge
- Tagged versions for important milestones

## Feature Categories (from User Guide)

### A. File Management
**From:** `getting_started.rst`

**Operations:**
- Open vistrail from file
- Open vistrail from database
- Save vistrail
- Save vistrail as (new name/location)
- Close vistrail
- Import vistrail
- Export vistrail

**API Endpoints Needed:**
```
GET    /api/vistrails                    # List available vistrails
POST   /api/vistrails                    # Create new vistrail
GET    /api/vistrails/:id                # Get vistrail metadata
PUT    /api/vistrails/:id                # Update vistrail metadata
DELETE /api/vistrails/:id                # Delete vistrail
POST   /api/vistrails/:id/export         # Export to file
POST   /api/vistrails/import             # Import from file
```

### B. Version Tree Management
**From:** `version_tree.rst`

**Operations:**
- View version tree
- Navigate to version
- Create new version (via edits)
- Tag version
- Remove tag
- Add version notes/annotations
- Compare versions (visual diff)
- Collapse/expand version sequences
- Undo/redo (navigate version tree)
- View version properties:
  - Creator
  - Creation date
  - Tag
  - Notes
  - Thumbnail

**API Endpoints Needed:**
```
GET    /api/vistrails/:id/versions              # Get version tree
GET    /api/vistrails/:id/versions/:version     # Get specific version
POST   /api/vistrails/:id/versions/:version/tag # Add/update tag
DELETE /api/vistrails/:id/versions/:version/tag # Remove tag
PUT    /api/vistrails/:id/versions/:version/notes  # Update notes
GET    /api/vistrails/:id/versions/:version/diff/:other  # Compare versions
GET    /api/vistrails/:id/versions/:version/thumbnail   # Get execution thumbnail
```

### C. Pipeline/Workflow Editing
**From:** `getting_started.rst`

**Operations:**
- View pipeline
- Add module
- Remove module
- Move module
- Configure module parameters
- Add connection
- Remove connection
- Copy/paste modules
- Group modules (subworkflow)

**API Endpoints Needed:**
```
GET    /api/vistrails/:id/pipeline/:version         # Get pipeline structure
POST   /api/vistrails/:id/pipeline/:version/modules # Add module
PUT    /api/vistrails/:id/pipeline/:version/modules/:mid  # Update module
DELETE /api/vistrails/:id/pipeline/:version/modules/:mid  # Remove module
POST   /api/vistrails/:id/pipeline/:version/connections   # Add connection
DELETE /api/vistrails/:id/pipeline/:version/connections/:cid  # Remove connection
PUT    /api/vistrails/:id/pipeline/:version/modules/:mid/position  # Update layout
PUT    /api/vistrails/:id/pipeline/:version/modules/:mid/params    # Set parameters
```

### D. Module Registry
**From:** `getting_started.rst`

**Operations:**
- List available packages
- List modules in package
- Get module descriptor (ports, parameters)
- Enable/disable packages
- Load user packages

**API Endpoints Needed:**
```
GET    /api/packages                    # List available packages
GET    /api/packages/:pkg               # Get package info
GET    /api/packages/:pkg/modules       # List modules in package
GET    /api/modules/:pkg/:name          # Get module descriptor
POST   /api/packages/:pkg/enable        # Enable package
POST   /api/packages/:pkg/disable       # Disable package
```

### E. Workflow Execution
**From:** `getting_started.rst`

**Operations:**
- Execute pipeline
- Cancel execution
- View execution progress
- View execution results
- Cache management
- Execution provenance

**API Endpoints Needed:**
```
POST   /api/vistrails/:id/execute/:version      # Execute workflow
GET    /api/vistrails/:id/execute/:version/status  # Get execution status
DELETE /api/vistrails/:id/execute/:version       # Cancel execution
GET    /api/vistrails/:id/execute/:version/results # Get execution results
GET    /api/vistrails/:id/provenance/:version   # Get execution provenance
POST   /api/vistrails/:id/cache/clear           # Clear cache
```

### F. Search/Query
**From:** `querying.rst`

**Operations:**
- Text-based query
- Query by example (visual)
- Search by:
  - Module name
  - Parameter value
  - Date range
  - User
  - Tag
  - Notes content
- Search scope:
  - Current version
  - Current vistrail
  - All vistrails

**API Endpoints Needed:**
```
POST   /api/search/text                 # Text-based search
POST   /api/search/visual               # Query by example
GET    /api/search/results/:query_id    # Get search results
```

### G. Parameter Exploration
**From:** `parameter_exploration.rst`

**Operations:**
- Select parameters for exploration
- Define parameter sets/ranges
- Execute all combinations
- View results in spreadsheet
- Compare results

**API Endpoints Needed:**
```
POST   /api/vistrails/:id/explore/:version      # Create exploration
GET    /api/vistrails/:id/explore/:eid          # Get exploration definition
POST   /api/vistrails/:id/explore/:eid/execute  # Run exploration
GET    /api/vistrails/:id/explore/:eid/results  # Get all results
```

### H. Provenance Browser
**From:** Getting Started (Provenance mode)

**Operations:**
- View execution history
- See which versions were executed
- View execution results
- Color-code modules by execution result
- See cached vs. recomputed

**API Endpoints Needed:**
```
GET    /api/vistrails/:id/provenance             # Get all executions
GET    /api/vistrails/:id/provenance/:exec_id    # Get execution details
GET    /api/vistrails/:id/provenance/:exec_id/modules  # Module exec status
```

### I. Mashups
**From:** `getting_started.rst`

**Operations:**
- Create mashup (simplified interface)
- Define exposed parameters
- Create parameter widgets
- Execute mashup
- Share mashup

**API Endpoints Needed:**
```
POST   /api/vistrails/:id/mashups                # Create mashup
GET    /api/vistrails/:id/mashups/:mid           # Get mashup definition
PUT    /api/vistrails/:id/mashups/:mid           # Update mashup
DELETE /api/vistrails/:id/mashups/:mid           # Delete mashup
POST   /api/vistrails/:id/mashups/:mid/execute   # Execute mashup
```

### J. Annotations
**From:** `version_tree.rst`

**Operations:**
- Add notes to version
- Add notes to module
- Add notes to connection
- Add notes to parameter
- View/edit annotations

**API Endpoints Needed:**
```
PUT    /api/vistrails/:id/versions/:version/annotations        # Version notes
PUT    /api/vistrails/:id/pipeline/:version/modules/:mid/annotations  # Module notes
GET    /api/vistrails/:id/annotations                          # Get all annotations
```

### K. Rendering/Visualization
**From:** `version_tree.rst`, Getting Started

**Operations:**
- Render version tree as SVG
- Render pipeline as SVG
- Generate thumbnails
- Export as image

**API Endpoints Needed:**
```
GET    /api/vistrails/:id/render/tree            # Version tree SVG
GET    /api/vistrails/:id/render/pipeline/:version  # Pipeline SVG
GET    /api/vistrails/:id/render/thumbnail/:version # Thumbnail image
```

### L. User Management
**From:** Version tree (user tracking)

**Operations:**
- Track user who created version
- Filter by user
- User preferences

**API Endpoints Needed:**
```
GET    /api/users                        # List users
GET    /api/users/:uid                   # Get user info
PUT    /api/users/:uid/preferences       # Update preferences
```

### M. Workspace Management
**From:** `getting_started.rst`

**Operations:**
- List open vistrails
- Switch between vistrails
- Manage tabs
- Recent vistrails

**API Endpoints Needed:**
```
GET    /api/workspace                    # Get workspace state
PUT    /api/workspace                    # Update workspace state
GET    /api/workspace/recent             # Recent vistrails
```

## Priority Classification

### Priority 1: MVP (Must Have) - 8 weeks
Essential for basic workflow editing with provenance.

**File Management:**
- ✅ Open/save vistrail
- ✅ Create new vistrail

**Version Management:**
- ✅ Get version tree
- ✅ Navigate to version
- ✅ Tag version
- ✅ Add notes

**Pipeline Editing:**
- ✅ View pipeline
- ✅ Add/remove modules
- ✅ Add/remove connections
- ✅ Set parameters
- ✅ Update layout

**Module Registry:**
- ✅ List packages
- ✅ List modules
- ✅ Get module descriptors

**Rendering:**
- ✅ Render version tree
- ✅ Render pipeline

**Execution:**
- ✅ Execute workflow
- ✅ View results

### Priority 2: Enhanced (Should Have) - 4 weeks
Important features for productive use.

**Version Management:**
- ⚠️ Visual diff
- ⚠️ Version comparison

**Provenance:**
- ⚠️ Execution history
- ⚠️ Module execution status

**Search:**
- ⚠️ Text-based search
- ⚠️ Search by module

**Annotations:**
- ⚠️ Module annotations
- ⚠️ Connection annotations

### Priority 3: Advanced (Nice to Have) - 8+ weeks
Advanced features for power users.

**Parameter Exploration:**
- 🔮 Define explorations
- 🔮 Execute combinations
- 🔮 Compare results

**Mashups:**
- 🔮 Create mashups
- 🔮 Simplified interfaces

**Advanced Search:**
- 🔮 Query by example
- 🔮 Complex queries

**Collaboration:**
- 🔮 Multi-user editing
- 🔮 User tracking
- 🔮 Sharing

### Priority 4: Future (Maybe) - TBD
Features that might not be needed.

- 🚫 Database backend (file-based OK)
- 🚫 Spreadsheet integration (separate viz)
- 🚫 Job submission (HPC)
- 🚫 Streaming workflows

## Recommended MVP API Surface

### Minimal Viable API (Priority 1 Only)

```javascript
// Vistrail Management
GET    /api/vistrails                    
POST   /api/vistrails                    
GET    /api/vistrails/:id                
PUT    /api/vistrails/:id                
DELETE /api/vistrails/:id                

// Version Tree
GET    /api/vistrails/:id/versions       
GET    /api/vistrails/:id/versions/:ver  
PUT    /api/vistrails/:id/versions/:ver/tag
PUT    /api/vistrails/:id/versions/:ver/notes

// Pipeline Editing
GET    /api/vistrails/:id/pipeline/:ver
POST   /api/vistrails/:id/pipeline/:ver/modules
DELETE /api/vistrails/:id/pipeline/:ver/modules/:mid
POST   /api/vistrails/:id/pipeline/:ver/connections
DELETE /api/vistrails/:id/pipeline/:ver/connections/:cid
PUT    /api/vistrails/:id/pipeline/:ver/modules/:mid/position
PUT    /api/vistrails/:id/pipeline/:ver/modules/:mid/params

// Module Registry
GET    /api/packages
GET    /api/packages/:pkg/modules
GET    /api/modules/:pkg/:name

// Execution
POST   /api/vistrails/:id/execute/:ver
GET    /api/vistrails/:id/execute/:ver/status
GET    /api/vistrails/:id/execute/:ver/results

// Rendering
GET    /api/vistrails/:id/render/tree
GET    /api/vistrails/:id/render/pipeline/:ver
```

**Total MVP Endpoints: ~20**

This covers:
- ✅ Create and edit workflows
- ✅ Full version control
- ✅ Tagging and notes
- ✅ Module registry
- ✅ Execution
- ✅ Visualization

## Implementation Notes

### VisTrailsJL Already Has:
- ✅ All version tree logic
- ✅ Action replay
- ✅ Pipeline structure
- ✅ Module registry
- ✅ Execution engine
- ✅ SVG rendering

### Need to Build:
- 🔨 REST API layer (Genie.jl)
- 🔨 WebSocket for real-time updates
- 🔨 Session management
- 🔨 File upload/download

### Don't Need:
- ❌ Database (file-based works)
- ❌ User authentication (single-user MVP)
- ❌ Complex querying (simple search OK)
- ❌ Mashups (future)

## Next Steps

1. **Implement Priority 1 API** (2 weeks)
   - File management
   - Version tree
   - Pipeline editing
   - Module registry
   - Execution
   - Rendering

2. **Build Frontend** (4 weeks)
   - Node graph editor
   - Version tree view
   - Module palette
   - Properties panel
   - Execute button

3. **Integration** (2 weeks)
   - WebSocket real-time
   - File sync
   - Error handling

**Total: 8 weeks to working provenance-enabled workflow editor!**

## References

- `getting_started.rst` - Basic operations
- `version_tree.rst` - Version management, tagging, annotations
- `querying.rst` - Search functionality
- `parameter_exploration.rst` - Parameter sweeps
- `controlflow.rst` - Conditional execution
- `provenance.rst` - Execution tracking
