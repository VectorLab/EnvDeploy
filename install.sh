#!/bin/bash

# 提示实验委员输入 MariaDB root 密码
read -s -p "请输入 MariaDB root 用户的密码: " root_password
echo
read -r -N1 -p "是否尝试设置强制跳转https [Yy/N(默认)]: " HAS_REDIRECT_HTTPS
echo
read -r -N1 -p "是否安装acme.sh [Nn/Y(默认)]: " HAS_ACMESH

ENV_SYS_DISTID=$(lsb_release -is | tail -n 1)

# 确保 Apache 未安装或已被移除
sudo systemctl stop apache2
sudo systemctl disable apache2
sudo apt remove apache2 -y

# 安装 MongoDB
#curl -fsSL https://pgp.mongodb.com/server-7.0.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/mongodb-server-7.0.gpg
#echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

case $ENV_SYS_DISTID in
"Ubuntu")
# 安装 MongoDB https://www.mongodb.com/docs/manual/tutorial/install-mongodb-on-ubuntu/#std-label-install-mdb-community-ubuntu
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs | tail -n 1)/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
# 安装 Nginx https://nginx.org/en/linux_packages.html
curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu `lsb_release -cs` nginx" | sudo tee /etc/apt/sources.list.d/nginx.list
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx
;;
"Debian")
# 安装 MongoDB https://www.mongodb.com/docs/manual/tutorial/install-mongodb-on-debian/#std-label-install-mdb-community-debian
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/8.0 main" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
# 安装 Nginx https://nginx.org/en/linux_packages.html
curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/debian `lsb_release -cs` nginx" | sudo tee /etc/apt/sources.list.d/nginx.list
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx
;;
*)
read -r -N1 -p "当前系统暂不支持自动安装nginx,按任意键继续或CTRL-C结束 " unused
;;
esac

# 更新系统包并安装必要工具
sudo apt update -y && sudo apt dist-upgrade -y && sudo apt install sudo unzip wget curl gnupg screen git -y

# 安装 Nginx
sudo apt install nginx -y

if [[ "y" == ${HAS_REDIRECT_HTTPS,,} ]] && [[ -f /etc/nginx/sites-available/default ]] && [[ "" == $(sudo cat /etc/nginx/sites-available/default | grep -F 'return 301 https://$server_name$request_uri;' ) ]]; then
echo "try to apply nginx redirect patch"
sudo cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.original.backup
sudo git apply --include=/etc/nginx/sites-available/default ./data/nginx_default_redirect.patch
echo "done"
fi

sudo systemctl enable nginx
sudo systemctl restart nginx

# 安装 PHP
sudo apt install php php-fpm php-mysql php-mbstring -y
PHP_VERSION=$(php -r 'echo PHP_VERSION;' | grep --only-matching --perl-regexp "^\\d+\\.\\d+")
PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
sudo systemctl restart ${PHP_FPM_SERVICE}
sudo systemctl enable ${PHP_FPM_SERVICE}

# 安装 MariaDB
sudo apt install mariadb-server -y

# MariaDB 安全配置自动化
sudo mysql -u root <<-EOF
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$root_password');
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
sudo apt install npm -y
npm install -g yarn
yarn global add pm2
yarn global add nodemon

# 安装 MongoDB
sudo apt update
sudo apt install -y mongodb-org
sudo systemctl start mongod
sudo systemctl enable mongod

if [[ "n" != ${HAS_ACMESH,,} ]]; then
# 安装 ACME.sh
curl https://get.acme.sh | sh
fi
