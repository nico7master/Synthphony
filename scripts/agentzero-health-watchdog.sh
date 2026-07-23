#!/bin/bash
# Agent Zero Health Watchdog
# Restarts run_ui service when container becomes unhealthy
# Cron: * * * * * /opt/Synthphony/scripts/agentzero-health-watchdog.sh >> /opt/Synthphony/scripts/agentzero-watchdog.log 2>&1

CONTAINER="orchestrai-agentzero"
STATE_FILE="/tmp/agentzero-unhealthy-count"
LOG_FILE="/opt/Synthphony/scripts/agentzero-watchdog.log"
MAX_SOFT_RESTARTS=2  # supervisor restarts before full container restart

health=$(docker inspect "$CONTAINER" --format='{{.State.Health.Status}}' 2>/dev/null)

if [ "$health" != "unhealthy" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') healthy - resetting counter"
    echo 0 > "$STATE_FILE"
    exit 0
fi

count=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" > "$STATE_FILE"

echo "$(date '+%Y-%m-%d %H:%M:%S') unhealthy (streak: $count)"

if [ "$count" -le "$MAX_SOFT_RESTARTS" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') soft restart: supervisorctl restart run_ui"
    docker exec "$CONTAINER" supervisorctl restart run_ui 2>&1
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') hard restart: docker restart $CONTAINER"
    docker restart "$CONTAINER" 2>&1
    echo 0 > "$STATE_FILE"
fi
