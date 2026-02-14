#!/usr/bin/env bash
# ==================== METRONOMNI START ====================
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
    err "Setup incomplete: missing or empty ${key} in $(basename "$env_file")"
    step "Run: ${C1}./setup.sh${C0}"
    exit 1
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

hdr "MetronOmni Stack Launcher"

step "Ensuring shared ingress network exists..."
docker network create bridgecade_web >/dev/null 2>&1 || true
ok "Network bridgecade_web ready"


if ! docker ps >/dev/null 2>&1; then
  err "Docker is not usable as your user"
  step "Run: ${C1}./setup.sh${C0}"
  step "Then logout/login (or reboot) and run: ${C1}./start.sh${C0}"
  exit 1
fi

[[ -f ../compose.yaml ]] || { err "compose.yaml not found"; exit 1; }
[[ -f ../.env ]]         || { err ".env not found (run: ./setup.sh)"; exit 1; }

ENV_FILE="$SCRIPT_DIR/../.env"
require_env BASE_DOMAIN "$ENV_FILE"
ok ".env looks sane"

step "Validating Docker Compose configuration..."
docker compose -f ../compose.yaml config >/dev/null
ok "compose.yaml is valid"
echo ""

hdr "Starting MetronOmni Services"
MAX_RETRIES=3
RETRY_DELAY=10

for attempt in $(seq 1 $MAX_RETRIES); do
  printf '%b\n' "${C1}Attempt $attempt of $MAX_RETRIES...${C0}"
  if docker compose -f ../compose.yaml up -d; then
    ok "MetronOmni stack started successfully"
    break
  else
    if [[ "$attempt" -lt $MAX_RETRIES ]]; then
      warn "docker compose -f ../compose.yaml up -d failed. Retrying in $RETRY_DELAY seconds..."
      sleep "$RETRY_DELAY"
    fi
  fi
done

echo ""
hdr "Quick Health Check"

source "$ENV_FILE" >/dev/null 2>&1 || true
BASE_DOMAIN="${BASE_DOMAIN:-synth.home.arpa}"

check_url() {
  local name="$1"; local url="$2"
  if curl -fsSLk "$url" >/dev/null 2>&1; then
    printf '%s %s%s%s\n' "${GRN}✓${C0}" "${C1}${name}${C0}" ": ready"
  else
    printf '%s %s%s%s\n' "${YLW}?${C0}" "${C1}${name}${C0}" ": starting..."
  fi
}

echo "📊 Endpoints:"
check_url "Portainer"  "https://portainer.${BASE_DOMAIN}"
check_url "UptimeKuma" "https://status.${BASE_DOMAIN}"
check_url "Netdata"    "https://netdata.${BASE_DOMAIN}"

echo ""
echo "🔗 URLs:"
echo "  - Portainer  : ${DIM}https://portainer.${BASE_DOMAIN}${C0}"
echo "  - UptimeKuma : ${DIM}https://status.${BASE_DOMAIN}${C0}"
echo "  - Netdata    : ${DIM}https://netdata.${BASE_DOMAIN}${C0}"
echo ""
ok "MetronOmni is running. Check status with: docker compose -f ../compose.yaml ps"
