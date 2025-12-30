"""
Workflow Editing Operations

Core functionality for modifying workflows in-memory.
Used by the HTTP API to enable visual editing in visflow-lite.
"""

using Dates
using VisTrailsJL

"""
    WorkflowSession

Represents an active editing session for a workflow.
Maintains in-memory state and tracks modifications.
"""
mutable struct WorkflowSession
    workflow_id::String
    vistrail::VisTrailsJL.Vistrail
    current_pipeline::VisTrailsJL.Pipeline
    modified::Bool
    last_saved::DateTime
    lock::ReentrantLock

    function WorkflowSession(workflow_id::String, vistrail::VisTrailsJL.Vistrail)
        # Get current pipeline or create empty one
        if !isempty(vistrail.pipelines)
            pipeline = vistrail.pipelines[vistrail.current_version]
        else
            pipeline = VisTrailsJL.Pipeline()
        end

        new(workflow_id, vistrail, pipeline, false, now(), ReentrantLock())
    end
end

# Global session management
const WORKFLOW_SESSIONS = Dict{String, WorkflowSession}()
const SESSIONS_LOCK = ReentrantLock()

"""
    get_or_create_session(workflow_id::String, vistrail_path::String) -> WorkflowSession

Get existing session or create new one for a workflow.
"""
function get_or_create_session(workflow_id::String, vistrail_path::String)
    lock(SESSIONS_LOCK) do
        if haskey(WORKFLOW_SESSIONS, workflow_id)
            return WORKFLOW_SESSIONS[workflow_id]
        end

        # Load vistrail
        vistrail = VisTrailsJL.load_vistrail_internal(vistrail_path)

        # Create session
        session = WorkflowSession(workflow_id, vistrail)
        WORKFLOW_SESSIONS[workflow_id] = session

        return session
    end
end

"""
    generate_module_id(pipeline::VisTrailsJL.Pipeline) -> Int

Generate a unique module ID for the pipeline.
"""
function generate_module_id(pipeline::VisTrailsJL.Pipeline)
    if isempty(pipeline.modules)
        return 1
    end
    return maximum(keys(pipeline.modules)) + 1
end

"""
    generate_connection_id(pipeline::VisTrailsJL.Pipeline) -> Int

Generate a unique connection ID for the pipeline.
"""
function generate_connection_id(pipeline::VisTrailsJL.Pipeline)
    if isempty(pipeline.connections)
        return 1
    end
    # Find max ID from existing connections
    max_id = maximum(conn.id for conn in pipeline.connections)
    return max_id + 1
end

"""
    parse_module_type(type_str::String) -> (package::String, name::String)

Parse module type string like "basic:Integer" into package and name.
"""
function parse_module_type(type_str::String)
    if occursin("::", type_str)
        # Full format: "org.vistrails.vistrails.basic::Integer"
        parts = split(type_str, "::")
        return String(parts[1]), String(parts[2])
    elseif occursin(":", type_str)
        # Short format: "basic:Integer"
        parts = split(type_str, ":")
        package_short = String(parts[1])
        name = String(parts[2])

        # Map short names to full package identifiers
        package_map = Dict(
            "basic" => "org.vistrails.vistrails.basic",
            "julia" => "org.vistrails.vistrails.julia",
            "pythoncalc" => "org.vistrails.vistrails.pythoncalc",
            "matplotlib" => "org.vistrails.vistrails.matplotlib",
            "control_flow" => "org.vistrails.vistrails.control_flow"
        )

        package = get(package_map, package_short, package_short)
        return package, name
    else
        error("Invalid module type format: $type_str")
    end
end

"""
    add_module!(session::WorkflowSession, module_type::String,
                position::Tuple{Float64, Float64},
                parameters::Dict=Dict()) -> (Int, VisTrailsJL.ModuleInstance)

Add a new module to the pipeline.
"""
function add_module!(session::WorkflowSession, module_type::String,
                     position::Tuple{Float64, Float64},
                     parameters::Dict=Dict())
    lock(session.lock) do
        # Parse module type
        package, name = parse_module_type(module_type)

        # Get module descriptor from registry
        descriptor = VisTrailsJL.get_module_descriptor(package, name)

        # Generate new ID
        module_id = generate_module_id(session.current_pipeline)

        # Create module instance (using the constructor that only takes id and descriptor)
        mod = VisTrailsJL.ModuleInstance(module_id, descriptor)

        # Set additional fields
        mod.parameters = copy(parameters)
        mod.layout_position = position

        # Add to pipeline
        session.current_pipeline.modules[module_id] = mod
        session.modified = true

        return module_id, mod
    end
end

"""
    update_module_parameters!(session::WorkflowSession, module_id::Int,
                              parameters::Dict) -> Bool

Update module parameters.
"""
function update_module_parameters!(session::WorkflowSession, module_id::Int,
                                   parameters::Dict)
    lock(session.lock) do
        if !haskey(session.current_pipeline.modules, module_id)
            error("Module $module_id not found")
        end

        mod = session.current_pipeline.modules[module_id]

        # Update parameters
        for (key, value) in parameters
            mod.parameters[key] = value
        end

        session.modified = true
        return true
    end
end

"""
    update_module_position!(session::WorkflowSession, module_id::Int,
                           position::Tuple{Float64, Float64}) -> Bool

Update module position on canvas.
"""
function update_module_position!(session::WorkflowSession, module_id::Int,
                                 position::Tuple{Float64, Float64})
    lock(session.lock) do
        if !haskey(session.current_pipeline.modules, module_id)
            error("Module $module_id not found")
        end

        mod = session.current_pipeline.modules[module_id]
        mod.layout_position = position
        session.modified = true

        return true
    end
end

"""
    delete_module!(session::WorkflowSession, module_id::Int) -> Vector{Int}

Delete a module and return IDs of removed connections.
"""
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

"""
    get_port_type(descriptor::VisTrailsJL.ModuleDescriptor, port_name::String,
                  is_output::Bool) -> Type

Get the type of a port from a module descriptor.
"""
function get_port_type(descriptor::VisTrailsJL.ModuleDescriptor, port_name::String,
                       is_output::Bool)
    ports = is_output ? descriptor.output_ports : descriptor.input_ports

    for port in ports
        if port.name == port_name
            return port.type
        end
    end

    port_type = is_output ? "output" : "input"
    error("Port '$port_name' not found in $port_type ports of $(descriptor.name)")
end

"""
    are_types_compatible(source_type::Type, dest_type::Type) -> Bool

Check if two port types are compatible for connection.
"""
function are_types_compatible(source_type::Type, dest_type::Type)
    # Exact match
    if source_type == dest_type
        return true
    end

    # Any is universal (accepts any type)
    if source_type == Any || dest_type == Any
        return true
    end

    # Check if source type is a subtype of destination type
    # This allows more specific types to connect to more general types
    if source_type <: dest_type
        return true
    end

    # Allow numeric type conversions
    # Int can connect to Float, Float can connect to Number, etc.
    if source_type <: Number && dest_type <: Number
        return true
    end

    # String types are compatible
    if source_type <: AbstractString && dest_type <: AbstractString
        return true
    end

    return false
end

"""
    add_connection!(session::WorkflowSession,
                   source_id::Int, source_port::String,
                   dest_id::Int, dest_port::String) -> (Int, VisTrailsJL.Connection)

Add a connection between two modules.
Validates port types before adding.
"""
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

        source_mod = pipeline.modules[source_id]
        dest_mod = pipeline.modules[dest_id]

        # Get port types
        source_type = get_port_type(source_mod.descriptor, source_port, true)
        dest_type = get_port_type(dest_mod.descriptor, dest_port, false)

        # Check compatibility
        if !are_types_compatible(source_type, dest_type)
            error("Type mismatch: Cannot connect $source_type to $dest_type")
        end

        # Generate connection ID
        conn_id = generate_connection_id(pipeline)

        # Create connection (using positional constructor)
        conn = VisTrailsJL.Connection(
            conn_id,
            source_id,
            source_port,
            dest_id,
            dest_port
        )

        # Add to pipeline
        push!(pipeline.connections, conn)
        session.modified = true

        return conn_id, conn
    end
end

"""
    delete_connection!(session::WorkflowSession, connection_id::Int) -> Bool

Delete a connection.
"""
function delete_connection!(session::WorkflowSession, connection_id::Int)
    lock(session.lock) do
        pipeline = session.current_pipeline

        # Find and remove connection
        idx = findfirst(c -> c.id == connection_id, pipeline.connections)

        if idx === nothing
            error("Connection $connection_id not found")
        end

        deleteat!(pipeline.connections, idx)
        session.modified = true

        return true
    end
end

"""
    save_workflow!(session::WorkflowSession, file_path::String;
                  create_version::Bool=true,
                  notes::String="",
                  tag::Union{String,Nothing}=nothing) -> Int

Save workflow to .vt file.
Optionally creates a new version in the version tree.
"""
function save_workflow!(session::WorkflowSession, file_path::String;
                       create_version::Bool=true,
                       notes::String="",
                       tag::Union{String,Nothing}=nothing)
    lock(session.lock) do
        vistrail = session.vistrail
        pipeline = session.current_pipeline

        if create_version
            # Create new version with current pipeline
            version_id = VisTrailsJL.add_version!(
                vistrail,
                pipeline,
                vistrail.current_version,
                notes=notes
            )

            # Add tag if provided
            if tag !== nothing
                VisTrailsJL.add_tag!(vistrail, tag, version_id)
            end

            vistrail.current_version = version_id
        else
            # Update current version in place
            vistrail.pipelines[vistrail.current_version] = pipeline
        end

        # Save to .vt file
        # TODO: Implement save_vistrail function
        # For now, we'll need to use the XML writer
        @info "Saving workflow to $file_path (save functionality pending)"

        session.modified = false
        session.last_saved = now()

        return vistrail.current_version
    end
end

"""
    create_new_workflow(workflow_id::String, name::String="") -> WorkflowSession

Create a new empty workflow.
"""
function create_new_workflow(workflow_id::String, name::String="")
    lock(SESSIONS_LOCK) do
        if haskey(WORKFLOW_SESSIONS, workflow_id)
            error("Workflow '$workflow_id' already exists")
        end

        # Create new vistrail
        vistrail = VisTrailsJL.Vistrail(isempty(name) ? workflow_id : name)

        # Create initial empty pipeline
        pipeline = VisTrailsJL.Pipeline()

        # Add as version 1
        version_id = VisTrailsJL.add_version!(
            vistrail,
            pipeline,
            0,
            notes="Initial workflow creation"
        )

        # Create session
        session = WorkflowSession(workflow_id, vistrail)
        WORKFLOW_SESSIONS[workflow_id] = session

        return session
    end
end

"""
    get_workflow_state(session::WorkflowSession) -> Dict

Get current workflow state as a dictionary.
"""
function get_workflow_state(session::WorkflowSession)
    lock(session.lock) do
        return Dict(
            "workflow_id" => session.workflow_id,
            "current_version" => session.vistrail.current_version,
            "modified" => session.modified,
            "last_saved" => session.last_saved,
            "module_count" => length(session.current_pipeline.modules),
            "connection_count" => length(session.current_pipeline.connections)
        )
    end
end
