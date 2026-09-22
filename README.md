# docmost-cherkovna

Deployment for the self-hosted Docmost instance at https://docs.rudinr.com.

Files are stored in S3, served by a single-node [Garage](https://garagehq.deuxfleurs.fr/)
container defined in this compose file. Moving to an external S3 provider later is a
change of the `AWS_S3_*` values in `.env` plus one `rclone copy`.

## Setup on a clean machine

```bash
git clone <this repo> docmost && cd docmost
cp .env.example .env
# fill in every CHANGE_ME; generate secrets with: openssl rand -hex 32
chmod 600 .env
docker compose up -d
```

Garage creates its cluster layout, access key and bucket on first boot from the
`AWS_S3_*` values in `.env`. No manual `garage layout` steps are needed.

## Backups

`backup-docmost.sh` runs nightly at 02:00 from cron and writes two artifacts to
`~/backups/docmost/`:

- `db/docmost_<timestamp>.sql.gz` — `pg_dump` of the database
- `storage/docmost-storage_<timestamp>.tar.gz` — every object in the bucket,
  pulled through the S3 API with `rclone`

Retention is 14 days. Logs go to `~/backups/docmost/backup.log`.

### Restore

```bash
# database
gunzip -c db/docmost_<timestamp>.sql.gz | docker compose exec -T db \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'

# files
mkdir /tmp/restore && tar xzf storage/docmost-storage_<timestamp>.tar.gz -C /tmp/restore
docker run --rm --network docmost_default --env-file .env \
  -v /tmp/restore:/restore --entrypoint /bin/sh rclone/rclone:1.72.0 -c '
    export RCLONE_CONFIG_GG_TYPE=s3 RCLONE_CONFIG_GG_PROVIDER=Other \
           RCLONE_CONFIG_GG_ENDPOINT="$AWS_S3_ENDPOINT" \
           RCLONE_CONFIG_GG_REGION="$AWS_S3_REGION" \
           RCLONE_CONFIG_GG_ACCESS_KEY_ID="$AWS_S3_ACCESS_KEY_ID" \
           RCLONE_CONFIG_GG_SECRET_ACCESS_KEY="$AWS_S3_SECRET_ACCESS_KEY" \
           RCLONE_CONFIG_GG_FORCE_PATH_STYLE=true
    rclone copy /restore "GG:$AWS_S3_BUCKET"'
```

The tarball holds the original files under their original keys, so it restores
into any S3 provider, or straight into `/app/data/storage` if you switch
`STORAGE_DRIVER` back to `local`.

## Upgrades

`upgrade-docmost.sh` runs Sundays at 03:00 from cron. It only touches the
`docmost` service; the Garage version is pinned on purpose.
