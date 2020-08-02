#!/bin/bash

set -e

# ref: https://docs.docker.com/engine/install/debian/

# root check
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Set up the repository
apt-get update
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common
curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/debian \
   $(lsb_release -cs) \
   stable"

# Install Docker Engine
apt-get update
apt-get install docker-ce docker-ce-cli containerd.io

echo run \"sudo usermod -aG docker \$USER\"
echo Logout to make usermod cmd effective
echo run \"docker run --rm hello-world\" to test
