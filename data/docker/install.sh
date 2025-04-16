#!/bin/bash

# Step 1: 更新包索引并安装依赖项
echo "Step 1: 更新包索引并安装依赖项..."
sudo apt update -y
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# Step 2: 添加 Docker 的官方 GPG 密钥
echo "Step 2: 添加 Docker 的官方 GPG 密钥..."
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Step 3: 设置 Docker 的稳定版本仓库
echo "Step 3: 设置 Docker 的稳定版本仓库..."
DOCKER_ARCH=$(dpkg --print-architecture)
DOCKER_VERSION=$(lsb_release -cs)
echo "deb [arch=${DOCKER_ARCH} signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian ${DOCKER_VERSION} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Step 4: 安装 Docker Engine
echo "Step 4: 安装 Docker Engine..."
sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Step 5: 启动 Docker 并将其设置为开机自启
echo "Step 5: 启动 Docker 并将其设置为开机自启..."
sudo systemctl start docker
sudo systemctl enable docker

# Step 6: 验证 Docker 安装
echo "Step 6: 验证 Docker 安装..."
sudo docker run hello-world

# 提示用户安装完成
echo "Docker 安装完成。如果您看到 'Hello from Docker!' 信息，则安装成功。"
