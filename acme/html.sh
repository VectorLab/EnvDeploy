#!/bin/bash

echo "请输入域名:"
read domain

if [[ $domain =~ \. ]]; then
  primary_domain=${domain#*.}
  subdomain=${domain%%.*}
  if [[ $primary_domain =~ \. ]]; then
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

sudo mkdir -p /websites/$full_domain
sudo mkdir -p /etc/letsencrypt/live/$full_domain

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
    return 200 'Temporary page - HTML setup';
  }
}
EOF

sudo ln -sf /etc/nginx/sites-available/$full_domain.conf /etc/nginx/conf.d/
sudo nginx -t
sudo systemctl reload nginx

~/.acme.sh/acme.sh --register-account -m support@nebulo.cn

if [ "$is_subdomain" = true ]; then
  ~/.acme.sh/acme.sh --issue -d $full_domain --webroot /websites/$full_domain
else
  ~/.acme.sh/acme.sh --issue -d $domain -d www.$domain --webroot /websites/$domain
fi

~/.acme.sh/acme.sh --install-cert -d $full_domain \
    --key-file       /etc/letsencrypt/live/$full_domain/privkey.pem  \
    --fullchain-file /etc/letsencrypt/live/$full_domain/fullchain.pem \
    --reloadcmd     "sudo systemctl reload nginx"

cat <<EOF | sudo tee /etc/nginx/sites-available/$full_domain.conf
server {
  listen 80;
  listen [::]:80;
  server_name $server_name_directive;
  return 301 https://$full_domain\$request_uri;
}

server {
  listen 443 ssl;
  listen [::]:443 ssl;
  http2 on;

  server_name $server_name_directive;
  root /websites/$full_domain;
  index index.html index.htm;

  ssl_certificate /etc/letsencrypt/live/$full_domain/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$full_domain/privkey.pem;
  ssl_protocols TLSv1.3;
  ssl_prefer_server_ciphers on;
  ssl_session_timeout 10m;
  ssl_session_cache shared:SSL:10m;
  ssl_session_tickets off;
  ssl_buffer_size 2k;
  ssl_stapling on;
  ssl_stapling_verify on;

  add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Content-Type-Options "nosniff" always;

  gzip on;
  gzip_vary on;
  gzip_min_length 1k;
  gzip_comp_level 6;
  gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

  if (\$host != $full_domain) { return 301 \$scheme://$full_domain\$request_uri; }

  location ~ .*\.(gif|jpg|jpeg|png|bmp|swf|flv|mp4|ico|webp|avif)$ {
    expires 30d;
    access_log off;
  }

  location ~ .*\.(js|css)$ {
    expires 7d;
    access_log off;
  }

  location ~ /(\.user\.ini|\.ht|\.git|\.svn|\.env.*) {
    deny all;
  }

  location /.well-known {
    allow all;
  }
}
EOF

sudo nginx -t
sudo systemctl reload nginx
