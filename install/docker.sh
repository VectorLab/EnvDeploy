#!/bin/bash

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: Please run this script as root"
  exit 1
fi

echo "=== Docker Installation Script ==="
echo ""

echo "[1/6] Updating package index and installing dependencies..."
apt update -y
apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

echo "[2/6] Adding Docker official GPG key..."
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "[3/6] Setting up Docker stable repository..."
DOCKER_ARCH=$(dpkg --print-architecture)
DOCKER_CODENAME=$(lsb_release -cs)
echo "deb [arch=${DOCKER_ARCH} signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian ${DOCKER_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

echo "[4/6] Installing Docker Engine..."
apt update -y
apt install -y docker-ce docker-ce-cli containerd.io

echo "[5/6] Starting Docker and enabling on boot..."
systemctl start docker
systemctl enable docker

echo "[6/6] Verifying Docker installation..."
docker run hello-world

echo ""
echo "=== Docker Installation Complete ==="
echo "If you see 'Hello from Docker!' message, the installation was successful."
