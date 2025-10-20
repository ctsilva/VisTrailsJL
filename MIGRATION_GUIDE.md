# Migrating to VisTrailsJL GitHub Repository

This guide explains how to migrate this project to your own GitHub repository at `github.com/ctsilva/VisTrailsJL`.

## Quick Start

### 1. Create GitHub Repository

Go to https://github.com/new and create a new repository:
- **Repository name**: `VisTrailsJL`
- **Description**: "Julia implementation of VisTrails with provenance tracking"
- **Public** or **Private** (your choice)
- **DO NOT** initialize with README, .gitignore, or license

### 2. Run Setup Script

```bash
./setup_new_repo.sh
```

The script will:
1. Stage all your new Julia files
2. Create a commit with your changes
3. Rename the original remote to `upstream`
4. Add your new repository as `origin`
5. Push to your new repository

## Manual Setup (if you prefer)

If you want to do it manually instead of using the script:

```bash
# 1. Stage all new files
git add julia_starter/ CLAUDE.md README.md .gitignore
git add DOCKER_QUICK_START.md DOCKER_SETUP.md JULIA_ARCHITECTURE.md
git add docker-compose.yml install-docker.sh run-vistrails-docker.sh
git add setup_new_repo.sh MIGRATION_GUIDE.md

# 2. Create commit
git commit -m "Add VisTrailsJL Julia implementation"

# 3. Rename original remote to 'upstream'
git remote rename origin upstream

# 4. Add your new repository
git remote add origin https://github.com/ctsilva/VisTrailsJL.git

# 5. Push to your repository
git push -u origin v2.2
```

## Working with Two Remotes

After setup, you'll have two remotes:

- **origin** (your repository): `https://github.com/ctsilva/VisTrailsJL.git`
- **upstream** (original VisTrails): `https://github.com/VisTrails/VisTrails.git`

### Pull updates from original VisTrails

```bash
git fetch upstream
git merge upstream/v2.2
```

### Push your changes

```bash
git push origin v2.2
```

### Create feature branches

```bash
git checkout -b feature/web-ui
# Make changes
git add .
git commit -m "Add web UI components"
git push origin feature/web-ui
```

## Setting Up on Another Computer

On your office computer:

```bash
# Clone your repository
git clone https://github.com/ctsilva/VisTrailsJL.git
cd VisTrailsJL

# Add original VisTrails as upstream (optional)
git remote add upstream https://github.com/VisTrails/VisTrails.git

# Setup Julia environment
cd julia_starter
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Test it works
julia --project=. -e 'using VisTrailsJL; println("VisTrailsJL loaded successfully!")'
```

## Repository Structure

After migration, your repository will have:

```
VisTrailsJL/
├── README.md                   # Main project README
├── CLAUDE.md                   # Python VisTrails documentation
├── MIGRATION_GUIDE.md          # This file
├── setup_new_repo.sh          # Setup script
│
├── vistrails/                  # Original Python VisTrails (reference)
│   ├── core/
│   ├── packages/
│   └── gui/
│
├── julia_starter/              # VisTrailsJL implementation
│   ├── src/                   # Julia source code
│   ├── docs/                  # Documentation
│   ├── examples/              # Example workflows
│   └── README.md              # VisTrailsJL specific docs
│
└── examples/                   # Example .vt files
```

## Syncing Between Computers

### From laptop → office

On laptop:
```bash
git add .
git commit -m "Your changes"
git push origin v2.2
```

On office computer:
```bash
git pull origin v2.2
```

### From office → laptop

On office computer:
```bash
git add .
git commit -m "Your changes"
git push origin v2.2
```

On laptop:
```bash
git pull origin v2.2
```

## Best Practices

1. **Commit often**: Small, focused commits are easier to track
2. **Write descriptive commit messages**: Explain what and why
3. **Use branches for experiments**: `git checkout -b experiment/new-feature`
4. **Keep Manifest.toml in sync**: Commit it so Julia packages match across computers
5. **Pull before starting work**: `git pull origin v2.2` to get latest changes

## Troubleshooting

### "Repository already exists"

If you already created the repository with README/license:
```bash
git push -f origin v2.2  # Force push (overwrites GitHub repo)
```

### Merge conflicts

If you have conflicting changes on both computers:
```bash
git pull origin v2.2      # Get remote changes
# Resolve conflicts in files
git add .
git commit -m "Resolve merge conflicts"
git push origin v2.2
```

### Want to start over?

```bash
# Remove new remote
git remote remove origin

# Restore original remote
git remote rename upstream origin

# Re-run setup script
./setup_new_repo.sh
```

## Need Help?

- Git documentation: https://git-scm.com/doc
- GitHub guides: https://guides.github.com
- Ask Claude Code! 😊
