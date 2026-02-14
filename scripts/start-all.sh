#!/usr/bin/env bash
# ==================== SYNTHPHONY START-ALL ====================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."

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

# Cache sudo credentials once at the start (avoids repeated password prompts)
if [[ $EUID -ne 0 ]]; then
  step "This script needs sudo for DNS and Docker config. Enter password once:"
  sudo -v
  # Keep sudo alive in background
  while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
fi

hdr "Synthphony Start-All"

step "Ensuring shared ingress network exists..."
docker network create bridgecade_web >/dev/null 2>&1 || true
ok "Network bridgecade_web ready"


# ============================================================
# PHASE 1: Lock host DNS to public servers
# ============================================================
# Prevents the host from losing internet when Pi-hole starts.
# Does NOT affect Docker containers (they use Docker DNS config).
hdr "Phase 1: Lock Host DNS"
if [[ -f /etc/resolv.conf ]]; then
  # Remove immutable flag if set from previous run
  sudo chattr -i /etc/resolv.conf 2>/dev/null || true
  if ! grep -q "nameserver 1.1.1.1" /etc/resolv.conf 2>/dev/null; then
    step "Locking host DNS to public servers (1.1.1.1, 8.8.8.8)..."
    echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null
    ok "Host DNS locked"
  else
    ok "Host DNS already using public servers"
  fi
  sudo chattr +i /etc/resolv.conf 2>/dev/null || true
fi
echo ""

# ============================================================
# PHASE 2: Configure Docker daemon DNS fallback
# ============================================================
# Ensures containers can ALWAYS resolve DNS, even when Pi-hole
# is restarting or not yet healthy. This is the KEY fix.
hdr "Phase 2: Docker DNS Fallback"
DAEMON_JSON="/etc/docker/daemon.json"
if [[ -f "$DAEMON_JSON" ]]; then
  if ! grep -q '"dns"' "$DAEMON_JSON" 2>/dev/null; then
    step "Adding DNS fallback to Docker daemon config..."
    # Merge dns into existing config
    sudo python3 -c "
import json
with open('$DAEMON_JSON') as f:
    cfg = json.load(f)
cfg['dns'] = ['1.1.1.1', '8.8.8.8']
with open('$DAEMON_JSON', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>/dev/null && sudo systemctl restart docker && ok "Docker DNS fallback configured" || warn "Could not update daemon.json (may need manual edit)"
  else
    ok "Docker daemon DNS already configured"
  fi
else
  step "Creating Docker daemon config with DNS fallback..."
  echo '{"dns": ["1.1.1.1", "8.8.8.8"]}' | sudo tee "$DAEMON_JSON" > /dev/null
  sudo systemctl restart docker
  ok "Docker DNS fallback configured"
fi
echo ""

# ============================================================
# PHASE 3: Pull ALL images BEFORE starting anything
# ============================================================
# This is critical: pull while internet is guaranteed to work.
# Once Pi-hole starts, DNS may be disrupted briefly.
hdr "Phase 3: Ensure Docker Images Available"
# Only pull images that are missing locally (skip multi-GB re-downloads)
# Use --force flag (./scripts/start-all.sh --force) to force update all images
FORCE_PULL=false
for arg in "$@"; do
  [[ "$arg" == "--force" || "$arg" == "--pull" ]] && FORCE_PULL=true
done

for stack_dir in "$ROOT_DIR/BridgeCade" "$ROOT_DIR/MetronOmni" "$ROOT_DIR/MYestro" "$ROOT_DIR/OrchestrAI"; do
  if [[ -f "$stack_dir/compose.yaml" ]]; then
    stack_name="$(basename "$stack_dir")"
    if [[ "$FORCE_PULL" == "true" ]]; then
      step "Force pulling images for $stack_name..."
      (cd "$stack_dir" && docker compose pull --ignore-buildable 2>&1) && ok "$stack_name images updated" || warn "$stack_name pull had issues"
    else
      # Only pull missing images
      MISSING="$(cd "$stack_dir" && docker compose images 2>/dev/null | grep -c "N/A" || true)"; MISSING="${MISSING:-0}"; MISSING="$(echo "$MISSING" | tr -d "[:space:]")"
      if [[ "$MISSING" -gt 0 ]]; then
        step "Pulling missing images for $stack_name ($MISSING missing)..."
        (cd "$stack_dir" && docker compose pull --ignore-buildable 2>&1) && ok "$stack_name images pulled" || warn "$stack_name pull had issues"
      else
        ok "$stack_name images already available locally"
      fi
    fi
  fi
done
echo ""

# ============================================================
# PHASE 4: Start stacks in order
# ============================================================
# BridgeCade FIRST (infra: Caddy, Pi-hole, WireGuard, certs, DNS)
# Then wait for Pi-hole to be healthy before continuing.

run_stack() {
  local name="$1"
  local path="$2"

  if [[ ! -d "$path" ]]; then
    warn "Skipping $name — directory not found: $path"
    return
  fi

  if [[ ! -x "$path/scripts/start.sh" ]]; then
    warn "Skipping $name — no executable scripts/start.sh in $path"
    return
  fi

  hdr "Starting $name"
  if (cd "$path" && ./scripts/start.sh); then
    ok "$name started"
  else
    warn "$name start script had non-critical issues (exit code: $?) — continuing"
  fi
  echo ""
}

hdr "Phase 4: Start BridgeCade (Infrastructure)"
run_stack "BridgeCade" "$ROOT_DIR/BridgeCade"

# Wait for Pi-hole to be healthy and responding before starting app stacks
step "Waiting for Pi-hole DNS to be ready..."
PIHOLE_READY=0
for i in $(seq 1 30); do
  if docker exec bridgecade-pihole dig +short pi.hole @127.0.0.1 >/dev/null 2>&1; then
    PIHOLE_READY=1
    break
  fi
  sleep 2
done

if [[ "$PIHOLE_READY" -eq 1 ]]; then
  ok "Pi-hole DNS is responding"
else
  warn "Pi-hole not responding yet (continuing anyway — Docker has DNS fallback)"
fi
echo ""

hdr "Phase 4: Start App Stacks"
run_stack "MetronOmni (Ops/Monitoring)"  "$ROOT_DIR/MetronOmni"
run_stack "MYestro (Personal Cloud)"     "$ROOT_DIR/MYestro"
run_stack "OrchestrAI (AI Stack)"        "$ROOT_DIR/OrchestrAI"

hr
ok "All Synthphony stacks started."
info "Check status: docker ps"
info "If any service is unhealthy, give it 2-3 minutes to stabilize."
