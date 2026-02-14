#!/usr/bin/env bash
# fix-agentzero.sh - Diagnose and fix AgentZero connection issues
set -euo pipefail

echo "=== AgentZero Connection Fix ==="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if container is healthy
check_container_health() {
    local container=$1
    local status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
    echo "$status"
}

# Function to wait for container to be healthy
wait_for_healthy() {
    local container=$1
    local max_attempts=30
    local attempt=1
    
    echo "Waiting for $container to be healthy..."
    while [ $attempt -le $max_attempts ]; do
        local status=$(check_container_health "$container")
        if [ "$status" = "healthy" ]; then
            echo -e "${GREEN}✓ $container is healthy${NC}"
            return 0
        fi
        echo "Attempt $attempt/$max_attempts: status=$status"
        sleep 2
        attempt=$((attempt + 1))
    done
    echo -e "${RED}✗ $container did not become healthy${NC}"
    return 1
}

echo "1. Checking AgentZero container status..."
if ! docker ps | grep -q orchestrai-agentzero; then
    echo -e "${RED}✗ AgentZero container not running!${NC}"
    echo "Starting OrchestrAI stack..."
    cd /opt/Synthphony/OrchestrAI
    docker compose up -d agentzero
    sleep 5
fi

echo -e "${GREEN}✓ AgentZero container exists${NC}"

# Check health status
echo ""
echo "2. Checking health status..."
HEALTH_STATUS=$(check_container_health orchestrai-agentzero)
echo "Health status: $HEALTH_STATUS"

if [ "$HEALTH_STATUS" != "healthy" ]; then
    echo -e "${YELLOW}! Container not healthy yet, waiting...${NC}"
    wait_for_healthy orchestrai-agentzero || true
fi

# Check logs for startup issues
echo ""
echo "3. Checking AgentZero logs..."
docker logs orchestrai-agentzero --tail 30 2>&1 | grep -E "(Listening|Server|Error|Failed|Traceback)" || echo "No obvious errors in logs"

# Check if AgentZero is on the correct network
echo ""
echo "4. Checking network configuration..."
AGENTZERO_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' orchestrai-agentzero 2>/dev/null || echo "")
if [ -z "$AGENTZERO_IP" ]; then
    echo -e "${RED}✗ Could not get AgentZero IP${NC}"
else
    echo "AgentZero IP: $AGENTZERO_IP"
fi

# Check if Caddy can reach AgentZero
echo ""
echo "5. Testing connectivity from Caddy to AgentZero..."
if docker exec bridgecade-caddy wget -qO- http://orchestrai-agentzero:80 2>/dev/null | head -1 | grep -q ""; then
    echo -e "${GREEN}✓ Caddy can reach AgentZero on port 80${NC}"
else
    echo -e "${RED}✗ Caddy cannot reach AgentZero${NC}"
    echo "Attempting to fix by restarting AgentZero..."
    
    # Restart AgentZero
    cd /opt/Synthphony/OrchestrAI
    docker compose restart agentzero
    sleep 10
    
    # Check again
    if docker exec bridgecade-caddy wget -qO- http://orchestrai-agentzero:80 2>/dev/null | head -1 | grep -q ""; then
        echo -e "${GREEN}✓ Fixed! Caddy can now reach AgentZero${NC}"
    else
        echo -e "${RED}✗ Still cannot reach AgentZero${NC}"
        echo "Checking if AgentZero is listening on port 80..."
        docker logs orchestrai-agentzero --tail 50 | grep -i "listen\|port\|80" || true
    fi
fi

# Final test
echo ""
echo "6. Final test from host..."
if curl -k https://agentzero.synth.home.arpa 2>/dev/null | head -1 | grep -q ""; then
    echo -e "${GREEN}✓ AgentZero is accessible via HTTPS${NC}"
else
    echo -e "${YELLOW}! AgentZero may not be fully ready yet${NC}"
    echo "Try accessing in a few seconds: https://agentzero.synth.home.arpa"
fi

echo ""
echo "=== Fix Complete ==="
