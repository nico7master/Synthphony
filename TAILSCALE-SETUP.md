# Tailscale Setup Guide for Synthphony

## What is Tailscale?

Tailscale is a zero-config VPN that uses WireGuard under the hood. It creates an encrypted mesh network between your devices without requiring port forwarding or public IPs.

## Why We Added It

If your ISP (<your-isp>) blocks all incoming connections via carrier-grade NAT, making traditional WireGuard port forwarding impossible. Tailscale works around this by:
- Creating outbound encrypted tunnels (bypasses ISP blocks)
- Using NAT traversal to establish direct connections when possible
- Falling back to relay servers when direct connections fail

## Split Tunnel Behavior

Tailscale operates as a **split tunnel VPN** by default:

| Traffic Type | Route | Example |
|-------------|-------|---------|
| Tailscale IPs (100.x.x.x) | Through Tailscale | `ping <phone-tailscale-ip>` |
| LAN subnet (<your-lan-network>) | Through Tailscale | `https://<your-lan-ip>` |
| Synthphony services | Through Tailscale | `https://pihole.synth.home.arpa` |
| Regular internet | Direct (fast) | `https://google.com` |

This means your phone's internet traffic goes directly to websites (fast), but Synthphony services route through the encrypted tunnel.

## Setup Instructions

### Prerequisites

- Synthphony BridgeCade stack running
- Tailscale account (free at https://login.tailscale.com)

### 1. Enable Tailscale in BridgeCade

Tailscale is included in the BridgeCade compose.yaml. Ensure it's enabled:

```bash
cd /opt/Synthphony/BridgeCade
docker compose ps | grep tailscale
```

If not running:
```bash
./scripts/setup.sh  # Creates LAN_NETWORK in .env
./scripts/stop.sh
./scripts/start.sh
```

### 2. Authenticate Tailscale

Get the authentication URL:
```bash
docker logs bridgecade-tailscale | grep "https://login.tailscale.com"
```

Open the URL in your browser and click **Authorize** to add this machine to your Tailscale network.

### 3. Approve Subnet Route

The server advertises your LAN subnet so devices can reach Synthphony services:

1. Go to https://login.tailscale.com/admin/machines
2. Find `synthphony-bridgecade`
3. Click **"Edit route settings"**
4. Check the box for your LAN network (e.g., `192.168.178.0/24`)
5. Save

### 4. Configure Tailscale DNS (Required for Remote Access)

Without this step, devices on 5G/external networks cannot resolve `*.synth.home.arpa` domains.

1. Go to **https://login.tailscale.com/admin/dns**
2. Click **"Add nameserver"** → **"Custom"**
3. Enter: `192.168.178.100` (your Pi-hole server IP)
4. **Check** "Restrict to domain" and enter: `synth.home.arpa`
5. Click **Save**
6. Enable **"Override local DNS"** (toggle ON on the same page)

This tells all Tailscale clients: "For any `*.synth.home.arpa` query, ask Pi-hole."

Without this, your phone on 5G uses your carrier's DNS which has no idea what `synth.home.arpa` is.

### 5. Connect Your Phone

1. Install Tailscale app (iOS/Android)
2. Sign in with the same account
3. Toggle the VPN ON
4. Access Synthphony: `https://pihole.synth.home.arpa`
5. Ensure DNS works:
   - On 5G: domains resolve via Tailscale DNS → Pi-hole
   - On home WiFi: domains resolve via Fritz.box → Pi-hole
6. Install mkcert CA certificate on phone (see FIRST-TIME-SETUP-GUIDE.txt Section 7)

---

## How It Works (Post-Setup)

Tailscale is now running as `bridgecade-tailscale` container.

### Current Status

Check if Tailscale is connected:
```bash
docker exec bridgecade-tailscale tailscale status
```

### What Routes Through Tailscale

| Traffic | Route | Example |
|---------|-------|---------|
| Tailscale IPs (100.x.x.x) | Through VPN | Other Tailscale devices |
| LAN subnet (<your-lan-network>) | Through VPN | `192.168.178.x` addresses |
| Synthphony services | Through VPN | `*.synth.home.arpa` |
| Regular internet | Direct | `google.com` (fast, no VPN overhead) |

### Connecting New Devices

1. Install Tailscale app on device
2. Sign in with your Tailscale account
3. Toggle ON
4. Access Synthphony services via `https://<service>.synth.home.arpa`

No additional server setup required.

## Tailscale vs WireGuard

| Feature | WireGuard | Tailscale |
|---------|-----------|-----------|
| **Setup complexity** | Manual config | Zero-config |
| **Port forwarding** | Required | Not needed |
| **ISP blocking** | Vulnerable | Works through |
| **Dependency** | Self-hosted | Tailscale servers |
| **Performance** | Direct | Direct (with fallback) |
| **Use case** | Backup/primary | Primary |

**Recommendation:** Keep both. Use Tailscale as primary (works everywhere), WireGuard as backup (no third-party dependency).

## Troubleshooting

### Container not running
```bash
docker ps | grep tailscale
docker logs bridgecade-tailscale --tail 20
```

### Not showing in admin panel
Re-authenticate:
```bash
docker exec -it bridgecade-tailscale tailscale up --reset
```

### Services not loading
Check if subnet route is approved:
1. https://login.tailscale.com/admin/machines
2. Verify `<your-lan-network>` is checked

### Phone shows "Address not found" on 5G
Cause: Tailscale DNS not configured to use Pi-hole for synth.home.arpa.
Fix:
1. Go to https://login.tailscale.com/admin/dns
2. Add custom nameserver: 192.168.178.100
3. Restrict to domain: synth.home.arpa
4. Enable "Override local DNS"

### DNS not working
Tailscale uses MagicDNS. Ensure your phone's Tailscale app shows "DNS: Enabled".

## Technical Details

- **Container image:** `tailscale/tailscale:latest`
- **Network mode:** Container joins `bridgecade_web` network
- **Subnet advertisement:** `TS_ROUTES=${LAN_NETWORK}` (<your-lan-network>)
- **Hostname:** `synthphony-bridgecade`
- **State persistence:** `./tailscale` volume

## Security Notes

- Tailscale control plane manages authentication
- All traffic is end-to-end encrypted
- Subnet routes require explicit admin approval
- No open ports on your firewall needed
