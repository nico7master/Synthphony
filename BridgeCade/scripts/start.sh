#!/usr/bin/env bash
# ==================== BRIDGECADE START ====================
set -euo pipefail

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

require_env() {
  local key="$1"; local env_file="$2"
  local line value
  line="$(grep -E "^${key}=" "$env_file" 2>/dev/null || true)"
  value="${line#*=}"
  if [[ -z "$line" || -z "$value" ]]; then
    err "Missing or empty ${key} in $(basename "$env_file")"
    step "Run: ./setup.sh"
    exit 1
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"


# Ensure firewall allows Docker forwarding (critical for external access)
if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" != "1" ]; then
  step "Enabling IP forwarding..."
  sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1 || true
fi
CURRENT_FORWARD_POLICY=$(sudo iptables -L FORWARD -n 2>/dev/null | head -1 | grep -oP 'policy \K\w+' || echo "UNKNOWN")
if [ "$CURRENT_FORWARD_POLICY" = "DROP" ]; then
  step "Fixing iptables FORWARD policy..."
  sudo iptables -P FORWARD ACCEPT
  ok "FORWARD policy set to ACCEPT"
fi

hdr "BridgeCade Launcher"

if ! docker ps >/dev/null 2>&1; then
  err "Docker is not usable as your user"
  step "Run: ./setup.sh"
  step "Then logout/login (or reboot) and run ./start.sh again"
  exit 1
fi

step "Ensuring shared ingress network exists..."
docker network create bridgecade_web >/dev/null 2>&1 || true
ok "Network bridgecade_web ready"

[[ -f ../compose.yaml ]] || { err "compose.yaml not found in $SCRIPT_DIR"; exit 1; }
[[ -f ../.env ]]         || { err ".env not found (run: ./setup.sh)"; exit 1; }

ENV_FILE="$SCRIPT_DIR/../.env"
source "$ENV_FILE" >/dev/null 2>&1 || true

step "Verifying .env configuration..."
require_env BASE_DOMAIN          "$ENV_FILE"
require_env BRIDGECADE_LAN_IP    "$ENV_FILE"
require_env LAN_CIDR             "$ENV_FILE"
require_env WG_SUBNET            "$ENV_FILE"
require_env WG_SERVER_IP         "$ENV_FILE"
require_env WG_INTERNAL_SUBNET   "$ENV_FILE"
require_env WG_ALLOWEDIPS        "$ENV_FILE"
require_env PIHOLE_ADMIN_PASSWORD "$ENV_FILE"
ok "Configuration looks complete"

step "Validating Docker Compose configuration..."
docker compose -f ../compose.yaml config >/dev/null
ok "compose.yaml is valid"
echo ""

hdr "Building Automation Images"
step "Building cert_issuer and dns_registrar (if necessary)..."
if docker compose --progress quiet build cert_issuer dns_registrar; then
  ok "Automation images built"
else
  warn "Build failed or not required; continuing (images may already exist)"
fi
echo ""

hdr "Starting BridgeCade Services"
MAX_RETRIES=3
RETRY_DELAY=10

for attempt in $(seq 1 $MAX_RETRIES); do
  printf '%b\n' "${C1}Attempt $attempt of $MAX_RETRIES...${C0}"
  if docker compose -f ../compose.yaml up -d; then
    ok "BridgeCade stack started successfully"
    break
  else
    if [[ "$attempt" -lt $MAX_RETRIES ]]; then
      warn "docker compose -f ../compose.yaml up -d failed. Retrying in $RETRY_DELAY seconds..."
      sleep "$RETRY_DELAY"
    fi
  fi
done

# ==================== AUTOMATIC CA TRUST ====================
trust_mkcert_ca() {
    local ca_file="/opt/Synthphony/BridgeCade/mkcert-ca/rootCA.pem"
    local ca_dest="/usr/local/share/ca-certificates/mkcert-rootCA.crt"

    step "Waiting for mkcert CA to be generated..."
    local retries=30
    while [[ ! -f "$ca_file" ]] && [[ $retries -gt 0 ]]; do
        sleep 2
        ((retries--))
    done

    if [[ ! -f "$ca_file" ]]; then
        warn "mkcert CA not found after 60 seconds. Skipping automatic trust."
        return 0
    fi

    step "Installing mkcert CA to system trust store..."

    # Copy to system CA store
    if sudo cp "$ca_file" "$ca_dest" 2>/dev/null; then
        sudo chmod 644 "$ca_dest"

        # Update system certificates
        if command -v update-ca-certificates >/dev/null 2>&1; then
            sudo update-ca-certificates >/dev/null 2>&1
            ok "System CA trust updated"
        elif command -v update-ca-trust >/dev/null 2>&1; then
            sudo update-ca-trust extract >/dev/null 2>&1
            ok "System CA trust updated"
        fi
    else
        warn "Could not install CA to system trust (may need sudo)"
    fi

    # Import to browser stores if tools available
    if command -v certutil >/dev/null 2>&1 && [[ -d "$HOME/.pki/nssdb" ]]; then
        step "Importing CA to Chrome/Chromium trust store..."
        certutil -d sql:"$HOME/.pki/nssdb" -A -t "C,," -n "mkcert-synthphony" -i "$ca_file" 2>/dev/null && \
            ok "Chrome/Chromium CA trust updated" || \
            warn "Could not update Chrome trust (may need manual import)"
    fi

    info "Browsers may need restart to recognize new CA"
}
# ==================== AUTOMATIC /etc/hosts ====================
update_etc_hosts() {
    local lan_ip="$1"
    local domain="$2"
    local hosts_file="/etc/hosts"
    local marker="# Synthphony auto-generated"

    step "Updating /etc/hosts for internal DNS resolution..."

    # Remove old entries
    if grep -q "$marker" "$hosts_file" 2>/dev/null; then
        sudo sed -i "/$marker/,/$marker/d" "$hosts_file"
    fi

    # Add new entries
    local entries="$marker
$lan_ip pihole.$domain nextcloud.$domain solidtime.$domain portainer.$domain status.$domain netdata.$domain openwebui.$domain windmill.$domain agentzero.$domain ollama.$domain
$marker"

    echo "$entries" | sudo tee -a "$hosts_file" >/dev/null
    ok "/etc/hosts updated with Synthphony services"
}

# Trust the mkcert CA automatically
trust_mkcert_ca

# Update /etc/hosts for internal DNS
update_etc_hosts "$BRIDGECADE_LAN_IP" "$BASE_DOMAIN"

echo ""

register_pihole_dns() {
  hdr "Registering DNS in Pi-hole"

  source "$SCRIPT_DIR/../.env" >/dev/null 2>&1 || true
  local BASE_DOMAIN="${BASE_DOMAIN:-synth.home.arpa}"
  local LAN_IP="${BRIDGECADE_LAN_IP:-192.168.178.77}"
  local DNSMASQ_DIR="/opt/Synthphony/BridgeCade/etc-dnsmasq.d"

  sudo mkdir -p "$DNSMASQ_DIR"

  # Write dnsmasq address records (Pi-hole v6 reads /etc/dnsmasq.d when etc_dnsmasq_d=true)
  sudo tee "$DNSMASQ_DIR/99-synthphony.conf" > /dev/null << DNSEOF
# Synthphony DNS entries - auto-generated by start.sh
address=/pihole.${BASE_DOMAIN}/${LAN_IP}
address=/nextcloud.${BASE_DOMAIN}/${LAN_IP}
address=/solidtime.${BASE_DOMAIN}/${LAN_IP}
address=/portainer.${BASE_DOMAIN}/${LAN_IP}
address=/status.${BASE_DOMAIN}/${LAN_IP}
address=/netdata.${BASE_DOMAIN}/${LAN_IP}
address=/ollama.${BASE_DOMAIN}/${LAN_IP}
address=/windmill.${BASE_DOMAIN}/${LAN_IP}
address=/agentzero.${BASE_DOMAIN}/${LAN_IP}
DNSEOF

  ok "DNS config written to $DNSMASQ_DIR/99-synthphony.conf"

  # Wait for Pi-hole to be ready, then restart DNS
  step "Restarting Pi-hole DNS to load new entries..."
  local waited=0
  while [[ $waited -lt 60 ]]; do
    if docker exec bridgecade-pihole pihole reloaddns 2>/dev/null; then
      ok "Pi-hole DNS restarted — all *.${BASE_DOMAIN} domains resolve to ${LAN_IP}"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  warn "Could not restart Pi-hole DNS — try: docker exec bridgecade-pihole pihole reloaddns"
}

register_pihole_dns

hdr "Quick Health Checks"

if command -v dig >/dev/null 2>&1; then
  if dig +short pi.hole @"$BRIDGECADE_LAN_IP" >/dev/null 2>&1; then
    ok "Pi-hole DNS responding at $BRIDGECADE_LAN_IP"
  else
    warn "Pi-hole DNS not yet responding at $BRIDGECADE_LAN_IP"
  fi
else
  warn "dig not installed; skipping DNS check"
fi

if docker compose -f ../compose.yaml ps wireguard >/dev/null 2>&1; then
  if docker compose -f ../compose.yaml exec -T wireguard wg show >/dev/null 2>&1; then
    ok "WireGuard interface present in bridgecade-wireguard"
  else
    warn "WireGuard interface not yet up in bridgecade-wireguard"
  fi
fi

if docker compose -f ../compose.yaml ps caddy >/dev/null 2>&1; then
  ok "Caddy container running (will pick up services via labels)"
else
  warn "Caddy container not running; check: docker compose logs bridgecade-caddy"
fi

echo ""
info "Set your router or client DNS to: ${C1}${BRIDGECADE_LAN_IP}${C0}"
info "Then access: ${C1}https://pihole.${BASE_DOMAIN}${C0} (after issuer & registrar have run)"

# ==================== Fix WireGuard Peer Configs ====================
fix_wireguard_peers() {
  local WG_DIR="$(realpath "$SCRIPT_DIR/../wireguard")"
  step "Waiting for WireGuard peer configs to be generated..."
  local waited=0
  while [[ $waited -lt 60 ]]; do
    if sudo find "$WG_DIR" -path '*/peer_*/peer_*.conf' -print -quit 2>/dev/null | grep -q .; then
      break
    fi
    sleep 2
    waited=$((waited + 2))
  done
  local confs
  confs=$(sudo find "$WG_DIR" -path '*/peer_*/peer_*.conf' 2>/dev/null)
  if [[ -z "$confs" ]]; then
    warn "No WireGuard peer configs found after 60s — check WG_PEERS in .env"
    return 0
  fi
  ok "Found peer configs"
  local fixed=0
  while IFS= read -r conf; do
    if ! sudo test -f "$conf"; then
      continue
    fi
    local peer_name
    peer_name=$(basename "$conf" .conf)
    if docker exec bridgecade-wireguard grep -qE "^Address = [0-9.]+$" "/config/$peer_name/$peer_name.conf" 2>/dev/null; then
      docker exec bridgecade-wireguard sed -i "s/^Address = \([0-9.]\+\)$/Address = \1\/32/" "/config/$peer_name/$peer_name.conf" 2>/dev/null
      fixed=$((fixed + 1))
    fi
    if docker exec bridgecade-wireguard grep -q "^ListenPort" "/config/$peer_name/$peer_name.conf" 2>/dev/null; then
      docker exec bridgecade-wireguard sed -i "/^ListenPort/d" "/config/$peer_name/$peer_name.conf" 2>/dev/null
      fixed=$((fixed + 1))
    fi
    # Remove LAN subnet from AllowedIPs to avoid routing conflict on WiFi
    if docker exec bridgecade-wireguard grep -q "192.168.178.0/24" "/config/$peer_name/$peer_name.conf" 2>/dev/null; then
      docker exec bridgecade-wireguard sed -i "s/,192.168.178.0\/24//" "/config/$peer_name/$peer_name.conf" 2>/dev/null
      fixed=$((fixed + 1))
    fi
  done <<< "$confs"
  if [[ $fixed -gt 0 ]]; then
    ok "Fixed $fixed issue(s) in peer configs"
  else
    ok "Peer configs already correct"
  fi
  docker restart bridgecade-wireguard >/dev/null 2>&1 || true
  sleep 3
  local verify_failed=0
  while IFS= read -r conf; do
    if ! sudo test -f "$conf"; then
      continue
    fi
    local peer_name
    peer_name=$(basename "$conf" .conf)
    if docker exec bridgecade-wireguard grep -qE "^Address = [0-9.]+$" "/config/$peer_name/$peer_name.conf" 2>/dev/null; then
      warn "Fix verification failed: $peer_name still missing /32"
      verify_failed=1
    fi
    if docker exec bridgecade-wireguard grep -q "^ListenPort" "/config/$peer_name/$peer_name.conf" 2>/dev/null; then
      warn "Fix verification failed: $peer_name still has ListenPort"
      verify_failed=1
    fi
  done <<< "$confs"
  if [[ $verify_failed -eq 0 ]]; then
    ok "Peer configs verified correct"
  else
    warn "Some peer configs could not be fixed"
  fi
}

fix_wireguard_peers

ok "BridgeCade is up. You can now start MetronOmni, MYestro, and OrchestrAI stacks."
