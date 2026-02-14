#!/usr/bin/env bash
# ==================== BRIDGECADE STOP ====================
set -euo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

hdr "Stopping BRIDGECADE"

if [[ -f ../compose.yaml ]]; then
  docker compose -f ../compose.yaml down || warn "Some containers may not have been running"
  ok "BRIDGECADE stopped"
else
  warn "compose.yaml not found — nothing to stop"
fi
