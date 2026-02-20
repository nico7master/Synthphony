#!/usr/bin/env bash
# ==================== ORCHESTRAI SETUP ====================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

# ----- SECRET GENERATORS -----
# IMPORTANT: gen_hex produces ONLY 0-9a-f characters.
# This is critical because these values go into DATABASE_URL.
# Base64 has /+= which BREAK URL parsing and cause "invalid port" errors.

gen_hex_32() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import secrets; print(secrets.token_hex(32))"
  else
    tr -dc '0-9a-f' </dev/urandom | head -c 64; echo
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

hdr "OrchestrAI Setup"

# ----- Docker Prerequisites -----
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

# ----- NVIDIA Container Toolkit -----
hdr "NVIDIA Container Toolkit"
if command -v nvidia-smi >/dev/null 2>&1; then
  ok "NVIDIA GPU detected"
  if ! command -v nvidia-ctk >/dev/null 2>&1; then
    step "Installing NVIDIA Container Toolkit"
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
      sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
      sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    sudo apt-get update -qq
    sudo apt-get install -y nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
    ok "NVIDIA Container Toolkit installed"
  else
    ok "NVIDIA Container Toolkit already installed"
  fi
else
  warn "No NVIDIA GPU detected — Ollama will run on CPU"
fi
echo ""

# ----- Shared Docker network -----
hdr "Docker Network"
step "Ensuring external network bridgecade_web exists"
docker network create bridgecade_web >/dev/null 2>&1 || true
ok "Network bridgecade_web ready"
echo ""

# ----- .env and Secrets -----
hdr ".env and Secrets"
ENV_EXAMPLE="$SCRIPT_DIR/../.env.example"
ENV_FILE="$SCRIPT_DIR/../.env"
SECRETS_DIR="$SCRIPT_DIR/../secrets"

if [[ ! -f "$ENV_EXAMPLE" ]]; then
  err ".env.example not found"
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

# Generate all secrets using HEX ONLY (0-9a-f) — URL-safe, no parsing issues
step "Generating Windmill secrets (hex-only, URL-safe)"

if [[ ! -f "$SECRETS_DIR/windmill_db_password.txt" ]]; then
  gen_hex_32 > "$SECRETS_DIR/windmill_db_password.txt"
  chmod 600 "$SECRETS_DIR/windmill_db_password.txt"
  ok "Windmill DB password generated (hex)"
else
  ok "Windmill DB password already exists"
fi

if [[ ! -f "$SECRETS_DIR/wm_encryption_key.txt" ]]; then
  gen_hex_32 > "$SECRETS_DIR/wm_encryption_key.txt"
  chmod 600 "$SECRETS_DIR/wm_encryption_key.txt"
  ok "Windmill encryption key generated (hex)"
else
  ok "Windmill encryption key already exists"
fi

if [[ ! -f "$SECRETS_DIR/wm_jwt_secret.txt" ]]; then
  gen_hex_32 > "$SECRETS_DIR/wm_jwt_secret.txt"
  chmod 600 "$SECRETS_DIR/wm_jwt_secret.txt"
  ok "Windmill JWT secret generated (hex)"
else
  ok "Windmill JWT secret already exists"
fi

# Inject ALL secrets into .env
set_or_update_env "WINDMILL_DB_PASSWORD" "$(<"$SECRETS_DIR/windmill_db_password.txt")" "$ENV_FILE"
set_or_update_env "WM_ENCRYPTION_KEY" "$(<"$SECRETS_DIR/wm_encryption_key.txt")" "$ENV_FILE"
set_or_update_env "WM_JWT_SECRET" "$(<"$SECRETS_DIR/wm_jwt_secret.txt")" "$ENV_FILE"
ok "All secrets injected into .env"
echo ""

# ----- Data Directories -----
hdr "Data Directories"
step "Creating data directories"
mkdir -p ../openwebui
mkdir -p ../windmill/db
mkdir -p ../windmill/data
mkdir -p ../ollama
mkdir -p ../agentzero_data
mkdir -p ../agentzero_config
mkdir -p ../wmill_config
ok "Data directories ready"
echo ""

hdr "OrchestrAI Setup Complete"

# Apply group changes without logout
if [[ "$NEEDS_LOGOUT" -eq 1 ]]; then
  echo ""
  hr
fi

hr
echo "Setup complete!"
