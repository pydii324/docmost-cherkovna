#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/home/pydi-ubuntu/docmost"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
BACKUP_ROOT="$HOME/backups/docmost"
DB_BACKUP_DIR="$BACKUP_ROOT/db"
STORAGE_BACKUP_DIR="$BACKUP_ROOT/storage"
RETENTION_DAYS=14
TIMESTAMP="$(date +%F_%H-%M-%S)"
DB_BACKUP_FILE="$DB_BACKUP_DIR/docmost_${TIMESTAMP}.sql.gz"
STORAGE_BACKUP_FILE="$STORAGE_BACKUP_DIR/docmost-storage_${TIMESTAMP}.tar.gz"
DB_TMP_FILE="$DB_BACKUP_FILE.tmp"
STORAGE_TMP_FILE="$STORAGE_BACKUP_FILE.tmp"

mkdir -p "$DB_BACKUP_DIR" "$STORAGE_BACKUP_DIR"

echo "Backing up database to $DB_BACKUP_FILE"
docker compose -f "$COMPOSE_FILE" exec -T db sh -lc '
  export PGPASSWORD="$POSTGRES_PASSWORD"
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"
' | gzip > "$DB_TMP_FILE"
mv "$DB_TMP_FILE" "$DB_BACKUP_FILE"

echo "Backing up Garage bucket to $STORAGE_BACKUP_FILE"
EXPORT_DIR="$(mktemp -d "$STORAGE_BACKUP_DIR/export.XXXXXX")"
trap 'rm -rf "$EXPORT_DIR"' EXIT

docker run --rm \
  --network docmost_default \
  --user "$(id -u):$(id -g)" \
  --env-file "$PROJECT_DIR/.env" \
  -v "$EXPORT_DIR:/export" \
  --entrypoint /bin/sh \
  rclone/rclone:1.72.0 -c '
    export RCLONE_CONFIG_GG_TYPE=s3 \
           RCLONE_CONFIG_GG_PROVIDER=Other \
           RCLONE_CONFIG_GG_ENDPOINT="$AWS_S3_ENDPOINT" \
           RCLONE_CONFIG_GG_REGION="$AWS_S3_REGION" \
           RCLONE_CONFIG_GG_ACCESS_KEY_ID="$AWS_S3_ACCESS_KEY_ID" \
           RCLONE_CONFIG_GG_SECRET_ACCESS_KEY="$AWS_S3_SECRET_ACCESS_KEY" \
           RCLONE_CONFIG_GG_FORCE_PATH_STYLE=true
    rclone copy "GG:$AWS_S3_BUCKET" /export'

tar -czf "$STORAGE_TMP_FILE" -C "$EXPORT_DIR" .
mv "$STORAGE_TMP_FILE" "$STORAGE_BACKUP_FILE"

find "$DB_BACKUP_DIR" -type f -name 'docmost_*.sql.gz' -mtime +$RETENTION_DAYS -delete
find "$STORAGE_BACKUP_DIR" -type f -name 'docmost-storage_*.tar.gz' -mtime +$RETENTION_DAYS -delete

echo "Backup completed successfully."
