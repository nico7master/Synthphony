#!/usr/bin/env bash
# ==================== ORCHESTRAI START ====================
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
    err "Setup incomplete: missing or empty ${key}"
    step "Run: ${C1}../scripts/setup.sh${C0}"
    exit 1
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

hdr "OrchestrAI Stack Launcher"

step "Ensuring shared ingress network exists..."
docker network create bridgecade_web >/dev/null 2>&1 || true
ok "Network bridgecade_web ready"


# ----- Preflight Checks -----
if ! docker ps >/dev/null 2>&1; then
  err "Docker is not usable as your user"
  step "Run: ${C1}./setup.sh${C0} then logout/login"
  exit 1
fi

[[ -f ../compose.yaml ]] || { err "compose.yaml not found"; exit 1; }
[[ -f ../.env ]]         || { err ".env not found (run: ./setup.sh)"; exit 1; }

ENV_FILE="$SCRIPT_DIR/../.env"

step "Verifying configuration..."
require_env BASE_DOMAIN          "$ENV_FILE"
require_env WINDMILL_DB_PASSWORD  "$ENV_FILE"
require_env WM_ENCRYPTION_KEY    "$ENV_FILE"
require_env WM_JWT_SECRET        "$ENV_FILE"
require_env OPENNOTEBOOK_ENCRYPTION_KEY "$ENV_FILE"
require_env SURREAL_PASSWORD           "$ENV_FILE"
ok "Configuration valid"

# Optional GPU warning
if command -v nvidia-smi >/dev/null 2>&1; then
  if ! docker info 2>/dev/null | grep -qi 'Runtimes:.*nvidia'; then
    warn "NVIDIA GPU detected but Docker NVIDIA runtime not configured (Ollama will use CPU)"
    info "Run ./setup.sh again after installing nvidia-container-toolkit"
  else
    ok "Docker NVIDIA runtime detected"
  fi
fi
echo ""

# ----- Ensure Data Directories -----
hdr "Data Directories"
mkdir -p ../openwebui ../windmill/db ../windmill/data ../ollama
mkdir -p ../agentzero_data ../agentzero_config ../wmill_config
mkdir -p ../surrealdb_data ../notebook_data
chown 1001:1001 ../surrealdb_data
ok "Data directories ensured"
echo ""

# ----- One-Time Windmill DB Reset -----
# When setup.sh generates a NEW password, the old Postgres data still has
# the OLD password hash baked in. Postgres ignores POSTGRES_PASSWORD when
# data already exists. So we must wipe the bind mount data once to force
# re-initialization with the new password.
hdr "Windmill DB Password Sync"
if [[ ! -f ../windmill/.password_ok ]]; then
  step "Resetting Windmill DB for password sync..."
  sudo rm -rf ../windmill/db/* 2>/dev/null || true
  mkdir -p ../windmill/db
  touch ../windmill/.password_ok
  ok "Windmill DB reset — will re-init with current password"
else
  ok "Windmill DB already initialized with current password"
fi
echo ""

# ----- Validate & Build -----
step "Validating Docker Compose configuration..."
docker compose -f ../compose.yaml config >/dev/null
ok "compose.yaml is valid"

hdr "Building Custom Images"
step "Building custom AgentZero image..."
if docker compose --progress quiet -f ../compose.yaml build agentzero; then
  ok "Custom AgentZero image built"
else
  err "Failed to build custom AgentZero image"
  exit 1
fi
echo ""

# ----- Start Services -----
hdr "Starting OrchestrAI Services"
MAX_RETRIES=5
RETRY_DELAY=15

for attempt in $(seq 1 $MAX_RETRIES); do
  printf '%b\n' "${C1}Attempt $attempt of $MAX_RETRIES...${C0}"
  if docker compose -f ../compose.yaml up -d; then
    ok "OrchestrAI stack started successfully"
    break
  else
    if [[ "$attempt" -lt $MAX_RETRIES ]]; then
      warn "Failed. Retrying in $RETRY_DELAY seconds..."
      sleep $RETRY_DELAY
    fi
  fi
done

# Update CA trust inside AgentZero (for mkcert HTTPS)
step "Updating CA store inside AgentZero container..."
docker compose -f ../compose.yaml exec -T agentzero sh -lc \
  'command -v update-ca-certificates >/dev/null 2>&1 && update-ca-certificates || true' 2>/dev/null || true
ok "AgentZero CA store updated"

echo ""
hdr "Quick Health Check"

source "$ENV_FILE" >/dev/null 2>&1 || true
BASE_DOMAIN="${BASE_DOMAIN:-synth.home.arpa}"

check_url() {
  local name="$1"; local url="$2"
  if curl -fsSLk "$url" >/dev/null 2>&1; then
    printf '%s %s: %s\n' "${GRN}✓${C0}" "${C1}${name}${C0}" "ready"
  else
    printf '%s %s: %s\n' "${YLW}?${C0}" "${C1}${name}${C0}" "starting..."
  fi
}

echo "Endpoints:"
check_url "Ollama"     "https://ollama.${BASE_DOMAIN}"
check_url "Windmill"   "https://windmill.${BASE_DOMAIN}"
check_url "AgentZero"  "https://agentzero.${BASE_DOMAIN}"
check_url "Open Notebook" "https://notebook.${BASE_DOMAIN}"

echo ""
echo "URLs:"
echo "  - Ollama    : ${DIM}https://ollama.${BASE_DOMAIN}${C0}"
echo "  - Windmill  : ${DIM}https://windmill.${BASE_DOMAIN}${C0}"
echo "  - AgentZero : ${DIM}https://agentzero.${BASE_DOMAIN}${C0}"
echo "  - Open Notebook : ${DIM}https://notebook.${BASE_DOMAIN}${C0}"
echo ""
ok "OrchestrAI is running. Check status: docker compose -f ../compose.yaml ps"
