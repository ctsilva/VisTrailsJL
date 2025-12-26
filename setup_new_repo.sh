#!/bin/bash

# Setup script for migrating to new VisTrailsJL repository
# Usage: ./setup_new_repo.sh

set -e

echo "=========================================="
echo "VisTrailsJL Repository Setup"
echo "=========================================="
echo ""

# Check if user has created the GitHub repo
echo "Before running this script, make sure you have:"
echo "1. Created a NEW repository at https://github.com/ctsilva/VisTrailsJL"
echo "2. DO NOT initialize it with README, .gitignore, or license"
echo ""
read -p "Have you created the repository? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please create the repository first, then run this script again."
    exit 1
fi

# Check current git status
echo ""
echo "Step 1: Checking current git status..."
git status

# Show current remote
echo ""
echo "Current git remote:"
git remote -v

# Add all new files
echo ""
echo "Step 2: Adding all new Julia files..."
git add julia/
git add CLAUDE.md
git add DOCKER_QUICK_START.md
git add DOCKER_SETUP.md
git add JULIA_ARCHITECTURE.md
git add MINIMAL_VISTRAILS.md
git add docker-compose.yml
git add install-docker.sh
git add run-vistrails-docker.sh
git add setup_vistrails_conda.sh
git add simple_vt_reader.py
git add minimal_vistrails.py
git add README_VISTRAILSJL.md
git add .gitignore
git add Dockerfile

# Show what will be committed
echo ""
echo "Step 3: Files staged for commit:"
git status

# Create commit
echo ""
echo "Step 4: Creating commit..."
read -p "Enter commit message (or press Enter for default): " commit_msg
if [ -z "$commit_msg" ]; then
    commit_msg="Add VisTrailsJL Julia implementation

- Complete Julia reimplementation of VisTrails
- Full .vt file compatibility with action replay
- SVG rendering for workflows and version trees
- Julia, Python, and Basic packages implemented
- Comprehensive documentation and analysis
- Docker support for development
- Web UI planning and design

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
fi

git commit -m "$commit_msg"

# Rename current remote to 'upstream'
echo ""
echo "Step 5: Renaming original VisTrails remote to 'upstream'..."
git remote rename origin upstream

# Add new remote
echo ""
echo "Step 6: Adding new remote 'origin' for VisTrailsJL..."
git remote add origin https://github.com/ctsilva/VisTrailsJL.git

# Show updated remotes
echo ""
echo "Updated git remotes:"
git remote -v

# Push to new repository
echo ""
echo "Step 7: Pushing to new repository..."
echo "This will push the v2.2 branch to your new repository."
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    git push -u origin v2.2
    echo ""
    echo "=========================================="
    echo "✅ Success!"
    echo "=========================================="
    echo ""
    echo "Your new repository is set up at:"
    echo "https://github.com/ctsilva/VisTrailsJL"
    echo ""
    echo "Remotes configured:"
    echo "  origin   -> https://github.com/ctsilva/VisTrailsJL.git (your repo)"
    echo "  upstream -> https://github.com/VisTrails/VisTrails.git (original)"
    echo ""
    echo "To pull updates from original VisTrails:"
    echo "  git fetch upstream"
    echo "  git merge upstream/v2.2"
    echo ""
    echo "To push to your repository:"
    echo "  git push origin v2.2"
    echo ""
else
    echo "Push cancelled. You can push manually later with:"
    echo "  git push -u origin v2.2"
fi
