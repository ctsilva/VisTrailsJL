# VisTrailsJL v1.0 Roadmap

Based on analysis of [The Architecture of Open Source Applications - VisTrails](https://aosabook.org/en/v1/vistrails.html) and current implementation status.

## Vision for v1.0

**Goal**: A functional, web-based workflow management system that can:
1. Load existing Python VisTrails .vt files
2. Create and edit workflows through a web interface
3. Execute workflows with Julia and Python code
4. Track provenance and version history
5. Visualize workflows and results

## Current Implementation Status

### ✅ Already Complete (Foundation)

**Core Architecture** (100%)
- ✅ Pipeline/Workflow DAG representation
- ✅ Module system (descriptors, instances, registry)
- ✅ Port system (input/output ports, port specs)
- ✅ Connection system
- ✅ Vistrail (version control structure)

**Persistence** (90%)
- ✅ Read .vt files (XML and ZIP formats)
- ✅ Action replay system
- ✅ JSON export/import
- ✅ Lightweight rendering (no package dependencies)
- ⚠️ Write .vt files (not implemented)

**Execution Engine** (85%)
- ✅ Pipeline interpreter
- ✅ Topological sorting
- ✅ Dependency resolution
- ✅ Module execution
- ✅ Result caching
- ✅ Execution logging/provenance
- ⚠️ Execution control (pause, cancel, step)

**Visualization** (100%)
- ✅ SVG workflow rendering
- ✅ SVG version tree rendering
- ✅ Dynamic module sizing
- ✅ Port positioning
- ✅ Connection routing (Bezier curves)
- ✅ Terse mode for version trees

**Packages** (60%)
- ✅ Basic package (HTTPFile, PythonSource, constants, data structures, I/O)
- ✅ Julia package (JuliaSource)
- ✅ PythonCalc package
- ✅ Control flow package (If, While, And, Or, Not)
- ⚠️ File I/O modules (File, WriteFile, Directory)
- ⚠️ Visualization packages (would use Julia plotting, not matplotlib)

**Backend API** (75%)
- ✅ HTTP.jl server
- ✅ REST endpoints for workflows
- ✅ JSON pipeline export
- ✅ SVG rendering endpoints
- ⚠️ Workflow editing endpoints (create, update, delete)
- ⚠️ Execution control endpoints

**Frontend** (0%)
- ❌ Web-based workflow editor
- ❌ Module palette
- ❌ Parameter editor
- ❌ Version tree browser
- ❌ Execution controls
- ❌ Result viewer

### Innovation Beyond Python VisTrails

The Julia implementation already has several improvements:

1. **Lightweight Rendering** - Render workflows without installing all module packages
2. **JSON Format** - Human-readable, git-friendly .vt export/import
3. **HTTP API** - RESTful API for web integration
4. **Native Julia Execution** - JuliaSource module (Python doesn't have this!)
5. **Modern Backend** - HTTP.jl instead of XML-RPC

## v1.0 Scope Definition

### Core Principle: Minimum Viable Workflow System

v1.0 should enable a complete workflow lifecycle:
- **Create** workflows from scratch
- **Edit** existing workflows
- **Execute** workflows
- **Track** provenance
- **Visualize** results

### In Scope for v1.0

#### 1. Web-Based Workflow Editor ⭐ CRITICAL

**Capabilities:**
- Visual workflow canvas (drag, pan, zoom)
- Add modules from palette
- Create connections between ports
- Delete modules and connections
- Move modules to rearrange layout
- Save workflows

**Technical Approach:**
- **Option A** (Recommended): Fork and integrate [VisFlow](https://github.com/yubowenok/visflow)
  - Existing dataflow editor in TypeScript/React
  - You already have analysis docs on this
  - Needs adaptation to VisTrails data model

- **Option B**: Use React Flow library
  - More modern, actively maintained
  - Need to build VisTrails-specific features

- **Option C**: Build custom editor with D3.js/SVG
  - Most control, most work

**Deliverables:**
- Interactive workflow editor
- Module palette with search/filter
- Connection drawing with port snapping
- Layout preservation (save positions)
- Undo/redo support

#### 2. Parameter Editing

**Capabilities:**
- Click module to open parameter panel
- Edit string, integer, float, boolean parameters
- Validate parameter values
- Apply changes to workflow
- See parameter history

**Technical Implementation:**
- Parameter editor sidebar/modal
- Type-specific input widgets
- Real-time validation
- Update workflow JSON

**Deliverables:**
- Parameter editor UI component
- API endpoint for updating parameters
- Type-safe parameter validation

#### 3. Workflow Execution UI

**Capabilities:**
- Execute workflow with one click
- See execution progress (which modules running)
- Cancel running execution
- View execution results
- See cached vs recomputed modules

**Technical Implementation:**
- Execute button in UI
- WebSocket or polling for execution status
- Display module execution state (pending/running/complete/error/cached)
- Result viewer panel

**Deliverables:**
- Execution control UI
- Progress visualization
- Error display
- Result viewer (text/JSON for v1.0)

#### 4. Version Tree Navigation

**Capabilities:**
- Browse version history
- Click version to load that workflow
- See tagged versions
- Create new version from current
- Tag versions with names

**Technical Implementation:**
- Render version tree SVG in UI
- Make SVG interactive (clickable nodes)
- Version switcher dropdown
- Tag editing interface

**Deliverables:**
- Interactive version tree viewer
- Version navigation
- Tag management UI

#### 5. Write .vt Files

**Capabilities:**
- Save edited workflows back to .vt format
- Create new .vt files from scratch
- Maintain compatibility with Python VisTrails
- Preserve all metadata

**Technical Implementation:**
- XML serialization (reverse of current parser)
- Action generation from pipeline changes
- ZIP archive creation
- Vistrail metadata preservation

**Deliverables:**
- `export_vistrail()` function
- XML generation for all element types
- ZIP packaging
- Test with Python VisTrails (round-trip test)

#### 6. Essential File I/O Modules

**Modules to Implement:**
- `File` - Read local files
- `WriteFile` - Write content to files
- `Directory` - List directory contents
- `Path` - Path manipulation (join, basename, dirname)

**Why Essential:**
- Most workflows need file I/O
- Currently can only use HTTPFile
- Enables batch processing workflows

**Deliverables:**
- Four new modules in basic package
- Documentation and examples
- Tests

#### 7. Basic Project Management

**Capabilities:**
- List available workflows
- Create new workflow
- Open existing workflow
- Save workflow
- Save As (duplicate)

**Technical Implementation:**
- Workflow browser UI
- File picker integration
- Autosave support
- Recent files list

**Deliverables:**
- Project browser UI
- Workflow CRUD operations
- File management

### Out of Scope for v1.0

These features are important but can wait for v1.1+:

#### Deferred to v1.1+

- **Advanced Execution Control**
  - Execute from selected module
  - Step-through execution
  - Breakpoints

- **Advanced Visualization**
  - Inline result preview for images/plots
  - Interactive plots
  - Custom result renderers

- **Workflow Comparison**
  - Visual diff between versions
  - Side-by-side comparison
  - Merge workflows

- **Subworkflows**
  - Nested workflows
  - Workflow as module
  - Hierarchical execution

- **Advanced Packages**
  - Plots.jl integration
  - Makie.jl integration
  - DataFrames modules
  - Distributed computing

- **Collaboration Features**
  - Multi-user editing
  - Workflow sharing
  - Comments and annotations

- **Performance Optimization**
  - Parallel module execution
  - Distributed execution
  - Streaming data

- **Developer Tools**
  - Module development wizard
  - Package creation tools
  - Debug mode

#### Never in Scope (Python VisTrails Legacy)

- Qt-based desktop GUI
- Spreadsheet view (mashups better served by web UI)
- XML-RPC server (using HTTP/REST instead)

## Implementation Plan

### Phase 1: Backend Completion (2-3 weeks)

**Goal**: Complete backend API for workflow editing and execution

**Tasks:**

1. **Write .vt Files** (Week 1)
   - Implement XML serialization for all types
   - Create ZIP archives
   - Test round-trip (load, save, load again)
   - Verify compatibility with Python VisTrails

2. **File I/O Modules** (Week 1)
   - Implement File, WriteFile, Directory, Path modules
   - Write tests
   - Add documentation

3. **Workflow Editing API** (Week 2)
   - POST /api/workflow - Create new workflow
   - PUT /api/workflow/:id/module - Add/update module
   - DELETE /api/workflow/:id/module/:module_id - Delete module
   - PUT /api/workflow/:id/connection - Add connection
   - DELETE /api/workflow/:id/connection/:conn_id - Delete connection
   - PUT /api/workflow/:id/module/:module_id/parameter - Update parameter

4. **Execution Control API** (Week 2)
   - POST /api/workflow/:id/execute - Execute workflow
   - GET /api/workflow/:id/execution/:exec_id/status - Check status
   - DELETE /api/workflow/:id/execution/:exec_id - Cancel execution
   - GET /api/workflow/:id/execution/:exec_id/results - Get results

5. **Version Management API** (Week 3)
   - POST /api/workflow/:id/version - Create new version
   - PUT /api/workflow/:id/version/:version_id/tag - Add/update tag
   - GET /api/workflow/:id/diff/:v1/:v2 - Compare versions

**Deliverables:**
- Complete REST API for workflow lifecycle
- File I/O modules
- .vt file writing capability
- API documentation

### Phase 2: Frontend Foundation (3-4 weeks)

**Goal**: Build basic web UI for workflow viewing and editing

**Tasks:**

1. **Project Setup** (Week 1)
   - Choose framework (React + React Flow OR VisFlow fork)
   - Set up build system (Vite/Webpack)
   - Create basic layout (header, sidebar, canvas, inspector)
   - Connect to backend API

2. **Workflow Viewer** (Week 1)
   - Display workflow from JSON
   - Render modules as nodes
   - Render connections as edges
   - Pan and zoom canvas
   - Module selection

3. **Workflow Editor** (Week 2)
   - Add module from palette
   - Delete modules
   - Create connections (drag from port to port)
   - Delete connections
   - Move modules
   - Save changes

4. **Parameter Editor** (Week 2)
   - Show module parameters in inspector
   - Edit string/number/boolean parameters
   - Validate inputs
   - Apply changes
   - Show parameter types

5. **Module Palette** (Week 3)
   - List all available modules by package
   - Search/filter modules
   - Drag to add to canvas
   - Show module documentation on hover

6. **Basic Execution UI** (Week 3)
   - Execute button
   - Show execution status
   - Display errors
   - Show results (text/JSON)

7. **Project Browser** (Week 4)
   - List available workflows
   - Open workflow
   - Create new workflow
   - Save/Save As
   - Delete workflow

**Deliverables:**
- Functional web UI
- Workflow editing capabilities
- Module palette
- Parameter editing
- Basic execution

### Phase 3: Version Control UI (1-2 weeks)

**Goal**: Add version tree navigation and management

**Tasks:**

1. **Version Tree Viewer** (Week 1)
   - Display version tree SVG
   - Make nodes clickable
   - Highlight current version
   - Show version tags
   - Navigate to version on click

2. **Version Management** (Week 2)
   - Create new version (save current changes)
   - Tag versions
   - Compare versions (diff display)
   - Revert to version

**Deliverables:**
- Interactive version tree
- Version navigation
- Tag management
- Version comparison

### Phase 4: Polish and Testing (2 weeks)

**Goal**: Make v1.0 production-ready

**Tasks:**

1. **Testing** (Week 1)
   - Write integration tests
   - Test with real Python VisTrails files
   - Cross-browser testing
   - Performance testing

2. **Documentation** (Week 1)
   - User guide
   - API documentation
   - Developer documentation
   - Video tutorials

3. **Polish** (Week 2)
   - UI/UX improvements
   - Error handling
   - Loading states
   - Keyboard shortcuts
   - Accessibility

4. **Deployment** (Week 2)
   - Docker containerization
   - Deployment scripts
   - Configuration management
   - Production builds

**Deliverables:**
- Test suite
- Complete documentation
- Polished UI
- Deployment package

## Success Criteria for v1.0

**v1.0 is successful if a user can:**

1. ✅ Open the web UI in a browser
2. ✅ Create a new workflow from scratch
3. ✅ Add modules to the workflow
4. ✅ Connect modules together
5. ✅ Edit module parameters
6. ✅ Execute the workflow
7. ✅ See execution results
8. ✅ Save the workflow to a .vt file
9. ✅ Load the .vt file in Python VisTrails (compatibility check)
10. ✅ View version history
11. ✅ Navigate between versions
12. ✅ Tag important versions

**Technical Requirements:**

- All Python VisTrails .vt files load correctly
- Round-trip compatibility (Julia → .vt → Python VisTrails)
- Execution produces same results as Python VisTrails
- Web UI works in Chrome, Firefox, Safari
- Response time < 1s for typical operations
- No data loss on save/load

## Timeline Estimate

**Total: 8-11 weeks (2-3 months)**

- Phase 1 (Backend): 2-3 weeks
- Phase 2 (Frontend): 3-4 weeks
- Phase 3 (Versions): 1-2 weeks
- Phase 4 (Polish): 2 weeks

**Assumptions:**
- One full-time developer
- Familiarity with Julia and web development
- No major technical blockers

**Risks:**
- VisFlow integration more complex than expected → Add 2 weeks
- .vt file writing compatibility issues → Add 1 week
- Performance issues with large workflows → Add 1 week

## Post-v1.0 Roadmap (v1.1, v1.2, ...)

### v1.1: Enhanced Execution (1-2 months)
- Execute from selected module
- Step-through execution
- Execution visualization (animated)
- Better result display (images, plots)
- Execution history

### v1.2: Collaboration (2-3 months)
- Multi-user editing
- Workflow sharing
- User authentication
- Permissions system
- Comments and annotations

### v1.3: Advanced Features (2-3 months)
- Subworkflows
- Workflow comparison/diff
- Advanced caching strategies
- Performance optimization
- Distributed execution

### v2.0: Julia Ecosystem Integration (3-4 months)
- Plots.jl package
- Makie.jl package
- DataFrames.jl integration
- Pluto.jl integration
- Package development tools

## Metrics for Success

**Usage Metrics:**
- Number of workflows created
- Number of executions per day
- Number of active users
- Average workflow size (modules, connections)

**Quality Metrics:**
- Test coverage > 80%
- No critical bugs in production
- Response time < 1s for 95% of operations
- 100% compatibility with Python VisTrails files

**Community Metrics:**
- GitHub stars
- Issues opened/closed
- Contributions from community
- Documentation page views

## Getting Started

### For Developers

1. **Backend Development**
   ```bash
   cd julia_starter
   julia --project=.
   include("backend/http_server.jl")
   ```

2. **Frontend Development**
   ```bash
   cd frontend  # To be created
   npm install
   npm run dev
   ```

3. **Run Tests**
   ```bash
   julia --project=. -e 'using Pkg; Pkg.test()'
   ```

### For Users

1. **Start the Server**
   ```bash
   docker run -p 8000:8000 vistrailsjl/server:v1.0
   ```

2. **Open Browser**
   ```
   http://localhost:8000
   ```

3. **Create Your First Workflow**
   - Click "New Workflow"
   - Drag modules from palette
   - Connect modules
   - Edit parameters
   - Execute!

## Conclusion

VisTrailsJL v1.0 will be a **functional, modern reimplementation** of VisTrails with:

✅ **Core capabilities** of Python VisTrails
✅ **Modern web interface** instead of Qt desktop
✅ **Native Julia execution** for performance
✅ **Full compatibility** with Python VisTrails files
✅ **Innovations** like lightweight rendering and JSON export

The foundation is already 70% complete. With focused effort on the web UI and workflow editing API, v1.0 is achievable in 2-3 months.

**Next immediate steps:**
1. Implement .vt file writing (1 week)
2. Add File I/O modules (1 week)
3. Choose frontend framework (React Flow vs VisFlow)
4. Build workflow editor prototype (2 weeks)
