# Synthphony v6 — Credentials Reference
# ======================================
# Single reference for all service logins.
# Generated: 2026-02-08
#
# IMPORTANT: Keep this file secure. Do not commit to Git.


## Quick Login Table

| Service | URL | Username | Password Location |
|---------|-----|----------|-------------------|
| Pi-hole | https://pihole.synth.home.arpa/admin/ | (none needed) | See below |
| Portainer | https://portainer.synth.home.arpa | (create on first visit) | You choose |
| Uptime Kuma | https://status.synth.home.arpa | (create on first visit) | You choose |
| Netdata | https://netdata.synth.home.arpa | (no login required) | — |
| Nextcloud | https://nextcloud.synth.home.arpa | admin | See below |
| Solidtime | https://solidtime.synth.home.arpa | (email) | See below |
| OpenWebUI | https://ollama.synth.home.arpa | (create on first visit) | You choose |
| Windmill | https://windmill.synth.home.arpa | admin@windmill.dev | changeme |
| AgentZero | https://agentzero.synth.home.arpa | (no login) | — |


## Password Details

### Pi-hole Admin
- Auto-generated during BridgeCade setup
- Retrieve: cat /opt/Synthphony/BridgeCade/secrets/pihole_admin_password.txt
- Also in: grep PIHOLE_ADMIN_PASSWORD /opt/Synthphony/BridgeCade/.env

### Nextcloud
- Username: admin
- Auto-generated during MYestro setup
- Retrieve: grep NEXTCLOUD_ADMIN_PASSWORD /opt/Synthphony/MYestro/.env
- Display name can be changed (doesn't affect login)

### Solidtime
- Email: (value of SOLIDTIME_ADMIN_EMAIL in MYestro .env)
- Retrieve email: grep SOLIDTIME_ADMIN_EMAIL /opt/Synthphony/MYestro/.env
- Password: auto-generated on first start by artisan command
- Retrieve: cat /opt/Synthphony/MYestro/.solidtime_admin_created
- If no password found, reset via:
  cd /opt/Synthphony/MYestro
  docker compose exec myestro-solidtime-scheduler php artisan admin:user:create "Admin" "your@email.com" --verify-email

### Windmill
- Default admin: admin@windmill.dev / changeme
- CHANGE THIS on first login! (Settings > Account)
- DB password (internal, not for login): grep WINDMILL_DB_PASSWORD /opt/Synthphony/OrchestrAI/.env

### Portainer
- Create admin account on FIRST visit
- Must visit within 5 minutes of first start or it locks out
- If locked out: docker volume rm metronomni_portainer-data, restart

### Uptime Kuma
- Create admin account on first visit
- No time limit

### OpenWebUI (at ollama.synth.home.arpa)
- Create account on first visit
- First account automatically becomes admin

### Netdata
- No login required (read-only monitoring dashboard)

### AgentZero
- No login required (direct access)


## Internal/Database Passwords (not for browser login)

These are used internally between services. You don't need them for daily use:

| Secret | Location | Used By |
|--------|----------|---------|
| Nextcloud DB root | /opt/Synthphony/MYestro/secrets/nextcloud_db_root_password.txt | MariaDB root |
| Nextcloud DB user | /opt/Synthphony/MYestro/secrets/nextcloud_db_password.txt | Nextcloud <-> MariaDB |
| Solidtime DB | grep SOLIDTIME_DB_PASSWORD /opt/Synthphony/MYestro/.env | Solidtime <-> PostgreSQL |
| Windmill DB | /opt/Synthphony/OrchestrAI/secrets/windmill_db_password.txt | Windmill <-> PostgreSQL |
| Windmill encryption | grep WM_ENCRYPTION_KEY /opt/Synthphony/OrchestrAI/.env | Windmill internal |
| Windmill JWT | grep WM_JWT_SECRET /opt/Synthphony/OrchestrAI/.env | Windmill internal |


## Quick Commands — Retrieve All Passwords at Once

```bash
echo "=== Pi-hole ==="
cat /opt/Synthphony/BridgeCade/secrets/pihole_admin_password.txt

echo "=== Nextcloud ==="
grep NEXTCLOUD_ADMIN_PASSWORD /opt/Synthphony/MYestro/.env

echo "=== Solidtime ==="
grep SOLIDTIME_ADMIN_EMAIL /opt/Synthphony/MYestro/.env
cat /opt/Synthphony/MYestro/.solidtime_admin_created 2>/dev/null || echo "(not yet created)"

echo "=== Windmill ==="
echo "admin@windmill.dev / changeme (CHANGE ON FIRST LOGIN)"
```
