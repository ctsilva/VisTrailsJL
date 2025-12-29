# Load VisTrailsJL from parent project FIRST
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using VisTrailsJL

# Now load other dependencies
using Genie.Router
using Genie.Requests
using Genie.Renderer.Json
using HTTP
using JSON3
using Dates

# Load workflow editing operations
include("workflow_editing.jl")

# Health check
route("/health") do
    json(Dict("status" => "healthy", "service" => "VisTrailsJL Backend", "version" => "0.1.0"))
end

# Get workflow as JSON
# GET /api/workflow/:id
# Example: /api/workflow/gcd or /api/workflow/1 (version number)
route("/api/workflow/:id", method = GET) do
    try
        workflow_id = payload(:id)

        # For now, load from examples directory
        # In production, this would query a database or file storage
        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")

        if !isfile(vt_file)
            return json(Dict("error" => "Workflow not found", "id" => workflow_id), status = 404)
        end

        # Load the vistrail
        vistrail = VisTrailsJL.load_vistrail(vt_file)

        # Get the latest pipeline (or specific version if provided)
        pipeline = VisTrailsJL.get_pipeline(vistrail)

        # Convert to JSON-friendly format
        workflow_json = pipeline_to_json(pipeline, vistrail)

        json(workflow_json)
    catch e
        @error "Error loading workflow" exception=(e, catch_backtrace())
        json(Dict("error" => "Internal server error", "message" => string(e)), status = 500)
    end
end

# Get specific version of workflow
# GET /api/workflow/:id/version/:version_id
route("/api/workflow/:id/version/:version_id", method = GET) do
    try
        workflow_id = payload(:id)
        version_id = parse(Int, payload(:version_id))

        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")

        if !isfile(vt_file)
            return json(Dict("error" => "Workflow not found", "id" => workflow_id), status = 404)
        end

        # Load vistrail with the specific version
        # This will reconstruct that version's pipeline
        vistrail = VisTrailsJL.load_vistrail(vt_file, version=version_id)

        # Get the pipeline (should be in vt.pipelines now)
        if haskey(vistrail.pipelines, version_id)
            pipeline = vistrail.pipelines[version_id]
        else
            return json(Dict("error" => "Version $version_id could not be reconstructed"), status = 404)
        end

        workflow_json = pipeline_to_json(pipeline, vistrail, version_id)

        json(workflow_json)
    catch e
        @error "Error loading workflow version" exception=(e, catch_backtrace())
        json(Dict("error" => "Internal server error", "message" => string(e)), status = 500)
    end
end

# List available workflows
route("/api/workflows", method = GET) do
    try
        examples_dir = joinpath(@__DIR__, "../../examples")
        vt_files = filter(f -> endswith(f, ".vt"), readdir(examples_dir))

        workflows = map(vt_files) do filename
            name = replace(filename, ".vt" => "")
            path = joinpath(examples_dir, filename)

            # Get basic info
            Dict(
                "id" => name,
                "name" => name,
                "path" => filename,
                "size" => filesize(path),
                "modified" => mtime(path)
            )
        end

        json(workflows)
    catch e
        @error "Error listing workflows" exception=(e, catch_backtrace())
        json(Dict("error" => "Internal server error", "message" => string(e)), status = 500)
    end
end

# Get workflow as SVG
# GET /api/workflow/:id/svg
route("/api/workflow/:id/svg", method = GET) do
    try
        workflow_id = payload(:id)
        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")

        if !isfile(vt_file)
            return json(Dict("error" => "Workflow not found"), status = 404)
        end

        vistrail = VisTrailsJL.load_vistrail(vt_file)
        pipeline = VisTrailsJL.get_pipeline(vistrail)

        # Generate SVG using VisTrailsJL's renderer
        svg_content = VisTrailsJL.render_pipeline_svg(pipeline)

        # Return SVG with proper content type
        return Genie.Renderer.respond(svg_content, :svg)
    catch e
        @error "Error generating SVG" exception=(e, catch_backtrace())
        json(Dict("error" => "Internal server error", "message" => string(e)), status = 500)
    end
end

# Get specific version as SVG
# GET /api/workflow/:id/version/:version_id/svg
route("/api/workflow/:id/version/:version_id/svg", method = GET) do
    try
        workflow_id = payload(:id)
        version_id = parse(Int, payload(:version_id))
        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")

        if !isfile(vt_file)
            return json(Dict("error" => "Workflow not found"), status = 404)
        end

        # Load vistrail with the specific version
        vistrail = VisTrailsJL.load_vistrail(vt_file, version=version_id)

        # Get the pipeline
        if haskey(vistrail.pipelines, version_id)
            pipeline = vistrail.pipelines[version_id]
        else
            return json(Dict("error" => "Version $version_id could not be reconstructed"), status = 404)
        end

        # Generate SVG
        svg_content = VisTrailsJL.render_pipeline_svg(pipeline)

        return Genie.Renderer.respond(svg_content, :svg)
    catch e
        @error "Error generating SVG for version" exception=(e, catch_backtrace())
        json(Dict("error" => "Internal server error", "message" => string(e)), status = 500)
    end
end

# Serve HTML test page
route("/") do
    html_file = joinpath(@__DIR__, "public/index.html")
    if isfile(html_file)
        html_content = read(html_file, String)
        return HTTP.Response(200, ["Content-Type" => "text/html"], body=html_content)
    else
        return json(Dict("status" => "ok", "message" => "VisTrailsJL Backend API"))
    end
end

# Serve demo page
route("/demo") do
    html_file = joinpath(@__DIR__, "public/vistrails-demo.html")
    if isfile(html_file)
        html_content = read(html_file, String)
        return HTTP.Response(200, ["Content-Type" => "text/html"], body=html_content)
    else
        return json(Dict("error" => "Demo page not found"), status = 404)
    end
end

# Serve version tree demo page
route("/tree-demo") do
    html_file = joinpath(@__DIR__, "public/tree-demo.html")
    if isfile(html_file)
        html_content = read(html_file, String)
        return HTTP.Response(200, ["Content-Type" => "text/html"], body=html_content)
    else
        return json(Dict("error" => "Tree demo page not found"), status = 404)
    end
end

# Get version tree for a workflow
route("/api/workflow/:id/versions", method = GET) do
    try
        workflow_id = payload(:id)
        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")

        if !isfile(vt_file)
            return json(Dict("error" => "Workflow not found"), status = 404)
        end

        vt_wrapper = VisTrailsJL.load_vistrail(vt_file)
        vistrail = vt_wrapper.vistrail

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

        json(Dict(
            "versions" => versions,
            "tags" => tags,
            "current_version" => vistrail.current_version,
            "count" => length(versions)
        ))
    catch e
        @error "Error getting versions" exception=(e, catch_backtrace())
        json(Dict("error" => "Internal server error", "message" => string(e)), status = 500)
    end
end

# Get version tree as SVG
# GET /api/workflow/:id/tree/svg
route("/api/workflow/:id/tree/svg", method = GET) do
    try
        workflow_id = payload(:id)
        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")

        if !isfile(vt_file)
            return json(Dict("error" => "Workflow not found"), status = 404)
        end

        vt_wrapper = VisTrailsJL.load_vistrail(vt_file)

        # Generate SVG using VisTrailsJL's version tree renderer
        # render_version_tree_svg expects a raw Vistrail, not a VistrailWrapper
        svg_content = VisTrailsJL.render_version_tree_svg(vt_wrapper.vistrail)

        # Return SVG with proper content type
        return Genie.Renderer.respond(svg_content, :svg)
    catch e
        @error "Error generating version tree SVG" exception=(e, catch_backtrace())
        json(Dict("error" => "Internal server error", "message" => string(e)), status = 500)
    end
end

# Helper function to convert pipeline to JSON
function pipeline_to_json(pipeline::VisTrailsJL.Pipeline, vistrail::VisTrailsJL.Vistrail, version_id::Union{Int,Nothing}=nothing)
    # Convert modules with simple grid layout
    modules = map(enumerate(collect(pipeline.modules))) do (idx, (id, mod))
        Dict(
            "id" => id,
            "name" => mod.descriptor.name,
            "package" => mod.descriptor.package,
            "x" => 100.0 + (id * 150.0),
            "y" => 100.0 + ((idx - 1) % 4) * 100.0,
            "inputs" => map(p -> Dict("name" => p.name, "type" => string(p.type)), mod.descriptor.input_ports),
            "outputs" => map(p -> Dict("name" => p.name, "type" => string(p.type)), mod.descriptor.output_ports)
        )
    end

    # Convert connections
    connections = map(pipeline.connections) do conn
        Dict(
            "source_id" => conn.source_module_id,
            "source_port" => conn.source_port,
            "target_id" => conn.dest_module_id,
            "target_port" => conn.dest_port
        )
    end

    result = Dict(
        "modules" => modules,
        "connections" => connections,
        "version_id" => version_id === nothing ? (isempty(vistrail.actions) ? 0 : maximum(keys(vistrail.actions))) : version_id
    )

    return result
end

# ============================================================================
# Workflow Editing Routes (for visflow-lite integration)
# ============================================================================

# Add module to workflow
# POST /api/workflow/:id/module
route("/api/workflow/:id/module", method = POST) do
    try
        workflow_id = payload(:id)

        # Parse request body
        body = JSON3.read(rawpayload())

        module_type = body.type
        position = (Float64(body.position.x), Float64(body.position.y))
        parameters = haskey(body, :parameters) ? Dict(body.parameters) : Dict()

        # Get or create session
        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
        if !isfile(vt_file)
            return json(Dict("error" => "Workflow not found"), status=404)
        end

        session = get_or_create_session(workflow_id, vt_file)

        # Add module
        module_id, mod = add_module!(session, module_type, position, parameters)

        # Return module info
        json(Dict(
            "module_id" => module_id,
            "descriptor" => Dict(
                "name" => mod.descriptor.name,
                "package" => mod.descriptor.package,
                "input_ports" => map(p -> Dict("name" => p.name, "type" => string(p.type)), mod.descriptor.input_ports),
                "output_ports" => map(p -> Dict("name" => p.name, "type" => string(p.type)), mod.descriptor.output_ports)
            ),
            "position" => Dict("x" => position[1], "y" => position[2]),
            "parameters" => parameters
        ))
    catch e
        @error "Error adding module" exception=(e, catch_backtrace())
        json(Dict("error" => string(e)), status=500)
    end
end

# Update module position
# PATCH /api/workflow/:id/module/:module_id/position
route("/api/workflow/:id/module/:module_id/position", method = PATCH) do
    try
        workflow_id = payload(:id)
        module_id = parse(Int, payload(:module_id))

        body = JSON3.read(rawpayload())
        position = (Float64(body.x), Float64(body.y))

        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
        session = get_or_create_session(workflow_id, vt_file)

        update_module_position!(session, module_id, position)

        json(Dict("success" => true, "module_id" => module_id, "position" => Dict("x" => position[1], "y" => position[2])))
    catch e
        @error "Error updating module position" exception=(e, catch_backtrace())
        json(Dict("error" => string(e)), status=500)
    end
end

# Update module parameters
# PATCH /api/workflow/:id/module/:module_id/parameters
route("/api/workflow/:id/module/:module_id/parameters", method = PATCH) do
    try
        workflow_id = payload(:id)
        module_id = parse(Int, payload(:module_id))

        body = JSON3.read(rawpayload())
        parameters = Dict(body)

        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
        session = get_or_create_session(workflow_id, vt_file)

        update_module_parameters!(session, module_id, parameters)

        json(Dict("success" => true, "module_id" => module_id, "parameters" => parameters))
    catch e
        @error "Error updating module parameters" exception=(e, catch_backtrace())
        json(Dict("error" => string(e)), status=500)
    end
end

# Delete module
# DELETE /api/workflow/:id/module/:module_id
route("/api/workflow/:id/module/:module_id", method = DELETE) do
    try
        workflow_id = payload(:id)
        module_id = parse(Int, payload(:module_id))

        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
        session = get_or_create_session(workflow_id, vt_file)

        removed_connections = delete_module!(session, module_id)

        json(Dict("success" => true, "module_id" => module_id, "removed_connections" => removed_connections))
    catch e
        @error "Error deleting module" exception=(e, catch_backtrace())
        json(Dict("error" => string(e)), status=500)
    end
end

# Add connection
# POST /api/workflow/:id/connection
route("/api/workflow/:id/connection", method = POST) do
    try
        workflow_id = payload(:id)

        body = JSON3.read(rawpayload())
        source_id = Int(body.source_module_id)
        source_port = String(body.source_port)
        dest_id = Int(body.dest_module_id)
        dest_port = String(body.dest_port)

        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
        session = get_or_create_session(workflow_id, vt_file)

        conn_id, conn = add_connection!(session, source_id, source_port, dest_id, dest_port)

        json(Dict(
            "connection_id" => conn_id,
            "source_module_id" => source_id,
            "source_port" => source_port,
            "dest_module_id" => dest_id,
            "dest_port" => dest_port
        ))
    catch e
        @error "Error adding connection" exception=(e, catch_backtrace())
        json(Dict("error" => string(e)), status=500)
    end
end

# Delete connection
# DELETE /api/workflow/:id/connection/:connection_id
route("/api/workflow/:id/connection/:connection_id", method = DELETE) do
    try
        workflow_id = payload(:id)
        connection_id = parse(Int, payload(:connection_id))

        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
        session = get_or_create_session(workflow_id, vt_file)

        delete_connection!(session, connection_id)

        json(Dict("success" => true, "connection_id" => connection_id))
    catch e
        @error "Error deleting connection" exception=(e, catch_backtrace())
        json(Dict("error" => string(e)), status=500)
    end
end

# Get workflow state (for debugging/status)
# GET /api/workflow/:id/state
route("/api/workflow/:id/state", method = GET) do
    try
        workflow_id = payload(:id)

        vt_file = joinpath(@__DIR__, "../../examples/$(workflow_id).vt")
        if !isfile(vt_file)
            return json(Dict("error" => "Workflow not found"), status=404)
        end

        session = get_or_create_session(workflow_id, vt_file)
        state = get_workflow_state(session)

        json(state)
    catch e
        @error "Error getting workflow state" exception=(e, catch_backtrace())
        json(Dict("error" => string(e)), status=500)
    end
end
