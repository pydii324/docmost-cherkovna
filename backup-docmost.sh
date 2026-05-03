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
STORAGE_TMP_BASENAME="$(basename "$STORAGE_TMP_FILE")"

mkdir -p "$DB_BACKUP_DIR" "$STORAGE_BACKUP_DIR"

DOCMOST_CONTAINER_ID="$(docker compose -f "$COMPOSE_FILE" ps -q docmost)"

if [[ -z "$DOCMOST_CONTAINER_ID" ]]; then
  echo "Docmost container is not running. Start the stack before running backups." >&2
  exit 1
fi

STORAGE_VOLUME_NAME="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/app/data/storage"}}{{.Name}}{{end}}{{end}}' "$DOCMOST_CONTAINER_ID")"

if [[ -z "$STORAGE_VOLUME_NAME" ]]; then
  echo "Could not determine the storage volume mounted at /app/data/storage." >&2
  exit 1
fi

echo "Backing up database to $DB_BACKUP_FILE"
docker compose -f "$COMPOSE_FILE" exec -T db sh -lc '
  export PGPASSWORD="$POSTGRES_PASSWORD"
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"
' | gzip > "$DB_TMP_FILE"
mv "$DB_TMP_FILE" "$DB_BACKUP_FILE"

echo "Backing up storage volume $STORAGE_VOLUME_NAME to $STORAGE_BACKUP_FILE"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$STORAGE_VOLUME_NAME:/source:ro" \
  -v "$STORAGE_BACKUP_DIR:/backup" \
  alpine:3.20 \
  sh -lc 'tar -czf "/backup/$1" -C /source .' sh "$STORAGE_TMP_BASENAME"
mv "$STORAGE_TMP_FILE" "$STORAGE_BACKUP_FILE"

find "$DB_BACKUP_DIR" -type f -name 'docmost_*.sql.gz' -mtime +$RETENTION_DAYS -delete
find "$STORAGE_BACKUP_DIR" -type f -name 'docmost-storage_*.tar.gz' -mtime +$RETENTION_DAYS -delete

echo "Backup completed successfully."
