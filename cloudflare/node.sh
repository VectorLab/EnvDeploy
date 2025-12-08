#!/bin/bash

set -euo pipefail

readonly NGINX_AVAILABLE="/etc/nginx/sites-available"
readonly NGINX_CONFD="/etc/nginx/conf.d"
readonly WEBSITES_DIR="/websites"
readonly CERT_DIR="/cloudflare"

check_dependencies() {
  local missing=()

  for dep in nginx openssl; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      missing+=("$dep")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    echo "Error: Missing dependencies: ${missing[*]}"
    echo "Please run install.sh first or install manually"
    exit 1
  fi
}

validate_domain() {
  local domain="$1"
  local domain_regex="^([a-zA-Z0-9][a-zA-Z0-9-]*\.)+[a-zA-Z]{2,}$"
  if [[ ! $domain =~ $domain_regex ]]; then
    echo "Error: Invalid domain format"
    return 1
  fi
  return 0
}

validate_port() {
  local port="$1"
  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
    echo "Error: Port must be a number between 1024-65535"
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
    echo "Error: Invalid certificate format"
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
      echo "Error: Failed to create directory $dir"
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
  return 301 https://$domain\$request_uri;
}

server {
  listen 443 ssl;
  listen [::]:443 ssl;
  http2 on;

  server_name $server_name_directive;

  server_tokens off;

  ssl_certificate $CERT_DIR/$domain/fullchain.pem;
  ssl_certificate_key $CERT_DIR/$domain/privkey.pem;
  ssl_protocols TLSv1.3;
  ssl_prefer_server_ciphers off;
  ssl_session_timeout 1d;
  ssl_session_cache shared:SSL:10m;
  ssl_session_tickets off;
  ssl_buffer_size 4k;

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
  gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml application/rss+xml application/atom+xml image/svg+xml font/woff font/woff2;

  if (\$host != $domain) { return 301 \$scheme://$domain\$request_uri; }

  client_max_body_size 64m;

  location / {
    proxy_pass http://127.0.0.1:$port;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_cache_bypass \$http_upgrade;
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
  }

  location /_next/static {
    proxy_pass http://127.0.0.1:$port;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    expires 1y;
    access_log off;
    add_header Cache-Control "public, max-age=31536000, immutable";
  }

  location ~* \\.(ico|jpg|jpeg|png|gif|svg|webp|avif)$ {
    proxy_pass http://127.0.0.1:$port;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    expires 1y;
    access_log off;
    add_header Cache-Control "public, max-age=31536000, immutable";
  }

  location ~* \\.(woff|woff2|ttf|otf|eot)$ {
    proxy_pass http://127.0.0.1:$port;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    expires 1y;
    access_log off;
    add_header Cache-Control "public, max-age=31536000, immutable";
    add_header Access-Control-Allow-Origin "*";
  }

  location ~ /(\\.user\\.ini|\\.ht|\\.git|\\.svn|\\.env|\\.DS_Store) {
    deny all;
  }
}
EOF

  sudo ln -sf "$NGINX_AVAILABLE/$domain.conf" "$NGINX_CONFD/"
}

reload_nginx() {
  if ! sudo nginx -t; then
    echo "Error: Nginx configuration test failed"
    return 1
  fi

  if ! sudo systemctl reload nginx; then
    echo "Error: Failed to reload Nginx"
    return 1
  fi

  return 0
}

main() {
  check_dependencies

  echo "Enter domain name:"
  read -r domain

  if ! validate_domain "$domain"; then
    exit 1
  fi

  echo "Enter port number (1024-65535):"
  read -r port

  if ! validate_port "$port"; then
    exit 1
  fi

  echo "Paste Cloudflare certificate content:"
  echo "(Start from -----BEGIN CERTIFICATE-----, press Ctrl+D when done)"
  cert_content=$(cat)

  if ! validate_certificate "$cert_content"; then
    exit 1
  fi

  echo "Paste Cloudflare private key content:"
  echo "(Start from -----BEGIN PRIVATE KEY-----, press Ctrl+D when done)"
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
    echo "Error: Please enter a valid domain name"
    exit 1
  fi

  if ! create_directories "$full_domain"; then
    exit 1
  fi

  save_certificates "$full_domain" "$cert_content" "$key_content"
  generate_nginx_config "$full_domain" "$is_subdomain" "$port"

  if ! reload_nginx; then
    exit 1
  fi

  echo "Configuration complete!"
  echo "Website directory: $WEBSITES_DIR/$full_domain"
  echo "Certificate location: $CERT_DIR/$full_domain"
  echo "Node.js port: $port"
}

main
