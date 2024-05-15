#!/bin/bash

echo "请输入域名:"
read domain

# 检查域名是一级域名还是二级域名
if [[ $domain =~ \. ]]; then
  primary_domain=${domain#*.}
  subdomain=${domain%%.*}
  if [[ $primary_domain =~ \. ]]; then
    # 如果 primary_domain 仍然包含一个点，它就是二级域名
    full_domain=$domain
    is_subdomain=true
  else
    full_domain=$domain
    is_subdomain=false
  fi
else
  echo "请输入有效的域名"
  exit 1
fi

# 创建目录
sudo mkdir -p /websites/$full_domain
sudo mkdir -p /etc/letsencrypt/live/$full_domain # 创建证书目录

# 创建 Node.js 的临时 Nginx 配置文件，仅监听 80 端口
cat <<EOF | sudo tee /etc/nginx/sites-available/$full_domain.conf
server {
  listen 80;
  listen [::]:80;
  server_name $full_domain;

  location /.well-known/acme-challenge/ {
    root /websites/$full_domain;
  }

  location / {
    return 200 'Temporary page - Node.js setup';
  }
}
EOF

sudo ln -s /etc/nginx/sites-available/$full_domain.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# 注册 ACME.sh 账户
~/.acme.sh/acme.sh --register-account -m support@nebulo.cn

# 使用 ACME.sh 获取 Let's Encrypt 证书
if [ "$is_subdomain" = true ]; then
  ~/.acme.sh/acme.sh --issue -d $full_domain --webroot /websites/$full_domain
else
  ~/.acme.sh/acme.sh --issue -d $domain -d www.$domain --webroot /websites/$domain
fi

# 安装证书到指定目录
