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

2. 在脚本菜单中，选择 **1 (BBR)**。大多数情况下，BBR已经默认开启，可以跳过此步骤
3. 接下来，选择 **4 (开启BBR)**，然后选择 **10 (优化)**
4. 同意重启以应用更改

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
运行安装脚本后，应该为MariaDB生成一个密码，并在安装完成后为MongoDB配置密码：

```javascript
use admin
db.createUser({
  user: "root",
  pwd: "[管理员密码]",
  roles: [ { role: "userAdminAnyDatabase", db: "admin" } ]
})
db.auth("root", "[管理员密码]")
use [数据库名]
db.createUser({
    user: "[数据库用户名]",
    pwd: "[数据库密码]",
    roles: [
        { role: "readWrite", db: "[数据库名]" }
    ]
})
```

或者可以运行[MongoDB设置脚本](data/mongodb_setup.sh)来直接设定内容

以上两者都须确保将 `[管理员密码]` ， `[数据库用户名]` 和 `[数据库密码]` 替换为需要的内容

另外脚本还需注意赋予执行权限后运行：

```
chmod +x /data/mongodb_setup.sh
./data/mongodb_setup.sh
```


另外，还需修改 `/etc/mongodb.conf` 文件，修改

```
net:
  port: 27017
  bindIp: 0.0.0.0  # 允许所有 IP 地址连接
```

并去掉安全注释，更改为

```
security:
  authorization: enabled
```

以此加强安全性

## 配置脚本选择
根据矢量实验室的技术栈需求，选择合适的配置脚本进行网站的初始设置。这里有三种类型的脚本可供选择：

1. **静态网站配置** - 如果需要部署静态网站，使用以下命令：
```bash
./html.sh
```

2. **Node.js 应用配置** - 对于需要部署Node.js应用的情况，使用此命令：
```bash
./node.sh
```

3. **PHP 环境配置** - 如果项目是基于PHP的，执行下面的命令：
```bash
./php.sh
```

在执行上述任一命令后，输入项目的域名，并等待acme.sh完成Let's Encrypt证书的签发

### 网站文件管理
所有网站文件均存放在 `/websites` 目录中。根据你的域名，你可以在此目录下上传或修改网站文件

### Nginx 配置
Nginx的配置文件位于 `/etc/nginx/sites-available/` 目录。按需修改配置文件，并重载Nginx以使更改生效。请注意，`/etc/nginx/sites-enabled/` 目录包含的是符号链接，不需要直接修改

### Tyepcho 伪静态配置文件
鉴于PHP环境多为typecho程序，已默认为php.sh脚本加上：

```bash
  if (!-e $request_filename) {
    rewrite ^(.*)$ /index.php$1 last;
  }
```

如不需要，则可以删除

### Node.js 应用的守护进程
如果部署了Node.js应用，需要使用pm2来守护进程。使用以下命令启动Node.js应用：

```bash
cd /websites/[域名] && pm2 start "yarn run start" --name [网站应用名字]
```

确保将 `[域名]` 和 `[网站应用名字]` 替换为实际的域名和应用名

如运行多个Node.js应用，需要自己调整不同的端口

**更改nginx配置文件时注意矢量实验室中的TAB键是两个空格，不应破坏美观度**