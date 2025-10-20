#!/bin/bash
# Helper script to run VisTrails in Docker
# Usage: ./run-vistrails-docker.sh [mode]
#   mode: gui, jupyter, console, or shell

set -e

MODE="${1:-help}"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}VisTrails Docker Runner${NC}"
echo ""

case "$MODE" in
    gui)
        echo -e "${GREEN}Starting VisTrails GUI with VNC...${NC}"
        echo ""
        echo "Starting container..."
        docker run -d --name vistrails-gui -p 5900:5900 -e DISPLAY=:99 \
            -v "$(pwd):/vistrails" \
            vistrails:latest \
            bash -c "Xvfb :99 -screen 0 1280x1024x24 > /dev/null 2>&1 & sleep 3 && \
                     x11vnc -display :99 -passwd vistrails -listen 0.0.0.0 -forever & sleep 2 && \
                     python2.7 /vistrails/vistrails/run.py"

        echo ""
        echo -e "${GREEN}VisTrails GUI is starting...${NC}"
        echo ""
        echo "Connect via VNC:"
        echo "  URL: vnc://localhost:5900"
        echo "  Password: vistrails"
        echo ""
        echo "Quick connect: open vnc://localhost:5900"
        echo ""
        echo "To stop: docker stop vistrails-gui"
        echo "To remove: docker rm vistrails-gui"
        ;;

    jupyter)
        echo -e "${GREEN}Starting VisTrails Jupyter notebook...${NC}"
        echo ""
        echo "Jupyter will be available at:"
        echo "  http://localhost:8888"
        echo ""
        docker-compose up vistrails-jupyter
        ;;

    console)
        echo -e "${GREEN}Running VisTrails in console mode...${NC}"
        shift
        docker-compose run --rm vistrails python2.7 /vistrails/vistrails/run.py "$@"
        ;;

    shell)
        echo -e "${GREEN}Starting interactive shell in VisTrails container...${NC}"
        docker-compose run --rm vistrails bash
        ;;

    build)
        echo -e "${GREEN}Building VisTrails Docker image...${NC}"
        docker-compose build
        ;;

    help|*)
        echo "Usage: $0 [mode] [args]"
        echo ""
        echo "Modes:"
        echo "  gui      - Launch VisTrails GUI (access via VNC at localhost:5900)"
        echo "  jupyter  - Launch Jupyter notebook server (access at localhost:8888)"
        echo "  console  - Run VisTrails in console/batch mode with args"
        echo "  shell    - Open interactive bash shell in container"
        echo "  build    - Build the Docker image"
        echo ""
        echo "Examples:"
        echo "  $0 build                    # Build the Docker image"
        echo "  $0 gui                      # Start GUI mode"
        echo "  $0 console --help           # Show VisTrails help"
        echo "  $0 console --batch workflow.vt  # Run workflow in batch mode"
        echo "  $0 shell                    # Interactive shell"
        echo ""
        echo -e "${YELLOW}Note: For GUI mode, you need a VNC viewer:${NC}"
        echo "  - macOS: Use built-in 'Screen Sharing' or 'open vnc://localhost:5900'"
        echo "  - Linux: vncviewer localhost:5900"
        echo "  - Windows: Use TightVNC, RealVNC, or similar"
        ;;
esac
