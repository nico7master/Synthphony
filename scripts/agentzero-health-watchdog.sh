#!/bin/bash
# Agent Zero Health Watchdog v2 (2026-09-06)
# Only restarts after 10 consecutive minutes of unhealthy status.
# Never hard-restarts the container automatically.

CONTAINER="orchestrai-agentzero"
STATE_FILE="$HOME/agentzero-unhealthy-count"
LOG_FILE="/opt/Synthphony/scripts/agentzero-watchdog.log"
MAX_SOFT_RESTARTS=10  # consecutive unhealthy minutes before supervisor restart

health=$(docker inspect "$CONTAINER" --format='{{.State.Health.Status}}' 2>/dev/null)

if [ "$health" != "unhealthy" ]; then
    if [ -s "$STATE_FILE" ] && [ "$(cat "$STATE_FILE" 2>/dev/null)" != "0" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') recovered - resetting counter"
    fi
    echo 0 > "$STATE_FILE" 2>/dev/null
    exit 0
fi

count=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" > "$STATE_FILE" 2>/dev/null

echo "$(date '+%Y-%m-%d %H:%M:%S') unhealthy (streak: $count)"

if [ "$count" -lt "$MAX_SOFT_RESTARTS" ]; then
    exit 0
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') soft restart after streak $MAX_SOFT_RESTARTS: supervisorctl restart run_ui"
docker exec "$CONTAINER" supervisorctl restart run_ui 2>&1
echo 0 > "$STATE_FILE" 2>/dev/null
