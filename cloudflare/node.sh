#!/bin/bash

set -euo pipefail

readonly NGINX_AVAILABLE="/etc/nginx/sites-available"
readonly NGINX_ENABLED="/etc/nginx/sites-enabled"
readonly WEBSITES_DIR="/websites"
readonly CERT_DIR="/cloudflare"

check_dependencies() {
  local dependencies=(nginx openssl)
  for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      if ! sudo apt-get update && sudo apt-get install -y "$dep"; then
        echo "错误: 安装 $dep 失败"
        exit 1
      fi
    fi
  done
}

validate_domain() {
  local domain="$1"
  local domain_regex="^([a-zA-Z0-9][a-zA-Z0-9-]*\.)+[a-zA-Z]{2,}$"
  if [[ ! $domain =~ $domain_regex ]]; then
    echo "错误：无效的域名格式"
    return 1
  fi
  return 0
}

validate_port() {
  local port="$1"
  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
    echo "错误：端口号必须是 1024-65535 之间的数字"
    return 1
  fi
  return 0
}

validate_certificate() {
  local cert="$1"
  local temp_file=$(mktemp)
  printf "%b" "$cert" > "$temp_file"
  
  if ! openssl x509 -in "$temp_file" -noout 2>/dev/null; then
    rm "$temp_file"
    echo "错误：无效的证书格式"
    return 1
  fi
  
  rm "$temp_file"
  return 0
}

create_directories() {
  local domain="$1"
  local dirs=("$WEBSITES_DIR/$domain" "$CERT_DIR/$domain")
  
  for dir in "${dirs[@]}"; do
    if ! sudo mkdir -p "$dir"; then
      echo "错误：创建目录 $dir 失败"
      return 1
    fi
  done
}

save_certificates() {
  local domain="$1"
  local cert="$2"
  local key="$3"
  
  printf "%b" "$cert" | sudo tee "$CERT_DIR/$domain/fullchain.pem" > /dev/null
  printf "%b" "$key" | sudo tee "$CERT_DIR/$domain/privkey.pem" > /dev/null
  
  sudo chmod 644 "$CERT_DIR/$domain/fullchain.pem"
  sudo chmod 600 "$CERT_DIR/$domain/privkey.pem"
}

generate_nginx_config() {
  local domain="$1"
  local is_subdomain="$2"
  local port="$3"
  local server_name_directive
  
  if [ "$is_subdomain" = true ]; then
    server_name_directive="$domain"
  else
    server_name_directive="$domain www.$domain"
  fi
  
  cat <<EOF | sudo tee "$NGINX_AVAILABLE/$domain.conf" > /dev/null
server {
    listen 80;
    listen [::]:80;
    server_name $server_name_directive;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    ssl_certificate $CERT_DIR/$domain/fullchain.pem;
    ssl_certificate_key $CERT_DIR/$domain/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ecdh_curve X25519:prime256v1:secp384r1:secp521r1;
    ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers on;
    ssl_session_timeout 10m;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    ssl_buffer_size 2k;
    
    add_header Strict-Transport-Security max-age=15768000;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1k;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/x-javascript application/xml;
    gzip_disable "MSIE [1-6]\\.";
    
    server_name $server_name_directive;
    
    if (\$host != $domain) { return 301 \$scheme://$domain\$request_uri; }
    
    index index.html index.htm index.js;
    root $WEBSITES_DIR/$domain;
    
    location / {
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Nginx-Proxy true;
        proxy_pass http://127.0.0.1:$port;
        proxy_redirect off;
    }
    
    location ~ .*\\.(gif|jpg|jpeg|png|bmp|swf|flv|mp4|ico)$ {
        expires 30d;
        proxy_pass http://127.0.0.1:$port;
        access_log off;
    }
    
    location ~ .*\\.(js|css)?$ {
        expires 7d;
        proxy_pass http://127.0.0.1:$port;
        access_log off;
    }
    
    location ~ /(\\\.user\\.ini|\\.ht|\\.git|\\.svn|\\.project|LICENSE|README\\.md) {
        deny all;
    }
}
EOF

  sudo ln -sf "$NGINX_AVAILABLE/$domain.conf" "$NGINX_ENABLED/"
}

reload_nginx() {
  if ! sudo nginx -t; then
    echo "Nginx 配置测试失败"
    return 1
  fi
  
  if ! sudo systemctl reload nginx; then
    echo "Nginx 重载失败"
    return 1
  fi
  
  return 0
}

main() {
  check_dependencies
  
  echo "请输入域名:"
  read -r domain
  
  if ! validate_domain "$domain"; then
    exit 1
  fi

  echo "请输入端口号 (1024-65535):"
  read -r port

  if ! validate_port "$port"; then
    exit 1
  fi
  
  echo "请粘贴 Cloudflare 证书内容:"
  echo "（从 -----BEGIN CERTIFICATE----- 开始粘贴，粘贴完成后按 Ctrl+D）"
  cert_content=$(cat)
  
  if ! validate_certificate "$cert_content"; then
    exit 1
  fi
  
  echo "请粘贴 Cloudflare 私钥内容:"
  echo "（从 -----BEGIN PRIVATE KEY----- 开始粘贴，粘贴完成后按 Ctrl+D）"
  key_content=$(cat)
  
  local primary_domain
  local subdomain
  local full_domain
  local is_subdomain
  
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
  
  if ! create_directories "$full_domain"; then
    exit 1
  fi
  
  save_certificates "$full_domain" "$cert_content" "$key_content"
  generate_nginx_config "$full_domain" "$is_subdomain" "$port" "$port"
  
  if ! reload_nginx; then
    exit 1
  fi
  
  echo "配置完成！"
  echo "网站目录: $WEBSITES_DIR/$full_domain"
  echo "证书位置: $CERT_DIR/$full_domain"
  echo "Node.js 端口: $port"
}

main
