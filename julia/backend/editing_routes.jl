"""
HTTP Routes for Workflow Editing

Endpoints for visflow-lite integration.
"""

using HTTP
using JSON3

# Load workflow editing operations
include("workflow_editing.jl")

"""
Register editing routes with the HTTP router.
"""
function register_editing_routes!(router)

    # =========================================================================
    # Module Operations
    # =========================================================================

    # Add module to workflow
    # POST /api/workflow/:id/module
    HTTP.register!(router, "POST", "/api/workflow/*/module", req -> begin
        try
            # Extract workflow ID from path
            path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
            workflow_id = path_parts[4]

            # Parse request body
            body = JSON3.read(String(req.body))

            module_type = body.type
            position = (Float64(body.position.x), Float64(body.position.y))
            parameters = get(body, :parameters, Dict())

            # Get or create session
            vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
            if !isfile(vt_file)
                return json_response(Dict("error" => "Workflow not found"), status=404)
            end

            session = get_or_create_session(workflow_id, vt_file)

            # Add module
            module_id, module = add_module!(session, module_type, position, parameters)

            # Return module info
            response = Dict(
                "module_id" => module_id,
                "descriptor" => Dict(
                    "name" => module.descriptor.name,
                    "package" => module.descriptor.package,
                    "input_ports" => [Dict("name" => p.name, "type" => p.type, "optional" => p.optional) for p in module.descriptor.input_ports],
                    "output_ports" => [Dict("name" => p.name, "type" => p.type) for p in module.descriptor.output_ports]
                ),
                "position" => Dict("x" => position[1], "y" => position[2])
            )

            json_response(response)
        catch e
            @error "Error adding module" exception=(e, catch_backtrace())
            error_msg = e isa ErrorException ? e.msg : string(e)
            json_response(Dict("error" => "Failed to add module", "message" => error_msg), status=400)
        end
    end)

    # Update module parameters
    # PUT /api/workflow/:id/module/:module_id
    HTTP.register!(router, "PUT", "/api/workflow/*/module/*", req -> begin
        try
            path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
            workflow_id = path_parts[4]
            module_id = parse(Int, path_parts[6])

            body = JSON3.read(String(req.body))
            parameters = Dict(body.parameters)

            vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
            if !isfile(vt_file)
                return json_response(Dict("error" => "Workflow not found"), status=404)
            end

            session = get_or_create_session(workflow_id, vt_file)
            update_module_parameters!(session, module_id, parameters)

            json_response(Dict("updated" => true, "module_id" => module_id))
        catch e
            @error "Error updating module" exception=(e, catch_backtrace())
            error_msg = e isa ErrorException ? e.msg : string(e)
            json_response(Dict("error" => "Failed to update module", "message" => error_msg), status=400)
        end
    end)

    # Update module position
    # PATCH /api/workflow/:id/module/:module_id/position
    HTTP.register!(router, "PATCH", "/api/workflow/*/module/*/position", req -> begin
        try
            path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
            workflow_id = path_parts[4]
            module_id = parse(Int, path_parts[6])

            body = JSON3.read(String(req.body))
            position = (Float64(body.x), Float64(body.y))

            vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
            if !isfile(vt_file)
                return json_response(Dict("error" => "Workflow not found"), status=404)
            end

            session = get_or_create_session(workflow_id, vt_file)
            update_module_position!(session, module_id, position)

            json_response(Dict(
                "updated" => true,
                "position" => Dict("x" => position[1], "y" => position[2])
            ))
        catch e
            @error "Error updating module position" exception=(e, catch_backtrace())
            error_msg = e isa ErrorException ? e.msg : string(e)
            json_response(Dict("error" => "Failed to update position", "message" => error_msg), status=400)
        end
    end)

    # Delete module
    # DELETE /api/workflow/:id/module/:module_id
    HTTP.register!(router, "DELETE", "/api/workflow/*/module/*", req -> begin
        try
            path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
            workflow_id = path_parts[4]
            module_id = parse(Int, path_parts[6])

            vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
            if !isfile(vt_file)
                return json_response(Dict("error" => "Workflow not found"), status=404)
            end

            session = get_or_create_session(workflow_id, vt_file)
            removed_connections = delete_module!(session, module_id)

            json_response(Dict(
                "deleted" => true,
                "module_id" => module_id,
                "removed_connections" => removed_connections
            ))
        catch e
            @error "Error deleting module" exception=(e, catch_backtrace())
            error_msg = e isa ErrorException ? e.msg : string(e)
            json_response(Dict("error" => "Failed to delete module", "message" => error_msg), status=400)
        end
    end)

    # =========================================================================
    # Connection Operations
    # =========================================================================

    # Add connection
    # POST /api/workflow/:id/connection
    HTTP.register!(router, "POST", "/api/workflow/*/connection", req -> begin
        try
            path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
            workflow_id = path_parts[4]

            body = JSON3.read(String(req.body))

            source_id = Int(body.source_module_id)
            source_port = String(body.source_port)
            dest_id = Int(body.dest_module_id)
            dest_port = String(body.dest_port)

            vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
            if !isfile(vt_file)
                return json_response(Dict("error" => "Workflow not found"), status=404)
            end

            session = get_or_create_session(workflow_id, vt_file)
            conn_id, conn = add_connection!(session, source_id, source_port, dest_id, dest_port)

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

            # Check if it's a type mismatch error
            if occursin("Type mismatch", error_msg) || occursin("Cannot connect", error_msg)
                return json_response(Dict("error" => "ValidationError", "message" => error_msg), status=400)
            end

            json_response(Dict("error" => "Failed to add connection", "message" => error_msg), status=400)
        end
    end)

    # Delete connection
    # DELETE /api/workflow/:id/connection/:connection_id
    HTTP.register!(router, "DELETE", "/api/workflow/*/connection/*", req -> begin
        try
            path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
            workflow_id = path_parts[4]
            connection_id = parse(Int, path_parts[6])

            vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
            if !isfile(vt_file)
                return json_response(Dict("error" => "Workflow not found"), status=404)
            end

            session = get_or_create_session(workflow_id, vt_file)
            delete_connection!(session, connection_id)

            json_response(Dict(
                "deleted" => true,
                "connection_id" => connection_id
            ))
        catch e
            @error "Error deleting connection" exception=(e, catch_backtrace())
            error_msg = e isa ErrorException ? e.msg : string(e)
            json_response(Dict("error" => "Failed to delete connection", "message" => error_msg), status=400)
        end
    end)

    # =========================================================================
    # Workflow Operations
    # =========================================================================

    # Get workflow state
    # GET /api/workflow/:id/state
    HTTP.register!(router, "GET", "/api/workflow/*/state", req -> begin
        try
            path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
            workflow_id = path_parts[4]

            vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
            if !isfile(vt_file)
                return json_response(Dict("error" => "Workflow not found"), status=404)
            end

            session = get_or_create_session(workflow_id, vt_file)
            state = get_workflow_state(session)

            json_response(state)
        catch e
            @error "Error getting workflow state" exception=(e, catch_backtrace())
            json_response(Dict("error" => "Internal server error", "message" => string(e)), status=500)
        end
    end)

    # Save workflow
    # POST /api/workflow/:id/save
    HTTP.register!(router, "POST", "/api/workflow/*/save", req -> begin
        try
            path_parts = split(HTTP.URIs.unescapeuri(req.target), "/")
            workflow_id = path_parts[4]

            body = JSON3.read(String(req.body))
            create_version = get(body, :create_version, true)
            notes = get(body, :notes, "")
            tag = get(body, :tag, nothing)

            vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
            if !isfile(vt_file)
                return json_response(Dict("error" => "Workflow not found"), status=404)
            end

            session = get_or_create_session(workflow_id, vt_file)
            version_id = save_workflow!(session, vt_file,
                                       create_version=create_version,
                                       notes=notes,
                                       tag=tag)

            response = Dict(
                "saved" => true,
                "version_id" => version_id,
                "path" => vt_file
            )
            if tag !== nothing
                response["tag"] = tag
            end

            json_response(response)
        catch e
            @error "Error saving workflow" exception=(e, catch_backtrace())
            json_response(Dict("error" => "Failed to save workflow", "message" => string(e)), status=500)
        end
    end)

    # Create new workflow
    # POST /api/workflow
    HTTP.register!(router, "POST", "/api/workflow", req -> begin
        try
            body = JSON3.read(String(req.body))
            workflow_id = body.id
            name = get(body, :name, workflow_id)

            session = create_new_workflow(workflow_id, name)

            # Create file path
            vt_file = joinpath(@__DIR__, "../../workflows/$(workflow_id).vt")

            # Save initial workflow
            version_id = save_workflow!(session, vt_file,
                                       create_version=false,
                                       notes="Initial workflow creation")

            json_response(Dict(
                "id" => workflow_id,
                "version_id" => version_id,
                "path" => vt_file
            ), status=201)
        catch e
            @error "Error creating workflow" exception=(e, catch_backtrace())
            json_response(Dict("error" => "Failed to create workflow", "message" => string(e)), status=500)
        end
    end)

    # =========================================================================
    # Module Information
    # =========================================================================

    # Get available modules
    # GET /api/modules?package=basic
    HTTP.register!(router, "GET", "/api/modules", req -> begin
        try
            # Parse query parameters
            uri = HTTP.URIs.URI(req.target)
            query = HTTP.URIs.queryparams(uri)
            package_filter = get(query, "package", nothing)

            # Get all modules from registry
            modules = VisTrailsJL.list_modules()

            # Filter by package if specified
            if package_filter !== nothing
                # Map short names to full package names
                package_map = Dict(
                    "basic" => "org.vistrails.vistrails.basic",
                    "julia" => "org.vistrails.vistrails.julia",
                    "pythoncalc" => "org.vistrails.vistrails.pythoncalc",
                    "matplotlib" => "org.vistrails.vistrails.matplotlib",
                    "control_flow" => "org.vistrails.vistrails.control_flow"
                )
                full_package = get(package_map, package_filter, package_filter)

                modules = filter(m -> m[:package] == full_package, modules)
            end

            json_response(Dict("modules" => modules, "count" => length(modules)))
        catch e
            @error "Error listing modules" exception=(e, catch_backtrace())
            json_response(Dict("error" => "Internal server error", "message" => string(e)), status=500)
        end
    end)

    @info "Editing routes registered successfully"
end
