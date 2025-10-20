# VisFlow Integration Analysis

Comprehensive analysis of using VisFlow's frontend with VisTrailsJL backend for a provenance-enabled workflow editor.

## VisFlow Architecture Analysis

### Technology Stack

**Frontend (Client):**
- **Framework:** Vue.js 2.5 + TypeScript
- **State Management:** Vuex (centralized store)
- **Router:** Vue Router
- **UI Components:** Bootstrap-Vue
- **Visualization:** D3.js
- **Animation:** GSAP (GreenSock)
- **Build Tool:** Vue CLI 3

**Backend (Server):**
- **Framework:** Express.js (Node.js)
- **Database:** MongoDB
- **API:** REST endpoints
- **File Storage:** Filesystem (JSON files)

### Core Components

**1. Dataflow Canvas (`dataflow-canvas/`):**
- Main workflow editing surface
- Drag-and-drop nodes
- Pan and zoom
- Selection box
- Canvas coordinate system

**2. Node System (`node/`):**
- Node component (visual representation)
- Node types (various processing nodes)
- Node state management
- History tracking

**3. Edge System (`edge/`):**
- Connections between nodes
- Drawing edges
- Port connections

**4. Port System (`port/`):**
- Input/output ports on nodes
- Type system
- Connection validation

### API Structure (Server)

**Diagram API (`/api/diagram/`):**
```typescript
POST /api/diagram/list/        // List user's diagrams
POST /api/diagram/load/        // Load diagram JSON
POST /api/diagram/save/        // Save diagram
POST /api/diagram/save-as/     // Save as new diagram
POST /api/diagram/delete/      // Delete diagram
```

**Data Format:**
- Diagrams stored as JSON files
- Metadata in MongoDB (name, user, timestamp)
- File content is the workflow structure

## Integration Assessment

### ✅ What Would Work Well

#### 1. Visual Editor Components (90% Reusable)
The entire visual editing interface is **highly modular and well-designed**:

- **DataflowCanvas** - Perfect for workflow editing
  - Pan/zoom already implemented
  - Selection already works
  - Drag-and-drop ready
  - Animation built-in

- **Node/Edge/Port System** - Exactly what we need
  - Visual nodes with ports
  - Connection drawing
  - Port type validation
  - Drag connections between ports

- **UI Components** - Professional and complete
  - Module palette
  - Properties panels
  - Menus and toolbars
  - Modal dialogs

**Compatibility:** ✅ Can be adapted to VisTrails with minimal changes

#### 2. State Management (Vuex Store)
VisFlow uses Vuex for centralized state management:

```
store/
├── dataflow/      # Workflow state
├── interaction/   # UI interaction state
├── history/       # Undo/redo
└── user/          # User state
```

**Compatibility:** ✅ Can be modified to use VisTrailsJL state

#### 3. TypeScript Codebase
- Strong typing throughout
- Good code organization
- Well-documented interfaces

**Compatibility:** ✅ Makes integration easier and safer

### ❌ What Would Need Replacement

#### 1. Backend (Complete Replacement)
**Current:** Node.js + Express + MongoDB
**Needed:** Julia + Genie.jl + VisTrailsJL

**Why Replace:**
- MongoDB not needed (file-based works better)
- VisTrailsJL has superior provenance
- No version control in VisFlow

**Effort:** Rewrite all server APIs

#### 2. Data Model (Significant Changes)
**VisFlow Model:**
```json
{
  "nodes": [...],
  "edges": [...],
  "metadata": {...}
}
```

**VisTrails Model:**
```xml
<vistrail>
  <actions>...</actions>
  <workflows>...</workflows>
  <tags>...</tags>
</vistrail>
```

**Why Change:**
- VisTrails uses action-based versioning
- Need full provenance tracking
- Version tree instead of single workflow

**Effort:** Adapt frontend to understand VisTrails format

#### 3. History System (Enhancement Required)
**VisFlow:** Simple undo/redo stack
**VisTrails:** Full version tree with branching

**Why Change:**
- VisFlow's history is session-only
- VisTrails has persistent version control
- Need version tree visualization

**Effort:** Replace history UI with version tree

### ⚠️ Challenges and Concerns

#### 1. Vue.js 2.5 (Outdated)
VisFlow uses Vue 2.5 (from 2018)
- Current Vue is 3.x (2024)
- Some dependencies may be outdated
- Security updates needed

**Options:**
- Use as-is (faster, but outdated)
- Upgrade to Vue 3 (cleaner, but time-consuming)

**Recommendation:** Use as-is for MVP, upgrade later

#### 2. MongoDB Dependency
VisFlow requires MongoDB for metadata
- Not needed for VisTrails (.vt files have everything)
- Adds deployment complexity

**Solution:** Remove MongoDB, use file-based storage

#### 3. Different Design Philosophy
**VisFlow:** Single workflow per diagram
**VisTrails:** Version tree of workflows

**Impact:** Significant UI changes needed for version navigation

#### 4. Licensing
**VisFlow:** BSD-3-Clause license ✅
**VisTrails:** BSD-style license ✅

**Compatibility:** ✅ No license conflicts!

## Integration Strategy

### Option 1: Fork and Adapt VisFlow (Recommended)

**Approach:**
1. Fork VisFlow repository
2. Keep frontend (Vue components)
3. Replace backend with Genie.jl + VisTrailsJL
4. Adapt data model to VisTrails format
5. Add version tree UI

**Timeline: 6-8 weeks**

**Breakdown:**
- Week 1-2: Backend API (Genie.jl)
  - Implement VisTrails API endpoints
  - File upload/download
  - Version management

- Week 3-4: Frontend Adaptation
  - Modify Vuex store for VisTrails
  - Update data serialization
  - Connect to new API

- Week 5-6: Version Tree UI
  - Add version tree component
  - Tagging interface
  - Version comparison

- Week 7-8: Testing and Polish
  - Integration testing
  - Bug fixes
  - Documentation

**Pros:**
- ✅ Professional UI already built
- ✅ Most code reusable (60-70%)
- ✅ Proven workflow editor
- ✅ Good TypeScript codebase

**Cons:**
- ❌ Need to learn Vue.js
- ❌ Backend rewrite required
- ❌ Data model translation
- ❌ Vue 2.5 is old

### Option 2: Extract Components Only

**Approach:**
1. Extract just the dataflow canvas
2. Rewrite in React (for modern stack)
3. Build new backend with Genie.jl

**Timeline: 10-12 weeks**

**Pros:**
- ✅ Modern stack (React)
- ✅ Full control
- ✅ No legacy code

**Cons:**
- ❌ Longer development time
- ❌ Lose VisFlow's polish
- ❌ Rewrite UI components

### Option 3: Build from Scratch with React Flow

**Approach:**
Use React Flow library (like in original plan)

**Timeline: 8-10 weeks**

**Pros:**
- ✅ Modern, maintained library
- ✅ Great documentation
- ✅ Active community

**Cons:**
- ❌ Build all UI from scratch
- ❌ No pre-built components

## Detailed Comparison

| Aspect | VisFlow Fork | Extract Components | React Flow |
|--------|--------------|-------------------|-----------|
| **Development Time** | 6-8 weeks | 10-12 weeks | 8-10 weeks |
| **Code Reuse** | 60-70% | 20-30% | 0% |
| **Technology** | Vue 2 (old) | React (modern) | React (modern) |
| **UI Polish** | High | Medium | Medium |
| **Maintainability** | Medium | High | High |
| **Learning Curve** | Vue.js | React | React Flow |
| **Community** | Small | Large | Large |

## Recommended Approach: **Fork VisFlow**

### Why This Makes Sense:

1. **Fastest Path to MVP** (6-8 weeks vs 8-12 weeks)
   - Professional UI already built
   - Workflow editor works great
   - Just need backend swap

2. **60-70% Code Reuse**
   - Entire frontend UI
   - Component library
   - State management structure

3. **Proven Design**
   - VisFlow is production software
   - Good UX patterns
   - Polished interactions

4. **Compatible License**
   - BSD-3-Clause (same as VisTrails)
   - Can modify freely

### What Gets Replaced:

**Backend (100% replacement):**
```
Node.js + Express + MongoDB
    ↓
Julia + Genie.jl + VisTrailsJL
```

**History System (80% replacement):**
```
Simple undo/redo
    ↓
Version tree with branching
```

**Data Model (Adaptation layer):**
```
JSON workflows
    ↓
VisTrails .vt files (with adapter)
```

### What Gets Kept:

**Frontend (70% kept):**
- ✅ Dataflow canvas
- ✅ Node/edge/port components
- ✅ Drag-and-drop
- ✅ Pan/zoom
- ✅ Selection
- ✅ UI components
- ✅ Styling

## Implementation Plan

### Phase 1: Backend (2 weeks)

**Build Genie.jl API compatible with VisFlow's expectations:**

```julia
using Genie, VisTrailsJL, JSON

# Adapt VisTrails to VisFlow format
function vistrails_to_visflow(vt::Vistrail, version::Int)
    pipeline = vt.pipelines[version]
    return Dict(
        "nodes" => [module_to_node(m) for m in pipeline.modules],
        "edges" => [conn_to_edge(c) for c in pipeline.connections]
    )
end

# API endpoints (VisFlow-compatible)
route("/api/diagram/load") do
    vt = load_vistrail(params(:filename))
    json(vistrails_to_visflow(vt, vt.current_version))
end

route("/api/diagram/save") do
    # Save changes as new version in VisTrails
    vt = load_vistrail(params(:filename))
    # Create new version from JSON changes
    # ...
end
```

### Phase 2: Frontend Adaptation (3 weeks)

**Modify VisFlow's Vuex store:**

```typescript
// store/dataflow/actions.ts
async loadDiagram({ commit }, filename: string) {
    // Call Genie.jl API instead of Node.js
    const response = await axios.post('http://localhost:8000/api/diagram/load', {
        filename
    });
    commit('setDiagram', response.data);
}
```

**Add version tree component:**
```vue
<template>
  <div class="version-tree">
    <svg ref="treeCanvas"></svg>
  </div>
</template>

<script lang="ts">
// Render version tree from VisTrailsJL
</script>
```

### Phase 3: Version Management (2 weeks)

**Add VisTrails-specific UI:**
- Version tree panel
- Tag editor
- Version comparison
- Notes/annotations

### Phase 4: Testing (1 week)

- Load existing .vt files
- Create new workflows
- Test versioning
- Test provenance

## File Structure After Integration

```
visflow-vistrails/
├── client/                 # VisFlow frontend (mostly unchanged)
│   ├── src/
│   │   ├── components/
│   │   │   ├── dataflow-canvas/  ✅ Keep
│   │   │   ├── node/             ✅ Keep
│   │   │   ├── edge/             ✅ Keep
│   │   │   ├── port/             ✅ Keep
│   │   │   └── version-tree/     🆕 Add
│   │   └── store/
│   │       ├── dataflow/         ⚠️ Adapt
│   │       └── history/          ⚠️ Replace
│   └── package.json
├── server/                 # Genie.jl backend (complete rewrite)
│   ├── Project.toml
│   ├── src/
│   │   ├── api.jl         # REST API
│   │   ├── adapter.jl     # VisFlow ↔ VisTrails
│   │   └── server.jl
│   └── vistrails_backend.jl
└── README.md
```

## Proof of Concept

### Step 1: Run VisFlow Locally (30 minutes)
```bash
cd /Users/csilva/github/visflow
yarn install
yarn --cwd client start      # Port 8080
# Skip server for now
```

### Step 2: Create Mock Backend (2 hours)
```julia
# mock_visflow_api.jl
using Genie, JSON

route("/api/diagram/load") do
    # Return sample VisFlow JSON
    json(Dict(
        "nodes" => [
            Dict("id" => 1, "label" => "Module1", "x" => 100, "y" => 100)
        ],
        "edges" => []
    ))
end

up(8000)  # Run on port 8000
```

### Step 3: Modify VisFlow Client (1 hour)
Change API endpoint in VisFlow to point to localhost:8000

### Step 4: Test Integration (1 hour)
- Load workflow from Julia backend
- Verify rendering in VisFlow UI

**Total POC Time: ~4 hours**

## Conclusion

### Recommendation: **Fork VisFlow + VisTrailsJL Backend**

**Advantages:**
1. ✅ **Fastest**: 6-8 weeks vs 8-12 weeks
2. ✅ **Proven UI**: Professional workflow editor
3. ✅ **Code Reuse**: 60-70% of frontend
4. ✅ **Complete**: All UI components included
5. ✅ **Licensed**: BSD-compatible

**Disadvantages:**
1. ❌ **Old Stack**: Vue 2.5 (2018)
2. ❌ **Learning**: Need to learn Vue.js
3. ❌ **Backend Rewrite**: Complete Node.js → Julia

**Verdict:**
Despite the old Vue version, **forking VisFlow is the fastest path to a production-ready provenance-enabled workflow editor**. The professional UI and complete component library offset the drawbacks.

### Alternative if Vue is a Dealbreaker:
Use **React Flow** from scratch (8-10 weeks, modern stack, full control)

### Next Steps:
1. Create proof of concept (4 hours)
2. If POC works, proceed with fork
3. Implement Genie.jl backend (2 weeks)
4. Adapt frontend to VisTrails (3 weeks)
5. Add version tree UI (2 weeks)
6. Test and polish (1 week)

**Total: 6-8 weeks to production!** 🚀
