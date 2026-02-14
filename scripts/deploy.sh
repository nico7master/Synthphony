#!/usr/bin/env bash
# Synthphony deploy.sh - copies ALL project files to /opt/Synthphony
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DST="/opt/Synthphony"

echo "Deploying Synthphony from $SRC to $DST"

# Create base structure
sudo mkdir -p "$DST"/{scripts,BridgeCade/{scripts,cert-issuer,dns-registrar,secrets,certs,mkcert-ca,pihole,etc-dnsmasq.d,wireguard},MetronOmni/scripts,MYestro/{scripts,secrets},OrchestrAI/{scripts,secrets},backups/{bridgecade,myestro,orchestrai,metronomni}}

# Root scripts
sudo cp "$SRC"/scripts/*.sh "$DST/scripts/"

# BridgeCade
sudo cp "$SRC"/BridgeCade/compose.yaml "$DST/BridgeCade/"
sudo cp "$SRC"/BridgeCade/.env.example "$DST/BridgeCade/"
sudo cp "$SRC"/BridgeCade/scripts/*.sh "$DST/BridgeCade/scripts/"
sudo cp "$SRC"/BridgeCade/cert-issuer/Dockerfile "$DST/BridgeCade/cert-issuer/"
sudo cp "$SRC"/BridgeCade/cert-issuer/issuer.py "$DST/BridgeCade/cert-issuer/"
sudo cp "$SRC"/BridgeCade/cert-issuer/.dockerignore "$DST/BridgeCade/cert-issuer/" 2>/dev/null || true
sudo cp "$SRC"/BridgeCade/dns-registrar/Dockerfile "$DST/BridgeCade/dns-registrar/"
sudo cp "$SRC"/BridgeCade/dns-registrar/registrar.py "$DST/BridgeCade/dns-registrar/"
sudo cp "$SRC"/BridgeCade/dns-registrar/.dockerignore "$DST/BridgeCade/dns-registrar/" 2>/dev/null || true

# MetronOmni
sudo cp "$SRC"/MetronOmni/compose.yaml "$DST/MetronOmni/"
sudo cp "$SRC"/MetronOmni/.env.example "$DST/MetronOmni/"
sudo cp "$SRC"/MetronOmni/scripts/*.sh "$DST/MetronOmni/scripts/"

# MYestro
sudo cp "$SRC"/MYestro/compose.yaml "$DST/MYestro/"
sudo cp "$SRC"/MYestro/.env.example "$DST/MYestro/"
sudo cp "$SRC"/MYestro/scripts/*.sh "$DST/MYestro/scripts/"
sudo cp -r "$SRC"/MYestro/homepage "$DST/MYestro/" 2>/dev/null || true

# OrchestrAI
sudo cp "$SRC"/OrchestrAI/compose.yaml "$DST/OrchestrAI/"
sudo cp "$SRC"/OrchestrAI/.env.example "$DST/OrchestrAI/"
sudo cp "$SRC"/OrchestrAI/scripts/*.sh "$DST/OrchestrAI/scripts/"

# Ensure scripts are executable
sudo chmod +x "$DST/scripts/"*.sh
sudo chmod +x "$DST/BridgeCade/scripts/"*.sh
sudo chmod +x "$DST/MetronOmni/scripts/"*.sh
sudo chmod +x "$DST/MYestro/scripts/"*.sh
sudo chmod +x "$DST/OrchestrAI/scripts/"*.sh

echo ""
echo "✓ Deployed to $DST"
echo ""
echo "To reset WireGuard and get new QR codes:"
echo "  cd $DST/BridgeCade"
echo "  ./scripts/stop.sh"
echo "  sudo rm -rf wireguard/peer_*"
echo "  ./scripts/start.sh"
echo "  docker exec -it bridgecade-wireguard /app/show-peer phone"
