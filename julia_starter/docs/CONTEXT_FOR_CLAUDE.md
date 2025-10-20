# Context Document for Claude Code

This document provides comprehensive context for another Claude instance to understand the VisTrails + VisFlow integration project.

## What Has Been Built

We have successfully integrated two systems:

1. **VisTrailsJL** - A Julia reimplementation of VisTrails that:
   - Loads .vt workflow files (both plain XML and ZIP formats)
   - Reconstructs workflows from version history using action replay
   - Renders workflows and version trees as SVG (lightweight mode - no package dependencies needed)
   - Provides a REST API via Genie.jl web framework

2. **VisFlow Integration** - A Vue.js web component that:
   - Displays VisTrails workflows in a modern web interface
   - Lists all available .vt files
   - Shows interactive version tree visualizations
   - Allows selecting and viewing specific workflow versions
   - Communicates with VisTrailsJL backend via REST API

## Current Status: ✅ FULLY FUNCTIONAL

Both systems are running and tested:
- Backend: http://localhost:8000 (VisTrailsJL + Genie)
- Frontend: http://localhost:8080/vistrails (VisFlow + Vue.js)
- Integration works via webpack proxy (no CORS issues)
- Multiple workflow files successfully tested

## Repository State

### VisTrails Repository
- **Path:** `/Users/csilva/src/VisTrails`
- **Branch:** `v2.2`
- **Status:** Has untracked documentation files (see below)

### VisFlow Repository
- **Path:** `/Users/csilva/github/visflow`
- **Branch:** `feature/vistrails-integration`
- **Status:** ✅ All changes committed

## Key Technical Decisions

### 1. Sass Migration (node-sass → sass)
**Why:** node-sass uses native C++ bindings incompatible with Node v22 + ARM64
**Solution:** Migrated to pure JavaScript `sass` package
**Files affected:** package.json, vue.config.js

### 2. Sass Syntax Updates (/deep/ → ::v-deep)
**Why:** Modern Sass compiler doesn't support deprecated `/deep/` syntax
**Solution:** Updated 13 files with `::v-deep` selector
**Files affected:** 11 .scss files, 2 .vue files, .stylelintrc.json

### 3. CORS Solution (Webpack Proxy)
**Why:** Browser blocks requests from localhost:8080 to localhost:8000
**Solution:** Configured webpack dev server proxy to forward `/api/*` requests
**Files affected:** vue.config.js, vistrails-viewer.ts (apiBase changed to `/api`)

### 4. Node v22 Compatibility
**Why:** Old webpack incompatible with Node v22's OpenSSL
**Solution:** Use `NODE_OPTIONS=--openssl-legacy-provider` flag when starting dev server
**Command:** `NODE_OPTIONS=--openssl-legacy-provider yarn start`

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ Browser (http://localhost:8080/vistrails)                   │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ VisTrailsViewer Component                          │    │
│  │  - Workflow list sidebar                           │    │
│  │  - Version tree SVG display                        │    │
│  │  - Workflow diagram SVG display                    │    │
│  │  - Version selector                                │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                           ↓
                    axios.get('/api/...')
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Webpack Dev Server (localhost:8080)                         │
│   proxy: { '/api': 'http://localhost:8000' }                │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ VisTrailsJL Backend (localhost:8000)                        │
│                                                              │
│  Genie.jl Routes:                                           │
│  • GET /health                                              │
│  • GET /api/workflows                                       │
│  • GET /api/workflow/:id/tree/svg                          │
│  • GET /api/workflow/:id/version/:version/svg              │
│                                                              │
│  VisTrailsJL Module:                                        │
│  • Load .vt files (XML/ZIP)                                │
│  • Action replay system                                     │
│  • Lightweight rendering mode                               │
│  • SVG generation                                           │
└─────────────────────────────────────────────────────────────┘
                           ↓
              julia_starter/workflows/*.vt
```

## File Locations and Purposes

### Backend Files

```
/Users/csilva/src/VisTrails/julia_starter/
├── backend/
│   ├── server.jl          # Genie server entry point
│   ├── start.sh           # Startup script with Julia command
│   ├── Project.toml       # Julia dependencies (Genie, JSON3, HTTP)
│   ├── routes.jl          # API endpoint definitions
│   └── Manifest.toml      # Locked dependency versions
├── src/
│   ├── VisTrailsJL.jl    # Main module
│   ├── db/
│   │   ├── xml/          # XML parsing
│   │   └── services/
│   │       └── action_replay.jl  # Reconstruct workflows from history
│   ├── core/
│   │   ├── modules/      # Module registry
│   │   └── vistrail.jl   # Vistrail data structure
│   └── rendering/
│       ├── workflow_layout.jl      # Workflow SVG generation
│       └── version_tree_layout.jl  # Version tree SVG generation
├── workflows/            # .vt files to load (gcd.vt, lung.vt, etc.)
└── docs/
    ├── SETUP_GUIDE.md                    # Complete setup instructions
    ├── CONTEXT_FOR_CLAUDE.md             # This file
    ├── RENDERING.md                      # SVG rendering details
    ├── VISFLOW_INTEGRATION.md            # Backend API docs
    ├── VERSION_TREE_DEMO_COMPLETE.md     # Version tree implementation
    ├── VISFLOW_FORK_PLAN.md              # Planning doc (untracked)
    ├── VISFLOW_INTEGRATION_POC.md        # POC doc (untracked)
    └── VISFLOW_STATUS_AND_NEXT_STEPS.md  # Status doc (untracked)
```

### Frontend Files

```
/Users/csilva/github/visflow/client/
├── src/
│   ├── components/
│   │   └── vistrails-viewer/
│   │       ├── vistrails-viewer.vue  # Vue component template + styles
│   │       ├── vistrails-viewer.ts   # TypeScript component logic
│   │       └── README.md             # Component documentation
│   └── router.ts                     # Added /vistrails route
├── vue.config.js                     # Webpack config (proxy + sass)
├── package.json                      # Dependencies (added sass)
├── .stylelintrc.json                 # Added v-deep exception
└── yarn.lock                         # Locked dependency versions

/Users/csilva/github/visflow/docs/
└── VISFLOW_VISTRAILS_INTEGRATION.md  # Full integration guide
```

## Critical Code Sections

### Backend API (backend/routes.jl)
```julia
# Health check
route("/health") do
    json(Dict("status" => "ok", "message" => "VisTrailsJL Backend is running"))
end

# List workflows
route("/api/workflows") do
    # Returns array of workflow metadata
end

# Version tree SVG
route("/api/workflow/:id/tree/svg") do
    # Returns SVG string of version tree
end

# Workflow version SVG
route("/api/workflow/:id/version/:version/svg") do
    # Returns SVG string of workflow diagram
end
```

### Frontend Component (vistrails-viewer.ts)
```typescript
@Component
export default class VisTrailsViewer extends Vue {
  private apiBase: string = '/api';  // IMPORTANT: relative URL for proxy

  private async loadWorkflows() {
    const response = await axios.get(`${this.apiBase}/workflows`);
    this.workflows = response.data;
  }

  private async loadVersionTreeSVG() {
    const response = await axios.get(
      `${this.apiBase}/workflow/${this.selectedWorkflow.id}/tree/svg`,
      { responseType: 'text' }
    );
    this.versionTreeSVG = response.data;
  }
}
```

### Webpack Proxy (vue.config.js)
```javascript
module.exports = {
  devServer: {
    historyApiFallback: true,  // Support Vue Router history mode
    proxy: {
      '/api': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      },
    },
  },
  css: {
    loaderOptions: {
      sass: {
        implementation: require('sass'),  // Use modern sass
      },
    },
  },
}
```

## How to Run (Quick Reference)

```bash
# Terminal 1 - Backend
cd /Users/csilva/src/VisTrails/julia_starter/backend
./start.sh

# Terminal 2 - Frontend
cd /Users/csilva/github/visflow/client
NODE_OPTIONS=--openssl-legacy-provider yarn start

# Browser
open http://localhost:8080/vistrails
```

## Known Issues and Workarounds

### 1. Julia Precompilation Warning
**Warning:** `Method overwriting is not permitted during Module precompilation`
**Impact:** Non-fatal - server runs correctly
**Cause:** Duplicate includes in module structure
**Action:** Can be ignored

### 2. "Failed to add module" Warnings
**Warning:** Many warnings about VTK, matplotlib, etc. modules not found
**Impact:** Expected behavior - lightweight mode works without these
**Cause:** Modules not implemented in Julia version
**Action:** Normal operation, no action needed

### 3. Browser Cache After Code Changes
**Issue:** Changes to vistrails-viewer.ts not reflected after rebuild
**Solution:** Hard refresh browser with `Cmd+Shift+R` (macOS)

### 4. Multiple Background Bash Processes
**Issue:** Many Julia backend processes running from previous sessions
**Note:** Only the most recent one (ac9c29) is active
**Action:** Can kill old processes if needed

## Testing Strategy

### Backend Tests
```bash
# Test health endpoint
curl http://localhost:8000/health

# Test workflow list
curl http://localhost:8000/api/workflows | jq

# Test version tree SVG
curl http://localhost:8000/api/workflow/gcd/tree/svg > tree.svg
open tree.svg

# Test workflow version SVG
curl http://localhost:8000/api/workflow/gcd/version/1/svg > workflow.svg
open workflow.svg
```

### Frontend Tests
1. Open http://localhost:8080/vistrails
2. Verify workflow list appears in left sidebar
3. Click on "gcd.vt"
4. Verify version tree SVG displays
5. Switch to "Workflow View" tab
6. Select different versions from dropdown
7. Verify workflow SVG updates correctly

### Integration Tests
1. Check browser console for no errors
2. Check Network tab shows successful `/api/*` requests
3. Verify SVGs are not empty (should have actual graphics)
4. Test multiple workflows from the list

## User's Environment

- **OS:** macOS (Darwin 25.0.0)
- **Architecture:** ARM64 (Apple Silicon)
- **Node.js:** v22
- **Julia:** 1.9+
- **Working Directory:** `/Users/csilva/src/VisTrails`
- **Additional Directory:** `/Users/csilva/github/visflow/client/src/components`

## Untracked Files in Git

In VisTrails repository (branch v2.2):
```
julia_starter/docs/VERSION_TREE_DEMO_COMPLETE.md
julia_starter/docs/VISFLOW_FORK_PLAN.md
julia_starter/docs/VISFLOW_INTEGRATION_POC.md
julia_starter/docs/VISFLOW_STATUS_AND_NEXT_STEPS.md
```

These are documentation files from earlier work that haven't been committed yet.

## What Works

✅ Backend loads all .vt files from workflows directory
✅ Backend generates SVG for version trees
✅ Backend generates SVG for workflow diagrams
✅ Backend API responds correctly to all endpoints
✅ Frontend displays workflow list
✅ Frontend displays version tree SVG
✅ Frontend displays workflow diagram SVG
✅ Frontend allows version selection
✅ Proxy forwards API requests correctly (no CORS)
✅ Sass compilation works with modern compiler
✅ Vue Router works with /vistrails route
✅ Hard refresh clears browser cache issues

## What's Next (Potential Future Work)

- Interactive workflow editing in VisFlow
- Workflow execution from web interface
- More module implementations in Julia
- Production deployment configuration
- Add tests for frontend component
- Optimize SVG rendering for large workflows
- Add workflow search/filtering
- Add diff view between versions

## Important Notes for Another Claude Instance

1. **Always use relative `/api` URL in frontend** - NOT absolute `http://localhost:8000/api`
2. **Always use `NODE_OPTIONS=--openssl-legacy-provider`** when starting VisFlow dev server
3. **User doesn't like `sed` command** - use Edit tool for file modifications
4. **Background processes** - Many old backend processes running, only latest is active
5. **Hard refresh browser** - Often needed after frontend code changes
6. **Git status** - VisFlow is clean, VisTrails has untracked docs
7. **Lightweight rendering** - Key feature that makes this work without Python packages

## User Communication Style

The user uses shorthand to indicate success:
- "#to memorize" means something worked and should be remembered
- "continue working" means proceed without asking for confirmation
- Shows screenshots when encountering issues
- Prefers concise responses

## Critical Success Factors

What made this integration work:

1. **Webpack proxy** - Solved CORS without backend changes
2. **Relative API URLs** - Required for proxy to intercept requests
3. **Sass migration** - Required for Node v22 + ARM64 compatibility
4. **::v-deep syntax** - Required for modern Sass compiler
5. **Hard refresh** - Required to clear browser cache after changes
6. **Lightweight mode** - Makes backend work without implementing all modules

## How This Document Should Be Used

If you're another Claude instance:

1. **Read SETUP_GUIDE.md first** - Step-by-step instructions
2. **Read this file** - Understand context and decisions
3. **Check git status** - See what's committed vs. untracked
4. **Start both servers** - Backend then frontend
5. **Test in browser** - Verify everything works
6. **Make changes carefully** - Follow established patterns

## Questions You Might Have

**Q: Where are the .vt workflow files?**
A: `/Users/csilva/src/VisTrails/julia_starter/workflows/`

**Q: How do I add a new API endpoint?**
A: Edit `backend/routes.jl`, restart backend with `./start.sh`

**Q: How do I modify the frontend UI?**
A: Edit `vistrails-viewer.vue` or `vistrails-viewer.ts`, auto-reloads

**Q: Why so many background bash processes?**
A: Multiple backend restart attempts during development, only latest is active

**Q: Can I use a different port?**
A: Yes, but update proxy config in vue.config.js and restart frontend

**Q: Do I need to install VTK, matplotlib, etc.?**
A: No - lightweight rendering mode works without Python packages

**Q: How do I add a new workflow file?**
A: Drop .vt file in `julia_starter/workflows/`, restart backend

**Q: Why does it take so long to start the backend?**
A: First run installs Julia packages, subsequent runs are faster

## Summary

This is a **complete, working integration** that:
- Loads VisTrails .vt files via Julia
- Serves them via REST API
- Displays them in a modern web interface
- Works without Python dependencies
- Is fully documented and tested

The main value is enabling VisTrails workflow viewing through a web browser without requiring the full Python VisTrails installation.

Everything is ready to use. Just start both servers and open the browser.
