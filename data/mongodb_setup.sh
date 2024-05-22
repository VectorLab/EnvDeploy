#!/bin/bash

# 定义变量
MONGO_ROOT_USER="root"
MONGO_ROOT_PASSWORD="管理员密码"
MONGO_DB_NAME="数据库名"
MONGO_DB_USER="数据库用户名"
MONGO_DB_PASSWORD="数据库密码"

# Step 1: 创建管理员用户
echo "Step 1: 创建管理员用户..."
mongo <<EOF
use admin
db.createUser({
  user: "$MONGO_ROOT_USER",
  pwd: "$MONGO_ROOT_PASSWORD",
  roles: [ { role: "userAdminAnyDatabase", db: "admin" } ]
})
EOF

# Step 2: 认证管理员用户
echo "Step 2: 认证管理员用户..."
mongo <<EOF
use admin
db.auth("$MONGO_ROOT_USER", "$MONGO_ROOT_PASSWORD")
EOF

# Step 3: 切换到目标数据库并创建普通用户
echo "Step 3: 切换到目标数据库并创建普通用户..."
mongo <<EOF
use $MONGO_DB_NAME
db.createUser({
    user: "$MONGO_DB_USER",
    pwd: "$MONGO_DB_PASSWORD",
    roles: [
        { role: "readWrite", db: "$MONGO_DB_NAME" }
    ]
})
EOF

echo "MongoDB 用户创建完成。"
