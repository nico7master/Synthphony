# Synthphony Troubleshooting Guide

Common issues and their solutions when running Synthphony.

---

## Table of Contents

1. [Connection Issues](#connection-issues)
2. [DNS Issues](#dns-issues)
3. [Certificate Issues](#certificate-issues)
4. [Docker Issues](#docker-issues)
5. [Service-Specific Issues](#service-specific-issues)
6. [Migration Issues](#migration-issues)

---

## Connection Issues

### Services Unreachable From LAN (Connection Refused)

**Symptoms:**
- `curl` returns "Failed to connect" or "Connection refused"
- Browser shows "This site can't be reached"
- Works from mini PC itself but not from other devices

**Cause:** iptables FORWARD policy set to DROP, blocking Docker port forwarding.

**Fix:**
```bash
# Check current policy
sudo iptables -L FORWARD -n | head -1

# If it shows "policy DROP":
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -P FORWARD ACCEPT
```

This is handled automatically by `BridgeCade/scripts/setup.sh`.

---

### Services Work on Server But Not From Other Devices

**Symptoms:**
- `curl https://agentzero.synth.home.arpa` works on mini PC
- Same command fails from local PC with "Connection refused"

**Cause 1: Old /etc/hosts entries**

Previous Synthphony installation added entries to `/etc/hosts` pointing `*.synth.home.arpa` to the old host IP. `/etc/hosts` takes priority over DNS.

**Fix:**
```bash
# Check for old entries
grep synth /etc/hosts

# Remove them
sudo sed -i '/synth\.home\.arpa/d' /etc/hosts

# Verify
grep synth /etc/hosts # Should return nothing
```

**Cause 2: Wrong DNS server**

Your device is not using Pi-hole as its DNS server.

**Fix:**
- Check router DNS settings (should point to Synthphony server IP)
- Or manually set DNS on your device to the Synthphony server IP

---

## DNS Issues

### "Address Not Found" on Phone (5G/Mobile Data)

**Symptoms:**
- Phone on WiFi works fine
- Phone on 5G shows "Address not found" or "DNS_PROBE_FINISHED_NXDOMAIN"

**Cause:** Phone uses carrier DNS which can't resolve `synth.home.arpa`.

**Fix:** Configure Tailscale DNS:

1. Go to https://login.tailscale.com/admin/dns
2. Click "Add nameserver" → "Custom"
3. Enter your Synthphony server IP (e.g., `192.168.178.100`)
4. Check "Restrict to domain" and enter: `synth.home.arpa`
5. Click Save
6. Enable "Override local DNS"
7. Connect Tailscale on your phone

Without this, phones on 5G cannot resolve `*.synth.home.arpa`.

---

### Pi-hole Not Responding to DNS Queries

**Symptoms:**
- `dig @192.168.178.100 google.com` times out
- Internet stops working after starting BridgeCade

**Cause:** systemd-resolved or another service is using port 53.

**Fix:**
```bash
# Check what's using port 53
sudo ss -tlnp | grep :53

# If systemd-resolved, disable stub listener
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved

# Restart BridgeCade
cd /opt/Synthphony/BridgeCade && ./scripts/stop.sh && ./scripts/start.sh
```

---

## Certificate Issues

### "Not Secure" / Certificate Warning in Browser

**Symptoms:**
- Browser shows "Your connection is not private"
- NET::ERR_CERT_AUTHORITY_INVALID

**Cause:** mkcert CA not trusted on your device.

**Fix:** See [CLIENT-SETUP.md](CLIENT-SETUP.md) for per-platform CA installation instructions.

Quick fix for Linux:
```bash
# Copy CA from server
scp home-server@192.168.178.100:/opt/Synthphony/BridgeCade/mkcert-ca/rootCA.pem ~/Downloads/

# Install system-wide
sudo cp ~/Downloads/rootCA.pem /usr/local/share/ca-certificates/synthphony-ca.crt
sudo update-ca-certificates

# For Chrome: also install to NSS database
sudo apt install libnss3-tools
certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n "Synthphony mkcert CA" -i ~/Downloads/rootCA.pem
```

**Restart browser completely after installation!**

---

### Certificate Warning Persists After Installing CA

**Cause:** Old certificates cached by browser or conflicting old CAs.

**Fix:**
```bash
# Remove old mkcert CAs from Chrome
sudo apt install libnss3-tools
certutil -d sql:$HOME/.pki/nssdb -L | grep mkcert
certutil -d sql:$HOME/.pki/nssdb -D -n "mkcert development CA"

# Re-install new CA
certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n "Synthphony mkcert CA" -i ~/Downloads/rootCA.pem
```

Clear browser cache and restart.

---

## Docker Issues

### "Cannot connect to the Docker daemon"

**Symptoms:**
- `docker ps` shows permission denied
- Setup script fails with Docker errors

**Fix:**
```bash
# Check if user is in docker group
groups $USER | grep docker

# If not, add and re-login
sudo usermod -aG docker $USER
# Log out and log back in!
```

---

### Container Keeps Restarting

**Symptoms:**
- `docker ps` shows container status as "Restarting"

**Diagnose:**
```bash
# Check logs
docker logs <container-name>

# Check exit code
docker inspect <container-name> | grep -A5 State
```

**Common causes:**
- Missing environment variables (check .env file)
- Port conflict (another service using the port)
- Resource limits (OOM killed)

---

### "Network bridgecade_web not found"

**Symptoms:**
- `docker compose up` fails with network error
- Services can't start

**Fix:**
```bash
# Create the network
docker network create bridgecade_web

# Or run setup which does this automatically
cd /opt/Synthphony/BridgeCade && ./scripts/setup.sh
```

---

## Service-Specific Issues

### Portainer Locked Out

**Symptoms:**
- "Your session has expired" or can't create admin account

**Cause:** Took too long to create admin account after first start.

**Fix:**
```bash
cd /opt/Synthphony/MetronOmni
docker compose down
rm -rf portainer-data
docker compose up -d
# Visit immediately and create admin account
```

---

### Nextcloud Shows "Internal Server Error"

**Diagnose:**
```bash
# Check Nextcloud logs
docker logs myestro-nextcloud

# Check database
docker logs myestro-nextcloud-db
```

**Common fix:**
```bash
# Fix permissions
cd /opt/Synthphony/MYestro
sudo chown -R 33:33 nextcloud/html
sudo chown -R 999:999 nextcloud/db
```

---

### Windmill Shows "Database Connection Error"

**Diagnose:**
```bash
# Check if database is running
docker ps | grep windmill-db

# Check logs
docker logs orchestrai-windmill-db
docker logs orchestrai-windmill
```

**Fix:**
```bash
# Re-run setup to sync passwords
cd /opt/Synthphony/OrchestrAI && ./scripts/setup.sh
```

---

## Migration Issues

### After Migrating to New Server, Services Don't Work

**Checklist:**

1. **Clean up old /etc/hosts on local PC:**
   ```bash
   sudo sed -i '/synth\.home\.arpa/d' /etc/hosts
   ```

2. **Update router DNS to new server IP**

3. **Renew DHCP on all devices**

4. **Verify firewall on new server:**
   ```bash
   sudo iptables -L FORWARD -n | head -1
   # Should show: Chain FORWARD (policy ACCEPT)
   ```

5. **Install new CA certificate on all devices** (see CLIENT-SETUP.md)

6. **Update Tailscale DNS to new server IP** (if using Tailscale)

See [FIRST-TIME-SETUP-GUIDE.txt](FIRST-TIME-SETUP-GUIDE.txt) Section 13 for complete migration checklist.

---

## Getting Help

If issues persist:

1. Check container logs: `docker logs <container-name>`
2. Check service status: `docker ps`
3. Verify network: `docker network inspect bridgecade_web`
4. Review setup output for errors

For detailed setup instructions, see:
- [README.md](README.md) - Overview and quick start
- [FIRST-TIME-SETUP-GUIDE.txt](FIRST-TIME-SETUP-GUIDE.txt) - Complete setup walkthrough
- [CLIENT-SETUP.md](CLIENT-SETUP.md) - Device configuration
- [TAILSCALE-SETUP.md](TAILSCALE-SETUP.md) - VPN configuration
