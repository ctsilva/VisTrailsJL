#!/bin/bash

# Start VisTrailsJL Backend Server

echo "=========================================="
echo "VisTrailsJL Backend Server"
echo "=========================================="
echo ""

# Check if we're in the backend directory
if [ ! -f "server.jl" ]; then
    echo "Error: Must be run from backend/ directory"
    exit 1
fi

# Set default port
export PORT=${PORT:-8000}
export GENIE_ENV=${GENIE_ENV:-dev}

echo "Environment: $GENIE_ENV"
echo "Port: $PORT"
echo ""

# Check if dependencies are installed
if [ ! -d "Manifest.toml" ]; then
    echo "Installing dependencies..."
    julia --project=. -e 'using Pkg; Pkg.instantiate()'
    echo ""
fi

echo "Starting server..."
echo "API will be available at: http://localhost:$PORT"
echo "Health check: http://localhost:$PORT/health"
echo "API docs: http://localhost:$PORT/api/workflows"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Start server (using HTTP.jl instead of Genie.jl)
julia --project=. http_server.jl
