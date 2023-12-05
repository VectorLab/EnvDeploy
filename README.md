# EnvDeploy

## 概述
本指南旨在指导矢量实验室如何初始化Debian 12 VPS。请各位实验委员注意，本脚本仅在该系统上进行过测试。

## 初始设置
### 系统更新
在开始配置之前，请确保系统是最新的。可以通过以下命令进行系统更新：

```bash
apt update -y && apt upgrade -y
```

### 修改密码
更新系统后，建议修改密码以增强安全性。可以使用以下命令生成一个强密码：

```bash
openssl rand -hex 16
```

## 开启BBR加速
BBR是一种用于TCP网络拥塞控制的算法，可以显著提高网络传输速度。按照以下步骤开启BBR加速：

1. 下载并安装BBR脚本：

    ```bash
    wget -N --no-check-certificate https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh
    chmod +x tcp.sh
    ./tcp.sh
    ```

2. 在脚本菜单中，选择 **1 (BBR)**。大多数情况下，BBR已经默认开启，可以跳过此步骤。
3. 接下来，选择 **4 (开启BBR)**，然后选择 **10 (优化)**。
4. 同意重启以应用更改。

## 安装Git和安装脚本运行
为了运行必要的脚本，需要安装Git并克隆相应的仓库：

```bash
apt install git -y
git clone https://github.com/VectorLab/EnvDeploy
cd EnvDeploy
chmod +x install.sh html.sh node.sh php.sh
./install.sh
```

### 数据库密码设置
运行安装脚本后，应该为MariaDB生成一个密码，并在安装完成后为MongoDB配置密码。