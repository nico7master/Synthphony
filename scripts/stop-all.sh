#!/usr/bin/env bash
# ==================== SYNTHPHONY STOP-ALL ====================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -t 1 ]]; then
  C0=$'\033[0m'; C1=$'\033[1m'
  GRN=$'\033[32m'; YLW=$'\033[33m'; RED=$'\033[31m'
  BLU=$'\033[34m'; DIM=$'\033[2m'
else
  C0=""; C1=""; GRN=""; YLW=""; RED=""; BLU=""; DIM=""
fi

hr()   { printf '%s\n' "${DIM}───────────────────────────────────────────────────────${C0}"; }
hdr()  { hr; printf '%b\n' "${C1}${BLU}▶ $1${C0}"; hr; }
ok()   { printf '%s\n' "${GRN}✓${C0} $*"; }
warn() { printf '%s\n' "${YLW}!${C0} $*"; }

stop_stack() {
  local name="$1"
  local path="$2"

  if [[ ! -d "$path" ]]; then
    warn "Skipping $name — directory not found: $path"
    return
  fi

  if [[ ! -x "$path/scripts/stop.sh" ]]; then
    warn "Skipping $name — no executable stop.sh in $path/scripts/"
    return
  fi

  hdr "Stopping $name"
  (cd "$path/scripts" && ./stop.sh)
}

hdr "Synthphony Stop-All"

# Stop in reverse order (apps first, infra last)
stop_stack "OrchestrAI (AI Stack)"        "$ROOT_DIR/OrchestrAI"
stop_stack "MYestro (Personal Cloud)"     "$ROOT_DIR/MYestro"
stop_stack "MetronOmni (Ops/Monitoring)"  "$ROOT_DIR/MetronOmni"
stop_stack "BridgeCade (Ingress/DNS/VPN)" "$ROOT_DIR/BridgeCade"

hr
ok "All Synthphony stacks stopped (where present)."
