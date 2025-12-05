#!/bin/bash

set -euo pipefail

readonly NGINX_AVAILABLE="/etc/nginx/sites-available"
readonly NGINX_CONFD="/etc/nginx/conf.d"
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

  if ! command -v php >/dev/null 2>&1; then
    echo "错误: PHP 未安装，请先运行 install/php-mariadb.sh"
    exit 1
  fi
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

detect_php_version() {
  local php_version
  php_version=$(php -r 'echo PHP_VERSION;' | grep -oP "^\d+\.\d+")
  echo "/var/run/php/php${php_version}-fpm.sock"
}

generate_nginx_config() {
  local domain="$1"
  local is_subdomain="$2"
  local php_sock="$3"
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
  return 301 https://$domain\$request_uri;
}

server {
  listen 443 ssl;
  listen [::]:443 ssl;
  http2 on;

  server_name $server_name_directive;
  root $WEBSITES_DIR/$domain;
  index index.php index.html index.htm;

  ssl_certificate $CERT_DIR/$domain/fullchain.pem;
  ssl_certificate_key $CERT_DIR/$domain/privkey.pem;
  ssl_protocols TLSv1.3;
  ssl_prefer_server_ciphers on;
  ssl_session_timeout 10m;
  ssl_session_cache shared:SSL:10m;
  ssl_session_tickets off;
  ssl_buffer_size 2k;

  add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Content-Type-Options "nosniff" always;

  gzip on;
  gzip_vary on;
  gzip_min_length 1k;
  gzip_comp_level 6;
  gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

  if (\$host != $domain) { return 301 \$scheme://$domain\$request_uri; }

  client_max_body_size 64m;

  location / {
    try_files \$uri \$uri/ /index.php\$is_args\$args;
  }

  location ~ \.php$ {
    try_files \$uri =404;
    fastcgi_split_path_info ^(.+\.php)(/.+)$;
    fastcgi_pass unix:$php_sock;
    fastcgi_index index.php;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    fastcgi_param PATH_INFO \$fastcgi_path_info;
  }

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
}
EOF

  sudo ln -sf "$NGINX_AVAILABLE/$domain.conf" "$NGINX_CONFD/"
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

  local php_sock
  php_sock=$(detect_php_version)

  save_certificates "$full_domain" "$cert_content" "$key_content"
  generate_nginx_config "$full_domain" "$is_subdomain" "$php_sock"

  if ! reload_nginx; then
    exit 1
  fi

  echo "配置完成！"
  echo "网站目录: $WEBSITES_DIR/$full_domain"
  echo "证书位置: $CERT_DIR/$full_domain"
  echo "PHP-FPM Socket: $php_sock"
}

main
