# 🎼 Synthphony

> A single-host homelab platform with four planes — automated, secure, and ready to orchestrate your digital life.

[![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)](https://docker.com)
[![Caddy](https://img.shields.io/badge/Caddy-1F8C79?logo=caddy&logoColor=white)](https://caddyserver.com)
[![Pi-hole](https://img.shields.io/badge/Pi--hole-96060C?logo=pi-hole&logoColor=white)](https://pi-hole.net)
[![WireGuard](https://img.shields.io/badge/WireGuard-88171A?logo=wireguard&logoColor=white)](https://wireguard.com)
[![Tailscale](https://img.shields.io/badge/Tailscale-242424?logo=tailscale&logoColor=white)](https://tailscale.com)

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Architecture](#-architecture)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [The Four Planes](#-the-four-planes)
- [Network Architecture](#-network-architecture)
- [Security Features](#-security-features)
- [Daily Operations](#-daily-operations)
- [Service URLs & Credentials](#-service-urls--credentials)
- [Troubleshooting](#-troubleshooting)
- [Directory Structure](#-directory-structure)
- [License](#-license)

---

## 🎯 Overview

**Synthphony** is a complete homelab platform designed for single-host deployment. It provides:

- 🔒 **Automatic HTTPS** — Zero-config TLS certificates via mkcert
- 🌐 **Private DNS** — Local domain resolution with Pi-hole
- 🛡️ **VPN Access** — WireGuard + Tailscale for remote connectivity
- 🤖 **AI Stack** — AgentZero AI assistant, self-hosted LLMs with Ollama/OpenWebUI, Windmill automation
- ☁️ **Personal Cloud** — Nextcloud for files, Solidtime for time tracking
- 📊 **Monitoring** — Portainer, Uptime Kuma, and Netdata
- 🎛️ **Automation** — Windmill for workflows
- 🏠 **Dashboard** — Homepage with all your services

**Domain:** `*.synth.home.arpa`  
**Base Path:** `/opt/Synthphony`

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        SYNTHPHONY                              │
│                    Single-Host Homelab                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────┐│
│  │  BridgeCade │  │  MetronOmni │  │   MYestro   │  │Orchestr││
│  │  (Infra)    │  │  (Ops)      │  │ (Personal)  │  │  (AI)  ││
│  ├─────────────┤  ├─────────────┤  ├─────────────┤  ├────────┤│
│  │ • Caddy     │  │ • Portainer │  │ • Nextcloud │  │• AgentZ││
│  │ • Pi-hole   │  │ • Uptime    │  │ • Solidtime │  │• Ollama││
│  │ • WireGuard │  │   Kuma      │  │ • Homepage  │  │• OpenW ││
│  │ • Tailscale │  │ • Netdata   │  │             │  │• Windm ││
│  │ • Cert Iss. │  │             │  │             │  │• OpenNb ││
│  │ • DNS Reg.  │  │             │  │             │  │        ││
│  └──────┬──────┘  └─────────────┘  └─────────────┘  └────┬───┘│
│         │                                                │    │
│         └────────────────┬─────────────────────────────┘    │
│                          │                                   │
│              ┌───────────┴───────────┐                      │
│              │   bridgecade_web        │                      │
│              │   (Docker Network)      │                      │
│              └───────────────────────┘                      │
│                                                             │
└─────────────────────────────────────────────────────────────────┘
```

### Design Principles

1. **Automation-First** — Every operation is scripted; no manual steps in the main flow
2. **Zero-Config TLS** — mkcert generates trusted certificates automatically
3. **Label-Driven Ingress** — Caddy discovers services via Docker labels
4. **Split-Tunnel VPN** — Only LAN + VPN traffic routes through WireGuard
5. **Secrets Management** — Passwords in `secrets/` files, never in Git
6. **Idempotent Setup** — Run setup scripts multiple times safely

---

## 📦 Prerequisites

### Hardware

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| RAM | 16 GB | 32 GB (for AI workloads) |
| Storage | 100 GB SSD | 500 GB+ SSD |
| GPU | Optional | NVIDIA (for Ollama acceleration) |

### Software

- Linux host (Ubuntu 22.04+, Debian 12+, Linux Mint 22.3+)
- Docker Engine 24.0+ and Docker Compose v2
- NVIDIA Container Toolkit (optional, for GPU)

### Network

- Static or DHCP-reserved IP for the host
- Router access to configure DNS settings
- (Optional) Port forwarding for WireGuard UDP port

---

## 🚀 Quick Start

### 1. Clone and Prepare

```bash
# Copy Synthphony to /opt (recommended location)
sudo mkdir -p /opt/Synthphony
sudo cp -r /path/to/synthphony/* /opt/Synthphony/
sudo chown -R $USER:$USER /opt/Synthphony
cd /opt/Synthphony
```

### 2. Run Setup (One-Time)

```bash
./scripts/setup-all.sh
```

This automatically:
- ✅ Installs Docker (if missing)
- ✅ Creates the `bridgecade_web` Docker network
- ✅ Fixes port 53 conflicts (systemd-resolved)
- ✅ Generates all secrets and passwords
- ✅ Creates `.env` files from templates
- ✅ Sets up data directories with correct permissions

> ⚠️ **If prompted about Docker group changes:** Log out and log back in, then continue.

### 3. Start Everything

```bash
./scripts/start-all.sh
```

Starts stacks in order:
1. **BridgeCade** — Infrastructure (Caddy, Pi-hole, WireGuard, Tailscale)
2. **MetronOmni** — Monitoring (Portainer, Uptime Kuma, Netdata)
3. **MYestro** — Personal Cloud (Nextcloud, Solidtime, Homepage)
4. **OrchestrAI** — AI Stack (AgentZero, Ollama, OpenWebUI, Windmill)

### 4. Post-Startup Configuration

#### A. Point DNS to Pi-hole

**Router-wide (recommended):**
1. Log into your router admin panel
2. Find DHCP / DNS settings
3. Set primary DNS to your host IP (e.g., `192.168.1.100`)
4. Save and reconnect devices

**Verify:**
```bash
dig nextcloud.synth.home.arpa
# Should return your host IP
```

#### B. Trust the mkcert CA

Install the root CA certificate on your devices. See [CLIENT-SETUP.md](CLIENT-SETUP.md) for per-platform instructions.

```bash
# Linux (host)
sudo cp /opt/Synthphony/BridgeCade/mkcert-ca/rootCA.pem \
  /usr/local/share/ca-certificates/synthphony-ca.crt
sudo update-ca-certificates

# macOS
# Double-click rootCA.pem → Keychain Access → Trust → Always Trust

# Windows
# Double-click rootCA.pem → Install Certificate → Local Machine → Trusted Root
```

#### C. Configure WireGuard (Optional)

1. Port forward UDP `51821` (or your chosen port) to your host IP
2. Edit `/opt/Synthphony/BridgeCade/.env`:
   ```
   WG_SERVERURL=your-public-ip-or-ddns
   ```
3. Peer configs are in `/opt/Synthphony/BridgeCade/wireguard/`

#### D. Authenticate Tailscale (Optional)

```bash
# Get auth URL
docker logs bridgecade-tailscale | grep "https://login.tailscale.com"

# Open URL and authorize
# Approve subnet route at https://login.tailscale.com/admin/machines
```

```bash
# Configure Tailscale DNS (required for remote access)
# Go to https://login.tailscale.com/admin/dns
# Add custom nameserver: <YOUR-HOST-IP>, restricted to synth.home.arpa
# Enable "Override local DNS"
```



---

## 🏛️ The Four Planes

### 1. BridgeCade — Infrastructure Plane

**Purpose:** Ingress, DNS, VPN, and certificate management

| Service | Description | Port |
|---------|-------------|------|
| **Caddy** | Reverse proxy with automatic HTTPS | 80, 443 |
| **Pi-hole** | DNS server with ad blocking | 53 |
| **WireGuard** | VPN server for remote access | 51821/udp (configurable) |
| **Tailscale** | Mesh VPN (no port forwarding needed) | — |
| **cert-issuer** | Auto-generates TLS certificates | — |
| **dns-registrar** | Auto-registers DNS entries in Pi-hole | — |

**Key Features:**
- Caddy discovers services via Docker labels (`caddy`, `caddy.reverse_proxy`, `caddy.tls`)
- mkcert generates trusted certificates for `*.synth.home.arpa`
- Pi-hole v6 with automatic DNS registration
- Split-tunnel WireGuard (only LAN + VPN traffic)

### 2. MetronOmni — Operations Plane

**Purpose:** Monitoring and container management

| Service | Description | URL |
|---------|-------------|-----|
| **Portainer** | Docker management UI | https://portainer.synth.home.arpa |
| **Uptime Kuma** | Service monitoring & alerts | https://status.synth.home.arpa |
| **Netdata** | Real-time system metrics | https://netdata.synth.home.arpa |

### 3. MYestro — Personal Cloud Plane

**Purpose:** File storage, productivity, and dashboard

| Service | Description | URL |
|---------|-------------|-----|
| **Nextcloud** | Files, calendar, contacts | https://nextcloud.synth.home.arpa |
| **Solidtime** | Time tracking | https://solidtime.synth.home.arpa |
| **Homepage** | Service dashboard | https://page.synth.home.arpa |

### 4. OrchestrAI — AI Plane

**Purpose:** AI assistant, self-hosted LLMs, and automation

| Service | Description | URL |
|---------|-------------|-----|
| **AgentZero** | 🤖 AI assistant — the heart of the AI stack | https://agentzero.synth.home.arpa |
| **Ollama** | LLM inference server | (Internal only) |
| **OpenWebUI** | Chat interface for Ollama | https://ollama.synth.home.arpa |
| **Windmill** | Workflow automation platform | https://windmill.synth.home.arpa |
| **Open Notebook** | AI-powered research notebook | https://notebook.synth.home.arpa |

**Note:** AgentZero is the primary AI interface, integrating with Windmill for automation and Ollama for local LLM inference.

---

## 🌐 Network Architecture

### Shared Network

All ingress-exposed services connect to the external Docker network `bridgecade_web`:

```yaml
networks:
  bridgecade_web:
    external: true
```

### Caddy Label Convention

Services expose themselves to Caddy via Docker labels:

```yaml
labels:
  caddy: "service.synth.home.arpa"
  caddy.reverse_proxy: "{{upstreams 8080}}"
  caddy.tls: "/certs/service.synth.home.arpa.crt /certs/service.synth.home.arpa.key"
```

### DNS Resolution Flow

```
Client → Pi-hole (53) → Caddy (443) → Service Container
              ↑
         dns-registrar (auto-updates from Caddy labels)
```

### VPN Options

| Feature | WireGuard | Tailscale |
|---------|-----------|-----------|
| Setup | Port forwarding required | Zero-config |
| ISP Blocking | Vulnerable | Works through |
| Performance | Direct | Direct (with DERP fallback) |
| Use Case | Backup/primary | Primary (recommended) |

**Recommendation:** Use Tailscale as primary, WireGuard as backup.

---

## 🔐 Security Features

### TLS Certificates

- **Auto-generated:** mkcert creates certificates on first start
- **Trusted:** Install root CA on devices for no browser warnings
- **Per-service:** Each hostname gets its own certificate

### Secrets Management

```
/opt/Synthphony/
├── BridgeCade/secrets/pihole_admin_password.txt
├── MYestro/secrets/nextcloud_db_root_password.txt
├── MYestro/secrets/nextcloud_db_password.txt
└── OrchestrAI/secrets/windmill_db_password.txt
```

- Secrets are auto-generated by `setup.sh` scripts
- Files are `chmod 600` (owner read/write only)
- Never commit secrets to Git

### Network Security

- **DNS (53):** Restricted to LAN + VPN only (prevents open resolver)
- **Admin UIs:** LAN/VPN accessible only
- **No exposed ports:** App stacks bind to Docker network only

### Firewall (UFW Example)

```bash
# Allow HTTP/HTTPS from LAN
sudo ufw allow from 192.168.1.0/24 to any port 80,443 proto tcp

# Allow DNS from LAN + VPN only
sudo ufw allow from 192.168.1.0/24 to any port 53
sudo ufw allow from 10.66.66.0/24 to any port 53

# Allow WireGuard
sudo ufw allow 51821/udp
```

---

## 🔄 Daily Operations

### Global Commands

```bash
# Start all stacks
cd /opt/Synthphony && ./scripts/start-all.sh

# Stop all stacks
cd /opt/Synthphony && ./scripts/stop-all.sh

# Update all images (pull latest)
cd /opt/Synthphony && ./scripts/start-all.sh --force
```

### Individual Stack Commands

```bash
cd /opt/Synthphony/BridgeCade
./scripts/setup.sh   # Run setup (idempotent)
./scripts/start.sh   # Start the stack
./scripts/stop.sh    # Stop the stack

# Or use docker compose directly
docker compose up -d
docker compose down
docker compose logs -f
```

### View Passwords

```bash
# Pi-hole
cat /opt/Synthphony/BridgeCade/secrets/pihole_admin_password.txt

# Nextcloud
grep NEXTCLOUD_ADMIN_PASSWORD /opt/Synthphony/MYestro/.env

# Windmill DB
cat /opt/Synthphony/OrchestrAI/secrets/windmill_db_password.txt
```

### Check Status

```bash
# All containers
docker ps

# Specific stack
cd /opt/Synthphony/BridgeCade && docker compose ps

# Logs
docker logs bridgecade-caddy
docker logs -f orchestrai-ollama
```

---

## 🔑 Service URLs & Credentials

| Service | URL | Username | Password |
|---------|-----|----------|----------|
| **Pi-hole** | https://pihole.synth.home.arpa/admin | — | `secrets/pihole_admin_password.txt` |
| **Portainer** | https://portainer.synth.home.arpa | Create on first visit | You choose |
| **Uptime Kuma** | https://status.synth.home.arpa | Create on first visit | You choose |
| **Netdata** | https://netdata.synth.home.arpa | No login | — |
| **Nextcloud** | https://nextcloud.synth.home.arpa | admin | `.env` file |
| **Solidtime** | https://solidtime.synth.home.arpa | Email | Auto-generated |
| **Homepage** | https://page.synth.home.arpa | No login | — |
| **OpenWebUI** | https://ollama.synth.home.arpa | Create on first visit | You choose |
| **Windmill** | https://windmill.synth.home.arpa | admin@windmill.dev | `changeme` |
| **Open Notebook** | https://notebook.synth.home.arpa | — | — |
| **AgentZero** | https://agentzero.synth.home.arpa | No login | — |

> ⚠️ **Portainer:** Must create admin account within 5 minutes of first start!

---

## 🛠️ Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

Quick fixes:
- **Connection refused:** Check `sudo iptables -L FORWARD -n | head -1` shows ACCEPT
- **DNS not working:** Verify router DNS points to Synthphony server
- **Certificate warning:** Install mkcert CA (see [CLIENT-SETUP.md](CLIENT-SETUP.md))
- **Phone on 5G:** Configure Tailscale DNS (see [TAILSCALE-SETUP.md](TAILSCALE-SETUP.md))

---

## 📁 Directory Structure

```
/opt/Synthphony/
├── CLIENT-SETUP.md # Device configuration guide
├── TROUBLESHOOTING.md # Common issues and solutions
├── scripts/
│   ├── setup-all.sh          # Global setup orchestrator
│   ├── start-all.sh          # Start all stacks with DNS resilience
│   └── stop-all.sh           # Stop all stacks
│
├── BridgeCade/               # Infrastructure plane
│   ├── compose.yaml          # Caddy, Pi-hole, WireGuard, Tailscale
│   ├── .env.example          # Configuration template
│   ├── .env                  # Live configuration (chmod 600)
│   ├── scripts/
│   │   ├── setup.sh          # Docker, network, port 53 fix
│   │   ├── start.sh          # Start with health checks
│   │   └── stop.sh           # Stop stack
│   ├── cert-issuer/          # Auto-TLS container
│   │   ├── Dockerfile
│   │   └── issuer.py
│   ├── dns-registrar/        # Auto-DNS container
│   │   ├── Dockerfile
│   │   └── registrar.py
│   ├── certs/                # Generated TLS certificates
│   ├── mkcert-ca/            # mkcert CA persistence
│   ├── pihole/               # Pi-hole state
│   ├── wireguard/            # WireGuard keys & configs
│   └── secrets/
│       └── pihole_admin_password.txt
│
├── MetronOmni/               # Monitoring plane
│   ├── compose.yaml          # Portainer, Uptime Kuma, Netdata
│   ├── .env.example
│   ├── scripts/
│   │   ├── setup.sh
│   │   ├── start.sh
│   │   └── stop.sh
│   ├── portainer-data/
│   ├── uptime-kuma/
│   └── netdata/
│
├── MYestro/                  # Personal cloud plane
│   ├── compose.yaml          # Nextcloud, Solidtime, Homepage
│   ├── .env.example
│   ├── scripts/
│   │   ├── setup.sh
│   │   ├── start.sh
│   │   └── stop.sh
│   ├── secrets/
│   │   ├── nextcloud_db_root_password.txt
│   │   └── nextcloud_db_password.txt
│   ├── nextcloud/
│   │   ├── html/             # Nextcloud web root
│   │   └── db/               # MariaDB data
│   ├── solidtime/            # Solidtime data
│   └── homepage/             # Homepage dashboard config
│       ├── services.yaml     # Service definitions
│       ├── settings.yaml     # Dashboard settings
│       ├── widgets.yaml      # Widget configuration
│       └── docker.yaml       # Docker integration
│
├── OrchestrAI/               # AI plane
│   ├── compose.yaml          # AgentZero, Ollama, OpenWebUI, Windmill
│   ├── Dockerfile.agentzero-custom
│   ├── .env.example
│   ├── scripts/
│   │   ├── setup.sh
│   │   ├── start.sh
│   │   └── stop.sh
│   ├── secrets/
│   │   └── windmill_db_password.txt
│   ├── ollama/               # LLM models
│   ├── openwebui/            # OpenWebUI data
│   ├── windmill/             # Windmill data + DB
│   └── agentzero_data/       # AgentZero data
│
└── backups/                  # Backup storage
    ├── bridgecade/
    ├── metronomni/
    ├── myestro/
    └── orchestrai/
```

---

## 📝 Configuration Reference

### Environment Variables

#### BridgeCade `.env`

```bash
BASE_DOMAIN=synth.home.arpa

# Auto-detected by setup.sh (do not edit manually)
BRIDGECADE_LAN_IP=<YOUR-HOST-IP>
LAN_CIDR=<YOUR-LAN-CIDR>
LAN_NETWORK=<YOUR-LAN-NETWORK>
WG_SUBNET=10.66.66.0/24
WG_SERVER_IP=10.66.66.1
WG_ALLOWEDIPS=10.66.66.1/32,10.66.66.0/24,<YOUR-LAN-CIDR>
WG_INTERNAL_SUBNET=10.66.66.0

# WireGuard endpoint
WG_SERVERURL=<YOUR-PUBLIC-IP-OR-DDNS>  # For remote access
WG_SERVERPORT=51821
WG_PEERS=laptop,phone

# Tailscale (optional)
TAILSCALE_AUTHKEY=                # Or leave empty for interactive auth

# Secrets
PIHOLE_ADMIN_PASSWORD=********
```

#### MYestro `.env`

```bash
BASE_DOMAIN=synth.home.arpa

NEXTCLOUD_ADMIN_PASSWORD=********
NEXTCLOUD_DB_PASSWORD=********
NEXTCLOUD_DB_ROOT_PASSWORD=********

SOLIDTIME_ADMIN_EMAIL=admin@example.com
SOLIDTIME_DB_PASSWORD=********
```

#### OrchestrAI `.env`

```bash
BASE_DOMAIN=synth.home.arpa

WINDMILL_DB_PASSWORD=********
WM_ENCRYPTION_KEY=********
WM_JWT_SECRET=********

AGENTZERO_IMAGE=ghcr.io/your-org/agentzero:v1.0.0
```

---

## 🔄 Backup & Restore

### What to Back Up

| Data | Location | Importance |
|------|----------|------------|
| mkcert CA | `BridgeCade/mkcert-ca/` | Critical (all TLS) |
| Certificates | `BridgeCade/certs/` | High |
| WireGuard keys | `BridgeCade/wireguard/` | High |
| Pi-hole | `BridgeCade/pihole/` | Medium |
| Nextcloud | `MYestro/nextcloud/` | High |
| Solidtime | `MYestro/solidtime/` | Medium |
| Windmill | `OrchestrAI/windmill/` | Medium |
| SurrealDB | `OrchestrAI/surrealdb_data/` | Medium |
| Open Notebook | `OrchestrAI/notebook_data/` | Low (re-downloadable) |
| Ollama models | `OrchestrAI/ollama/` | Low (re-downloadable) |
| Secrets | `*/secrets/` | Critical |
| Configs | `*/.env` | High |

### Simple Backup Script

```bash
#!/bin/bash
BACKUP_DIR="/opt/Synthphony/backups/$(date +%F)"
mkdir -p "$BACKUP_DIR"

# Database dumps
docker exec myestro-nextcloud-db mysqldump -unextcloud -p"$(cat /opt/Synthphony/MYestro/secrets/nextcloud_db_password.txt)" nextcloud > "$BACKUP_DIR/nextcloud.sql"
docker exec orchestrai-windmill-db pg_dump -U windmill -d windmill > "$BACKUP_DIR/windmill.sql"

# File backups
tar czf "$BACKUP_DIR/configs.tar.gz" \
  /opt/Synthphony/BridgeCade/mkcert-ca \
  /opt/Synthphony/BridgeCade/certs \
  /opt/Synthphony/BridgeCade/wireguard \
  /opt/Synthphony/*/secrets \
  /opt/Synthphony/*/.env
```

---

## 📜 License

MIT License — See [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- **[AgentZero](https://www.agent-zero.ai/)** — 🤖 The AI assistant that powers the OrchestrAI plane
- [Caddy](https://caddyserver.com) — The ultimate reverse proxy
- [Pi-hole](https://pi-hole.net) — Network-wide ad blocking
- [WireGuard](https://wireguard.com) — Fast, modern VPN
- [Tailscale](https://tailscale.com) — Zero-config mesh VPN
- [Nextcloud](https://nextcloud.com) — Self-hosted cloud
- [Ollama](https://ollama.com) — Local LLMs made easy
- [OpenWebUI](https://openwebui.com) — Chat interface for LLMs
- [Windmill](https://windmill.dev) — Open-source workflow engine
- [Homepage](https://gethomepage.dev) — Self-hosted dashboard
- [Solidtime](https://solidtime.io) — Open-source time tracking

---

<div align="center">

**Made with ❤️ for the self-hosted community**

</div>
