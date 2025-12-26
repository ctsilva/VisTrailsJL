# VisFlow Fork & Integration Plan

## Objective

Fork VisFlow and adapt it to use VisTrailsJL backend instead of its original backend.

## Why Fork VisFlow?

Based on our earlier analysis (see [CURIO_VS_VISFLOW_COMPARISON.md](CURIO_VS_VISFLOW_COMPARISON.md)):

✅ **Simpler architecture** - Custom canvas easier to adapt than React Flow
✅ **Higher code reuse** - 60-70% vs 40-50% for Curio
✅ **Better fit** - General dataflow system, closer to VisTrails
✅ **Faster timeline** - 6-8 weeks vs 10-14 weeks for Curio
✅ **No provenance conflicts** - VisFlow has no built-in provenance

## Repository Setup

### 1. Fork VisFlow

Original: https://github.com/yubowenok/visflow
Fork to: https://github.com/ctsilva/visflow-vistrails

### 2. Clone and Setup

```bash
cd ~/github
git clone https://github.com/ctsilva/visflow-vistrails.git
cd visflow-vistrails

# Add upstream for pulling updates
git remote add upstream https://github.com/yubowenok/visflow.git

# Install dependencies
cd client
npm install
```

### 3. Create Integration Branch

```bash
git checkout -b feature/vistrails-backend
```

## VisFlow Architecture Overview

### Frontend (client/)
- **Framework**: Vue.js 2.5 + TypeScript
- **Build**: Vue CLI 3
- **UI**: Bootstrap-Vue
- **State**: Vuex store
- **Canvas**: Custom jQuery-based workflow editor

### Backend (server/)
- **Framework**: Express + Node.js
- **Database**: MongoDB
- **Execution**: Server-side JavaScript

### Key Components to Modify

1. **API Client** (`client/src/api/`) - Point to VisTrailsJL backend
2. **Workflow Store** (`client/src/store/workflow/`) - Adapt data structures
3. **Canvas Rendering** - Replace with SVG embed from backend
4. **Module Palette** - Fetch from VisTrailsJL module registry

## Integration Strategy

### Phase 1: Backend Connection (Week 1-2)

**Goal**: Connect VisFlow frontend to VisTrailsJL backend

**Tasks**:
1. Update API base URL to `http://localhost:8000`
2. Map VisFlow API calls to VisTrailsJL endpoints:
   - `GET /api/dataflows` → `GET /api/workflows`
   - `GET /api/dataflow/:id` → `GET /api/workflow/:id`
   - Create workflow → POST to VisTrailsJL
3. Test workflow loading

**Files to Modify**:
- `client/src/api/dataflow.ts` - API client
- `client/src/store/workflow/actions.ts` - Vuex actions
- `client/src/common/env.ts` - Backend URL configuration

### Phase 2: SVG Rendering (Week 3-4)

**Goal**: Replace VisFlow's canvas with SVG from backend

**Current**: VisFlow renders workflows in custom jQuery canvas
**New**: Embed SVG from `GET /api/workflow/:id/svg`

**Implementation**:
```vue
<!-- Replace canvas component -->
<template>
  <div class="workflow-canvas">
    <object
      :data="svgUrl"
      type="image/svg+xml"
      @load="onSvgLoad"
    />
  </div>
</template>

<script>
export default {
  computed: {
    svgUrl() {
      return `http://localhost:8000/api/workflow/${this.workflowId}/svg`;
    }
  }
}
</script>
```

**Files to Modify**:
- `client/src/components/dataflow-canvas/` - Canvas component
- Keep interaction logic (zoom, pan)
- Add SVG click handlers for module editing

### Phase 3: Data Structure Mapping (Week 5-6)

**Goal**: Map between VisFlow and VisTrailsJL data formats

**VisFlow Format**:
```json
{
  "nodes": [{"id": 1, "type": "filter", "x": 100, "y": 200}],
  "edges": [{"source": 1, "target": 2}]
}
```

**VisTrailsJL Format**:
```json
{
  "modules": [{"id": 1, "name": "Filter", "package": "...", "x": 100, "y": 200}],
  "connections": [{"source_id": 1, "source_port": "out", "target_id": 2, "target_port": "in"}]
}
```

**Create Adapter**:
```typescript
// client/src/adapters/vistrails.ts
export class VisTrailsAdapter {
  static toVisFlow(vistrailsData: VisTrailsWorkflow): VisFlowDataflow {
    // Convert modules → nodes, connections → edges
  }

  static toVisTrails(visflowData: VisFlowDataflow): VisTrailsWorkflow {
    // Convert nodes → modules, edges → connections
  }
}
```

### Phase 4: Module Registry (Week 7)

**Goal**: Fetch available modules from VisTrailsJL

**New Endpoint** (add to VisTrailsJL backend):
```julia
# GET /api/modules
route("/api/modules") do
    modules = VisTrailsJL.get_all_modules()
    json(Dict("modules" => modules))
end
```

**Update Module Palette**:
- Fetch modules from backend
- Display in VisFlow's left sidebar
- Drag-and-drop to canvas (triggers backend module creation)

### Phase 5: Provenance Features (Week 8)

**Goal**: Add VisTrails-specific provenance UI

**New Components**:
1. **Version Tree Viewer** - Show workflow history
2. **Version Selector** - Load specific versions
3. **Diff Viewer** - Compare workflow versions
4. **Action History** - Show change log

**Use Backend Endpoints**:
- `GET /api/workflow/:id/versions` - Version tree
- `GET /api/workflow/:id/version/:vid/svg` - Version SVG

## API Mapping Reference

| VisFlow Original | VisTrailsJL Backend | Status |
|------------------|---------------------|--------|
| `GET /api/dataflows` | `GET /api/workflows` | ✅ Ready |
| `GET /api/dataflow/:id` | `GET /api/workflow/:id` | ✅ Ready |
| `POST /api/dataflow` | `POST /api/workflow` | ⚠️ TODO |
| `PUT /api/dataflow/:id` | `PUT /api/workflow/:id` | ⚠️ TODO |
| `DELETE /api/dataflow/:id` | `DELETE /api/workflow/:id` | ⚠️ TODO |
| N/A | `GET /api/workflow/:id/svg` | ✅ Ready |
| N/A | `GET /api/workflow/:id/versions` | ✅ Ready |

## File Structure After Integration

```
visflow-vistrails/
├── client/                    # VisFlow frontend (keep)
│   ├── src/
│   │   ├── adapters/         # NEW: VisTrails ↔ VisFlow adapters
│   │   │   └── vistrails.ts
│   │   ├── api/              # Modify: point to VisTrailsJL
│   │   │   └── vistrails.ts  # NEW: VisTrails API client
│   │   ├── components/
│   │   │   ├── workflow-canvas/  # Replace with SVG embed
│   │   │   └── provenance/       # NEW: Version tree, diff viewer
│   │   └── store/
│   │       └── workflow/     # Adapt for VisTrails data
│   └── package.json
│
└── docs/
    └── VISTRAILS_INTEGRATION.md  # Integration guide
```

## Configuration

### Environment Variables

Create `client/.env.local`:
```bash
VUE_APP_BACKEND_URL=http://localhost:8000
VUE_APP_BACKEND_TYPE=vistrails
```

### Backend Configuration

Update VisTrailsJL backend CORS:
```julia
# backend/server.jl
Genie.config.cors_allowed_origins = ["http://localhost:3000"]  # VisFlow dev server
```

## Testing Strategy

### Unit Tests
- Adapter functions (VisFlow ↔ VisTrails conversion)
- API client methods

### Integration Tests
1. Load workflow from backend → display SVG
2. Create new module → POST to backend → reload SVG
3. Version navigation → display different versions

### E2E Tests
1. Full workflow creation flow
2. Module editing
3. Version tree navigation

## Success Criteria

✅ **Week 2**: VisFlow loads workflows from VisTrailsJL backend
✅ **Week 4**: Workflows display as SVG from backend
✅ **Week 6**: Can create/edit workflows via frontend
✅ **Week 8**: Full provenance features working

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| Data format incompatibility | Create comprehensive adapter layer |
| Vue 2.5 is old | Plan Vue 3 upgrade for later |
| jQuery canvas replacement | Keep canvas for editing, add SVG overlay |
| Backend API incomplete | Implement missing endpoints in parallel |

## Next Steps

1. ✅ Fork VisFlow repository
2. ⚠️ Clone and set up development environment
3. ⚠️ Create integration branch
4. ⚠️ Update backend URL configuration
5. ⚠️ Test basic workflow loading

## Timeline

- **Weeks 1-2**: Backend connection
- **Weeks 3-4**: SVG rendering
- **Weeks 5-6**: Data mapping
- **Week 7**: Module registry
- **Week 8**: Provenance UI

**Total**: 8 weeks to full integration
**MVP**: 4 weeks (backend + SVG rendering)

## Resources

- Original VisFlow: https://github.com/yubowenok/visflow
- VisFlow Docs: https://visflow.org
- VisTrails Docs: `../IMPLEMENTATION_STATUS.md`
- API Requirements: `API_REQUIREMENTS.md`
