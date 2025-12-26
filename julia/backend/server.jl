using Genie
using Genie.Router
using Genie.Requests
using Logging

# Set log level
global_logger(ConsoleLogger(stderr, Logging.Info))

# Configure Genie
ENV["GENIE_ENV"] = "dev"
ENV["PORT"] = get(ENV, "PORT", "8000")

@info "Starting VisTrailsJL Backend Server..."
@info "Environment: $(ENV["GENIE_ENV"])"
@info "Port: $(ENV["PORT"])"

# Load routes
include("routes.jl")

# Start server
Genie.config.run_as_server = true
Genie.config.server_host = "0.0.0.0"
Genie.config.server_port = parse(Int, ENV["PORT"])
Genie.config.websockets_server = false

# Enable CORS for frontend development
Genie.config.cors_headers["Access-Control-Allow-Origin"] = "*"
Genie.config.cors_headers["Access-Control-Allow-Headers"] = "Content-Type"
Genie.config.cors_headers["Access-Control-Allow-Methods"] = "GET,POST,PUT,DELETE,OPTIONS"
Genie.config.cors_allowed_origins = ["*"]

@info "Server configured, starting up..."
@info "API will be available at http://localhost:$(ENV["PORT"])"
@info "Try: http://localhost:$(ENV["PORT"])/health"

up()
