#!/usr/bin/env bash
# ==================== MYESTRO START ====================
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

hdr "MYestro Stack Launcher"

step "Ensuring shared ingress network exists..."
docker network create bridgecade_web >/dev/null 2>&1 || true
ok "Network bridgecade_web ready"


if ! docker ps >/dev/null 2>&1; then
  err "Docker is not usable as your user"
  step "Run: ${C1}./setup.sh${C0}, then logout/login, then ${C1}./start.sh${C0}"
  exit 1
fi

[[ -f ../compose.yaml ]]   || { err "compose.yaml not found"; exit 1; }
[[ -f ../.env ]]           || { err ".env not found (run: ./setup.sh)"; exit 1; }
[[ -f ../solidtime.env ]]  || { err "solidtime.env not found (run: ./setup.sh)"; exit 1; }

ENV_FILE="$SCRIPT_DIR/../.env"

step "Verifying configuration..."
require_env BASE_DOMAIN              "$ENV_FILE"
require_env NEXTCLOUD_DB_PASSWORD    "$ENV_FILE"
require_env NEXTCLOUD_ADMIN_PASSWORD "$ENV_FILE"
require_env SOLIDTIME_DB_PASSWORD    "$ENV_FILE"
ok "Configuration valid"

# Ensure volume dirs & permissions
mkdir -p ../nextcloud/html ../nextcloud/db ../solidtime/logs ../solidtime/app-storage

if [[ "$(uname)" == "Linux" ]]; then
  step "Ensuring Nextcloud volume permissions..."
  sudo chown -R 33:33 ../nextcloud/html 2>/dev/null || warn "Could not chown nextcloud/html"
  sudo chown -R 999:999 ../nextcloud/db 2>/dev/null || warn "Could not chown nextcloud/db"
  step "Ensuring Solidtime volume permissions (UID 1000)..."
  sudo chown -R 1000:1000 ../solidtime 2>/dev/null || warn "Could not chown solidtime"
fi
ok "Volume permissions ensured"

step "Validating Docker Compose configuration..."
docker compose -f ../compose.yaml config >/dev/null
ok "compose.yaml is valid"
echo ""

# ==================== Start Services ====================
hdr "Starting MYestro Services"
MAX_RETRIES=3
RETRY_DELAY=10

for attempt in $(seq 1 $MAX_RETRIES); do
  printf '%b\n' "${C1}Attempt $attempt of $MAX_RETRIES...${C0}"
  if docker compose -f ../compose.yaml up -d; then
    ok "MYestro stack started successfully"
    break
  else
    if [[ "$attempt" -lt $MAX_RETRIES ]]; then
      warn "docker compose up failed. Retrying in $RETRY_DELAY seconds..."
      sleep "$RETRY_DELAY"
    fi
  fi
done

# Wait for Solidtime DB and app to be ready
if [[ ! -f "$SCRIPT_DIR/../.solidtime_admin_created" ]]; then
  step "First run: waiting for Solidtime to initialize (15s)..."
  sleep 15
fi

# ==================== Solidtime Key Generation ====================
hdr "Solidtime Post-Start Setup"

SOLIDTIME_ENV="$SCRIPT_DIR/../solidtime.env"

# Generate Passport/OAuth keys if not already done
if ! grep -q '^PASSPORT_PRIVATE_KEY=' "$SOLIDTIME_ENV" 2>/dev/null; then
  step "Generating Solidtime OAuth keys (first run only)..."

  KEYS_OUTPUT="$(docker compose -f ../compose.yaml exec -T solidtime-scheduler \
    php artisan self-host:generate-keys 2>/dev/null || true)"

  if [[ -n "$KEYS_OUTPUT" ]]; then
    # Extract KEY=VALUE lines and append to solidtime.env
    echo "$KEYS_OUTPUT" | grep -E '^(APP_KEY|PASSPORT_PRIVATE_KEY|PASSPORT_PUBLIC_KEY)=' >> "$SOLIDTIME_ENV" || true
    ok "OAuth keys generated and added to solidtime.env"

    # Restart Solidtime services to pick up new keys
    step "Restarting Solidtime services with new keys..."
    docker compose -f ../compose.yaml restart solidtime-app solidtime-scheduler solidtime-queue 2>/dev/null || true
    sleep 5
  else
    warn "Could not generate OAuth keys (solidtime-scheduler may still be starting)"
    info "Run manually later: docker compose -f compose.yaml exec solidtime-scheduler php artisan self-host:generate-keys"
  fi
else
  ok "OAuth keys already present in solidtime.env"
fi

# ==================== Solidtime Admin User ====================
ADMIN_CREATED_FLAG="$SCRIPT_DIR/../.solidtime_admin_created"

if [[ ! -f "$ADMIN_CREATED_FLAG" ]]; then
  source "$ENV_FILE" >/dev/null 2>&1 || true
  SOLIDTIME_ADMIN_EMAIL="${SOLIDTIME_ADMIN_EMAIL:-}"

  if [[ -n "$SOLIDTIME_ADMIN_EMAIL" ]]; then
    step "Creating initial Solidtime admin user..."

    ADMIN_OUTPUT="$(docker compose -f ../compose.yaml exec -T solidtime-scheduler \
      php artisan admin:user:create "Admin" "${SOLIDTIME_ADMIN_EMAIL}" --verify-email 2>&1 || true)"

    if [[ -n "$ADMIN_OUTPUT" ]]; then
      echo "$ADMIN_OUTPUT" > "$ADMIN_CREATED_FLAG"
      ok "Solidtime admin user created:"
      echo "  Email: ${SOLIDTIME_ADMIN_EMAIL}"

      PASSWORD_LINE="$(echo "$ADMIN_OUTPUT" | grep -i 'password' | head -n1 || true)"
      if [[ -n "$PASSWORD_LINE" ]]; then
        echo "  $PASSWORD_LINE"
      else
        info "Check $ADMIN_CREATED_FLAG for CLI output with credentials."
      fi
    else
      warn "Admin user creation may have failed (check solidtime-scheduler logs)"
    fi
  else
    warn "SOLIDTIME_ADMIN_EMAIL not set in .env — skipping admin creation"
    info "Set it in .env and re-run ./start.sh to create the admin user."
  fi
else
  ok "Solidtime admin user already created (skipping)"
fi

# ==================== Health Check ====================
echo ""
hdr "Quick Health Check"

source "$ENV_FILE" >/dev/null 2>&1 || true
BASE_DOMAIN="${BASE_DOMAIN:-synth.home.arpa}"

check_url() {
  local name="$1"; local url="$2"
  if curl -fsSLk "$url" >/dev/null 2>&1; then
    printf '%s %s%s\n' "${GRN}✓${C0}" "${C1}${name}${C0}" ": ready"
  else
    printf '%s %s%s\n' "${YLW}?${C0}" "${C1}${name}${C0}" ": starting..."
  fi
}

echo "📊 Endpoints:"
check_url "Nextcloud"  "https://nextcloud.${BASE_DOMAIN}"
check_url "Solidtime"  "https://solidtime.${BASE_DOMAIN}"

echo ""
echo "🔗 URLs:"
echo "  - Nextcloud : ${DIM}https://nextcloud.${BASE_DOMAIN}${C0}"
echo "  - Solidtime : ${DIM}https://solidtime.${BASE_DOMAIN}${C0}"
echo ""
ok "MYestro is running. Check status with: docker compose -f ../compose.yaml ps"
