#!/usr/bin/env bash
# ==================== MYESTRO SETUP ====================
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

gen_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import secrets, base64; print(base64.b64encode(secrets.token_bytes(32)).decode())'
  else
    head -c 32 /dev/urandom | base64
  fi
}

gen_laravel_key() {
  # Laravel requires base64:<44-char-base64> format
  local raw
  raw="$(openssl rand -base64 32 2>/dev/null || head -c 32 /dev/urandom | base64)"
  echo "base64:${raw}"
}

set_or_update_env() {
  local key="$1"; local value="$2"; local env_file="$3"
  if grep -qE "^${key}=" "$env_file" 2>/dev/null; then
    sed -i "s|^${key}=.*$|${key}=${value}|" "$env_file"
  else
    echo "${key}=${value}" >> "$env_file"
  fi
}

hdr "MYestro Setup"

# ==================== Docker Prerequisites ====================
hdr "Docker Prerequisites"
if ! command -v docker >/dev/null 2>&1; then
  step "Docker not found — installing via get.docker.com"
  require_cmd curl
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
  NEEDS_LOGOUT=1
  export SETUP_NEEDS_NEWGRP=1
fi

if ! id -nG "$USER" 2>/dev/null | grep -q '\bdocker\b'; then
  step "Adding $USER to docker group"
  sudo usermod -aG docker "$USER" 2>/dev/null
  NEEDS_LOGOUT=1
  export SETUP_NEEDS_NEWGRP=1
fi
ok "Docker group ready"
echo ""

# ==================== Docker Network ====================
hdr "Docker Network"
docker network create bridgecade_web >/dev/null 2>&1 || true
ok "Network bridgecade_web ready"
echo ""

# ==================== .env and Secrets ====================
hdr ".env and Secrets"

ENV_EXAMPLE="$SCRIPT_DIR/../.env.example"
ENV_FILE="$SCRIPT_DIR/../.env"
SECRETS_DIR="$SCRIPT_DIR/../secrets"
SOLIDTIME_ENV="$SCRIPT_DIR/../solidtime.env"

if [[ ! -f "$ENV_EXAMPLE" ]]; then
  err ".env.example not found at $ENV_EXAMPLE"
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

# --- Nextcloud secrets ---
if [[ ! -f "$SECRETS_DIR/nextcloud_db_root_password.txt" ]]; then
  step "Generating Nextcloud DB root password"
  gen_password > "$SECRETS_DIR/nextcloud_db_root_password.txt"
  chmod 600 "$SECRETS_DIR/nextcloud_db_root_password.txt"
  ok "Root DB password stored"
else
  ok "Root DB password already exists"
fi

if [[ ! -f "$SECRETS_DIR/nextcloud_db_password.txt" ]]; then
  step "Generating Nextcloud DB user password"
  gen_password > "$SECRETS_DIR/nextcloud_db_password.txt"
  chmod 600 "$SECRETS_DIR/nextcloud_db_password.txt"
  ok "User DB password stored"
else
  ok "User DB password already exists"
fi

# --- Solidtime secrets ---
if [[ ! -f "$SECRETS_DIR/solidtime_db_password.txt" ]]; then
  step "Generating Solidtime DB password"
  gen_password > "$SECRETS_DIR/solidtime_db_password.txt"
  chmod 600 "$SECRETS_DIR/solidtime_db_password.txt"
  ok "Solidtime DB password stored"
else
  ok "Solidtime DB password already exists"
fi

# Inject secrets into .env
NEXTCLOUD_DB_ROOT_PASSWORD="$(<"$SECRETS_DIR/nextcloud_db_root_password.txt")"
NEXTCLOUD_DB_PASSWORD="$(<"$SECRETS_DIR/nextcloud_db_password.txt")"
SOLIDTIME_DB_PASSWORD="$(<"$SECRETS_DIR/solidtime_db_password.txt")"

set_or_update_env "NEXTCLOUD_DB_ROOT_PASSWORD" "$NEXTCLOUD_DB_ROOT_PASSWORD" "$ENV_FILE"
set_or_update_env "NEXTCLOUD_DB_PASSWORD"      "$NEXTCLOUD_DB_PASSWORD"      "$ENV_FILE"
set_or_update_env "SOLIDTIME_DB_PASSWORD"       "$SOLIDTIME_DB_PASSWORD"       "$ENV_FILE"

# Warn if Nextcloud admin password is still default
if grep -q "NEXTCLOUD_ADMIN_PASSWORD=change-me-strong-password" "$ENV_FILE" 2>/dev/null; then
  GENERATED_NC_PW="$(gen_password | head -c 24)"
  set_or_update_env "NEXTCLOUD_ADMIN_PASSWORD" "$GENERATED_NC_PW" "$ENV_FILE"
  ok "Auto-generated NEXTCLOUD_ADMIN_PASSWORD (saved in .env)"
fi

ok "Secrets and .env prepared"
echo ""
# ==================== Solidtime Admin Email ====================
hdr "Solidtime Admin Email"

ADMIN_EMAIL_EXISTING="$(grep -E '^SOLIDTIME_ADMIN_EMAIL=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"
if [[ -z "${ADMIN_EMAIL_EXISTING}" || "${ADMIN_EMAIL_EXISTING}" == "admin@example.com" ]]; then
  echo ""
  if [[ -t 0 ]]; then
    read -rp "Enter admin email for Solidtime (used for first login): " ADMIN_EMAIL_INPUT
    if [[ -z "${ADMIN_EMAIL_INPUT}" ]]; then
      warn "No email provided — using default admin@example.com"
      ADMIN_EMAIL_INPUT="admin@example.com"
    fi
  else
    ADMIN_EMAIL_INPUT="admin@example.com"
    info "Non-interactive mode: using default admin@example.com"
  fi
  set_or_update_env "SOLIDTIME_ADMIN_EMAIL" "$ADMIN_EMAIL_INPUT" "$ENV_FILE"
  ok "SOLIDTIME_ADMIN_EMAIL set to ${ADMIN_EMAIL_INPUT}"
else
  ok "SOLIDTIME_ADMIN_EMAIL already set (${ADMIN_EMAIL_EXISTING})"
fi
echo ""



# ==================== solidtime.env (Laravel app config) ====================
hdr "Solidtime Application Config"

if [[ ! -f "$SOLIDTIME_ENV" ]]; then
  step "Generating solidtime.env"

  APP_KEY="$(gen_laravel_key)"

  # Source .env to get BASE_DOMAIN
  source "$ENV_FILE" >/dev/null 2>&1 || true
  BASE_DOMAIN="${BASE_DOMAIN:-synth.home.arpa}"

  cat > "$SOLIDTIME_ENV" <<ENVEOF
APP_NAME=solidtime
APP_ENV=production
APP_DEBUG=false
APP_URL=https://solidtime.${BASE_DOMAIN}

APP_KEY=${APP_KEY}

LOG_CHANNEL=stack

DB_CONNECTION=pgsql
DB_HOST=myestro-solidtime-db
DB_PORT=5432
DB_DATABASE=solidtime
DB_USERNAME=solidtime
DB_PASSWORD=${SOLIDTIME_DB_PASSWORD}

QUEUE_CONNECTION=database
CACHE_DRIVER=file
SESSION_DRIVER=file
SESSION_LIFETIME=120
ENVEOF

  chmod 600 "$SOLIDTIME_ENV"
  ok "solidtime.env created"
else
  ok "solidtime.env already exists"
fi
echo ""

# ==================== Volume Directories ====================
hdr "Volume Directories"

mkdir -p "$SCRIPT_DIR/../nextcloud/html"
mkdir -p "$SCRIPT_DIR/../nextcloud/db"
mkdir -p "$SCRIPT_DIR/../solidtime/logs"
mkdir -p "$SCRIPT_DIR/../solidtime/app-storage"
ok "Volume directories created"
echo ""

# ==================== Summary ====================
hdr "MYestro Setup Complete"


# Apply group changes without logout
if [[ "$NEEDS_LOGOUT" -eq 1 ]]; then
  echo ""
  hr
fi

hr
echo "Setup complete!"
