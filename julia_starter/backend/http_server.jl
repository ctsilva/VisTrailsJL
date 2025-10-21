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

        vistrail = VisTrailsJL.load_vistrail(vt_file)

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

        vistrail = VisTrailsJL.load_vistrail(vt_file)
        svg_content = VisTrailsJL.render_version_tree_svg(vistrail)

        svg_response(svg_content)
    catch e
        @error "Error generating version tree SVG" exception=(e, catch_backtrace())
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

        vistrail = VisTrailsJL.load_vistrail(vt_file, version=version_id)

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
