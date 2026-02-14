#!/usr/bin/env bash
# ==================== BRIDGECADE SETUP ====================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../"  # Go to BridgeCade root

# ----- PRETTY OUTPUT -----
if [[ -t 1 ]]; then
  C0=$'\033[0m'; C1=$'\033[1m'
  GRN=$'\033[32m'; YLW=$'\033[33m'; RED=$'\033[31m'
  BLU=$'\033[34m'; CYN=$'\033[36m'; DIM=$'\033[2m'
else
  C0=""; C1=""; GRN=""; YLW=""; RED=""; BLU=""; CYN=""; DIM=""
fi

hr()   { printf '%s\n' "${DIM}───────────────────────────────────────────────────────${C0}"; }
hdr()  { hr; printf '%b\n' "${C1}${BLU}▶ $1${C0}"; hr; }
ok()   { printf '%s\n' "${GRN}✓${C0} $*"; }
warn() { printf '%s\n' "${YLW}!${C0} $*"; }
err()  { printf '%s\n' "${RED}✗${C0} $*"; }
step() { printf '%s\n' "${C1}>${C0} $*"; }
info() { printf '%s\n' "${CYN}i${C0} $*"; }

NEEDS_LOGOUT=0

require_cmd() {
  local cmd="$1"; local hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Missing required command: $cmd"
    [[ -n "$hint" ]] && info "$hint"
    exit 1
  fi
}

gen_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import secrets, base64; print(base64.b64encode(secrets.token_bytes(32)).decode())"
  else
    head -c 32 /dev/urandom | base64
  fi
}

set_or_update_env() {
  local key="$1"; local value="$2"; local env_file="$3"
  if grep -qE "^${key}=" "$env_file" 2>/dev/null; then
    sed -i "s|^${key}=.*$|${key}=${value}|" "$env_file"
  else
    echo "${key}=${value}" >> "$env_file"
  fi
}

# ==================== PORT 53 PREREQUISITE CHECK ====================

check_port_53_prerequisite() {
  hdr "Port 53 Prerequisite Check"

  # Check if anything is listening on port 53
  local port_53_listener
  # If our own Pi-hole container is running, port 53 is ours — skip check
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'bridgecade-pihole'; then
    ok "Port 53 is used by our Pi-hole (already running)"
    ensure_host_dns_resilience
    return 0
  fi

  # Check if anything else is listening on port 53 (exact match, not :53317 etc.)
  local port_53_listener
  port_53_listener=$(sudo ss -tlnp 2>/dev/null | grep -E ":53\s" || true)

  if [[ -z "$port_53_listener" ]]; then
    ok "Port 53 is free - Pi-hole can bind"
    ensure_host_dns_resilience
    return 0
  fi

  # Check if it is systemd-resolved
  if echo "$port_53_listener" | grep -qE "systemd-resolve|127\.0\.0\.5[34]"; then
    warn "systemd-resolved is using port 53 (conflicts with Pi-hole)"
    info "Pi-hole needs port 53 to provide DNS services"
    echo ""

    if [[ -t 0 ]]; then
      read -p "Fix this automatically? [Y/n]: " response
    else
      response="Y"
    fi

    if [[ "$response" =~ ^[Yy]?$ ]]; then
      step "Creating backup of systemd-resolved config..."
      sudo cp /etc/systemd/resolved.conf "/etc/systemd/resolved.conf.backup.$(date +%s)" 2>/dev/null || true

      step "Configuring systemd-resolved to free port 53 for Pi-hole (preserving DHCP DNS)..."
      sudo tee /etc/systemd/resolved.conf > /dev/null << 'RESOLVEOF'
[Resolve]
#DNS=
# Fritz.box DHCP provides Pi-hole as DNS - do not override here
FallbackDNS=1.1.1.1 8.8.8.8
DNSStubListener=no
RESOLVEOF

    # Clean up any toggle-dns.sh overrides that could conflict
    if [[ -f /etc/systemd/resolved.conf.d/99-synthphony-dns.conf ]]; then
      step "Removing toggle-dns.sh DNS override..."
      sudo rm -f /etc/systemd/resolved.conf.d/99-synthphony-dns.conf
      ok "Override removed"
    fi

      step "Restarting systemd-resolved..."
      sudo systemctl restart systemd-resolved

      # CRITICAL: Fix /etc/resolv.conf — the stub symlink is now dead
      ensure_host_dns_resilience

      # Wait for changes to take effect
      sleep 2

      # Verify port 53 is now free
      if ! sudo ss -tlnp 2>/dev/null | grep -qE ":53\s"; then
        ok "Port 53 is now free - systemd-resolved stub disabled"
        info "Host DNS uses public resolvers (1.1.1.1, 8.8.8.8) directly"
        info "Pi-hole will serve LAN/VPN clients, NOT this host"
        return 0
      else
        err "Port 53 still in use after fix"
        err "Please check: sudo ss -tlnp | grep :53"
        exit 1
      fi
    else
      err "Cannot continue - port 53 conflict must be resolved first"
      info "Manual fix: sudo nano /etc/systemd/resolved.conf"
      info "Set: DNSStubListener=no"
      info "Then: sudo systemctl restart systemd-resolved"
      exit 1
    fi
  else
    err "Another service is using port 53:"
    echo "$port_53_listener"
    err "Please stop this service before continuing"
    exit 1
  fi
}




ensure_host_dns_resilience() {
 # ──────────────────────────────────────────────────────────────
 # DNS for the host comes from Fritz.box DHCP, which provides
 # Pi-hole (via "Lokaler DNS-Server" setting) as the DNS server.
 #
 # DNSStubListener=no is needed so Pi-hole can bind port 53.
 # FallbackDNS=1.1.1.1 8.8.8.8 ensures the host can still
 # resolve if Pi-hole is temporarily down (container restart).
 #
 # This function ensures:
 # 1. resolved.conf does NOT override Fritz.box DHCP DNS
 # 2. resolv.conf is managed by systemd-resolved (not static)
 # 3. Any previous overrides are cleaned up
 # ──────────────────────────────────────────────────────────────
 step "Ensuring host DNS resilience..."

 # Remove immutable flag from previous setup if present
 sudo chattr -i /etc/resolv.conf 2>/dev/null || true

 # Clean up any toggle-dns.sh overrides
 if [[ -f /etc/systemd/resolved.conf.d/99-synthphony-dns.conf ]]; then
   step "Removing toggle-dns.sh DNS override..."
   sudo rm -f /etc/systemd/resolved.conf.d/99-synthphony-dns.conf
   ok "Override removed"
 fi

 # Fix resolved.conf: remove any DNS= line that overrides Fritz.box DHCP
 # Keep DNSStubListener=no (Pi-hole needs port 53) and FallbackDNS
 if grep -q '^DNS=' /etc/systemd/resolved.conf 2>/dev/null; then
   step "Removing DNS override from resolved.conf (Fritz.box DHCP provides DNS)..."
   sudo sed -i 's/^DNS=.*/#DNS=/' /etc/systemd/resolved.conf
   ok "DNS override removed from resolved.conf"
 fi

 # Ensure FallbackDNS is set (safety net if Pi-hole is down)
 if ! grep -q '^FallbackDNS=' /etc/systemd/resolved.conf 2>/dev/null; then
   step "Adding FallbackDNS to resolved.conf..."
   sudo sed -i '/^\[Resolve\]/a FallbackDNS=1.1.1.1 8.8.8.8' /etc/systemd/resolved.conf
   ok "FallbackDNS added"
 fi

 # Ensure DNSStubListener=no is set (Pi-hole needs port 53)
 if ! grep -q '^DNSStubListener=no' /etc/systemd/resolved.conf 2>/dev/null; then
   step "Setting DNSStubListener=no in resolved.conf..."
   sudo sed -i '/^\[Resolve\]/a DNSStubListener=no' /etc/systemd/resolved.conf
   ok "DNSStubListener=no set"
 fi

 # Restart systemd-resolved to apply changes
 step "Restarting systemd-resolved..."
 sudo systemctl restart systemd-resolved
 sleep 1

 # Check if resolv.conf is a static file (from previous setup)
 if [[ -f /etc/resolv.conf && ! -L /etc/resolv.conf ]]; then
   warn "/etc/resolv.conf is a static file — restoring systemd-resolved symlink"
   sudo rm -f /etc/resolv.conf
   sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
   ok "resolv.conf restored to systemd-resolved symlink"
 fi

 # Verify DNS is working
 local current_dns
 current_dns="$(grep '^nameserver' /etc/resolv.conf 2>/dev/null | head -1 || true)"
 if [[ -n "$current_dns" ]]; then
   ok "Host DNS: $current_dns (via Fritz.box DHCP + systemd-resolved)"
 else
   warn "No nameserver found in resolv.conf — check systemd-resolved"
 fi
}

hdr "Synthphony BridgeCade Setup"

# Check port 53 prerequisite
check_port_53_prerequisite

# ----- Docker prerequisites -----
hdr "Docker Prerequisites"
if ! command -v docker >/dev/null 2>&1; then
  step "Docker not found — installing via get.docker.com"
  require_cmd curl "Install curl first (e.g. sudo apt-get install -y curl)."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh 2>&1 | tail -5
  rm -f get-docker.sh
  ok "Docker installed"
  NEEDS_LOGOUT=1
  export SETUP_NEEDS_NEWGRP=1
else
  ok "Docker already installed"
fi

if ! getent group docker >/dev/null 2>&1; then
  step "Creating docker group"
  sudo groupadd docker 2>/dev/null || true
  ok "Docker group created"
  NEEDS_LOGOUT=1
  export SETUP_NEEDS_NEWGRP=1
else
  ok "Docker group already exists"
fi

if ! id -nG "$USER" 2>/dev/null | grep -q 'docker'; then
  step "Adding $USER to docker group"
  sudo usermod -aG docker "$USER" 2>/dev/null
  ok "User added to docker group"
  NEEDS_LOGOUT=1
  export SETUP_NEEDS_NEWGRP=1
else
  ok "User already in docker group"
fi
echo ""

# ----- Base directories -----
hdr "Filesystem Layout"
BASE="/opt/Synthphony"
step "Ensuring base directories under $BASE"
sudo mkdir -p "$BASE"/BridgeCade/{certs,mkcert-ca,pihole,etc-dnsmasq.d,wireguard,secrets}
sudo mkdir -p "$BASE"/backups/{bridgecade,myestro,orchestrai,metronomni}
sudo chown -R "$(id -u)":"$(id -g)" "$BASE"
ok "Base directories ensured at $BASE"
echo ""

# ----- Shared Docker network -----
hdr "Docker Network"
step "Ensuring external network bridgecade_web exists"
docker network create bridgecade_web >/dev/null 2>&1 || true
ok "Network bridgecade_web ready"
echo ""

# ----- .env and secrets -----
hdr ".env and Secrets"

ENV_EXAMPLE="$PWD/.env.example"
ENV_FILE="$PWD/.env"
SECRETS_DIR="$PWD/secrets"
PIHOLE_PW_FILE="$SECRETS_DIR/pihole_admin_password.txt"

if [[ ! -f "$ENV_EXAMPLE" ]]; then
  err ".env.example not found in $PWD — generate it from the v6 spec first."
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  step "Creating .env from .env.example"
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  ok ".env created"
else
  ok ".env already exists"
fi

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

if [[ ! -f "$PIHOLE_PW_FILE" ]]; then
  step "Generating Pi-hole admin password"
  gen_password > "$PIHOLE_PW_FILE"
  chmod 600 "$PIHOLE_PW_FILE"
  ok "Pi-hole admin password stored in $PIHOLE_PW_FILE"
else
  ok "Pi-hole admin password already exists"
fi

PIHOLE_ADMIN_PASSWORD="$(<"$PIHOLE_PW_FILE")"
set_or_update_env "PIHOLE_ADMIN_PASSWORD" "$PIHOLE_ADMIN_PASSWORD" "$ENV_FILE"
ok "PIHOLE_ADMIN_PASSWORD injected into .env"
echo ""

# ----- LAN & WireGuard auto-detect -----
hdr "LAN & WireGuard Autodetect"

LAN_IFACE="$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
LAN_CIDR="$(ip -o -f inet addr show "$LAN_IFACE" | awk '{print $4}' | head -n1)"
LAN_IP="${LAN_CIDR%/*}"
LAN_MASK="${LAN_CIDR#*/}"

# Compute proper network address (e.g., 192.168.178.77/24 -> 192.168.178.0/24)
# This avoids WireGuard "Bad address" errors on mobile clients
LAN_NETWORK="$(python3 -c "import ipaddress; print(ipaddress.ip_network('${LAN_CIDR}', strict=False))" 2>/dev/null || echo "${LAN_CIDR}")"

step "Detected LAN interface: $LAN_IFACE"
step "Detected LAN CIDR:      $LAN_CIDR"
step "Detected LAN IP:        $LAN_IP"

WG_SUBNET_DEFAULT="10.66.66.0/24"
WG_SUBNET="${WG_SUBNET:-$WG_SUBNET_DEFAULT}"
WG_SERVER_IP_DEFAULT="10.66.66.1"
WG_SERVER_IP="${WG_SERVER_IP:-$WG_SERVER_IP_DEFAULT}"
WG_INTERNAL_SUBNET="${WG_INTERNAL_SUBNET:-${WG_SUBNET%/*}}"

WG_ALLOWEDIPS_DEFAULT="${WG_SERVER_IP}/32,${WG_SUBNET},${LAN_NETWORK}"

set_or_update_env "BRIDGECADE_LAN_IP"       "$LAN_IP"          "$ENV_FILE"

# Auto-detect WG_SERVERURL: use existing value if set, otherwise detect public IP
CURRENT_WG_URL="$(grep -E '^WG_SERVERURL=' "$ENV_FILE" 2>/dev/null | cut -d= -f2-)"
if [[ -z "$CURRENT_WG_URL" || "$CURRENT_WG_URL" == "vpn.example.net" || "$CURRENT_WG_URL" == "$LAN_IP" ]]; then
  step "Detecting public IP for WireGuard..."
  PUBLIC_IP="$(curl -fsSL --max-time 10 https://ifconfig.me 2>/dev/null || true)"
  if [[ -n "$PUBLIC_IP" ]]; then
    set_or_update_env "WG_SERVERURL" "$PUBLIC_IP" "$ENV_FILE"
    ok "WG_SERVERURL set to public IP: $PUBLIC_IP"
  else
    set_or_update_env "WG_SERVERURL" "$LAN_IP" "$ENV_FILE"
    warn "Could not detect public IP — WG_SERVERURL set to LAN IP ($LAN_IP)"
    info "Change WG_SERVERURL to your public IP or DDNS for remote VPN access"
  fi
else
  ok "WG_SERVERURL already configured: $CURRENT_WG_URL"
fi
set_or_update_env "LAN_CIDR"               "$LAN_CIDR"        "$ENV_FILE"
set_or_update_env "WG_SUBNET"              "$WG_SUBNET"       "$ENV_FILE"
set_or_update_env "WG_SERVER_IP"           "$WG_SERVER_IP"    "$ENV_FILE"
set_or_update_env "WG_INTERNAL_SUBNET"     "$WG_INTERNAL_SUBNET" "$ENV_FILE"
set_or_update_env "WG_ALLOWEDIPS"          "$WG_ALLOWEDIPS_DEFAULT" "$ENV_FILE"
set_or_update_env "WG_SERVERPORT" "51821" "$ENV_FILE"
set_or_update_env "WG_PEERS" "laptop,phone" "$ENV_FILE"
# Tailscale auth key - user must set manually from tailscale.com
if ! grep -q "^TAILSCALE_AUTHKEY=" "$ENV_FILE" 2>/dev/null; then
  echo "TAILSCALE_AUTHKEY=" >> "$ENV_FILE"
fi

ok "LAN and WireGuard defaults written to .env"
echo ""


# Ensure LAN_NETWORK is set correctly (for Tailscale subnet routing)
# Always update based on TAILSCALE_ROUTE_MODE (even if already exists)
TAILSCALE_ROUTE_MODE="${TAILSCALE_ROUTE_MODE:-minimal}"
if [ "$TAILSCALE_ROUTE_MODE" = "minimal" ]; then
  # Minimal: only this server (/32)
  LAN_NETWORK="${LAN_IP}/32"
  info "TAILSCALE_ROUTE_MODE=minimal: Using /32 (this server only)"
else
  # Full: entire LAN (/24)
  LAN_NETWORK="${LAN_IP%.*}.0/${LAN_CIDR#*/}"
  info "TAILSCALE_ROUTE_MODE=full: Using /24 (entire LAN)"
fi
set_or_update_env "LAN_NETWORK" "$LAN_NETWORK" "$ENV_FILE"
ok "LAN_NETWORK set to: $LAN_NETWORK"



# ----- Firewall Configuration for Docker -----
hdr "Firewall Configuration"
step "Ensuring IP forwarding is enabled..."
if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" != "1" ]; then
  sudo sysctl -w net.ipv4.ip_forward=1
  echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-docker-forward.conf > /dev/null
  ok "IP forwarding enabled"
else
  ok "IP forwarding already enabled"
fi

step "Ensuring iptables FORWARD policy allows Docker traffic..."
CURRENT_POLICY=$(sudo iptables -L FORWARD -n 2>/dev/null | head -1 | grep -oP 'policy \K\w+' || echo "UNKNOWN")
if [ "$CURRENT_POLICY" = "DROP" ]; then
  sudo iptables -P FORWARD ACCEPT
  ok "FORWARD policy changed from DROP to ACCEPT"
else
  ok "FORWARD policy is already $CURRENT_POLICY"
fi

step "Adding Docker bridge forwarding rules..."
sudo iptables -C FORWARD -i docker0 -j ACCEPT 2>/dev/null || sudo iptables -A FORWARD -i docker0 -j ACCEPT
sudo iptables -C FORWARD -o docker0 -j ACCEPT 2>/dev/null || sudo iptables -A FORWARD -o docker0 -j ACCEPT
sudo iptables -C FORWARD -i bridgecade_web -j ACCEPT 2>/dev/null || sudo iptables -A FORWARD -i bridgecade_web -j ACCEPT
sudo iptables -C FORWARD -o bridgecade_web -j ACCEPT 2>/dev/null || sudo iptables -A FORWARD -o bridgecade_web -j ACCEPT
ok "Docker forwarding rules configured"
echo ""

hdr "BridgeCade Setup Complete"


# Apply group changes without logout
if [[ "$NEEDS_LOGOUT" -eq 1 ]]; then
  echo ""
  hr
fi

hr
echo "Setup complete!"
