#!/usr/bin/env bash
# ==================== SYNTHPHONY SETUP-ALL ====================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

run_setup() {
  local name="$1"
  local path="$2"

  if [[ ! -d "$path" ]]; then
    warn "Skipping $name — directory not found: $path"
    return
  fi

  if [[ ! -x "$path/scripts/setup.sh" ]]; then
    warn "Skipping $name — no executable scripts/setup.sh in $path"
    return
  fi

  hdr "Setting up $name"
  (cd "$path" && ./scripts/setup.sh)
  ok "$name setup complete"
  echo ""
}

hdr "Synthphony Setup-All"
info "This will run setup for all stacks in order:"
echo "  1. BridgeCade (Infrastructure - Docker, network, port 53 fix)"
echo "  2. MetronOmni (Ops/Monitoring)"
echo "  3. MYestro (Personal Cloud)"
echo "  4. OrchestrAI (AI Stack)"
echo ""

if [[ -t 0 ]]; then
  read -p "Continue? [Y/n]: " response
  if [[ ! "$response" =~ ^[Yy]?$ ]]; then
    info "Setup cancelled"
    exit 0
  fi
fi

# Run setups in order (BridgeCade MUST be first for network/port 53)
run_setup "BridgeCade (Infrastructure)" "$ROOT_DIR/BridgeCade"
run_setup "MetronOmni (Ops/Monitoring)" "$ROOT_DIR/MetronOmni"
run_setup "MYestro (Personal Cloud)" "$ROOT_DIR/MYestro"
run_setup "OrchestrAI (AI Stack)" "$ROOT_DIR/OrchestrAI"

hr
ok "All Synthphony stacks set up!"
echo ""
info "Next steps:"
echo "  1. Logout and login again (if prompted during setup)"
echo "  2. Start all stacks: ${C1}./scripts/start-all.sh${C0}"
echo "  3. Or start individually:"
echo "     cd BridgeCade && ./scripts/start.sh"
echo "     cd MetronOmni && ./scripts/start.sh"
echo "     etc."

# Activate docker group if needed (runs once at end)
if [[ "${SETUP_NEEDS_NEWGRP:-0}" -eq 1 ]]; then
  echo ""
  echo "───────────────────────────────────────────────────────"
  echo "▶ Activating Docker Group"
  echo "───────────────────────────────────────────────────────"
  echo "> Running: newgrp docker"
  echo "Your session will continue with docker group active"
  exec newgrp docker
fi
