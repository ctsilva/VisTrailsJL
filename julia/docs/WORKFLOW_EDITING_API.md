# Workflow Editing API Design

API design for visflow-lite integration, enabling visual workflow editing.

## Design Principles

1. **Incremental Updates**: Frontend sends small, atomic changes (add module, move module, etc.)
2. **Immediate Feedback**: Backend responds with updated workflow state
3. **Version Tracking**: Each change can optionally create a new version
4. **Undo/Redo Support**: Changes are reversible via version navigation
5. **Real-time Sync**: Multiple clients can edit the same workflow (future)

## Frontend-Backend Communication Flow

```
┌──────────────┐                    ┌──────────────┐
│ visflow-lite │ ←─── WebSocket ──→ │   Backend    │
│  (Frontend)  │                    │   (Julia)    │
└──────────────┘                    └──────────────┘
       │                                   │
       │ User adds module                  │
       ├─→ POST /api/workflow/xyz/module   │
       │                                   ├─→ Add to pipeline
       │                                   ├─→ Assign ID
       │   ← 200 OK {module_id: 7}        ←┤
       │                                   │
       │ User moves module                 │
       ├─→ PATCH .../module/7/position    │
       │   {x: 250, y: 150}               │
       │                                   ├─→ Update position
       │   ← 200 OK {updated: true}       ←┤
       │                                   │
       │ User connects modules             │
       ├─→ POST .../connection             │
       │   {source: 7, target: 3, ...}    │
       │                                   ├─→ Validate & add
       │   ← 200 OK {connection_id: 12}   ←┤
       │                                   │
       │ User saves workflow               │
       ├─→ POST .../save                   │
       │   {create_version: true}         │
       │                                   ├─→ Create version
       │                                   ├─→ Save to .vt file
       │   ← 200 OK {version: 38}         ←┤
```

## API Endpoints

### 1. Module Operations

#### Add Module
```http
POST /api/workflow/:id/module
Content-Type: application/json

{
  "type": "org.vistrails.vistrails.basic::Integer",
  "position": {"x": 100, "y": 200},
  "parameters": {
    "value": 42
  }
}

Response 200:
{
  "module_id": 7,
  "descriptor": {
    "name": "Integer",
    "package": "org.vistrails.vistrails.basic",
    "input_ports": [...],
    "output_ports": [{"name": "value", "type": "basic:Integer"}]
  }
}
```

#### Update Module Parameters
```http
PUT /api/workflow/:id/module/:module_id
Content-Type: application/json

{
  "parameters": {
    "value": 100
  }
}

Response 200:
{
  "updated": true,
  "module_id": 7
}
```

#### Update Module Position
```http
PATCH /api/workflow/:id/module/:module_id/position
Content-Type: application/json

{
  "x": 250.5,
  "y": 150.0
}

Response 200:
{
  "updated": true,
  "position": {"x": 250.5, "y": 150.0}
}
```

#### Delete Module
```http
DELETE /api/workflow/:id/module/:module_id

Response 200:
{
  "deleted": true,
  "module_id": 7,
  "removed_connections": [12, 13]  # Connections that were also removed
}
```

### 2. Connection Operations

#### Add Connection
```http
POST /api/workflow/:id/connection
Content-Type: application/json

{
  "source_module_id": 7,
  "source_port": "value",
  "dest_module_id": 3,
  "dest_port": "input"
}

Response 200:
{
  "connection_id": 12,
  "source_module_id": 7,
  "source_port": "value",
  "dest_module_id": 3,
  "dest_port": "input"
}

Response 400:  # Validation error
{
  "error": "Type mismatch",
  "details": "Cannot connect Integer to String"
}
```

#### Delete Connection
```http
DELETE /api/workflow/:id/connection/:connection_id

Response 200:
{
  "deleted": true,
  "connection_id": 12
}
```

### 3. Workflow Operations

#### Save Workflow
```http
POST /api/workflow/:id/save
Content-Type: application/json

{
  "create_version": true,
  "notes": "Added input validation",
  "tag": "v1.2"  # optional
}

Response 200:
{
  "saved": true,
  "version_id": 38,
  "path": "workflows/myworkflow.vt",
  "tag": "v1.2"
}
```

#### Create New Workflow
```http
POST /api/workflow
Content-Type: application/json

{
  "name": "new_workflow",
  "description": "My new workflow"
}

Response 201:
{
  "id": "new_workflow",
  "version_id": 1,
  "path": "workflows/new_workflow.vt"
}
```

#### Get Workflow State
```http
GET /api/workflow/:id/state

Response 200:
{
  "modules": [...],
  "connections": [...],
  "current_version": 37,
  "modified": true,  # Has unsaved changes
  "last_saved": "2025-12-28T10:30:00Z"
}
```

### 4. Validation & Information

#### Validate Connection
```http
POST /api/workflow/:id/validate-connection
Content-Type: application/json

{
  "source_module_id": 7,
  "source_port": "value",
  "dest_module_id": 3,
  "dest_port": "input"
}

Response 200:
{
  "valid": true
}

Response 400:
{
  "valid": false,
  "error": "Type mismatch: Integer → String"
}
```

#### Get Available Modules
```http
GET /api/modules?package=basic

Response 200:
{
  "modules": [
    {
      "name": "Integer",
      "package": "org.vistrails.vistrails.basic",
      "input_ports": [],
      "output_ports": [{"name": "value", "type": "basic:Integer"}],
      "description": "Integer constant"
    },
    ...
  ]
}
```

#### Get Module Descriptor
```http
GET /api/module/:package/:name

Response 200:
{
  "name": "PythonCalc",
  "package": "org.vistrails.vistrails.pythoncalc",
  "input_ports": [
    {"name": "value1", "type": "basic:Float", "optional": false},
    {"name": "value2", "type": "basic:Float", "optional": false}
  ],
  "output_ports": [
    {"name": "value", "type": "basic:Float"}
  ],
  "parameters": [
    {"name": "op", "type": "basic:String", "default": "+"}
  ]
}
```

## Backend Implementation Requirements

### In-Memory Workflow State

The backend needs to maintain workflow state in memory:

```julia
mutable struct WorkflowSession
    workflow_id::String
    vistrail::Vistrail
    current_pipeline::Pipeline
    modified::Bool
    last_saved::DateTime
    lock::ReentrantLock  # For thread safety
end

# Global state management
const WORKFLOW_SESSIONS = Dict{String, WorkflowSession}()
```

### Core Operations

```julia
# Add module to pipeline
function add_module!(session::WorkflowSession, module_type::String,
                     position::Tuple{Float64, Float64},
                     parameters::Dict)
    lock(session.lock) do
        # Create module descriptor
        descriptor = get_module_descriptor_from_type(module_type)

        # Generate new ID
        module_id = generate_module_id(session.current_pipeline)

        # Create module instance
        module = ModuleInstance(
            id=module_id,
            descriptor=descriptor,
            parameters=parameters,
            layout_position=position
        )

        # Add to pipeline
        session.current_pipeline.modules[module_id] = module
        session.modified = true

        return module_id, module
    end
end

# Update module position
function update_module_position!(session::WorkflowSession,
                                 module_id::Int,
                                 position::Tuple{Float64, Float64})
    lock(session.lock) do
        if !haskey(session.current_pipeline.modules, module_id)
            error("Module $module_id not found")
        end

        module = session.current_pipeline.modules[module_id]
        module.layout_position = position
        session.modified = true

        return true
    end
end

# Add connection
function add_connection!(session::WorkflowSession,
                        source_id::Int, source_port::String,
                        dest_id::Int, dest_port::String)
    lock(session.lock) do
        pipeline = session.current_pipeline

        # Validate modules exist
        if !haskey(pipeline.modules, source_id)
            error("Source module $source_id not found")
        end
        if !haskey(pipeline.modules, dest_id)
            error("Destination module $dest_id not found")
        end

        # Validate port types match
        source_mod = pipeline.modules[source_id]
        dest_mod = pipeline.modules[dest_id]

        # Get port types from descriptors
        source_port_type = get_output_port_type(source_mod.descriptor, source_port)
        dest_port_type = get_input_port_type(dest_mod.descriptor, dest_port)

        # Check compatibility
        if !are_types_compatible(source_port_type, dest_port_type)
            error("Type mismatch: $source_port_type → $dest_port_type")
        end

        # Generate connection ID
        conn_id = generate_connection_id(pipeline)

        # Create connection
        conn = Connection(
            id=conn_id,
            source_module_id=source_id,
            source_port=source_port,
            dest_module_id=dest_id,
            dest_port=dest_port
        )

        # Add to pipeline
        push!(pipeline.connections, conn)
        session.modified = true

        return conn_id, conn
    end
end

# Delete module
function delete_module!(session::WorkflowSession, module_id::Int)
    lock(session.lock) do
        pipeline = session.current_pipeline

        if !haskey(pipeline.modules, module_id)
            error("Module $module_id not found")
        end

        # Find and remove all connections to/from this module
        removed_connections = Int[]
        filter!(pipeline.connections) do conn
            if conn.source_module_id == module_id || conn.dest_module_id == module_id
                push!(removed_connections, conn.id)
                return false
            end
            return true
        end

        # Remove module
        delete!(pipeline.modules, module_id)
        session.modified = true

        return removed_connections
    end
end

# Save workflow
function save_workflow!(session::WorkflowSession;
                       create_version::Bool=true,
                       notes::String="",
                       tag::Union{String,Nothing}=nothing)
    lock(session.lock) do
        vistrail = session.vistrail
        pipeline = session.current_pipeline

        if create_version
            # Create new version with current pipeline
            version_id = add_version!(
                vistrail,
                pipeline,
                vistrail.current_version,
                notes=notes
            )

            # Add tag if provided
            if tag !== nothing
                add_tag!(vistrail, tag, version_id)
            end

            vistrail.current_version = version_id
        end

        # Save to .vt file
        file_path = get_workflow_file_path(session.workflow_id)
        save_vistrail(vistrail, file_path)

        session.modified = false
        session.last_saved = now()

        return vistrail.current_version
    end
end
```

### Type Validation

```julia
function are_types_compatible(source_type::String, dest_type::String)
    # Exact match
    if source_type == dest_type
        return true
    end

    # Module type (generic match)
    if source_type == "basic:Module" || dest_type == "basic:Module"
        return true
    end

    # Check subtype relationships (would need registry)
    # For now, simple string matching
    return false
end

function get_output_port_type(descriptor::ModuleDescriptor, port_name::String)
    for port in descriptor.output_ports
        if port.name == port_name
            return port.type
        end
    end
    error("Output port '$port_name' not found")
end

function get_input_port_type(descriptor::ModuleDescriptor, port_name::String)
    for port in descriptor.input_ports
        if port.name == port_name
            return port.type
        end
    end
    error("Input port '$port_name' not found")
end
```

## Error Handling

All endpoints should return structured errors:

```json
{
  "error": "ValidationError",
  "message": "Cannot connect Integer to String",
  "details": {
    "source_type": "basic:Integer",
    "dest_type": "basic:String",
    "source_module": 7,
    "dest_module": 3
  }
}
```

Error types:
- `ValidationError` - Invalid operation (type mismatch, etc.)
- `NotFoundError` - Module/connection/workflow not found
- `ConflictError` - Concurrent modification
- `InternalError` - Server error

## Implementation Priority

1. **Phase 1: Core Module Operations** (Week 1)
   - Add module
   - Update module position
   - Delete module

2. **Phase 2: Connection Operations** (Week 1)
   - Add connection
   - Delete connection
   - Validate connection

3. **Phase 3: Workflow Management** (Week 2)
   - Save workflow
   - Create new workflow
   - Get workflow state

4. **Phase 4: Information & Discovery** (Week 2)
   - Get available modules
   - Get module descriptor
   - Module search/filter

5. **Phase 5: Advanced Features** (Future)
   - Undo/redo
   - Real-time collaboration
   - Conflict resolution

## Testing Strategy

### Unit Tests
- Test each operation in isolation
- Validate error conditions
- Test type checking

### Integration Tests
- Test workflow creation flow
- Test module addition → connection → save
- Test error recovery

### Frontend Integration
- Test with visflow-lite
- Test drag-and-drop workflow creation
- Test real-time updates

## Next Steps

1. ✅ Design API (this document)
2. 🔄 Implement core operations in `julia/backend/workflow_editing.jl`
3. 🔄 Add routes to `julia/backend/http_server.jl`
4. 🔄 Create test suite
5. 🔄 Document for visflow-lite integration
6. 🔄 Test with frontend

This API design provides the foundation for visual workflow editing in visflow-lite!
