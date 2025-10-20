# Running VisTrails with Docker

This guide helps you run VisTrails using Docker, which provides a complete Python 2.7 environment with PyQt4, VTK, and all dependencies.

## Prerequisites

1. **Install Docker Desktop** (if not already installed):
   - macOS: Download from https://www.docker.com/products/docker-desktop/
   - Or via Homebrew: `brew install --cask docker`
   - After installation, launch Docker Desktop from Applications

2. **Verify Docker is running**:
   ```bash
   docker --version
   docker-compose --version
   ```

## Quick Start

### 1. Build the Docker Image

First time only - build the VisTrails Docker image:

```bash
./run-vistrails-docker.sh build
```

This will take 5-10 minutes as it downloads Ubuntu 18.04 and installs all dependencies.

### 2. Run VisTrails

Choose your preferred mode:

#### **GUI Mode (via VNC)**

```bash
./run-vistrails-docker.sh gui
```

Then connect with a VNC viewer:
- **macOS**: Open Finder → Go → Connect to Server → `vnc://localhost:5900`
- **Or use built-in**: `open vnc://localhost:5900`
- **Linux**: `vncviewer localhost:5900`
- **Windows**: Use TightVNC, RealVNC, or any VNC client

No password is required. You'll see the VisTrails GUI window.

#### **Jupyter Notebook Mode**

```bash
./run-vistrails-docker.sh jupyter
```

Then open your browser to: http://localhost:8888

Look for the token in the terminal output (or use the URL that's printed).

#### **Console/Batch Mode**

```bash
./run-vistrails-docker.sh console --help
./run-vistrails-docker.sh console --batch workflow.vt
```

#### **Interactive Shell**

For debugging or exploration:

```bash
./run-vistrails-docker.sh shell
```

This gives you a bash shell inside the container with Python 2.7 and all dependencies.

## Manual Docker Commands

If you prefer not to use the helper script:

### Build
```bash
docker-compose build
```

### Run GUI with VNC
```bash
docker-compose up vistrails-gui
# Connect VNC to localhost:5900
```

### Run Jupyter
```bash
docker-compose up vistrails-jupyter
# Open http://localhost:8888
```

### Run console mode
```bash
docker run --rm vistrails:latest vistrails --help
```

### Interactive shell
```bash
docker-compose run --rm vistrails bash
```

## File Access

The Docker container mounts your current directory at `/vistrails`, so:
- Changes to VisTrails source code on your Mac are immediately available in the container
- Workflows and files created in the container appear in your local directory
- User settings are persisted in a Docker volume named `vistrails-data`

## Troubleshooting

### Docker not found
```bash
# Install Docker Desktop for Mac
brew install --cask docker
# Then launch Docker Desktop from Applications
```

### Build fails
```bash
# Clean and rebuild
docker-compose down
docker system prune -a
./run-vistrails-docker.sh build
```

### VNC connection refused
- Make sure the container is running: `docker ps`
- Check if port 5900 is available: `lsof -i :5900`
- Try restarting the container: `docker-compose restart vistrails-gui`

### Can't see GUI in VNC
- VNC is running headless with Xvfb (virtual framebuffer)
- It may take a few seconds for the GUI to appear
- Check container logs: `docker-compose logs vistrails-gui`

### Permission issues
```bash
# If you get permission errors with files:
docker-compose run --rm vistrails chown -R $(id -u):$(id -g) /vistrails
```

## Architecture

The Docker setup includes:
- **Base**: Ubuntu 18.04 (last version with good Python 2.7 support)
- **Python**: 2.7.17 with pip
- **GUI**: PyQt4, Xvfb (virtual display), x11vnc (VNC server)
- **Visualization**: VTK 6
- **Scientific**: NumPy, SciPy, matplotlib, scikit-learn
- **Notebooks**: Jupyter with IPython
- **All dependencies** from requirements.txt

## Next Steps

1. **Test with examples**:
   ```bash
   ./run-vistrails-docker.sh gui
   # In VNC, open File → Open → examples/
   ```

2. **Create workflows**: Your workflows are saved in the mounted directory

3. **Batch processing**: Use console mode for automated workflow execution

4. **Development**: Edit code on your Mac, test in Docker

## Comparison with Conda Approach

| Feature | Docker | Conda (x86_64) |
|---------|--------|----------------|
| PyQt4 GUI | ✅ Full support | ❌ Not available |
| VTK | ✅ Version 6 | ❌ Limited |
| All dependencies | ✅ Complete | ⚠️ Partial |
| Setup time | ~10 min | ~5 min |
| Isolation | ✅ Perfect | ⚠️ Good |
| File access | ✅ Mounted | ✅ Native |
| Performance | ✅ Native (ARM) or ⚠️ Rosetta | ⚠️ Rosetta |

**Recommendation**: Use Docker for full VisTrails functionality, especially if you need the GUI.
