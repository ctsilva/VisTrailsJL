# VisTrails Docker - Quick Reference

## 🎉 Success! VisTrails is Running

You now have a fully functional VisTrails installation with Python 2.7, PyQt4, and VTK running in Docker!

## Quick Start

### Running VisTrails GUI

```bash
# Start the GUI
./run-vistrails-docker.sh gui

# Or manually:
docker run -d --name vistrails-gui -p 5900:5900 -e DISPLAY=:99 vistrails:latest \
    bash -c "Xvfb :99 -screen 0 1280x1024x24 > /dev/null 2>&1 & sleep 3 && \
             x11vnc -display :99 -passwd vistrails -listen 0.0.0.0 -forever & sleep 2 && \
             python2.7 /vistrails/vistrails/run.py"

# Connect via VNC
open vnc://localhost:5900
# Password: vistrails
```

### Managing the Container

```bash
# Check if running
docker ps | grep vistrails

# Stop the container
docker stop vistrails-gui

# Start it again
docker start vistrails-gui

# Remove the container
docker rm -f vistrails-gui

# View logs
docker logs vistrails-gui

# Access shell inside container
docker exec -it vistrails-gui bash
```

### Running in Console/Batch Mode

```bash
# Run a specific workflow
docker run --rm -v "$(pwd):/data" vistrails:latest \
    bash -c "DISPLAY=:99 Xvfb :99 -screen 0 1280x1024x24 & \
             sleep 2 && python2.7 /vistrails/vistrails/run.py --batch /data/workflow.vt"

# Show help
docker run --rm vistrails:latest vistrails --help
```

## VNC Connection Details

- **Host**: localhost
- **Port**: 5900
- **Password**: vistrails
- **URL**: `vnc://localhost:5900`

### Connecting on macOS

```bash
# Method 1: Terminal
open vnc://localhost:5900

# Method 2: Finder
# Press ⌘K, enter: vnc://localhost:5900

# Method 3: Screen Sharing app
# Search for "Screen Sharing" in Spotlight
# Enter: localhost:5900
```

## What's Installed

The Docker image includes:

- **Base**: Ubuntu 18.04
- **Python**: 2.7.17
- **GUI**: PyQt4 + Xvfb + x11vnc
- **Visualization**: VTK 6
- **Scientific**: NumPy, SciPy, matplotlib, scikit-learn
- **Database**: MySQL-python, SQLAlchemy
- **All VisTrails dependencies**

## File Access

The current directory is mounted to `/vistrails` in the container, so:

- Edit files on your Mac
- Changes appear immediately in the container
- Workflows saved in the container appear on your Mac

## Troubleshooting

### VNC asks for password
Use password: **vistrails**

### Container won't start (port in use)
```bash
# Stop any existing container
docker stop vistrails-gui
docker rm vistrails-gui

# Or use a different port
docker run -d --name vistrails-gui -p 5901:5900 ...
# Then connect to vnc://localhost:5901
```

### "Required packages missing" dialog
This is normal on first startup. Click **"No"** to skip - core packages are already installed.

### GUI is slow
VNC can be slower than native apps. For better performance:
- Use console/batch mode when possible
- Reduce screen resolution in the Xvfb command (e.g., 1024x768x24)

### Need to rebuild image
```bash
docker build -t vistrails:latest .
```

## Next Steps

1. **Explore VisTrails**: Try opening example workflows in `examples/` directory
2. **Create workflows**: Build your own computational pipelines
3. **Batch processing**: Use console mode for automated execution
4. **Save your work**: Files in the container's `/vistrails` directory persist on your Mac

## Useful Commands

```bash
# List all VisTrails images
docker images | grep vistrails

# Remove old images
docker rmi vistrails:latest

# Clean up stopped containers
docker container prune

# See resource usage
docker stats vistrails-gui

# Export/backup a workflow
docker cp vistrails-gui:/root/.vistrails/ ./vistrails-backup/
```

## Support

For VisTrails documentation: https://www.vistrails.org/

For Docker issues, check:
- Container logs: `docker logs vistrails-gui`
- Container status: `docker ps -a`
- Docker system info: `docker info`
