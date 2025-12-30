# Deprecated Backend Files

The following files are **NOT FUNCTIONAL** and should not be used:

- `editing_routes.jl.DEPRECATED` - Older editing routes implementation (not integrated)
- `routes.jl.DEPRECATED` - Older routes implementation (not integrated)
- `server.jl.DEPRECATED` - Older server implementation (not used)

## Active Implementation

The **active and functional** backend server is:

**`http_server.jl`** - Main HTTP server with all endpoints

This file includes:
- Workflow listing and loading
- SVG rendering
- Version tree visualization
- **Workflow creation** (`POST /api/workflows`)
- **Module operations** (`POST /api/workflow/:id/module`, `PATCH /api/workflow/:id/module/:id/position`)
- **Connection operations** (`POST /api/workflow/:id/connection`, `DELETE /api/workflow/:id/connection/:id`)
- **Version control** (`POST /api/workflow/:id/commit`)

## Supporting Files

- `workflow_editing.jl` - Core editing functions used by http_server.jl
- `start.sh` - Convenience script to start http_server.jl

## Starting the Server

```bash
cd julia/backend
PORT=8000 julia --project=. http_server.jl

# Or use the convenience script
PORT=8000 ./start.sh
```

## Why These Files Were Deprecated

The `editing_routes.jl`, `routes.jl`, and `server.jl` files were part of an earlier design that was never integrated into the main server. All functionality has been consolidated into `http_server.jl` to avoid confusion and maintain a single source of truth.

**Date:** 2025-12-30
