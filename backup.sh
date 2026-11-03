#!/bin/sh

set -eu

# Fail early, with a clear message, if a setting is missing
: "${RESTIC_REPOSITORY:?is not set}" "${RESTIC_PASSWORD:?is not set}"
: "${AWS_ACCESS_KEY_ID:?is not set}" "${AWS_SECRET_ACCESS_KEY:?is not set}"
: "${BOOKSTACK_DB_ROOT_PASSWORD:?is not set}"
: "${AUTHENTIK_DB_PASSWORD:?is not set}" "${PTERODACTYL_DB_ROOT_PASSWORD:?is not set}"

# restic with the option Garage needs: address buckets by path (s3.example.com/bucket)
r() { restic -o s3.bucket-lookup=path "$@"; }

STAGING=/tmp/backup
mkdir -p "$STAGING"

echo "Dumping BookStack's database"
MYSQL_PWD="$BOOKSTACK_DB_ROOT_PASSWORD" mariadb-dump --host=bookstack-db --user=root \
  --single-transaction --routines --databases bookstack > "$STAGING/bookstack.sql"

echo "Dumping Authentik's database"
PGPASSWORD="$AUTHENTIK_DB_PASSWORD" pg_dump --host=authentik-db --username=authentik \
  --format=custom --file="$STAGING/authentik.dump" authentik

echo "Dumping the Pterodactyl Panel's database"
MYSQL_PWD="$PTERODACTYL_DB_ROOT_PASSWORD" mariadb-dump --host=pterodactyl-db --user=root \
  --single-transaction --routines --databases panel > "$STAGING/pterodactyl.sql"

echo "Copying Vaultwarden's database safely"
sqlite3 /data/vaultwarden/db.sqlite3 ".backup '$STAGING/vaultwarden.sqlite3'"

echo "Copying Forgejo's database safely"
sqlite3 /data/forgejo/gitea/gitea.db ".backup '$STAGING/forgejo.db'"

echo "Creating the restic repository if it doesn't exist yet"
r cat config > /dev/null 2>&1 || r init

echo "Backing up"
r backup --host apps --tag nightly \
  --exclude '/data/vaultwarden/db.sqlite3*' \
  --exclude '/data/forgejo/gitea/gitea.db*' \
  "$STAGING" /data/vaultwarden /data/bookstack /data/forgejo /data/pterodactyl-var

echo "Keeping the last 14 daily snapshots"
r forget --tag nightly --keep-daily 14 --prune

echo "Checking the repository"
r check

rm -rf "$STAGING"
echo "Backup finished"
