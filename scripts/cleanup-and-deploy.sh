#!/usr/bin/env bash
# cleanup-and-deploy.sh - Fix the flattened files mess, then deploy properly
set -euo pipefail

REMOTE_HOST="home-server@192.168.178.100"
REMOTE_PATH="/opt/Synthphony"

echo "🧹 Cleaning up wrongly-placed flattened files on remote..."
echo ""

# The old deploy script flattened scripts/*.sh into the stack root dirs
# e.g. BridgeCade/scripts/setup.sh -> BridgeCade/setup.sh (WRONG)
# Remove these misplaced files (they should only exist in scripts/ subdirs)

ssh "$REMOTE_HOST" bash -s << 'REMOTE_CLEANUP'
set -euo pipefail

echo "Checking for misplaced files..."

# List of stack dirs that should NOT have .sh files at their root
STACKS="BridgeCade MetronOmni MYestro OrchestrAI"

for stack in $STACKS; do
  DIR="/opt/Synthphony/$stack"
  if [ -d "$DIR" ]; then
    # Find .sh files directly in stack root (NOT in scripts/ subdir)
    for f in "$DIR"/*.sh; do
      if [ -f "$f" ]; then
        basename=$(basename "$f")
        echo "  ❌ Removing misplaced: $stack/$basename"
        rm -f "$f"
      fi
    done

    # Also check for misplaced .py, Dockerfile etc that got flattened
    for f in "$DIR"/issuer.py "$DIR"/registrar.py "$DIR"/.dockerignore; do
      if [ -f "$f" ]; then
        basename=$(basename "$f")
        echo "  ❌ Removing misplaced: $stack/$basename"
        rm -f "$f"
      fi
    done
  fi
done

echo "✅ Cleanup complete"
REMOTE_CLEANUP

echo ""
echo "🚀 Now deploying with fixed script..."
echo ""

# Run the fixed deploy-code.sh
cd /home/nicos/Projects/AgentZeroLocal/agentzero_local_data/usr/projects/synthphony
./scripts/deploy-code.sh

echo ""
echo "✅ Cleanup + Deploy complete!"
echo ""
echo "Verify on mini PC:"
echo "  grep -A3 'Firewall Configuration' /opt/Synthphony/BridgeCade/scripts/setup.sh"
