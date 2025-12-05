#!/bin/bash

set -euo pipefail

echo "=== PHP + MariaDB 安装脚本 ==="
echo ""

read -s -p "请输入 MariaDB root 密码: " MARIADB_ROOT_PASSWORD
echo ""

if [ -z "$MARIADB_ROOT_PASSWORD" ]; then
  echo "错误: 密码不能为空"
  exit 1
fi

echo ""
echo "正在安装 PHP..."
sudo apt update
sudo apt install -y php php-fpm php-mysql php-mbstring php-xml php-curl php-zip php-gd

PHP_VERSION=$(php -r 'echo PHP_VERSION;' | grep -oP "^\d+\.\d+")
PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"

sudo systemctl enable ${PHP_FPM_SERVICE}
sudo systemctl start ${PHP_FPM_SERVICE}

echo "PHP ${PHP_VERSION} 安装完成"
echo ""

echo "正在安装 MariaDB..."
sudo apt install -y mariadb-server

sudo mysql -u root <<-EOF
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$MARIADB_ROOT_PASSWORD');
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

sudo systemctl enable mariadb
sudo systemctl restart mariadb

echo ""
echo "=== 安装完成 ==="
echo "PHP 版本: ${PHP_VERSION}"
echo "PHP-FPM 服务: ${PHP_FPM_SERVICE}"
echo "MariaDB root 密码已设置"
echo ""
echo "创建数据库和用户示例:"
echo "  mysql -u root -p"
echo "  CREATE DATABASE mydb;"
echo "  CREATE USER 'myuser'@'localhost' IDENTIFIED BY 'mypassword';"
echo "  GRANT ALL PRIVILEGES ON mydb.* TO 'myuser'@'localhost';"
echo "  FLUSH PRIVILEGES;"
