# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

EnvDeploy is a collection of bash scripts for initialising Debian/Ubuntu VPS environments. It automates nginx, SSL certificate, Node.js, PHP, and database setup for Vector Lab infrastructure.

## Architecture

```
EnvDeploy/
├── install.sh              # Main installer (nginx, bun, node, npm, pm2, acme.sh)
├── install/                # Optional component installers
│   ├── docker.sh           # Docker Engine
│   ├── mongodb.sh          # MongoDB 8.0 with user setup
│   └── php-mariadb.sh      # PHP-FPM + MariaDB
├── acme/                   # Let's Encrypt SSL site configs
│   ├── html.sh             # Static site
│   ├── node.sh             # Node.js reverse proxy
│   └── php.sh              # PHP-FPM site
├── cloudflare/             # Cloudflare Origin SSL site configs
│   ├── html.sh             # Static site
│   ├── node.sh             # Node.js reverse proxy
│   └── php.sh              # PHP-FPM site
└── data/                   # Templates and configs
```

### SSL Certificate Approaches

| Directory | Method | Certificates stored at |
|-----------|--------|------------------------|
| `acme/` | acme.sh + Let's Encrypt webroot | `/etc/letsencrypt/live/{domain}/` |
| `cloudflare/` | Manual Cloudflare Origin cert paste | `/cloudflare/{domain}/` |

### Site Configuration Flow

All site scripts follow the same pattern:
1. Prompt for domain (and port for Node.js)
2. Create `/websites/{domain}/` directory
3. Generate nginx config at `/etc/nginx/conf.d/{domain}.conf`
4. Issue/install SSL certificate
5. Reload nginx

## Key Paths on Deployed Servers

| Path | Purpose |
|------|---------|
| `/websites/{domain}/` | Site root directories |
| `/etc/nginx/conf.d/` | Nginx config files |
| `/etc/letsencrypt/live/{domain}/` | Let's Encrypt certificates |
| `/cloudflare/{domain}/` | Cloudflare Origin certificates |

## Common Commands

```bash
# Initial server setup
./install.sh

# Optional components
./install/docker.sh
./install/mongodb.sh
./install/php-mariadb.sh

# Add site with Let's Encrypt SSL
./acme/html.sh       # Static
./acme/node.sh       # Node.js (prompts for port)
./acme/php.sh        # PHP

# Add site with Cloudflare Origin SSL
./cloudflare/html.sh
./cloudflare/node.sh
./cloudflare/php.sh
```

## Code Conventions

- All scripts use `#!/bin/bash`
- All scripts use `set -euo pipefail` for strict error handling
- All scripts require root privileges and check with `id -u`
- Indentation: 2 spaces (nginx configs use 2-space indentation)
- User prompts and error messages are in English
- Variable naming: `snake_case` for locals, `UPPER_SNAKE` for readonly constants
