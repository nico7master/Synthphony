#!/usr/bin/env bash
# ==================== METRONOMNI SETUP ====================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

hdr "MetronOmni Setup"

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

if ! id -nG "$USER" 2>/dev/null | grep -q '\bdocker\b'; then
  step "Adding $USER to docker group"
  sudo usermod -aG docker "$USER" 2>/dev/null
  ok "User added to docker group"
  NEEDS_LOGOUT=1
  export SETUP_NEEDS_NEWGRP=1
else
  ok "User already in docker group"
fi
echo ""

hdr "Docker Network"
step "Ensuring external network bridgecade_web exists"
docker network create bridgecade_web >/dev/null 2>&1 || true
ok "Network bridgecade_web ready"
echo ""

hdr ".env and Data Directories"
ENV_EXAMPLE="$SCRIPT_DIR/../.env.example"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ ! -f "$ENV_EXAMPLE" ]]; then
  err ".env.example not found in $SCRIPT_DIR — create it per v6 spec."
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

step "Ensuring data directories"
mkdir -p ../portainer-data
mkdir -p ../uptime-kuma
mkdir -p ../netdata/config ../netdata/lib ../netdata/cache
mkdir -p ../infrastructure-monitor/logs ../infrastructure-monitor/data
ok "Data directories ready"
echo ""

hdr "MetronOmni Setup Complete"

# Apply group changes without logout
if [[ "$NEEDS_LOGOUT" -eq 1 ]]; then
  echo ""
  hr
fi

hr
echo "Setup complete!"
