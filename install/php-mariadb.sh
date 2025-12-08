#!/bin/bash

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: Please run this script as root"
  exit 1
fi

echo "=== PHP + MariaDB Installation Script ==="
echo ""

read -s -p "Enter MariaDB root password: " MARIADB_ROOT_PASSWORD
echo ""

if [ -z "$MARIADB_ROOT_PASSWORD" ]; then
  echo "Error: Password cannot be empty"
  exit 1
fi

echo ""
echo "Installing PHP..."
apt update
apt install -y php php-fpm php-mysql php-mbstring php-xml php-curl php-zip php-gd

PHP_VERSION=$(php -r 'echo PHP_VERSION;' | grep -oP "^\d+\.\d+")
PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"

systemctl enable "${PHP_FPM_SERVICE}"
systemctl start "${PHP_FPM_SERVICE}"

echo "PHP ${PHP_VERSION} installed successfully"
echo ""

echo "Installing MariaDB..."
apt install -y mariadb-server

mysql -u root <<-EOF
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$MARIADB_ROOT_PASSWORD');
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

systemctl enable mariadb
systemctl restart mariadb

echo ""
echo "=== Installation Complete ==="
echo "PHP version: ${PHP_VERSION}"
echo "PHP-FPM service: ${PHP_FPM_SERVICE}"
echo "MariaDB root password configured"
echo ""
echo "Example: Create database and user:"
echo "  mysql -u root -p"
echo "  CREATE DATABASE mydb;"
echo "  CREATE USER 'myuser'@'localhost' IDENTIFIED BY 'mypassword';"
echo "  GRANT ALL PRIVILEGES ON mydb.* TO 'myuser'@'localhost';"
echo "  FLUSH PRIVILEGES;"
