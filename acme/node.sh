#!/bin/bash

echo "请输入域名:"
read domain

echo "请输入端口号:"
read port

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
if [ "$is_subdomain" = true ]; then
  server_name_directive=$full_domain
else
  server_name_directive="$domain www.$domain"
fi

cat <<EOF | sudo tee /etc/nginx/sites-available/$full_domain.conf
server {
  listen 80;
  listen [::]:80;
  server_name $server_name_directive;

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
~/.acme.sh/acme.sh --install-cert -d $full_domain \
    --key-file       /etc/letsencrypt/live/$full_domain/privkey.pem  \
    --fullchain-file /etc/letsencrypt/live/$full_domain/fullchain.pem \
    --reloadcmd     "sudo systemctl reload nginx"

# 更新 Nginx 配置以包括 SSL 以及 Node.js 相关设置
cat <<EOF | sudo tee /etc/nginx/sites-available/$full_domain.conf
server {
  listen 443 ssl;
  listen [::]:443 ssl;
  http2 on;

  ssl_certificate /etc/letsencrypt/live/$full_domain/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$full_domain/privkey.pem;
  ssl_protocols TLSv1.3;
  ssl_prefer_server_ciphers on;
  ssl_session_timeout 10m;
  ssl_session_cache shared:SSL:10m;
  ssl_buffer_size 2k;
  add_header Strict-Transport-Security max-age=15768000;
  ssl_stapling on;
  ssl_stapling_verify on;
  server_name $server_name_directive;

  if (\$ssl_protocol = "") { return 301 https://\$host\$request_uri; }
  if (\$host != $full_domain) {  return 301 \$scheme://$full_domain\$request_uri;  }

  index index.html index.htm index.js;
  root /websites/$full_domain;

  location / {
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header Host \$http_host;
    proxy_set_header X-Nginx-Proxy true;
    proxy_pass http://127.0.0.1:$port;
    proxy_redirect off;
  }
  location ~ .*\.(gif|jpg|jpeg|png|bmp|swf|flv|mp4|ico)$ {
    expires 30d;
    proxy_pass http://127.0.0.1:$port;
    access_log off;
  }
  location ~ .*\.(js|css)?$ {
    expires 7d;
    proxy_pass http://127.0.0.1:$port;
    access_log off;
  }
  location ~ /(\.user\.ini|\.ht|\.git|\.svn|\.project|LICENSE|README\.md) {
    deny all;
  }
  location /.well-known {
    allow all;
  }
}
EOF

sudo nginx -t
sudo systemctl reload nginx
