#!/bin/bash
# Install Docker Desktop on macOS (if needed)

set -e

echo "Checking for Docker installation..."

if command -v docker &> /dev/null; then
    echo "✓ Docker is already installed!"
    docker --version
    docker-compose --version 2>/dev/null || echo "Note: docker-compose might need Docker Desktop running"
    echo ""
    echo "If Docker commands fail, make sure Docker Desktop is running."
    echo "You can start it from Applications or with: open -a Docker"
    exit 0
fi

echo "Docker not found. Installing Docker Desktop..."
echo ""

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "Error: Homebrew is not installed."
    echo "Please install Homebrew first: https://brew.sh"
    echo "Or download Docker Desktop manually: https://www.docker.com/products/docker-desktop/"
    exit 1
fi

echo "Installing Docker Desktop via Homebrew..."
brew install --cask docker

echo ""
echo "✓ Docker Desktop installed!"
echo ""
echo "IMPORTANT: You must now:"
echo "  1. Launch Docker Desktop from Applications"
echo "  2. Wait for it to finish starting (whale icon in menu bar)"
echo "  3. Then run: ./run-vistrails-docker.sh build"
echo ""
echo "Opening Docker Desktop now..."
open -a Docker

echo ""
echo "Waiting for Docker to start..."
echo "(This may take 30-60 seconds on first launch)"

# Wait for Docker daemon to be ready
for i in {1..30}; do
    if docker ps &> /dev/null; then
        echo ""
        echo "✓ Docker is ready!"
        docker --version
        docker-compose --version
        exit 0
    fi
    echo -n "."
    sleep 2
done

echo ""
echo "Docker is starting but not ready yet."
echo "Please wait for Docker Desktop to finish starting, then run:"
echo "  ./run-vistrails-docker.sh build"
