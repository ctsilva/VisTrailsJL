# VisFlow Integration Status & Next Steps

## Current Status

### ✅ What's Working

**VisTrailsJL Backend (Complete)**:
- Genie.jl REST API running at http://localhost:8000
- SVG rendering endpoint: `GET /api/workflow/:id/svg`
- JSON data endpoint: `GET /api/workflow/:id`
- 31 workflows available from examples/
- Version support built-in

**VisFlow Fork**:
- Fork created: https://github.com/ctsilva/visflow
- Git remotes configured
- Integration branch: `feature/vistrails-integration`

### ⚠️ Issue Encountered

VisFlow has **old dependencies** (2018-era):
- node-sass requires Python 2 (deprecated)
- Vue 2.5 (old, but workable)
- Dependency conflicts with modern Node.js

**Error**: `node-sass` build fails with Python 2/3 issues

## Options Moving Forward

### Option 1: Fix VisFlow Dependencies (Recommended for Learning)

**Effort**: 1-2 days
**Approach**: Update package.json to modern equivalents

**Steps**:
1. Replace `node-sass` with `sass` (Dart Sass)
2. Update Vue CLI to v5
3. Fix other deprecated packages
4. Test that VisFlow still works

**Pros**:
- Learn VisFlow codebase deeply
- Full control over frontend
- Can modernize incrementally

**Cons**:
- Time-consuming dependency fixes
- May break existing features
- Need to test thoroughly

### Option 2: Start with Simple HTML Viewer (Fastest MVP)

**Effort**: 1-2 hours
**Approach**: Build minimal workflow viewer using what we already have

**You Already Have**:
```html
<!-- /backend/public/index.html -->
<select id="workflow">...</select>
<button onclick="loadWorkflow()">Load</button>
<img src="http://localhost:8000/api/workflow/gcd/svg" />
```

**Enhance It To**:
- Add module palette (fetch from backend)
- Add click handlers on SVG (edit modules)
- Add version selector
- Add simple editing (delegate to backend)

**Pros**:
- Works immediately
- No dependency issues
- Focus on backend integration
- Can migrate to VisFlow later

**Cons**:
- Less polished UI
- Missing VisFlow's advanced features

### Option 3: Use Modern React Flow Instead

**Effort**: 2-3 weeks
**Approach**: Build new frontend with modern tools

**Stack**:
- React 18 + TypeScript
- React Flow (node editor library)
- Vite (fast build tool)
- Tailwind CSS (styling)

**Pros**:
- Modern, maintained dependencies
- Large community and examples
- Better TypeScript support
- Fast development

**Cons**:
- Start from scratch
- More work than fixing VisFlow
- Different UX than VisTrails

### Option 4: Just Use SVG with Minimal JS (Simplest)

**Effort**: 2-3 hours
**Approach**: Enhance the HTML viewer to be "good enough"

**Features to Add**:
```javascript
// Make SVG interactive
svg.querySelector('.module').onclick = (e) => {
  // Edit module
  fetch('http://localhost:8000/api/module/' + moduleId)
}

// Add version slider
<input type="range" min="1" max="134"
  onchange="loadVersion(this.value)" />

// Add module palette
fetch('http://localhost:8000/api/modules')
  .then(modules => renderPalette(modules))
```

**Pros**:
- Immediate progress
- No build tools needed
- Focus on backend features
- Can demo quickly

**Cons**:
- Won't look as polished
- Limited interactivity

## Recommendation

**Start with Option 4 (Enhanced HTML Viewer)**, then decide:

### Phase 1: Enhanced HTML Viewer (This Week)
1. Make SVG clickable for module editing
2. Add version selector/slider
3. Add module palette from backend
4. Add workflow save/load
5. Polish the UI with better CSS

### Phase 2: Evaluate (Next Week)
After using the HTML viewer:
- If it's "good enough" → stick with it, enhance incrementally
- If you want VisFlow's features → fix dependencies (Option 1)
- If you want modern stack → React Flow (Option 3)

## Immediate Next Steps

### 1. Enhance HTML Viewer (Today)

Create `backend/public/viewer.html`:
```html
<!DOCTYPE html>
<html>
<head>
  <title>VisTrailsJL Workflow Editor</title>
  <style>
    /* Modern, clean CSS */
    body { font-family: system-ui; }
    .sidebar { width: 250px; float: left; }
    .canvas { margin-left: 260px; }
    .module-palette { /* styling */ }
  </style>
</head>
<body>
  <div class="sidebar">
    <h3>Workflows</h3>
    <select id="workflow-select"></select>

    <h3>Version</h3>
    <input type="range" id="version-slider" />

    <h3>Modules</h3>
    <div id="module-palette"></div>
  </div>

  <div class="canvas">
    <object id="workflow-svg" type="image/svg+xml"></object>
  </div>

  <script>
    // Load workflows
    // Make SVG interactive
    // Handle module drag-drop
  </script>
</body>
</html>
```

### 2. Add Backend Endpoints (If Needed)

```julia
# GET /api/modules - List available modules
# POST /api/workflow - Create new workflow
# PUT /api/workflow/:id - Update workflow
# POST /api/workflow/:id/module - Add module
```

### 3. Test Full Workflow

1. Open viewer
2. Select workflow
3. View SVG
4. Click module → edit
5. Add new module
6. Save changes

## Decision Matrix

| Criterion | Option 1 (Fix VisFlow) | Option 2 (HTML) | Option 3 (React Flow) | Option 4 (Enhanced HTML) |
|-----------|----------------------|-----------------|---------------------|------------------------|
| Time to MVP | 3-5 days | 2 hours | 2-3 weeks | 4-6 hours |
| Maintenance | Medium | Low | Medium | Low |
| Features | Full VisFlow | Basic | Custom | Good enough |
| Learning Curve | High (Vue 2) | Low | Medium (React) | Low |
| Modern Stack | No | N/A | Yes | N/A |

## My Recommendation

**Go with Enhanced HTML Viewer (Option 4) for now.**

**Why**:
1. You already have working backend with SVG
2. Can demo in hours, not days
3. No dependency hell
4. Focus on backend features, not frontend fights
5. Can always build fancier UI later

**Timeline**:
- **Today**: Enhanced HTML viewer with version selector
- **Tomorrow**: Module editing and workflow save
- **Next Week**: Decide if you need more (VisFlow/React Flow)

The backend is solid. Don't let frontend dependency issues block progress!
