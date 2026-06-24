#!/bin/bash
# Postiz Database Backup Script
# Runs daily via cron, keeps 7 days of backups

BACKUP_DIR="/opt/Synthphony/backups/myestro"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
KEEP_DAYS=7

mkdir -p $BACKUP_DIR

# Dump the database
docker exec myestro-postiz-postgres pg_dump -U postiz postiz > "${BACKUP_DIR}/postiz_${TIMESTAMP}.sql"

# Compress
gzip "${BACKUP_DIR}/postiz_${TIMESTAMP}.sql"

# Remove old backups
find $BACKUP_DIR -name "postiz_*.sql.gz" -mtime +$KEEP_DAYS -delete

echo "[$(date)] Backup completed: postiz_${TIMESTAMP}.sql.gz"
