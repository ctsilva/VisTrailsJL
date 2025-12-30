using HTTP
using JSON3
using Logging

# Set log level
global_logger(ConsoleLogger(stderr, Logging.Info))

# Load VisTrailsJL from parent project
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using VisTrailsJL

@info "Starting VisTrailsJL Backend Server (HTTP.jl)..."

# Create router
router = HTTP.Router()

# Helper to create JSON response
json_response(data; status=200) = HTTP.Response(
    status,
    ["Content-Type" => "application/json",
     "Access-Control-Allow-Origin" => "*"],
    JSON3.write(data)
)

# Helper to create SVG response
svg_response(svg_content) = HTTP.Response(
    200,
    ["Content-Type" => "image/svg+xml",
     "Access-Control-Allow-Origin" => "*"],
    svg_content
)

# Health check
HTTP.register!(router, "GET", "/health", req -> begin
    json_response(Dict("status" => "healthy", "service" => "VisTrailsJL Backend", "version" => "0.1.0"))
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

# Start server
port = parse(Int, get(ENV, "PORT", "8000"))

@info "Server configured"
@info "API will be available at http://localhost:$port"
@info "Try: http://localhost:$port/health"
@info ""

server = HTTP.serve!(router, "0.0.0.0", port; verbose=true, stream=false)

@info "Server running. Press Ctrl+C to stop."
wait(server)
