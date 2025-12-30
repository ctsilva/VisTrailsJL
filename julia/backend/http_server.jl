using HTTP
using JSON3
using Logging
using Dates

# Set log level
global_logger(ConsoleLogger(stderr, Logging.Info))

# Load VisTrailsJL from parent project
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using VisTrailsJL

# Load workflow editing functions
include("workflow_editing.jl")

@info "Starting VisTrailsJL Backend Server (HTTP.jl)..."

# Create router
router = HTTP.Router()

# CORS headers for all responses
const CORS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, PUT, PATCH, DELETE, OPTIONS",
    "Access-Control-Allow-Headers" => "Content-Type, Authorization"
]

# Helper to create JSON response
json_response(data; status=200) = HTTP.Response(
    status,
    ["Content-Type" => "application/json"; CORS_HEADERS...],
    JSON3.write(data)
)

# CORS preflight handler
cors_preflight(req) = HTTP.Response(204, CORS_HEADERS)

# Helper to create SVG response
svg_response(svg_content) = HTTP.Response(
    200,
    ["Content-Type" => "image/svg+xml"; CORS_HEADERS...],
    svg_content
)

# Register OPTIONS handlers for CORS preflight
HTTP.register!(router, "OPTIONS", "/api/modules", cors_preflight)
HTTP.register!(router, "OPTIONS", "/api/workflows", cors_preflight)
HTTP.register!(router, "OPTIONS", "/api/workflow/*", cors_preflight)
HTTP.register!(router, "OPTIONS", "/api/workflow/*/module", cors_preflight)
HTTP.register!(router, "OPTIONS", "/api/workflow/*/module/*", cors_preflight)
HTTP.register!(router, "OPTIONS", "/api/workflow/*/module/*/position", cors_preflight)
HTTP.register!(router, "OPTIONS", "/api/workflow/*/module/*/parameters", cors_preflight)
HTTP.register!(router, "OPTIONS", "/api/workflow/*/connection", cors_preflight)
HTTP.register!(router, "OPTIONS", "/api/workflow/*/connection/*", cors_preflight)
HTTP.register!(router, "OPTIONS", "/api/workflow/*/commit", cors_preflight)
HTTP.register!(router, "OPTIONS", "/health", cors_preflight)

# Health check
HTTP.register!(router, "GET", "/health", req -> begin
    json_response(Dict("status" => "healthy", "service" => "VisTrailsJL Backend", "version" => "0.1.0"))
end)

# List available modules
HTTP.register!(router, "GET", "/api/modules", req -> begin
    try
        # Get all registered modules
        module_keys = VisTrailsJL.list_modules()

        # Build list with full details
        modules = []
        for (package, name) in module_keys
            try
                descriptor = VisTrailsJL.get_module_descriptor(package, name)

                push!(modules, Dict(
                    "package" => package,
                    "name" => name,
                    "type" => "$(package)::$(name)",
                    "input_ports" => [
                        Dict(
                            "name" => p.name,
                            "type" => string(p.type),
                            "optional" => p.optional
                        ) for p in descriptor.input_ports
                    ],
                    "output_ports" => [
                        Dict(
                            "name" => p.name,
                            "type" => string(p.type)
                        ) for p in descriptor.output_ports
                    ]
                ))
            catch e
                @warn "Failed to get descriptor for module" package name exception=e
            end
        end

        # Sort by package then name for consistency
        sort!(modules, by = m -> (m["package"], m["name"]))

        json_response(Dict("modules" => modules, "count" => length(modules)))
    catch e
        @error "Error listing modules" exception=(e, catch_backtrace())
        json_response(Dict("error" => "Failed to list modules", "message" => string(e)), status=500)
    end
end)

# Create new workflow
HTTP.register!(router, "POST", "/api/workflows", req -> begin
    try
        # Parse request body
        body = String(req.body)
        data = isempty(body) ? Dict{String,Any}() : JSON3.read(body, Dict{String,Any})

        # Generate random name if not provided
        workflow_name = if haskey(data, "name") && !isempty(get(data, "name", ""))
            data["name"]
        else
            # Generate random name: "workflow_YYYYMMDD_HHMMSS"
            timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
            "workflow_$(timestamp)"
        end
        user = get(data, "user", "visflow-user")

        # Create new vistrail
        vistrail = VisTrailsJL.Vistrail(workflow_name)

        # Create empty initial pipeline as version 1
        empty_pipeline = VisTrailsJL.Pipeline()
        VisTrailsJL.add_version!(
            vistrail,
            empty_pipeline,
            0,  # No parent (root version)
            notes="Initial empty workflow",
            user=user
        )

        # Generate workflow ID from name (sanitize)
        workflow_id = replace(lowercase(workflow_name), r"[^a-z0-9]+" => "_")

        # Make sure ID is unique by appending timestamp if needed
        if haskey(WORKFLOW_SESSIONS, workflow_id)
            workflow_id = "$(workflow_id)_$(Int(floor(time())))"
        end

        # Create workflow session
        session = WorkflowSession(workflow_id, vistrail)
        lock(SESSIONS_LOCK) do
            WORKFLOW_SESSIONS[workflow_id] = session
        end

        @info "Created new workflow" workflow_id name=workflow_name

        json_response(Dict(
            "success" => true,
            "workflow_id" => workflow_id,
            "name" => workflow_name,
            "version_id" => 1,
            "message" => "Workflow created successfully. Use POST /api/workflow/$workflow_id/module to add modules."
        ))
    catch e
        @error "Error creating workflow" exception=(e, catch_backtrace())
        json_response(Dict("error" => "Internal server error", "message" => string(e)), status=500)
    end
end)

# List available workflows
HTTP.register!(router, "GET", "/api/workflows", req -> begin
    try
        examples_dir = joinpath(@__DIR__, "../../examples")
        if !isdir(examples_dir)
            @warn "Examples directory not found: $examples_dir"
            return json_response(Dict("workflows" => [], "count" => 0))
        end

        vt_files = filter(f -> endswith(f, ".vt"), readdir(examples_dir))

        workflows = map(vt_files) do filename
            name = replace(filename, ".vt" => "")
            path = joinpath(examples_dir, filename)

            # Try to get version count
            version_count = 1
            try
                vt = VisTrailsJL.load_vistrail(path)
                version_count = length(vt.actions)
            catch e
                @warn "Could not load workflow for metadata" filename exception=e
            end

            Dict(
                "id" => name,
                "name" => name,
                "path" => filename,
                "size" => filesize(path),
                "modified" => mtime(path),
                "version_count" => version_count
            )
        end

        json_response(workflows)
    catch e
        @error "Error listing workflows" exception=(e, catch_backtrace())
        json_response(Dict("error" => "Internal server error", "message" => string(e)), status=500)
    end
end)

# Helper function to convert pipeline to JSON
function pipeline_to_json(pipeline, vistrail, version_id)
    # Convert modules
    modules = map(collect(pipeline.modules)) do (id, mod)
        # Get position from layout_position if available
        x, y = if mod.layout_position !== nothing
            mod.layout_position
        else
            # Fallback simple layout
            (100.0 + (id * 150.0), 100.0)
        end

        # Get ports from instance-specific port_specs (matching SVG renderer logic)
        # Prefer mod.port_specs over mod.descriptor ports
        inputs = if !isempty(mod.port_specs)
            input_specs = filter(ps -> ps.port_type == :input, mod.port_specs)
            sort!(input_specs, by = ps -> ps.sort_key)
            map(input_specs) do ps
                Dict(
                    "name" => ps.name,
                    "type" => ps.signature
                )
            end
        else
            # Fallback to descriptor ports
            map(mod.descriptor.input_ports) do p
                Dict(
                    "name" => p.name,
                    "type" => string(p.type),
                    "optional" => p.optional
                )
            end
        end

        outputs = if !isempty(mod.port_specs)
            output_specs = filter(ps -> ps.port_type == :output, mod.port_specs)
            sort!(output_specs, by = ps -> ps.sort_key)
            map(output_specs) do ps
                Dict(
                    "name" => ps.name,
                    "type" => ps.signature
                )
            end
        else
            # Fallback to descriptor ports
            map(mod.descriptor.output_ports) do p
                Dict(
                    "name" => p.name,
                    "type" => string(p.type)
                )
            end
        end

        Dict(
            "id" => id,
            "name" => mod.descriptor.name,
            "package" => mod.descriptor.package,
            "x" => x,
            "y" => y,
            "inputs" => inputs,
            "outputs" => outputs,
            "parameters" => mod.parameters,
            "annotations" => mod.annotations
        )
    end

    # Convert connections
    connections = map(pipeline.connections) do conn
        Dict(
            "id" => conn.id,
            "source_id" => conn.source_module_id,
            "source_port" => conn.source_port,
            "target_id" => conn.dest_module_id,
            "target_port" => conn.dest_port
        )
    end

    Dict(
        "modules" => modules,
        "connections" => connections,
        "version_id" => version_id
    )
end

# Get workflow as JSON (current version pipeline)
HTTP.register!(router, "GET", "/api/workflow/*/json", req -> begin
    try
        # Extract workflow ID from path
        path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
        workflow_id = path_parts[4]  # /api/workflow/:id/json

        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")

        if !isfile(vt_file)
            return json_response(Dict("error" => "Workflow not found", "id" => workflow_id), status=404)
        end

        vistrail = VisTrailsJL.load_vistrail_internal(vt_file)
        

        # Get current version pipeline
        current_version = vistrail.current_version
        if !haskey(vistrail.pipelines, current_version)
            return json_response(Dict("error" => "Current version $current_version could not be reconstructed"), status=404)
        end

        pipeline = vistrail.pipelines[current_version]
        workflow_json = pipeline_to_json(pipeline, vistrail, current_version)

        json_response(workflow_json)
    catch e
        @error "Error loading workflow as JSON" exception=(e, catch_backtrace())
        json_response(Dict("error" => "Internal server error", "message" => string(e)), status=500)
    end
end)

# Get workflow metadata
HTTP.register!(router, "GET", "/api/workflow/*", req -> begin
    try
        # Extract workflow ID from path
        path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
        workflow_id = path_parts[4]  # /api/workflow/:id

        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")

        if !isfile(vt_file)
            return json_response(Dict("error" => "Workflow not found", "id" => workflow_id), status=404)
        end

        vistrail = VisTrailsJL.load_vistrail_internal(vt_file)
        

        # Get version information
        versions = map(collect(vistrail.actions)) do (version_id, action)
            Dict("id" => version_id)
        end

        json_response(Dict(
            "id" => workflow_id,
            "name" => workflow_id,
            "current_version" => vistrail.current_version,
            "version_count" => length(vistrail.actions),
            "versions" => versions
        ))
    catch e
        @error "Error loading workflow metadata" exception=(e, catch_backtrace())
        json_response(Dict("error" => "Internal server error", "message" => string(e)), status=500)
    end
end)

# Get version tree SVG
HTTP.register!(router, "GET", "/api/workflow/*/tree/svg", req -> begin
    try
        path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
        workflow_id = path_parts[4]  # /api/workflow/:id/tree/svg

        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")

        if !isfile(vt_file)
            return json_response(Dict("error" => "Workflow not found"), status=404)
        end

        vistrail = VisTrailsJL.load_vistrail_internal(vt_file)
        svg_content = VisTrailsJL.render_version_tree_svg(vistrail)

        svg_response(svg_content)
    catch e
        @error "Error generating version tree SVG" exception=(e, catch_backtrace())
        json_response(Dict("error" => "Internal server error", "message" => string(e)), status=500)
    end
end)

# Get version tree metadata (versions and tags)
HTTP.register!(router, "GET", "/api/workflow/*/versions", req -> begin
    try
        path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
        workflow_id = path_parts[4]  # /api/workflow/:id/versions

        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")

        if !isfile(vt_file)
            return json_response(Dict("error" => "Workflow not found"), status=404)
        end

        vistrail = VisTrailsJL.load_vistrail_internal(vt_file)
        

        # Build version tree with all actions
        versions = map(collect(vistrail.actions)) do (version_id, action)
            Dict(
                "id" => version_id,
                "parent" => action.prev_id,
                "timestamp" => action.timestamp,
                "user" => action.user,
                "notes" => action.notes
            )
        end

        # Build tags list
        tags = map(vistrail.tags) do tag
            Dict(
                "name" => tag.name,
                "version_id" => tag.version_id
            )
        end

        json_response(Dict(
            "versions" => versions,
            "tags" => tags,
            "current_version" => vistrail.current_version,
            "count" => length(versions)
        ))
    catch e
        @error "Error getting versions" exception=(e, catch_backtrace())
        json_response(Dict("error" => "Internal server error", "message" => string(e)), status=500)
    end
end)

# Get workflow version as JSON
HTTP.register!(router, "GET", "/api/workflow/*/version/*/json", req -> begin
    try
        path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
        workflow_id = path_parts[4]  # /api/workflow/:id/version/:version_id/json
        version_id = parse(Int, path_parts[6])

        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")

        if !isfile(vt_file)
            return json_response(Dict("error" => "Workflow not found"), status=404)
        end

        vistrail = VisTrailsJL.load_vistrail_internal(vt_file, version=version_id)
        

        if haskey(vistrail.pipelines, version_id)
            pipeline = vistrail.pipelines[version_id]
            workflow_json = pipeline_to_json(pipeline, vistrail, version_id)
            json_response(workflow_json)
        else
            json_response(Dict("error" => "Version $version_id could not be reconstructed"), status=404)
        end
    catch e
        @error "Error generating workflow JSON" exception=(e, catch_backtrace())
        json_response(Dict("error" => "Internal server error", "message" => string(e)), status=500)
    end
end)

# Get workflow version SVG
HTTP.register!(router, "GET", "/api/workflow/*/version/*/svg", req -> begin
    try
        path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
        workflow_id = path_parts[4]  # /api/workflow/:id/version/:version_id/svg
        version_id = parse(Int, path_parts[6])

        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")

        if !isfile(vt_file)
            return json_response(Dict("error" => "Workflow not found"), status=404)
        end

        vistrail = VisTrailsJL.load_vistrail_internal(vt_file, version=version_id)
        

        if haskey(vistrail.pipelines, version_id)
            pipeline = vistrail.pipelines[version_id]
            svg_content = VisTrailsJL.render_pipeline_svg(pipeline)
            svg_response(svg_content)
        else
            json_response(Dict("error" => "Version $version_id could not be reconstructed"), status=404)
        end
    catch e
        @error "Error generating workflow SVG" exception=(e, catch_backtrace())
        json_response(Dict("error" => "Internal server error", "message" => string(e)), status=500)
    end
end)

# =========================================================================
# Workflow Editing Operations
# =========================================================================

# Add module to workflow
HTTP.register!(router, "POST", "/api/workflow/*/module", req -> begin
    try
        path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
        workflow_id = path_parts[4]

        body = JSON3.read(String(req.body))
        module_type = body.type
        position = (Float64(body.position.x), Float64(body.position.y))
        # Convert JSON3 object to Dict with String keys
        parameters = if haskey(body, :parameters)
            Dict{String,Any}(String(k) => v for (k, v) in pairs(body.parameters))
        else
            Dict{String,Any}()
        end

        # Get session (works for both new workflows and existing .vt files)
        session = if haskey(WORKFLOW_SESSIONS, workflow_id)
            WORKFLOW_SESSIONS[workflow_id]
        else
            vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
            if !isfile(vt_file)
                return json_response(Dict("error" => "Workflow not found"), status=404)
            end
            get_or_create_session(workflow_id, vt_file)
        end

        result = add_module!(session, module_type, position, parameters)
        module_id = result[1]
        module_obj = result[2]

        json_response(Dict(
            "module_id" => module_id,
            "descriptor" => Dict(
                "name" => module_obj.descriptor.name,
                "package" => module_obj.descriptor.package,
                "input_ports" => [Dict("name" => p.name, "type" => string(p.type), "optional" => p.optional) for p in module_obj.descriptor.input_ports],
                "output_ports" => [Dict("name" => p.name, "type" => string(p.type)) for p in module_obj.descriptor.output_ports]
            ),
            "position" => Dict("x" => position[1], "y" => position[2]),
            "parameters" => parameters
        ))
    catch e
        @error "Error adding module" exception=(e, catch_backtrace())
        error_msg = e isa ErrorException ? e.msg : string(e)
        json_response(Dict("error" => "Failed to add module", "message" => error_msg), status=400)
    end
end)

# Update module position
HTTP.register!(router, "PATCH", "/api/workflow/*/module/*/position", req -> begin
    try
        path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
        workflow_id = path_parts[4]
        module_id = parse(Int, path_parts[6])

        body = JSON3.read(String(req.body))
        position = (Float64(body.x), Float64(body.y))

        session = get(WORKFLOW_SESSIONS, workflow_id, nothing)
        if session === nothing
            vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
            if !isfile(vt_file)
                return json_response(Dict("error" => "Workflow not found"), status=404)
            end
            session = get_or_create_session(workflow_id, vt_file)
        end

        update_module_position!(session, module_id, position)

        json_response(Dict(
            "success" => true,
            "module_id" => module_id,
            "position" => Dict("x" => position[1], "y" => position[2])
        ))
    catch e
        @error "Error updating module position" exception=(e, catch_backtrace())
        error_msg = e isa ErrorException ? e.msg : string(e)
        json_response(Dict("error" => "Failed to update position", "message" => error_msg), status=400)
    end
end)

# Update module parameters
HTTP.register!(router, "PATCH", "/api/workflow/*/module/*/parameters", req -> begin
    try
        path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
        workflow_id = path_parts[4]
        module_id = parse(Int, path_parts[6])

        body = JSON3.read(String(req.body))
        parameters = Dict{String,Any}(String(k) => v for (k, v) in pairs(body))

        session = get(WORKFLOW_SESSIONS, workflow_id, nothing)
        if session === nothing
            vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
            if !isfile(vt_file)
                return json_response(Dict("error" => "Workflow not found"), status=404)
            end
            session = get_or_create_session(workflow_id, vt_file)
        end

        update_module_parameters!(session, module_id, parameters)

        json_response(Dict(
            "success" => true,
            "module_id" => module_id,
            "parameters" => parameters
        ))
    catch e
        @error "Error updating module parameters" exception=(e, catch_backtrace())
        error_msg = e isa ErrorException ? e.msg : string(e)
        json_response(Dict("error" => "Failed to update parameters", "message" => error_msg), status=400)
    end
end)

# Add connection between modules
HTTP.register!(router, "POST", "/api/workflow/*/connection", req -> begin
    try
        path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
        workflow_id = path_parts[4]

        body = JSON3.read(String(req.body))
        source_id = Int(body.source_module_id)
        source_port = String(body.source_port)
        dest_id = Int(body.dest_module_id)
        dest_port = String(body.dest_port)

        session = get(WORKFLOW_SESSIONS, workflow_id, nothing)
        if session === nothing
            vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
            if !isfile(vt_file)
                return json_response(Dict("error" => "Workflow not found"), status=404)
            end
            session = get_or_create_session(workflow_id, vt_file)
        end

        result = add_connection!(session, source_id, source_port, dest_id, dest_port)
        conn_id = result[1]

        json_response(Dict(
            "connection_id" => conn_id,
            "source_module_id" => source_id,
            "source_port" => source_port,
            "dest_module_id" => dest_id,
            "dest_port" => dest_port
        ))
    catch e
        @error "Error adding connection" exception=(e, catch_backtrace())
        error_msg = e isa ErrorException ? e.msg : string(e)

        if occursin("Type mismatch", error_msg) || occursin("Cannot connect", error_msg)
            return json_response(Dict("error" => "ValidationError", "message" => error_msg), status=400)
        end

        json_response(Dict("error" => "Failed to add connection", "message" => error_msg), status=400)
    end
end)

# Delete connection
HTTP.register!(router, "DELETE", "/api/workflow/*/connection/*", req -> begin
    try
        path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
        workflow_id = path_parts[4]
        connection_id = parse(Int, path_parts[6])

        session = get(WORKFLOW_SESSIONS, workflow_id, nothing)
        if session === nothing
            vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
            if !isfile(vt_file)
                return json_response(Dict("error" => "Workflow not found"), status=404)
            end
            session = get_or_create_session(workflow_id, vt_file)
        end

        delete_connection!(session, connection_id)

        json_response(Dict(
            "success" => true,
            "connection_id" => connection_id
        ))
    catch e
        @error "Error deleting connection" exception=(e, catch_backtrace())
        error_msg = e isa ErrorException ? e.msg : string(e)
        json_response(Dict("error" => "Failed to delete connection", "message" => error_msg), status=400)
    end
end)

# =========================================================================
# Version Control
# =========================================================================

# Commit workflow changes (create new version)
HTTP.register!(router, "POST", "/api/workflow/*/commit", req -> begin
    try
        # Parse workflow ID from path
        path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
        workflow_id = path_parts[4]  # /api/workflow/:id/commit

        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")

        if !isfile(vt_file)
            return json_response(Dict("error" => "Workflow not found", "id" => workflow_id), status=404)
        end

        # Parse request body for commit notes
        body = String(req.body)
        data = isempty(body) ? Dict{String,Any}() : JSON3.read(body, Dict{String,Any})

        notes = get(data, "notes", "Updated from VisFlow-Lite")
        user = get(data, "user", "visflow-user")

        # Get or create editing session
        session = get_or_create_session(workflow_id, vt_file)

        lock(session.lock) do
            # Get the edited pipeline from the session
            edited_pipeline = session.current_pipeline
            parent_version_id = session.vistrail.current_version

            # Create a new version with the edited pipeline
            new_version_id = VisTrailsJL.add_version!(
                session.vistrail,
                edited_pipeline,
                parent_version_id,
                notes=notes,
                user=user
            )

            # Mark as saved
            session.modified = false
            session.last_saved = now()

            # TODO: Implement save_vistrail to persist changes to disk
            # For now, this only updates the in-memory state
            @warn "save_vistrail not yet implemented - changes are in-memory only" workflow_id new_version_id

            json_response(Dict(
                "success" => true,
                "workflow_id" => workflow_id,
                "new_version_id" => new_version_id,
                "parent_version_id" => parent_version_id,
                "notes" => notes,
                "user" => user,
                "module_count" => length(edited_pipeline.modules),
                "connection_count" => length(edited_pipeline.connections),
                "warning" => "Changes not persisted to disk (save_vistrail not implemented)"
            ))
        end
    catch e
        @error "Error committing workflow" exception=(e, catch_backtrace())
        json_response(Dict("error" => "Internal server error", "message" => string(e)), status=500)
    end
end)

# Start server
port = parse(Int, get(ENV, "PORT", "8000"))

@info "Server configured"
@info "API will be available at http://localhost:$port"
@info "Try: http://localhost:$port/health"
@info ""

server = HTTP.serve!(router, "0.0.0.0", port; verbose=true, stream=false)

@info "Server running. Press Ctrl+C to stop."
wait(server)
