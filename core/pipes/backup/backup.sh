#!/usr/bin/env bash
# Encrypted backup: pg_dump (custom format) + wiki/ + archive/ via restic.
# Destination DEFAULTS to Backblaze B2 + a private git remote per specs — UNCONFIRMED
# (docs/questions-queue.md): set RESTIC_REPOSITORY + RESTIC_PASSWORD_FILE before first run.
# Scheduling (daily cron) happens at deploy, not here.
set -euo pipefail

PG_BIN="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
export PGHOST="${PGHOST:-$HOME/.claudio/sock}" PGPORT="${CLAUDIO_PGPORT:-5433}"
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
STAGE="$HOME/.claudio/backup-stage"

: "${RESTIC_REPOSITORY:?set RESTIC_REPOSITORY (e.g. b2:claudio-backup:/) — destination is a queue item until Sam confirms}"
: "${RESTIC_PASSWORD_FILE:?set RESTIC_PASSWORD_FILE (0600, outside the repo)}"

mkdir -p "$STAGE"
"$PG_BIN/pg_dump" -U postgres -d claudio -Fc -f "$STAGE/claudio.dump"
shasum -a 256 "$STAGE/claudio.dump" > "$STAGE/claudio.dump.sha256"

restic backup "$STAGE/claudio.dump" "$STAGE/claudio.dump.sha256" "$REPO/wiki" "$REPO/archive" \
  --tag claudio --tag "$(date +%Y-%m-%d)"
restic forget --tag claudio --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune

echo "backup ok: $(date)"
