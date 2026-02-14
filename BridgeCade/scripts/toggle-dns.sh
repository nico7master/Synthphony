#!/usr/bin/env bash
# Toggle DNS between Full Tunnel (Pi-hole), Split Tunnel, and Off
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
if [[ -t 1 ]]; then
  C0=$'\033[0m'; C1=$'\033[1m'
  GRN=$'\033[32m'; YLW=$'\033[33m'; RED=$'\033[31m'
  BLU=$'\033[34m'; CYN=$'\033[36m'
else
  C0=""; C1=""; GRN=""; YLW=""; RED=""; BLU=""; CYN=""
fi

ok()   { printf '%s\n' "${GRN}✓${C0} $*"; }
warn() { printf '%s\n' "${YLW}!${C0} $*"; }
err()  { printf '%s\n' "${RED}✗${C0} $*"; }
step() { printf '%s\n' "${C1}>${C0} $*"; }
info() { printf '%s\n' "${CYN}i${C0} $*"; }

show_help() {
  cat << 'HELP'
Usage: toggle-dns.sh [MODE]

Toggle system DNS configuration for Pi-hole

Modes:
  full    - Full tunnel: All DNS through Pi-hole (ad blocking)
  split   - Split tunnel: Only synth.home.arpa through Pi-hole
  off     - Off: Use public DNS (1.1.1.1, 8.8.8.8)
  status  - Show current DNS configuration

Examples:
  toggle-dns.sh full     # Enable ad blocking
  toggle-dns.sh split    # Local domains only
  toggle-dns.sh off      # Disable Pi-hole DNS
  toggle-dns.sh status   # Check current mode
HELP
}

get_pihole_ip() {
  local env_file="/opt/synthphony/BridgeCade/.env"
  if [[ -f "$env_file" ]]; then
    grep "^BRIDGECADE_LAN_IP=" "$env_file" 2>/dev/null | cut -d= -f2 || echo "192.168.178.77"
  else
    echo "192.168.178.77"
  fi
}

mode_full() {
  local pihole_ip
  pihole_ip="$(get_pihole_ip)"
  step "Enabling FULL TUNNEL (all DNS through Pi-hole)..."
  
  sudo mkdir -p /etc/systemd/resolved.conf.d/
  
  sudo tee /etc/systemd/resolved.conf.d/99-synthphony-dns.conf > /dev/null << 'EOF'
[Resolve]
DNS=PIHOLE_IP
FallbackDNS=1.1.1.1 8.8.8.8
EOF
  
  sudo sed -i "s/PIHOLE_IP/${pihole_ip}/g" /etc/systemd/resolved.conf.d/99-synthphony-dns.conf
  sudo systemctl restart systemd-resolved
  
  ok "Full tunnel enabled - all DNS through Pi-hole (${pihole_ip})"
  info "Ad blocking is now active!"
}

mode_split() {
  local pihole_ip
  pihole_ip="$(get_pihole_ip)"
  step "Enabling SPLIT TUNNEL (only synth.home.arpa through Pi-hole)..."
  
  sudo mkdir -p /etc/systemd/resolved.conf.d/
  
  sudo tee /etc/systemd/resolved.conf.d/99-synthphony-dns.conf > /dev/null << 'EOF'
[Resolve]
DNS=PIHOLE_IP
FallbackDNS=1.1.1.1 8.8.8.8
Domains=~synth.home.arpa
EOF
  
  sudo sed -i "s/PIHOLE_IP/${pihole_ip}/g" /etc/systemd/resolved.conf.d/99-synthphony-dns.conf
  sudo systemctl restart systemd-resolved
  
  ok "Split tunnel enabled - only *.synth.home.arpa through Pi-hole"
  info "Internet uses public DNS, local domains use Pi-hole"
}

mode_off() {
  step "Disabling Pi-hole DNS (using public DNS)..."
  
  if [[ -f /etc/systemd/resolved.conf.d/99-synthphony-dns.conf ]]; then
    sudo rm /etc/systemd/resolved.conf.d/99-synthphony-dns.conf
  fi
  
  sudo systemctl restart systemd-resolved
  ok "Pi-hole DNS disabled - using public DNS"
  info "Ad blocking is now inactive"
}

mode_status() {
  step "Current DNS configuration:"
  echo ""
  
  if [[ -f /etc/systemd/resolved.conf.d/99-synthphony-dns.conf ]]; then
    echo "Config file: /etc/systemd/resolved.conf.d/99-synthphony-dns.conf"
    echo "---"
    cat /etc/systemd/resolved.conf.d/99-synthphony-dns.conf
    echo "---"
    
    if grep -q "Domains=~synth.home.arpa" /etc/systemd/resolved.conf.d/99-synthphony-dns.conf 2>/dev/null; then
      info "Mode: SPLIT TUNNEL (local domains only)"
    else
      info "Mode: FULL TUNNEL (all DNS through Pi-hole)"
    fi
  else
    warn "Mode: OFF (using default/public DNS)"
  fi
  
  echo ""
  step "Active DNS servers:"
  systemd-resolve --status 2>/dev/null | grep "DNS Servers" || true
}

# Main
case "${1:-status}" in
  full|on|enable)
    mode_full
    ;;
  split|local)
    mode_split
    ;;
  off|disable)
    mode_off
    ;;
  status|show)
    mode_status
    ;;
  help|-h|--help)
    show_help
    ;;
  *)
    err "Unknown mode: $1"
    show_help
    exit 1
    ;;
esac
