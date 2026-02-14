#!/usr/bin/env bash
# deploy-code.sh - Deploy only scripts and compose files to remote server
# Uses --relative to preserve directory structure
set -euo pipefail

LOCAL_PATH="/home/nicos/Projects/AgentZeroLocal/agentzero_local_data/usr/projects/synthphony/"
REMOTE_HOST="home-server@192.168.178.100"
REMOTE_PATH="/opt/Synthphony/"

echo "🚀 Deploying Synthphony code (scripts + compose) to $REMOTE_HOST..."
echo ""

# Use --relative so directory structure is preserved
# e.g. BridgeCade/scripts/setup.sh -> $REMOTE_PATH/BridgeCade/scripts/setup.sh
cd "$LOCAL_PATH"

# Deploy root scripts
echo "> Deploying root scripts..."
rsync -avz --checksum --relative --progress \
  -e "ssh" \
  scripts/setup-all.sh \
  scripts/start-all.sh \
  scripts/stop-all.sh \
  scripts/deploy-code.sh \
  scripts/deploy.sh \
  "$REMOTE_HOST:$REMOTE_PATH"

# Deploy BridgeCade
echo "> Deploying BridgeCade..."
rsync -avz --checksum --relative --progress \
  -e "ssh" \
  BridgeCade/compose.yaml \
  BridgeCade/.env.example \
  BridgeCade/scripts/setup.sh \
  BridgeCade/scripts/start.sh \
  BridgeCade/scripts/stop.sh \
  BridgeCade/scripts/toggle-dns.sh \
  "$REMOTE_HOST:$REMOTE_PATH"

# Deploy BridgeCade subdirectories
rsync -avz --checksum --progress \
  -e "ssh" \
  BridgeCade/cert-issuer/ \
  "$REMOTE_HOST:${REMOTE_PATH}BridgeCade/cert-issuer/"

rsync -avz --checksum --progress \
  -e "ssh" \
  BridgeCade/dns-registrar/ \
  "$REMOTE_HOST:${REMOTE_PATH}BridgeCade/dns-registrar/"

# Deploy MetronOmni
echo "> Deploying MetronOmni..."
rsync -avz --checksum --relative --progress \
  -e "ssh" \
  MetronOmni/compose.yaml \
  MetronOmni/.env.example \
  MetronOmni/scripts/setup.sh \
  MetronOmni/scripts/start.sh \
  MetronOmni/scripts/stop.sh \
  "$REMOTE_HOST:$REMOTE_PATH"

# Deploy MYestro
echo "> Deploying MYestro..."
rsync -avz --checksum --relative --progress \
  -e "ssh" \
  MYestro/compose.yaml \
  MYestro/.env.example \
  MYestro/scripts/setup.sh \
  MYestro/scripts/start.sh \
  MYestro/scripts/stop.sh \
  "$REMOTE_HOST:$REMOTE_PATH"

# Deploy MYestro homepage
rsync -avz --checksum --progress \
  -e "ssh" \
  MYestro/homepage/ \
  "$REMOTE_HOST:${REMOTE_PATH}MYestro/homepage/"

# Deploy OrchestrAI
echo "> Deploying OrchestrAI..."
rsync -avz --checksum --relative --progress \
  -e "ssh" \
  OrchestrAI/compose.yaml \
  OrchestrAI/.env.example \
  OrchestrAI/scripts/setup.sh \
  OrchestrAI/scripts/start.sh \
  OrchestrAI/scripts/stop.sh \
  OrchestrAI/Dockerfile.agentzero-custom \
  OrchestrAI/.dockerignore \
  "$REMOTE_HOST:$REMOTE_PATH"

echo ""
echo "🔧 Fixing permissions..."
ssh "$REMOTE_HOST" "find $REMOTE_PATH -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true"

echo ""
echo "✅ Code deployed!"
echo ""
echo "To restart:"
echo " ssh $REMOTE_HOST 'cd $REMOTE_PATH && ./scripts/stop-all.sh && ./scripts/start-all.sh'"
