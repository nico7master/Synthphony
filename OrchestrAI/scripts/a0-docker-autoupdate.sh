#!/usr/bin/env bash
#
# a0-docker-autoupdate.sh
# Agent Zero Docker Auto-Update Script with Backup
#
# Checks for new Agent Zero Docker images, backs up data,
# stops the container, pulls the new image, and recreates it.
# Designed to run via cron at 3 AM.
#
# USAGE:
#   1. Copy this script to your HOST machine (not inside the container).
#   2. Edit the CONFIG section below to match your setup.
#   3. chmod +x a0-docker-autoupdate.sh
#   4. Test run: sudo ./a0-docker-autoupdate.sh
#   5. Schedule via cron (see bottom of this file)
#

set -euo pipefail

# =============================================================================
# CONFIGURATION — Edit these values to match your setup
# =============================================================================

# Docker image to watch
A0_IMAGE="agent0ai/agent-zero:latest"

# Block automatic MAJOR version upgrades (e.g. 1.x -> 2.x).
# Per A0 guidance, major upgrades require a new Docker image + data migration and
# should be applied manually after reviewing migration notes.
# When "true", the script detects a major jump, logs + notifies, then exits WITHOUT
# updating. Set to "false" to allow unattended major upgrades.
BLOCK_MAJOR_UPGRADES=true

# Host-side path to A0 settings.json (fallback for reading the running version)
A0_HOST_SETTINGS_JSON="/opt/Synthphony/OrchestrAI/agentzero_data/settings.json"

# Name of your running Agent Zero container
A0_CONTAINER_NAME="orchestrai-agentzero"

# Directory where backups will be stored
BACKUP_DIR="${BACKUP_DIR:-/mnt/hdd/backups/agentzero}"

# How many backups to keep (rotates old ones)
KEEP_BACKUPS=5

# Log file location
LOG_FILE="${BACKUP_DIR}/a0-autoupdate.log"

# If you use docker-compose, set the path to your compose file.
# Leave empty ("") if you launch with `docker run` directly.
COMPOSE_FILE="/opt/Synthphony/OrchestrAI/compose.yaml"

# If using docker run (COMPOSE_FILE is empty), the script auto-detects
# the container config. You can override the full docker run command here:
# Leave empty to auto-detect from the running container.
OVERRIDE_RUN_CMD=""

# Set to "true" to enable Gotify notifications (optional)
GOTIFY_ENABLED=false
GOTIFY_URL=""
GOTIFY_TOKEN=""

# Compose service name for Agent Zero (used when COMPOSE_FILE is set)
# Must match the service name in your compose.yaml
A0_SERVICE_NAME="agentzero"

# Compose project name (usually the directory name or set via COMPOSE_PROJECT_NAME)
# Default: auto-detected from COMPOSE_FILE directory
A0_PROJECT_NAME="orchestrai"

# Lock file to prevent concurrent runs
LOCK_FILE="/tmp/a0-autoupdate.lock"

# Comma-separated list of volume source paths to EXCLUDE from backup
# (e.g. backup directories mounted into the container)
EXCLUDE_VOLUME_SOURCES="/opt/Synthphony/OrchestrAI/agentzero_update_backups"

# =============================================================================
# A0 NATIVE BACKUP (UI-importable via Settings > Backup Restore)
# =============================================================================
# Creates a proper A0 backup ZIP via the API before updating.
# The container MUST be running for this to work.

A0_NATIVE_BACKUP=false

# URL of your Agent Zero web UI (used to call the backup API)
A0_WEB_URL="http://localhost:50020"

# Auth — use ONE of these:
# A) API key (leave empty if not set)
A0_API_KEY=""
# B) Username + password (web UI login)
A0_USERNAME=""
A0_PASSWORD=""

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $*" | tee -a "${LOG_FILE}"
}

notify() {
    local title="$1"
    local message="$2"
    if [[ "${GOTIFY_ENABLED}" == "true" && -n "${GOTIFY_URL}" && -n "${GOTIFY_TOKEN}" ]]; then
        curl -s -X POST "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" \
            -F "title=${title}" \
            -F "message=${message}" \
            -F "priority=5" > /dev/null 2>&1 || true
    fi
}

# =============================================================================
# A0 NATIVE BACKUP (UI-importable ZIP via Settings > Backup Restore)
# =============================================================================

create_native_a0_backup() {
    local backup_ts="$1"
    local backup_path="${BACKUP_DIR}/a0-backup-${backup_ts}"

    if [[ "${A0_NATIVE_BACKUP}" != "true" ]]; then
        log "  A0 native backup skipped (disabled in config)."
        return 0
    fi

    log "  Creating A0 native backup (UI-importable ZIP)..."

    local cookie_jar="${backup_path}/a0-cookies.txt"
    local csrf_token=""
    local api_base="${A0_WEB_URL}"

    # Step 1: Get CSRF token
    log "    Getting CSRF token from ${api_base}/api/csrf_token..."
    local csrf_response
    csrf_response=$(curl -s -c "${cookie_jar}" -b "${cookie_jar}" \
        -H "Origin: ${api_base}" \
        "${api_base}/api/csrf_token" 2>/dev/null)

    csrf_token=$(echo "${csrf_response}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)

    if [[ -z "${csrf_token}" ]]; then
        log "    WARN: Could not get CSRF token. A0 native backup failed."
        log "    Response was: ${csrf_response:0:200}"
        return 1
    fi

    log "    CSRF token obtained: ${csrf_token:0:10}..."

    # Step 2: Authenticate if credentials are set
    # A0 uses form-based login at POST /login
    if [[ -n "${A0_USERNAME}" && -n "${A0_PASSWORD}" ]]; then
        log "    Authenticating via /login..."
        curl -s -c "${cookie_jar}" -b "${cookie_jar}" -L \
            -X POST "${api_base}/login" \
            -H "Origin: ${api_base}" \
            -d "username=${A0_USERNAME}&password=${A0_PASSWORD}" > /dev/null 2>&1
        # Re-get CSRF token after auth (session may change)
        csrf_response=$(curl -s -c "${cookie_jar}" -b "${cookie_jar}" \
            -H "Origin: ${api_base}" \
            "${api_base}/api/csrf_token" 2>/dev/null)
        csrf_token=$(echo "${csrf_response}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)
        if [[ -z "${csrf_token}" ]]; then
            log "    WARN: Auth may have failed. Continuing anyway..."
        fi
    fi

    # Step 3: Call backup_create API
    log "    Calling /api/backup_create..."
    local backup_name="a0-autoupdate-backup-${backup_ts}"
    local http_code
    http_code=$(curl -s -w "%{http_code}" -o "${backup_path}/a0-native-backup.zip" \
        -c "${cookie_jar}" -b "${cookie_jar}" \
        -X POST "${api_base}/api/backup_create" \
        -H "Content-Type: application/json" \
        -H "X-CSRF-Token: ${csrf_token}" \
        -H "Origin: ${api_base}" \
        -d "{\"backup_name\":\"${backup_name}\",\"include_hidden\":true}" 2>/dev/null)

    # Clean up cookie jar
    rm -f "${cookie_jar}"

    if [[ "${http_code}" == "200" ]]; then
        local zip_size
        zip_size=$(du -sh "${backup_path}/a0-native-backup.zip" 2>/dev/null | cut -f1 || echo "unknown")
        log "    A0 native backup created: a0-native-backup.zip (${zip_size})"
        log "    This ZIP can be imported from Settings > Backup Restore in the A0 UI."
        return 0
    else
        log "    WARN: A0 native backup API returned HTTP ${http_code}."
        if [[ -f "${backup_path}/a0-native-backup.zip" ]]; then
            local head_content
            head_content=$(head -c 200 "${backup_path}/a0-native-backup.zip" 2>/dev/null)
            if echo "${head_content}" | grep -q '"error"'; then
                log "    Error: ${head_content}"
                rm -f "${backup_path}/a0-native-backup.zip"
            fi
        fi
        log "    Raw volume backup is still available as fallback."
        return 1
    fi
}

cleanup_old_backups() {
    local count
    count=$(find "${BACKUP_DIR}" -maxdepth 1 -name "a0-backup-*" -type d 2>/dev/null | wc -l)
    if [[ ${count} -gt ${KEEP_BACKUPS} ]]; then
        local to_remove
        to_remove=$((count - KEEP_BACKUPS))
        log "Rotating ${to_remove} old backup(s)..."
        find "${BACKUP_DIR}" -maxdepth 1 -name "a0-backup-*" -type d | sort | head -n "${to_remove}" | while read -r dir; do
            log "  Removing old backup: ${dir}"
            rm -rf "${dir}"
        done
    fi
}

# =============================================================================
# STEP 1: PRE-FLIGHT CHECKS
# =============================================================================

preflight() {
    log "==========================================="
    log "=== Agent Zero Docker Auto-Update Start ==="
    log "==========================================="

    # Ensure log file exists
    touch "${LOG_FILE}" 2>/dev/null || LOG_FILE="/tmp/a0-autoupdate.log"

    # Lock file to prevent concurrent runs
    if [[ -f "${LOCK_FILE}" ]]; then
        local lock_pid
        lock_pid=$(cat "${LOCK_FILE}" 2>/dev/null)
        if [[ -n "${lock_pid}" ]] && kill -0 "${lock_pid}" 2>/dev/null; then
            log "Another instance is already running (PID ${lock_pid}). Exiting."
            exit 0
        fi
        log "Stale lock file found. Removing."
        rm -f "${LOCK_FILE}"
    fi
    echo $$ > "${LOCK_FILE}"
    trap 'rm -f "${LOCK_FILE}"' EXIT

    # Check Docker is available
    if ! command -v docker &> /dev/null; then
        log "ERROR: Docker command not found. Is Docker installed?"
        exit 1
    fi

    # Check the container exists and is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${A0_CONTAINER_NAME}$"; then
        log "WARN: Container '${A0_CONTAINER_NAME}' is not running. Skipping update."
        exit 0
    fi

    local current_image
    current_image=$(docker inspect --format '{{.Config.Image}}' "${A0_CONTAINER_NAME}" 2>/dev/null || echo "")
    if [[ -z "${current_image}" ]]; then
        log "ERROR: Could not determine current image for container '${A0_CONTAINER_NAME}'."
        exit 1
    fi

    log "Container:  ${A0_CONTAINER_NAME}"
    log "Image:      ${current_image}"
    log "Watching:   ${A0_IMAGE}"
}

# =============================================================================
# MAJOR-VERSION GUARD HELPERS
# =============================================================================

# Echo the major version number from a string like "v1.20" / "2.1" (empty if unknown)
version_major() {
    echo "$1" | grep -oiE '^[vV]?[0-9]+' | grep -oE '[0-9]+$'
}

# Echo the currently-running A0 version (e.g. "v1.20") from settings.json
get_current_a0_version() {
    local ver=""
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${A0_CONTAINER_NAME}$"; then
        ver=$(docker exec "${A0_CONTAINER_NAME}" bash -c 'cat /a0/usr/settings.json 2>/dev/null' 2>/dev/null \
            | python3 -c "import json,sys; print(json.load(sys.stdin).get('version',''))" 2>/dev/null)
    fi
    if [[ -z "${ver}" && -f "${A0_HOST_SETTINGS_JSON}" ]]; then
        ver=$(python3 -c "import json; print(json.load(open('${A0_HOST_SETTINGS_JSON}')).get('version',''))" 2>/dev/null)
    fi
    echo "${ver}"
}

# Echo the vX.Y registry tag whose digest matches the given manifest digest
get_remote_a0_version() {
    local target_digest="$1"
    local page=1 found=""
    while [[ -z "${found}" && ${page} -le 5 ]]; do
        local resp
        resp=$(curl -sf "https://hub.docker.com/v2/repositories/agent0ai/agent-zero/tags/?page_size=100&page=${page}" 2>/dev/null || true)
        found=$(echo "${resp}" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
target = sys.argv[1]
for t in data.get('results', []):
    if t.get('digest') == target:
        name = t.get('name', '')
        if name.lower().startswith('v') and any(c.isdigit() for c in name):
            print(name); break
" "${target_digest}" 2>/dev/null)
        page=$((page + 1))
    done
    echo "${found}"
}

# =============================================================================
# STEP 2: CHECK FOR UPDATE
# =============================================================================

check_for_update() {
    log "Checking for new image version..."

    # Get the digest of the currently running container's image
    local current_digest
    current_digest=$(docker inspect --format '{{.Image}}' "${A0_CONTAINER_NAME}" 2>/dev/null)
    log "Current digest: ${current_digest:0:24}..."

    # Pull the latest image
    log "Pulling latest image: ${A0_IMAGE}"
    if ! docker pull "${A0_IMAGE}" >> "${LOG_FILE}" 2>&1; then
        log "ERROR: Failed to pull image. Aborting update."
        notify "A0 Update Failed" "Could not pull image ${A0_IMAGE}"
        exit 1
    fi

    # Compare digests
    local new_digest
    new_digest=$(docker inspect --format '{{.Id}}' "${A0_IMAGE}" 2>/dev/null)
    log "New digest:    ${new_digest:0:24}..."

    if [[ "${current_digest}" == "${new_digest}" ]]; then
        log "No update available — digests match."
        log "=== Auto-Update Check Complete (no update needed) ==="
        exit 0
    fi

    log "UPDATE DETECTED! New image version available."

    # ---- Major-version guard: never auto-apply a breaking major upgrade ----
    if [[ "${BLOCK_MAJOR_UPGRADES}" == "true" ]]; then
        local cur_ver cur_major new_manifest new_ver new_major
        cur_ver=$(get_current_a0_version)
        cur_major=$(version_major "${cur_ver}")
        new_manifest=$(docker inspect --format '{{json .RepoDigests}}' "${A0_IMAGE}" 2>/dev/null \
            | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].split('@')[1] if d else '')" 2>/dev/null)
        new_ver=$(get_remote_a0_version "${new_manifest}")
        new_major=$(version_major "${new_ver}")
        log "Version check: current=${cur_ver:-unknown} (major ${cur_major:-?}) -> new=${new_ver:-unknown} (major ${new_major:-?})"
        if [[ -n "${cur_major}" && -n "${new_major}" && "${cur_major}" != "${new_major}" ]]; then
            log "MAJOR VERSION UPGRADE DETECTED (${cur_ver} -> ${new_ver}). Skipping auto-update."
            log "Major upgrades require a new Docker image + data migration (per A0 guidance)."
            log "To proceed manually: review migration notes, then set BLOCK_MAJOR_UPGRADES=false."
            notify "A0 Major Upgrade Held" "Detected ${cur_ver} -> ${new_ver}; auto-update skipped (major version)."
            log "=== Auto-Update Check Complete (major upgrade held) ==="
            exit 0
        fi
    fi
    # ---- end major-version guard ----

    notify "A0 Update Available" "New version detected. Starting backup + update."
}

# =============================================================================
# STEP 3: CREATE BACKUP
# =============================================================================

create_backup() {
    local backup_ts
    backup_ts=$(date '+%Y%m%d-%H%M%S')
    local backup_path="${BACKUP_DIR}/a0-backup-${backup_ts}"

    log "Creating backup at: ${backup_path}"
    mkdir -p "${backup_path}/volumes"

    # Create A0 native backup FIRST (requires container to be running)
    create_native_a0_backup "${backup_ts}" || true

    # Capture full container inspect for restoration reference
    log "  Saving container configuration..."
    docker inspect "${A0_CONTAINER_NAME}" > "${backup_path}/container-inspect.json" 2>/dev/null || true

    # Generate a reproducible docker run command from the current container
    log "  Generating docker-run command from current container..."
    generate_docker_run_cmd > "${backup_path}/docker-run-cmd.sh" 2>/dev/null || {
        log "  WARN: Could not auto-generate docker-run command."
        echo "#!/bin/bash" > "${backup_path}/docker-run-cmd.sh"
        echo "# Auto-generation failed. Recreate manually from container-inspect.json" >> "${backup_path}/docker-run-cmd.sh"
    }
    chmod +x "${backup_path}/docker-run-cmd.sh"

    # Backup each bind-mounted volume
    local mounts_json
    mounts_json=$(docker inspect --format '{{json .Mounts}}' "${A0_CONTAINER_NAME}")

    export BACKUP_DIR EXCLUDE_VOLUME_SOURCES
    echo "${mounts_json}" | python3 -c "
import json, sys, os
mounts = json.loads(sys.stdin.read())
exclude_dirs = set()
for p in os.environ.get('EXCLUDE_VOLUME_SOURCES', '').split(','):
    p = p.strip()
    if p:
        exclude_dirs.add(p)
backup_dir = os.environ.get('BACKUP_DIR', '')
if backup_dir:
    exclude_dirs.add(backup_dir)
for m in mounts:
    src = m.get('Source', '')
    mtype = m.get('Type', '')
    dst = m.get('Destination', '')
    if mtype == 'bind' and os.path.isdir(src) and src not in exclude_dirs:
        safe = dst.replace('/', '_').strip('_') or 'root'
        print(f'{src}|{dst}|{safe}')
" 2>/dev/null | while IFS='|' read -r src_dir dst_dir safe_name; do
        if [[ -z "${src_dir}" || -z "${dst_dir}" ]]; then continue; fi
        local dest_path="${backup_path}/volumes/${safe_name}"
        log "  Backing up volume: ${dst_dir} (container) -> ${safe_name}/"
        mkdir -p "${dest_path}"

        # Primary: use docker exec tar (reads as root inside container — no permission issues)
        if docker exec "${A0_CONTAINER_NAME}" tar -C "${dst_dir}" -cf - . 2>/dev/null \
            | tar -xf - -C "${dest_path}" 2>/dev/null; then
            log "    Done (via docker exec)."
        else
            # Fallback: rsync from host path
            log "    docker exec failed, falling back to rsync from host..."
            if [[ -d "${src_dir}" ]]; then
                if command -v rsync &> /dev/null; then
                    rsync -a "${src_dir}/" "${dest_path}/" 2>> "${LOG_FILE}" || {
                        log "  WARN: rsync fallback also failed for ${src_dir}"
                    }
                else
                    tar -cf - -C "${src_dir}" . 2>> "${LOG_FILE}" \
                        | tar -xf - -C "${dest_path}" 2>> "${LOG_FILE}" || {
                        log "  WARN: tar fallback also failed for ${src_dir}"
                    }
                fi
            else
                log "  WARN: Host path ${src_dir} not found — skipping volume."
            fi
        fi
    done

    # Save a snapshot of the image for rollback
    log "  Saving current image for rollback..."
    docker save "$(docker inspect --format '{{.Image}}' "${A0_CONTAINER_NAME}")" \
        -o "${backup_path}/a0-image.tar" 2>> "${LOG_FILE}" || {
        log "  WARN: Could not save image (disk space?). Rollback will require re-pull."
        rm -f "${backup_path}/a0-image.tar"
    }

    local backup_size
    backup_size=$(du -sh "${backup_path}" 2>/dev/null | cut -f1 || echo "unknown")
    log "Backup complete! Size: ${backup_size}"

    # Rotate old backups
    cleanup_old_backups
}

# =============================================================================
# GENERATE DOCKER RUN COMMAND FROM RUNNING CONTAINER
# =============================================================================

generate_docker_run_cmd() {
    docker inspect "${A0_CONTAINER_NAME}" | python3 -c "
import json, sys, shlex

data = json.load(sys.stdin)
if not data:
    sys.exit(1)

c = data[0]
hc = c.get('HostConfig', {})
cmd = ['docker', 'run', '-d']

# Name
cmd += ['--name', c['Name'].lstrip('/')]

# Restart policy
rp = hc.get('RestartPolicy', {}).get('Name', 'no')
if rp != 'no':
    if rp == 'on-failure':
        mrr = hc.get('RestartPolicy', {}).get('MaximumRetryCount', 0)
        cmd += ['--restart', f'on-failure:{mrr}']
    else:
        cmd += ['--restart', rp]

# Hostname
if c.get('Config', {}).get('Hostname'):
    cmd += ['--hostname', c['Config']['Hostname']]

# Ports
ports = c.get('NetworkSettings', {}).get('Ports', {})
bindings = hc.get('PortBindings', {})
for container_port, host_binds in bindings.items():
    for b in host_binds:
        p = ''
        if b.get('HostIp') and b['HostIp'] != '0.0.0.0':
            p += b['HostIp'] + ':'
        p += str(b['HostPort']) + ':'
        p += container_port
        cmd += ['-p', p]

# Volumes (bind mounts)
for m in c.get('Mounts', []):
    if m.get('Type') == 'bind':
        cmd += ['-v', f"{m['Source']}:{m['Destination']}"]

# Environment variables
for e in c.get('Config', {}).get('Env', []):
    cmd += ['-e', e]

# Network
net_mode = hc.get('NetworkMode', '')
if net_mode and net_mode != 'default':
    cmd += ['--network', net_mode]

# GPU support
device_requests = hc.get('DeviceRequests', [])
if device_requests:
    cmd += ['--gpus', 'all']

# Capabilities / privileged
if hc.get('Privileged', False):
    cmd += ['--privileged']
for cap in hc.get('CapAdd', []):
    cmd += ['--cap-add', cap]

# shm_size
shm = hc.get('ShmSize', 0)
if shm and shm != 67108864:  # skip default 64MB
    cmd += ['--shm-size', str(shm)]

# Image
cmd.append(c.get('Config', {}).get('Image', 'frdel/agent-zero-run:latest'))

# Entrypoint override (if any)
ep = c.get('Config', {}).get('Entrypoint')
if ep:
    cmd += ['--entrypoint', ' '.join(ep)]

print('#!/bin/bash')
print('# Auto-generated docker run command for Agent Zero')
print('# Review and edit before using!')
print()
print(' '.join(shlex.quote(a) for a in cmd))
"
}

# =============================================================================
# STEP 4: STOP CONTAINER AND UPDATE
# =============================================================================

stop_and_update() {
    if [[ -n "${COMPOSE_FILE}" ]]; then
        log "Stopping compose service: ${A0_SERVICE_NAME}"
        docker compose -f "${COMPOSE_FILE}" stop "${A0_SERVICE_NAME}" >> "${LOG_FILE}" 2>&1
        log "Removing old container..."
        docker compose -f "${COMPOSE_FILE}" rm -f "${A0_SERVICE_NAME}" >> "${LOG_FILE}" 2>&1
    else
        log "Stopping container: ${A0_CONTAINER_NAME}"
        docker stop "${A0_CONTAINER_NAME}" >> "${LOG_FILE}" 2>&1
        log "Removing old container..."
        docker rm "${A0_CONTAINER_NAME}" >> "${LOG_FILE}" 2>&1
    fi

    # Remove old images to free space
    log "Cleaning up old images..."
    docker image prune -f >> "${LOG_FILE}" 2>&1 || true
}

# =============================================================================
# STEP 5: RECREATE CONTAINER
# =============================================================================

recreate_container() {
    if [[ -n "${COMPOSE_FILE}" ]]; then
        # ---- Docker Compose path ----
        log "Recreating compose service: ${A0_SERVICE_NAME}"
        docker compose -f "${COMPOSE_FILE}" up -d "${A0_SERVICE_NAME}" >> "${LOG_FILE}" 2>&1
    elif [[ -n "${OVERRIDE_RUN_CMD}" ]]; then
        # ---- Custom override command ----
        log "Recreating container using override command..."
        eval "${OVERRIDE_RUN_CMD}" >> "${LOG_FILE}" 2>&1
    else
        # ---- Auto-detected docker run command ----
        local run_cmd
        run_cmd=$(generate_docker_run_cmd 2>/dev/null | tail -1)
        if [[ -z "${run_cmd}" ]]; then
            log "ERROR: Could not auto-generate docker run command!"
            log "You must manually recreate the container. Backup is at: ${BACKUP_DIR}"
            notify "A0 Update FAILED" "Container stopped but could not auto-recreate. Manual intervention needed!"
            exit 1
        fi
        log "Recreating container with auto-detected command..."
        log "  CMD: ${run_cmd}"
        eval "${run_cmd}" >> "${LOG_FILE}" 2>&1
    fi

    # Wait and verify
    log "Waiting for container to start..."
    sleep 5

    if docker ps --format '{{.Names}}' | grep -q "^${A0_CONTAINER_NAME}$"; then
        log "SUCCESS! Container '${A0_CONTAINER_NAME}' is running with the new image."
        local new_image
        new_image=$(docker inspect --format '{{.Image}}' "${A0_CONTAINER_NAME}" 2>/dev/null)
        log "New image digest: ${new_image:0:24}..."
        notify "A0 Updated Successfully" "Container recreated with new image."
    else
        log "ERROR: Container failed to start!"
        log "Check logs: docker logs ${A0_CONTAINER_NAME}"
        log "Backup available at: ${BACKUP_DIR}"
        notify "A0 Update FAILED" "Container did not start after update. Manual intervention needed!"
        # Attempt automatic rollback
        rollback
        exit 1
    fi
}

# =============================================================================
# ROLLBACK (on failure)
# =============================================================================

rollback() {
    log "Attempting automatic rollback..."

    # Find the most recent backup
    local latest_backup
    latest_backup=$(find "${BACKUP_DIR}" -maxdepth 1 -name "a0-backup-*" -type d | sort | tail -1)

    if [[ -z "${latest_backup}" ]]; then
        log "No backup found for rollback."
        return 1
    fi

    # Check if we have a saved image
    if [[ -f "${latest_backup}/a0-image.tar" ]]; then
        log "Loading saved image for rollback..."
        docker load -i "${latest_backup}/a0-image.tar" >> "${LOG_FILE}" 2>&1 || {
            log "ERROR: Failed to load rollback image."
            return 1
        }
    else
        log "No saved image in backup. Cannot rollback automatically."
        return 1
    fi

    # Try to recreate from the saved docker-run command
    if [[ -n "${COMPOSE_FILE}" ]]; then
        # Compose rollback — just recreate with the loaded image
        log "Rolling back via compose..."
        docker compose -f "${COMPOSE_FILE}" up -d "${A0_SERVICE_NAME}" >> "${LOG_FILE}" 2>&1
        sleep 5
        if docker ps --format '{{.Names}}' | grep -q "^${A0_CONTAINER_NAME}$"; then
            log "Rollback successful! Container is running with the previous image."
            notify "A0 Rollback Successful" "Container restored to previous version."
            return 0
        fi
    elif [[ -f "${latest_backup}/docker-run-cmd.sh" ]]; then
        local run_cmd
        run_cmd=$(tail -1 "${latest_backup}/docker-run-cmd.sh")
        if [[ -n "${run_cmd}" ]]; then
            docker rm -f "${A0_CONTAINER_NAME}" >> "${LOG_FILE}" 2>&1 || true
            log "Rolling back with command: ${run_cmd}"
            eval "${run_cmd}" >> "${LOG_FILE}" 2>&1
            sleep 5
            if docker ps --format '{{.Names}}' | grep -q "^${A0_CONTAINER_NAME}$"; then
                log "Rollback successful! Container is running with the previous image."
                notify "A0 Rollback Successful" "Container restored to previous version."
                return 0
            fi
        fi
    fi

    log "Rollback failed. Manual intervention required."
    log "Backup location: ${latest_backup}"
    return 1
}

# =============================================================================
# MAIN
# =============================================================================

install_cron() {
    local script_path
    script_path=$(readlink -f "$0" 2>/dev/null || echo "$0")

    # Check if cron entry already exists
    if crontab -l 2>/dev/null | grep -q "a0-docker-autoupdate"; then
        echo "Cron entry already exists. Current entry:"
        crontab -l 2>/dev/null | grep "a0-docker-autoupdate"
        echo ""
        echo "To update, remove the old entry first: sudo crontab -e"
        exit 0
    fi

    echo "Installing cron job to run at 3 AM daily..."
    echo "  Script: ${script_path}"
    echo ""

    (crontab -l 2>/dev/null; echo "0 3 * * * ${script_path}") | crontab -

    echo "Done! Cron entry added:"
    crontab -l | grep "a0-docker-autoupdate"
    echo ""
    echo "Logs will be written to: ${LOG_FILE}"
    exit 0
}

backup_only() {
    preflight
    log "=== Backup-only mode (no update) ==="
    create_backup
    log "==========================================="
    log "=== Agent Zero Backup Complete ==="
    log "==========================================="
}

main() {
    preflight
    check_for_update
    create_backup
    stop_and_update
    recreate_container

    log "==========================================="
    log "=== Agent Zero Docker Auto-Update Done  ==="
    log "==========================================="
}

if [[ $# -gt 0 ]]; then
    case "$1" in
        --install-cron)
            install_cron
            ;;
        --backup-only)
            backup_only
            exit $?
            ;;
    esac
fi

main "$@"

# =============================================================================
# CRON SETUP INSTRUCTIONS
# =============================================================================
#
# To schedule this script to run at 3 AM daily on your host:
#
#   Option A — Quick (run the script with --install-cron):
#
#       sudo ./a0-docker-autoupdate.sh --install-cron
#
#   Option B — Manual:
#
#   1. Copy script to your host:
#      cp a0-docker-autoupdate.sh /opt/Synthphony/OrchestrAI/scripts/a0-docker-autoupdate.sh
#   2. Make executable:
#      chmod +x /opt/Synthphony/OrchestrAI/scripts/a0-docker-autoupdate.sh
#   3. Open crontab:
#      sudo crontab -e
#   4. Add this line:
#
#       0 3 * * * /opt/Synthphony/OrchestrAI/scripts/a0-docker-autoupdate.sh
#
#   5. Save and exit.
#
# Log rotation — create /etc/logrotate.d/a0-autoupdate:
#
#       /opt/Synthphony/OrchestrAI/agentzero_update_backups/a0-autoupdate.log {
#           weekly
#           rotate 4
#           compress
#           missingok
#           notifempty
#       }
#
# =============================================================================
