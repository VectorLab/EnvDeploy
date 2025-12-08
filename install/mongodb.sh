#!/bin/bash

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: Please run this script as root"
  exit 1
fi

echo "=== MongoDB Installation Script ==="
echo ""

apt update -y
apt install -y curl gnupg lsb-release

read -s -p "Enter MongoDB root password: " MONGO_ROOT_PASSWORD
echo ""

if [ -z "$MONGO_ROOT_PASSWORD" ]; then
  echo "Error: Password cannot be empty"
  exit 1
fi

read -p "Enter database name: " MONGO_DB_NAME
read -p "Enter database username: " MONGO_DB_USER
read -s -p "Enter database user password: " MONGO_DB_PASSWORD
echo ""

if [ -z "$MONGO_DB_NAME" ] || [ -z "$MONGO_DB_USER" ] || [ -z "$MONGO_DB_PASSWORD" ]; then
  echo "Error: All fields are required"
  exit 1
fi

ENV_SYS_DISTID=$(lsb_release -is | tail -n 1)

echo ""
echo "Adding MongoDB repository..."

case $ENV_SYS_DISTID in
"Ubuntu")
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/8.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-8.0.list
  ;;
"Debian")
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
  echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/8.0 main" > /etc/apt/sources.list.d/mongodb-org-8.0.list
  ;;
*)
  echo "Warning: Unsupported distribution, attempting to use default package"
  ;;
esac

echo "Installing MongoDB..."
apt update
apt install -y mongodb-org

systemctl enable mongod
systemctl start mongod

sleep 3

echo "Configuring MongoDB users..."

mongosh <<EOF
use admin
db.createUser({
  user: "root",
  pwd: "$MONGO_ROOT_PASSWORD",
  roles: [ { role: "userAdminAnyDatabase", db: "admin" }, { role: "root", db: "admin" } ]
})
EOF

mongosh -u root -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin <<EOF
use $MONGO_DB_NAME
db.createUser({
  user: "$MONGO_DB_USER",
  pwd: "$MONGO_DB_PASSWORD",
  roles: [ { role: "readWrite", db: "$MONGO_DB_NAME" } ]
})
EOF

MONGOD_CONF="/etc/mongod.conf"

if ! grep -q "authorization: enabled" "$MONGOD_CONF"; then
  echo "Enabling MongoDB authentication..."
  sed -i 's/#security:/security:\n  authorization: enabled/' "$MONGOD_CONF"
fi

systemctl restart mongod

echo ""
echo "=== Installation Complete ==="
echo "MongoDB version: $(mongod --version | head -1)"
echo "Root user created"
echo "Database: $MONGO_DB_NAME"
echo "Database user: $MONGO_DB_USER"
echo ""
echo "Connection example:"
echo "  mongosh -u $MONGO_DB_USER -p --authenticationDatabase $MONGO_DB_NAME"
echo ""
echo "To allow remote connections, edit $MONGOD_CONF:"
echo "  net:"
echo "    bindIp: 0.0.0.0"
echo "Then restart: systemctl restart mongod"
