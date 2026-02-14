#!/usr/bin/env bash
# diagnose-agentzero.sh - Diagnose AgentZero connection issues
set -euo pipefail

echo "=== AgentZero Diagnostics ==="
echo ""

# Check if AgentZero container is running
echo "1. Checking AgentZero container..."
docker ps | grep orchestrai-agentzero || echo "❌ AgentZero not running"

# Check AgentZero logs
echo ""
echo "2. Checking AgentZero logs (last 20 lines)..."
docker logs orchestrai-agentzero --tail 20 2>&1 | head -20 || echo "❌ Cannot get logs"

# Check if AgentZero is on bridgecade_web network
echo ""
echo "3. Checking network membership..."
docker network inspect bridgecade_web | grep -A2 orchestrai-agentzero || echo "❌ Not on bridgecade_web network"

# Check Caddy can resolve AgentZero
echo ""
echo "4. Testing Caddy -> AgentZero connectivity..."
docker exec bridgecade-caddy nslookup orchestrai-agentzero 2>/dev/null || echo "❌ Cannot resolve orchestrai-agentzero"

# Get AgentZero IP
echo ""
echo "5. AgentZero container IP:"
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' orchestrai-agentzero 2>/dev/null || echo "❌ Cannot get IP"

# Test from Caddy container using wget (might be available)
echo ""
echo "6. Testing HTTP from Caddy to AgentZero..."
docker exec bridgecade-caddy wget -qO- http://orchestrai-agentzero:80 2>&1 | head -3 || echo "❌ wget failed"

echo ""
echo "=== Diagnostics Complete ==="
