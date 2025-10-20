#!/bin/bash
# VisTrails Python 2.7 Conda Environment Setup
# For Apple Silicon (M1/M2/M3) Macs using Rosetta 2

set -e

echo "Setting up VisTrails Python 2.7 environment..."

# Source conda
source /opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh

# Create x86_64 Python 2.7 environment
echo "Creating vistrails conda environment with Python 2.7..."
CONDA_SUBDIR=osx-64 conda create -n vistrails python=2.7 -y

# Activate environment
conda activate vistrails

# Configure for x86_64
conda config --env --set subdir osx-64

# Install scientific packages via conda
echo "Installing scientific packages..."
conda install -c conda-forge numpy scipy matplotlib ipython scikit-learn -y

# Install pip dependencies
echo "Installing pip dependencies..."
pip install \
    backports.ssl_match_hostname \
    dulwich \
    pyth \
    SQLAlchemy \
    xlrd \
    xlwt \
    'requests<2.28' \
    'urllib3<2' \
    'idna<3' \
    'chardet<5' \
    usagestats \
    docutils

echo ""
echo "✓ Environment setup complete!"
echo ""
echo "⚠️  WARNING: PyQt4 is not available for modern macOS"
echo "This means the GUI mode will NOT work."
echo ""
echo "To activate the environment:"
echo "  conda activate vistrails"
echo ""
echo "Limitations:"
echo "  - GUI mode requires PyQt4 (unavailable)"
echo "  - Console/batch mode may work with limited functionality"
echo "  - Some packages (VTK, mysql-python, paramiko) not installed"
echo ""
echo "Next steps:"
echo "  1. Activate: conda activate vistrails"
echo "  2. Try console mode: python vistrails/run.py --batch --help"
echo "  3. For full functionality, consider Docker approach"
