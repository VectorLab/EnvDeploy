#!/bin/bash

echo "请输入域名:"
read domain

sudo mkdir -p /websites/$domain
sudo mkdir -p /etc/letsencrypt/live/$domain # 创建证书目录

# 创建 Node.js 的临时 Nginx 配置文件，仅监听 80 端口
cat <<EOF | sudo tee /etc/nginx/sites-available/$domain.conf
server {
  listen 80;
  listen [::]:80;
  server_name $domain www.$domain;

  location /.well-known/acme-challenge/ {
    root /websites/$domain;
  }

  location / {
    return 200 'Temporary page - Node.js setup';
  }
}
EOF

sudo ln -s /etc/nginx/sites-available/$domain.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# 注册 ACME.sh 账户
~/.acme.sh/acme.sh --register-account -m support@nebulo.cn

# 使用 ACME.sh 获取 Let's Encrypt 证书
~/.acme.sh/acme.sh --issue -d $domain -d www.$domain --webroot /websites/$domain

# 安装证书到指定目录
~/.acme.sh/acme.sh --install-cert -d $domain \
    --key-file       /etc/letsencrypt/live/$domain/privkey.pem  \
    --fullchain-file /etc/letsencrypt/live/$domain/fullchain.pem \
    --reloadcmd     "sudo systemctl reload nginx"

# 更新 Nginx 配置以包括 SSL 以及 Node.js 相关设置
cat <<EOF | sudo tee /etc/nginx/sites-available/$domain.conf
server {
  listen 80;
  listen [::]:80;
  listen 443 ssl http2;
  listen [::]:443 ssl http2;

  ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ecdh_curve X25519:prime256v1:secp384r1:secp521r1;
  ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256';
  ssl_prefer_server_ciphers on;
  ssl_session_timeout 10m;
  ssl_session_cache shared:SSL:10m;
  ssl_buffer_size 2k;
  add_header Strict-Transport-Security max-age=15768000;
  ssl_stapling on;
  ssl_stapling_verify on;
  server_name $domain www.$domain;

  if (\$ssl_protocol = "") { return 301 https://\$host\$request_uri; }
  if (\$host != $domain) {  return 301 \$scheme://$domain\$request_uri;  }

  index index.html index.htm index.js;
  root /websites/$domain;

  location / {
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header Host \$http_host;
    proxy_set_header X-Nginx-Proxy true;
    proxy_pass http://127.0.0.1:3000;
    proxy_redirect off;
  }
  location ~ .*\.(gif|jpg|jpeg|png|bmp|swf|flv|mp4|ico)$ {
    expires 30d;
    proxy_pass http://127.0.0.1:3000;
    access_log off;
  }
  location ~ .*\.(js|css)?$ {
    expires 7d;
    proxy_pass http://127.0.0.1:3000;
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
