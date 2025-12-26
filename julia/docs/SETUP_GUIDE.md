# VisTrails + VisFlow Integration Setup Guide

This guide provides complete instructions for setting up and running the VisTrails Julia backend with the VisFlow web frontend.

## Overview

This integration connects:
- **VisTrailsJL Backend** - Julia-based .vt file loader and SVG renderer (port 8000)
- **VisFlow Frontend** - Vue.js web interface for viewing workflows (port 8080)

The integration enables viewing VisTrails workflows and version history through a modern web interface without requiring the full Python VisTrails installation.

## Architecture

```
Browser (localhost:8080)
    ↓
VisFlow Vue.js Frontend
    ↓ (webpack proxy /api → http://localhost:8000)
VisTrailsJL Genie Backend
    ↓
.vt workflow files
```

## Prerequisites

### For VisTrailsJL Backend
- Julia 1.9 or later
- Dependencies (auto-installed):
  - Genie.jl (web framework)
  - JSON3.jl (JSON handling)
  - HTTP.jl (HTTP client)

### For VisFlow Frontend
- Node.js v22 (with legacy OpenSSL support)
- Yarn package manager
- Dependencies (managed via yarn):
  - Vue 2.5.16
  - axios (HTTP client)
  - sass (CSS preprocessor)
  - vue-router

## Directory Structure

```
/Users/csilva/src/VisTrails/julia/
├── backend/
│   ├── server.jl              # Main Genie server
│   ├── start.sh               # Startup script
│   ├── Project.toml           # Julia dependencies
│   └── routes.jl              # API routes
├── src/
│   ├── VisTrailsJL.jl        # Main module
│   ├── db/
│   │   └── services/
│   │       └── action_replay.jl
│   └── rendering/
│       ├── workflow_layout.jl
│       └── version_tree_layout.jl
└── workflows/                 # .vt files directory

/Users/csilva/github/visflow/
└── client/
    ├── src/
    │   ├── components/
    │   │   └── vistrails-viewer/
    │   │       ├── vistrails-viewer.vue    # UI component
    │   │       ├── vistrails-viewer.ts     # TypeScript logic
    │   │       └── README.md
    │   └── router.ts
    ├── vue.config.js          # Webpack config with proxy
    ├── package.json
    └── .stylelintrc.json
```

## Step-by-Step Setup

### 1. Start VisTrailsJL Backend

```bash
cd /Users/csilva/src/VisTrails/julia/backend
./start.sh
```

This will:
1. Install Julia dependencies (first run only)
2. Start Genie server on port 8000
3. Load all .vt files from `julia/workflows/`
4. Initialize module registry

**Verify backend is running:**
```bash
curl http://localhost:8000/health
# Should return: {"status": "ok", "message": "VisTrailsJL Backend is running"}

curl http://localhost:8000/api/workflows
# Should return JSON array of available workflows
```

### 2. Start VisFlow Frontend

```bash
cd /Users/csilva/github/visflow/client

# Install dependencies (first run only)
yarn

# Start dev server with OpenSSL legacy provider flag
NODE_OPTIONS=--openssl-legacy-provider yarn start
```

**Note:** The `NODE_OPTIONS=--openssl-legacy-provider` flag is required for Node v22 compatibility with older webpack versions.

**Verify frontend is running:**
- Open browser to http://localhost:8080
- Navigate to http://localhost:8080/vistrails

### 3. Access the Integration

Open http://localhost:8080/vistrails in your browser to:
- View list of available .vt workflow files
- Select a workflow to view its version tree (SVG)
- Select specific versions to view workflow diagrams (SVG)

## API Endpoints

The VisTrailsJL backend provides these REST endpoints:

### GET /health
Health check endpoint
```bash
curl http://localhost:8000/health
```

### GET /api/workflows
List all available workflows
```bash
curl http://localhost:8000/api/workflows
```
Returns:
```json
[
  {
    "id": "gcd",
    "name": "gcd.vt",
    "path": "/path/to/gcd.vt",
    "version_count": 22
  }
]
```

### GET /api/workflow/:id/tree/svg
Get version tree as SVG
```bash
curl http://localhost:8000/api/workflow/gcd/tree/svg
```

### GET /api/workflow/:id/version/:version/svg
Get specific workflow version as SVG
```bash
curl http://localhost:8000/api/workflow/gcd/version/1/svg
```

## Common Issues and Solutions

### Issue: Node.js Compatibility Error
**Error:** `error:0308010C:digital envelope routines::unsupported`

**Solution:** Use OpenSSL legacy provider flag:
```bash
NODE_OPTIONS=--openssl-legacy-provider yarn start
```

### Issue: node-sass ARM64 Compatibility
**Error:** `Node Sass does not yet support your current environment`

**Solution:** Already fixed - we migrated from `node-sass` to modern `sass`:
```bash
yarn remove node-sass
yarn add sass
```

### Issue: Sass `/deep/` Syntax Errors
**Error:** `Expected selector` when compiling Sass

**Solution:** Already fixed - all instances of `/deep/` replaced with `::v-deep` in:
- 11 .scss files
- 2 .vue files
- Updated `.stylelintrc.json` to ignore `v-deep` pseudo-element

### Issue: Network Error in Browser
**Error:** "Network Error" when accessing /vistrails

**Possible Causes:**
1. Backend not running on port 8000
2. Browser cache with old JavaScript

**Solutions:**
1. Verify backend is running: `curl http://localhost:8000/health`
2. Hard refresh browser: `Cmd+Shift+R` (macOS) or `Ctrl+Shift+R` (Windows/Linux)

### Issue: CORS Errors
**Solution:** Already configured - webpack proxy forwards `/api/*` requests to backend:
```javascript
// vue.config.js
devServer: {
  proxy: {
    '/api': {
      target: 'http://localhost:8000',
      changeOrigin: true,
    },
  },
}
```

### Issue: Julia Precompilation Warnings
**Warning:** `Method overwriting is not permitted during Module precompilation`

**Status:** Non-fatal warning - server still runs correctly. This is due to duplicate includes in the module structure and can be ignored.

## File Modifications Summary

### VisFlow Changes

**package.json** - Updated dependencies:
```json
{
  "dependencies": {
    "sass": "^1.93.2"  // Added (replaces node-sass)
  }
}
```

**vue.config.js** - Added proxy and sass config:
```javascript
devServer: {
  historyApiFallback: true,
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
      implementation: require('sass'),
    },
  },
},
```

**.stylelintrc.json** - Allow `::v-deep` selector:
```json
{
  "rules": {
    "selector-pseudo-element-no-unknown": [
      true,
      { "ignorePseudoElements": ["v-deep"] }
    ]
  }
}
```

**router.ts** - Added VisTrails route:
```typescript
import VisTrailsViewer from '@/components/vistrails-viewer/vistrails-viewer.vue';

const routes = [
  { path: '/vistrails', name: 'vistrails', component: VisTrailsViewer },
  // ... other routes
];
```

**New Component Files:**
- `src/components/vistrails-viewer/vistrails-viewer.vue` - UI component
- `src/components/vistrails-viewer/vistrails-viewer.ts` - TypeScript logic
- `src/components/vistrails-viewer/README.md` - Component docs

**Sass Syntax Updates (13 files):**
- Replaced all `/deep/` with `::v-deep` for modern Sass compatibility

### VisTrailsJL Changes

**backend/server.jl** - Genie web server with API routes
**backend/routes.jl** - REST API endpoint definitions
**backend/Project.toml** - Julia dependencies (Genie, JSON3, HTTP)

## Testing the Integration

### 1. Backend API Test
```bash
# List workflows
curl http://localhost:8000/api/workflows

# Get version tree for gcd.vt
curl http://localhost:8000/api/workflow/gcd/tree/svg > tree.svg
open tree.svg

# Get workflow version 1 for gcd.vt
curl http://localhost:8000/api/workflow/gcd/version/1/svg > workflow.svg
open workflow.svg
```

### 2. Frontend Integration Test
1. Open http://localhost:8080/vistrails
2. Verify workflow list loads on left sidebar
3. Click a workflow name
4. Verify version tree SVG displays
5. Switch to "Workflow View" tab
6. Select different versions from dropdown
7. Verify workflow SVG updates

## Development Workflow

### Making Changes to Frontend
1. Edit files in `/Users/csilva/github/visflow/client/src/`
2. Webpack dev server auto-reloads
3. Hard refresh browser if needed: `Cmd+Shift+R`

### Making Changes to Backend
1. Edit files in `/Users/csilva/src/VisTrails/julia/`
2. Restart backend: `Ctrl+C` then `./start.sh`
3. Or use `Revise.jl` for live reloading (advanced)

## Production Deployment Considerations

### Frontend Build
```bash
cd /Users/csilva/github/visflow/client
NODE_OPTIONS=--openssl-legacy-provider yarn build
```

Output in `dist/` directory can be served by any static web server.

### Backend Deployment
- Configure production port in `server.jl`
- Set up proper CORS headers if not using proxy
- Consider using systemd or Docker for process management
- Add HTTPS/TLS termination via nginx or Caddy

## Key Features

### Lightweight Rendering Mode
The Julia backend can render workflows **without requiring module packages** (VTK, matplotlib, etc.) by:
1. Extracting layout information from action history
2. Using module IDs and positions from XML
3. Generating SVG visualizations dynamically

This enables viewing any .vt file without Python dependencies.

### Tested Workflow Files
Successfully rendering:
- `gcd.vt` - 22 modules, 31 connections
- `lung.vt` - 13 modules, 12 connections (VTK)
- `mta.vt` - 17 modules, 18 connections (138 versions)
- `plot.vt` - 10 modules, 10 connections (43 versions)
- Many more in `julia/workflows/`

## Git Repositories

### VisTrails Repository
- **Location:** `/Users/csilva/src/VisTrails`
- **Branch:** `v2.2`
- **Recent Commits:**
  - "Add VisFlow web integration documentation"
  - "Add VisTrailsJL Julia implementation"

### VisFlow Repository
- **Location:** `/Users/csilva/github/visflow`
- **Branch:** `feature/vistrails-integration`
- **Recent Commit:**
  - "Add VisTrails integration with workflow viewer component"

## Related Documentation

- `/Users/csilva/src/VisTrails/julia/README.md` - VisTrailsJL overview
- `/Users/csilva/src/VisTrails/julia/docs/RENDERING.md` - Rendering details
- `/Users/csilva/src/VisTrails/julia/docs/VISFLOW_INTEGRATION.md` - Backend API docs
- `/Users/csilva/github/visflow/docs/VISFLOW_VISTRAILS_INTEGRATION.md` - Full integration guide
- `/Users/csilva/github/visflow/client/src/components/vistrails-viewer/README.md` - Component docs

## Quick Start Commands

```bash
# Terminal 1 - Backend
cd /Users/csilva/src/VisTrails/julia/backend
./start.sh

# Terminal 2 - Frontend
cd /Users/csilva/github/visflow/client
NODE_OPTIONS=--openssl-legacy-provider yarn start

# Browser
open http://localhost:8080/vistrails
```

## Support

For issues or questions:
1. Check "Common Issues and Solutions" section above
2. Review related documentation files
3. Check git commit history for recent changes
4. Verify both backend and frontend are running

## Summary

This integration provides:
- ✅ Modern web interface for VisTrails workflows
- ✅ No Python dependencies required
- ✅ SVG-based rendering for version trees and workflows
- ✅ REST API for programmatic access
- ✅ Lightweight mode works without module packages
- ✅ Full version history navigation
- ✅ Easy setup with two simple commands

The system is fully functional and ready for use.
