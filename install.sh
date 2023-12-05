#!/bin/bash

# 提示实验委员输入 MariaDB root 密码
echo "请输入 MariaDB root 用户的密码:"
read root_password

# 更新系统包并安装必要工具
apt update -y && apt upgrade -y && apt install sudo wget curl gnupg screen git -y

# 安装 Nginx
sudo apt install nginx -y
sudo systemctl restart nginx
sudo systemctl enable nginx

# 安装 PHP
sudo apt install php php-fpm php-mysql -y
PHP_VERSION=$(php -r 'echo PHP_VERSION;' | grep --only-matching --perl-regexp "^\\d+\\.\\d+")
PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
sudo systemctl restart ${PHP_FPM_SERVICE}
sudo systemctl enable ${PHP_FPM_SERVICE}

# 安装 MariaDB
sudo apt install mariadb-server -y

# MariaDB 安全配置自动化
sudo mysql -u root <<-EOF
UPDATE mysql.user SET Password=PASSWORD('$root_password') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

sudo systemctl restart mariadb
sudo systemctl enable mariadb

# 安装 Node.js
sudo apt install nodejs -y

# 安装 MongoDB
curl -fsSL https://pgp.mongodb.com/server-7.0.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/mongodb-server-7.0.gpg
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt update
sudo apt install -y mongodb-org
sudo systemctl start mongod
sudo systemctl enable mongod

# 安装 ACME.sh
curl https://get.acme.sh | sh
