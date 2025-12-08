#!/bin/bash

set -euo pipefail

check_dependencies() {
  local missing=()

  if ! command -v nginx >/dev/null 2>&1; then
    missing+=("nginx")
  fi

  if [ ! -f ~/.acme.sh/acme.sh ]; then
    missing+=("acme.sh")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    echo "Error: Missing dependencies: ${missing[*]}"
    echo "Please run install.sh first"
    exit 1
  fi
}

check_dependencies

echo "Enter domain name:"
read -r domain

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
  echo "Error: Please enter a valid domain name"
  exit 1
fi

sudo mkdir -p /websites/$full_domain
sudo mkdir -p /etc/letsencrypt/live/$full_domain
sudo mkdir -p /etc/nginx/sites-available

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

  server_tokens off;

  ssl_certificate /etc/letsencrypt/live/$full_domain/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$full_domain/privkey.pem;
  ssl_protocols TLSv1.3;
  ssl_prefer_server_ciphers off;
  ssl_session_timeout 1d;
  ssl_session_cache shared:SSL:10m;
  ssl_session_tickets off;
  ssl_buffer_size 4k;
  ssl_stapling on;
  ssl_stapling_verify on;
  resolver 1.1.1.1 8.8.8.8 valid=300s;
  resolver_timeout 5s;

  add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;
  add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

  gzip on;
  gzip_vary on;
  gzip_proxied any;
  gzip_min_length 1k;
  gzip_comp_level 5;
  gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml application/rss+xml application/atom+xml image/svg+xml font/woff font/woff2 application/font-woff application/font-woff2;

  if (\$host != $full_domain) { return 301 \$scheme://$full_domain\$request_uri; }

  location ~* \.(gif|jpg|jpeg|png|bmp|ico|webp|avif|svg)$ {
    expires 1y;
    access_log off;
    add_header Cache-Control "public, immutable";
  }

  location ~* \.(js|css)$ {
    expires 1y;
    access_log off;
    add_header Cache-Control "public, immutable";
  }

  location ~* \.(woff|woff2|ttf|otf|eot)$ {
    expires 1y;
    access_log off;
    add_header Cache-Control "public, immutable";
    add_header Access-Control-Allow-Origin "*";
  }

  location ~* \.(mp4|webm|ogg|mp3|wav|flv|swf)$ {
    expires 30d;
    access_log off;
    add_header Cache-Control "public";
  }

  location ~ /(\.user\.ini|\.ht|\.git|\.svn|\.env|\.DS_Store|Thumbs\.db) {
    deny all;
  }

  location /.well-known {
    allow all;
  }
}
EOF

sudo nginx -t
sudo systemctl reload nginx
