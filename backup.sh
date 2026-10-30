#!/bin/sh

set -eu

# Fail early, with a clear message, if a setting is missing
: "${RESTIC_REPOSITORY:?is not set}" "${RESTIC_PASSWORD:?is not set}"
: "${AWS_ACCESS_KEY_ID:?is not set}" "${AWS_SECRET_ACCESS_KEY:?is not set}"
: "${BOOKSTACK_DB_ROOT_PASSWORD:?is not set}"

# restic with the option Garage needs: address buckets by path (s3.example.com/bucket)
r() { restic -o s3.bucket-lookup=path "$@"; }

STAGING=/tmp/backup
mkdir -p "$STAGING"

echo "Dumping BookStack's database"
MYSQL_PWD="$BOOKSTACK_DB_ROOT_PASSWORD" mariadb-dump --host=bookstack-db --user=root \
  --single-transaction --routines --databases bookstack > "$STAGING/bookstack.sql"

echo "Copying Vaultwarden's database safely"
sqlite3 /data/vaultwarden/db.sqlite3 ".backup '$STAGING/vaultwarden.sqlite3'"

echo "Creating the restic repository if it doesn't exist yet"
r cat config > /dev/null 2>&1 || r init

echo "Backing up"
r backup --host apps --tag nightly \
  --exclude '/data/vaultwarden/db.sqlite3*' \
  "$STAGING" /data/vaultwarden /data/bookstack

echo "Keeping the last 14 daily snapshots"
r forget --tag nightly --keep-daily 14 --prune

echo "Checking the repository"
r check

rm -rf "$STAGING"
echo "Backup finished"
