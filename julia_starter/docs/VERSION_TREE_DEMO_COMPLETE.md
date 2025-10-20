# ✅ Version Tree Navigation Demo Complete!

## What Was Improved

Updated the demo interface to properly represent the VisTrails concept: **a .vt file is a vistrail (version tree) containing multiple workflow versions**, not just a single workflow.

## Key Concept: Vistrails

**Vistrail = Version Tree** with:
- Multiple workflow versions (like git commits)
- Parent-child relationships between versions
- Optional tags marking important versions
- Current version pointer

## New Demo Features

### 1. Three-Panel Layout

```
┌─────────────┬──────────────┬────────────────────┐
│  Vistrails  │   Versions   │   Workflow View    │
│  (31 files) │   & Tags     │   (Selected Ver.)  │
│             │              │                    │
│  • gcd      │  📌 Tags:    │  ┌──────────────┐  │
│  • plot ✓   │  Two Plots   │  │  Workflow    │  │
│  • mta      │              │  │  SVG         │  │
│             │  All:        │  └──────────────┘  │
│             │  v43 Current │                    │
│             │  v42         │  Modules: 10      │
│             │  v41         │  Connections: 10  │
└─────────────┴──────────────┴────────────────────┘
```

### 2. Vistrail Selection (Left Panel)

- Lists all 31 vistrails from examples/
- Click to load version tree
- Shows active selection

### 3. Version & Tag Navigation (Middle Panel)

**Version Statistics:**
- Total version count
- Number of tags
- Current version ID

**Tagged Versions (Top):**
- 📌 Visual tag indicator
- Tag name display
- Direct access to important versions

**All Versions (Scrollable):**
- Sorted by version ID (newest first)
- Visual indicators:
  - **Green border**: Current version
  - **Orange border**: Tagged version
  - **Blue highlight**: Selected version
- Shows user and notes for each version

### 4. Workflow Display (Right Panel)

- Version-specific workflow visualization
- Shows version ID, tag name (if any), current status
- Same three tabs: SVG, JSON, VisFlow Mapping
- Each version can have different modules/connections

## Example Workflows

### plot.vt
- **43 versions** with version history
- **1 tag**: "Two Plots" → version 43
- Current version: 43
- Demonstrates evolution of a matplotlib workflow

### mta.vt
- **138 versions** (extensive development history!)
- **0 tags** (no tagged versions)
- Current version: 138
- Shows MTA subway data visualization evolution

### gcd.vt
- **134 versions**
- Current version: 134
- GCD calculation workflow

## API Enhancements

### Fixed `/api/workflow/:id/versions` Endpoint

**Before (broken):**
```julia
notes => get(vistrail.notes, version_id, "")  # ❌ Field doesn't exist
```

**After (working):**
```julia
# Returns comprehensive version tree info
{
  "versions": [
    {
      "id": 43,
      "parent": 42,
      "timestamp": "2025-10-20T...",
      "user": "dakoop",
      "notes": "Added second plot"
    },
    ...
  ],
  "tags": [
    {
      "name": "Two Plots",
      "version_id": 43
    }
  ],
  "current_version": 43,
  "count": 43
}
```

## User Flow

1. **Select a vistrail** from left panel
   - Automatically loads version tree
   - Shows version statistics

2. **Browse versions** in middle panel
   - Tagged versions shown first (if any)
   - All versions listed below
   - Current version has green border

3. **Click a version** to view its workflow
   - Loads that specific version
   - Shows SVG visualization
   - Displays JSON data
   - Shows VisFlow mapping

4. **Navigate between versions** to see workflow evolution
   - Each version may have different modules/connections
   - Compare versions by switching between them
   - Understand workflow development history

## Technical Details

### Version Tree Data Structure

From VisTrailsJL:
```julia
struct Vistrail
    actions::Dict{Int, Action}      # All versions
    tags::Vector{Tag}                # Named pointers
    current_version::Int             # Latest version
    pipelines::Dict{Int, Pipeline}   # Workflows
    # ...
end

struct Action
    id::Int
    prev_id::Int       # Parent version (like git parent)
    timestamp::DateTime
    user::String
    notes::String
    operations::Vector{Any}
    end
end

struct Tag
    name::String
    version_id::Int
end
```

### Version Selection Logic

```javascript
// 1. Load vistrail → Fetch version tree
fetch(`/api/workflow/${id}/versions`)

// 2. Display tagged versions first
tags.forEach(tag => showVersion(tag.version_id, tag.name))

// 3. Show all versions sorted
versions.sort((a, b) => b.id - a.id)

// 4. Load specific version workflow
fetch(`/api/workflow/${id}/version/${versionId}`)
fetch(`/api/workflow/${id}/version/${versionId}/svg`)
```

## Visual Indicators

- 🟩 **Green border**: Current version
- 🟧 **Orange border**: Tagged version
- 🔵 **Blue background**: Selected/active version
- 📌 **Pin icon**: Tag marker

## Testing

Try these workflows to see different version tree patterns:

```bash
# Open demo
open http://localhost:8000/demo

# Click "plot" → See tagged workflow with 43 versions
# Click "mta" → See extensive 138-version history
# Click "gcd" → See 134 versions of algorithm evolution
```

## Next Steps for VisFlow

1. **Implement version tree panel** in VisFlow UI
2. **Add version comparison** view (diff between versions)
3. **Show version graph visualization** (like git graph)
4. **Enable version branching** (create new version from any version)
5. **Add version search/filter** (by user, date, notes)

## Files Modified

- `backend/routes.jl`:
  - Fixed `/api/workflow/:id/versions` endpoint
  - Now returns `versions`, `tags`, and `current_version`
  - Fixed field access: `action.notes` not `vistrail.notes`

- `backend/public/vistrails-demo.html`:
  - Three-panel layout
  - Version list with statistics
  - Tagged versions section
  - Version-specific workflow loading
  - Visual indicators for current/tagged versions

## Result

The demo now correctly represents the VisTrails model:
- ✅ One vistrail = multiple workflow versions
- ✅ Version tree navigation
- ✅ Tagged version highlights
- ✅ Current version indicator
- ✅ Version-specific workflow display
- ✅ Ready for VisFlow integration!

**Try it:** http://localhost:8000/demo
