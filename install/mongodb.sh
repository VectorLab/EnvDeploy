#!/bin/bash

set -euo pipefail

echo "=== MongoDB 安装脚本 ==="
echo ""

read -s -p "请输入 MongoDB root 密码: " MONGO_ROOT_PASSWORD
echo ""

if [ -z "$MONGO_ROOT_PASSWORD" ]; then
  echo "错误: 密码不能为空"
  exit 1
fi

read -p "请输入数据库名称: " MONGO_DB_NAME
read -p "请输入数据库用户名: " MONGO_DB_USER
read -s -p "请输入数据库用户密码: " MONGO_DB_PASSWORD
echo ""

if [ -z "$MONGO_DB_NAME" ] || [ -z "$MONGO_DB_USER" ] || [ -z "$MONGO_DB_PASSWORD" ]; then
  echo "错误: 所有字段都必须填写"
  exit 1
fi

ENV_SYS_DISTID=$(lsb_release -is | tail -n 1)

echo ""
echo "正在添加 MongoDB 源..."

case $ENV_SYS_DISTID in
"Ubuntu")
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
  ;;
"Debian")
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
  echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/8.0 main" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
  ;;
*)
  echo "警告: 不支持的系统，尝试使用默认包"
  ;;
esac

echo "正在安装 MongoDB..."
sudo apt update
sudo apt install -y mongodb-org

sudo systemctl enable mongod
sudo systemctl start mongod

sleep 3

echo "正在配置 MongoDB 用户..."

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
  echo "正在启用 MongoDB 认证..."
  sudo sed -i 's/#security:/security:\n  authorization: enabled/' "$MONGOD_CONF"
fi

sudo systemctl restart mongod

echo ""
echo "=== 安装完成 ==="
echo "MongoDB 版本: $(mongod --version | head -1)"
echo "root 用户已创建"
echo "数据库: $MONGO_DB_NAME"
echo "数据库用户: $MONGO_DB_USER"
echo ""
echo "连接示例:"
echo "  mongosh -u $MONGO_DB_USER -p --authenticationDatabase $MONGO_DB_NAME"
echo ""
echo "如需允许远程连接，请修改 $MONGOD_CONF:"
echo "  net:"
echo "    bindIp: 0.0.0.0"
echo "然后重启: sudo systemctl restart mongod"
