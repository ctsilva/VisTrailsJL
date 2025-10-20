FROM ubuntu:18.04
LABEL maintainer="VisTrails"

ENV DEBIAN_FRONTEND=noninteractive
# Install VisTrails system dependencies
RUN apt-get update && apt-get install -y \
    python2.7 \
    python-pip \
    python-dev \
    python-qt4 \
    python-qt4-gl \
    python-qt4-sql \
    python-vtk6 \
    python-numpy \
    python-scipy \
    python-matplotlib \
    python-sklearn \
    python-dateutil \
    python-docutils \
    python-mysqldb \
    python-paramiko \
    python-sqlalchemy \
    python-xlrd \
    python-xlwt \
    python-zmq \
    git \
    wget \
    xvfb \
    x11vnc \
    xterm \
    imagemagick \
    graphviz \
    libosmesa6 \
    libglapi-mesa \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip for Python 2.7
RUN python2.7 -m pip install --upgrade 'pip<21.0' 'setuptools<45'

# Set working directory
WORKDIR /vistrails

# Copy VisTrails source code
COPY . /vistrails/

# Install Python dependencies from requirements.txt
RUN pip install \
    backports.ssl_match_hostname \
    certifi \
    dulwich \
    'file_archive>=0.6' \
    'IPython<6' \
    pyth \
    scp \
    suds-jurko \
    'tej>=0.3' \
    'usagestats>=0.3' \
    'requests<2.28' \
    'urllib3<2' \
    'idna<3' \
    'chardet<5' \
    || true

# Create startup scripts
RUN echo '#!/bin/bash\n\
if [ -z "$DISPLAY" ]; then\n\
    export DISPLAY=:99\n\
    Xvfb :99 -screen 0 1280x1024x24 > /dev/null 2>&1 &\n\
    sleep 2\n\
fi\n\
exec python2.7 /vistrails/vistrails/run.py "$@"\n\
' > /usr/local/bin/vistrails && chmod +x /usr/local/bin/vistrails

RUN echo '#!/bin/bash\n\
export DISPLAY=:99\n\
Xvfb :99 -screen 0 1280x1024x24 > /dev/null 2>&1 &\n\
sleep 2\n\
x11vnc -display :99 -nopw -listen 0.0.0.0 -forever &\n\
cd /vistrails\n\
exec jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root\n\
' > /usr/local/bin/vistrails-jupyter && chmod +x /usr/local/bin/vistrails-jupyter

# Expose Jupyter and VNC ports
EXPOSE 8888 5900

# Default command
CMD ["vistrails", "--help"]
