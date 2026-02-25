# Synthphony Project Guide for Agent Zero

## Overview

**Synthphony** is a self-hosted Docker Compose homelab platform running on a Linux Mint server (192.168.178.77). It consists of 4 "planes" (stacks) that provide DNS, VPN, monitoring, and AI services.

**Agent Zero's Role:** Lead developer with direct git access for self-updates. Agent Zero can edit configuration files, commit changes, and push to the `synthphony-dev` branch.

---

## Architecture

### The 4 Planes

| Plane | Purpose | Key Services |
|-------|---------|--------------|
| **BridgeCade** | Network foundation | Caddy (reverse proxy), Pi-hole (DNS), WireGuard (VPN) |
| **MetronOmni** | Monitoring | Portainer, Uptime Kuma, Netdata |
| **MYestro** | Productivity | Nextcloud, Solidtime, Homepage |
| **OrchestrAI** | AI & Automation | Agent Zero, Windmill, Ollama, OpenWebUI |

### Domain Structure

All services accessible via `*.synth.home.arpa`:
- `agentzero.synth.home.arpa` - Agent Zero web UI
- `windmill.synth.home.arpa` - Windmill automation
- `ollama.synth.home.arpa` - OpenWebUI for LLMs
- `nextcloud.synth.home.arpa` - File storage
- `portainer.synth.home.arpa` - Container management

---

## Directory Structure

```
/a0/usr/projects/synthphony/          # Agent Zero's view (git repo)
├── OrchestrAI/                       # AI plane
│   ├── compose.yaml                  # Docker Compose config
│   ├── scripts/
│   │   ├── setup.sh                  # One-time setup
│   │   ├── start.sh                  # Start services
│   │   └── stop.sh                   # Stop services
│   ├── secrets/                      # Git-ignored secrets
│   └── .env.example                  # Template for .env
├── BridgeCade/                       # Network plane
├── MYestro/                          # Productivity plane
├── MetronOmni/                       # Monitoring plane
├── scripts/                          # Global scripts
│   ├── deploy-code.sh                # Sync changes to server
│   ├── start-all.sh                  # Start all planes
│   └── stop-all.sh                   # Stop all planes
└── .gitignore                        # Prevents committing data/secrets
```

---

## Git Workflow

### Branches

| Branch | Purpose | Auto-Deploy |
|--------|---------|-------------|
| `main` | Production - stable, reviewed changes | ✅ Yes (via GitHub Actions) |
| `synthphony-dev` | Development - testing, experiments | ❌ No (manual deploy) |

### Agent Zero's Capabilities

**✅ Agent Zero CAN:**
- Edit files in `/a0/usr/projects/synthphony/`
- Run `git add`, `git commit`, `git push origin synthphony-dev`
- Create and modify Docker Compose files
- Update scripts and documentation
- Test changes on the dev branch

**❌ Agent Zero CANNOT (Security Policy):**
- Push directly to `main` branch
- Modify production-critical configs without explicit permission
- Access production secrets (tokens are masked)
- Deploy to production (requires manual merge + GitHub Actions)

### Self-Update Workflow

```bash
# 1. Edit files
nano /a0/usr/projects/synthphony/OrchestrAI/compose.yaml

# 2. Stage changes
cd /a0/usr/projects/synthphony
git add -A

# 3. Commit with descriptive message
git commit -m "Update OrchestrAI: add healthcheck to Windmill"

# 4. Push to dev branch
git push origin synthphony-dev

# 5. User reviews on GitHub and merges to main
# 6. GitHub Actions auto-deploys to production
```

---

## Volume Mounts (Dual-Mount Setup)

Agent Zero uses a **dual-mount configuration** for self-updates:

| Container Path | Host Path | Purpose |
|----------------|-----------|---------|
| `/a0` | `/opt/Synthphony/OrchestrAI/agentzero_data` | Agent data (chats, uploads, settings) |
| `/a0/usr/projects/synthphony` | `/opt/Synthphony` | Full git repo with `.git` access |

**How it works:** Linux mount shadowing allows both mounts to coexist. The more specific mount (`/a0/usr/projects/synthphony`) takes precedence over the general one (`/a0`).

---

## Common Operations

### Check Service Status

```bash
# From server (SSH to 192.168.178.77)
cd /opt/Synthphony/OrchestrAI
docker compose ps
```

### View Logs

```bash
# Agent Zero logs
docker logs orchestrai-agentzero --tail 100

# Windmill logs
docker logs orchestrai-windmill --tail 50
```

### Restart a Service

```bash
# From server
cd /opt/Synthphony/OrchestrAI
docker compose restart agentzero
```

### Sync Changes to Server (Manual)

If Agent Zero pushes changes but they need to be applied immediately:

```bash
# On server
cd /opt/Synthphony
git pull origin synthphony-dev

# Restart affected services
cd OrchestrAI
docker compose up -d --remove-orphans
```

---

## Security & Best Practices

### Critical Rules

1. **Never commit secrets** - `.env` files and `secrets/` directories are git-ignored
2. **Always use synthphony-dev** - Never push directly to `main`
3. **Test before merging** - Verify changes work on dev before PR to main
4. **Ask before changing** - For Docker Compose, Caddy configs, or production-critical files

### Protected Files

The following require explicit user permission to modify:
- `OrchestrAI/compose.yaml` (core infrastructure)
- `BridgeCade/compose.yaml` (network/DNS)
- Any Caddy/Proxy configurations
- Production deployment scripts

### Backup Strategy

Before major changes:
```bash
# On server
cd /opt/Synthphony
./scripts/backup-all.sh
```

---

## Troubleshooting

### Git "dubious ownership" error

```bash
git config --global --add safe.directory /a0/usr/projects/synthphony
```

### Container won't start

```bash
# Check for port conflicts
docker compose logs <service-name>

# Verify .env file exists and is populated
cat OrchestrAI/.env
```

### Changes not reflecting

```bash
# Ensure you're on synthphony-dev branch
git branch

# Check if changes are committed
git status

# Pull latest on server
git pull origin synthphony-dev
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Check git status | `cd /a0/usr/projects/synthphony && git status` |
| Commit changes | `git add -A && git commit -m "message"` |
| Push to dev | `git push origin synthphony-dev` |
| View recent commits | `git log --oneline -5` |
| Edit compose.yaml | `nano /a0/usr/projects/synthphony/OrchestrAI/compose.yaml` |
| Restart Agent Zero | `docker compose restart agentzero` (from server) |

---

## Project Metadata

- **Repository:** https://github.com/nico7master/Synthphony
- **Server:** 192.168.178.77 (Home-Server, Linux Mint XFCE)
- **Domain:** *.synth.home.arpa
- **Agent Zero Container:** orchestrai-agentzero
- **Image:** agent0ai/agent-zero:latest
- **Git User:** Agent Zero <agentzero@synthphony.local>
- **Dev Branch:** synthphony-dev

---

*Last updated: 2026-02-25*
*Setup: Dual-mount self-update configuration enabled*
