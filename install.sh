#!/bin/bash

set -e

sudo systemctl stop apache2 2>/dev/null || true
sudo systemctl disable apache2 2>/dev/null || true
sudo apt remove apache2 -y 2>/dev/null || true

sudo rm -f /etc/apt/sources.list.d/nginx.list
sudo rm -f /usr/share/keyrings/nginx-archive-keyring.gpg
sudo rm -f /etc/apt/preferences.d/99nginx

sudo apt update -y
sudo apt install -y sudo unzip wget curl gnupg screen git rsync build-essential python3 cron lsb-release

ENV_SYS_DISTID=$(lsb_release -is | tail -n 1)
ENV_SYS_CODENAME=$(lsb_release -cs | tail -n 1)

case $ENV_SYS_DISTID in
"Ubuntu")
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu ${ENV_SYS_CODENAME} nginx" | sudo tee /etc/apt/sources.list.d/nginx.list
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx
;;
"Debian")
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/debian ${ENV_SYS_CODENAME} nginx" | sudo tee /etc/apt/sources.list.d/nginx.list
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx
;;
*)
echo "Warning: Unsupported distro, using default nginx package"
;;
esac

sudo apt update -y && sudo apt dist-upgrade -y
sudo apt install -y nginx

sudo systemctl enable nginx
sudo systemctl restart nginx

curl -fsSL https://bun.sh/install | bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

if ! grep -q 'BUN_INSTALL' ~/.bashrc 2>/dev/null; then
  echo '' >> ~/.bashrc
  echo 'export BUN_INSTALL="$HOME/.bun"' >> ~/.bashrc
  echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> ~/.bashrc
fi

curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs

npm install -g pm2
pm2 startup

curl https://get.acme.sh | sh -s email=admin@example.com --force

echo ""
echo "Installation complete!"
echo "Installed: git, screen, rsync, nginx, bun, node (LTS), npm, pm2, acme.sh, build-essential, python3"
