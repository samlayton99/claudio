#!/usr/bin/env bash
# THE MONTHLY RESTORE TEST (automated cron + checksum + alert — a backup that never restores
# is a hope, not a backup). Restores the latest snapshot to a scratch db and verifies.
set -euo pipefail

[ -f "$HOME/.claudio/STOPPED" ] && { echo "claudio is STOPPED (kill switch marker); refusing"; exit 1; }

PG_BIN="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
export PGHOST="${PGHOST:-$HOME/.claudio/sock}" PGPORT="${CLAUDIO_PGPORT:-5433}"
SCRATCH="claudio_restore_test"
TMP="$(mktemp -d)"
# scratch db holds live personal data mid-test — never leave it behind on a failed run
trap 'rm -rf "$TMP"; "$PG_BIN/psql" -U postgres -d postgres -qc "drop database if exists $SCRATCH" 2>/dev/null' EXIT

: "${RESTIC_REPOSITORY:?}" ; : "${RESTIC_PASSWORD_FILE:?}"

restic restore latest --target "$TMP" --include "*claudio.dump*"
DUMP="$(find "$TMP" -name claudio.dump | head -1)"
SUM="$(find "$TMP" -name claudio.dump.sha256 | head -1)"
[ -n "$DUMP" ] || { echo "ALERT: no dump in latest snapshot"; exit 1; }
(cd "$(dirname "$DUMP")" && shasum -a 256 -c "$(basename "$SUM")") || { echo "ALERT: checksum mismatch"; exit 1; }

"$PG_BIN/psql" -U postgres -d postgres -qc "drop database if exists $SCRATCH"
"$PG_BIN/createdb" -U postgres "$SCRATCH"
# pg_restore exits nonzero on ignorable ownership warnings; keep stderr for diagnosis
"$PG_BIN/pg_restore" -U postgres -d "$SCRATCH" --no-owner --role=postgres "$DUMP" || true
N_TABLES="$("$PG_BIN/psql" -U postgres -d "$SCRATCH" -tAqc "select count(*) from pg_tables where schemaname='l1'")"
N_AUDIT="$("$PG_BIN/psql" -U postgres -d "$SCRATCH" -tAqc "select count(*) from l1.audit" 2>/dev/null || echo 0)"
"$PG_BIN/psql" -U postgres -d postgres -qc "drop database $SCRATCH"

if [ "${N_TABLES:-0}" -lt 15 ]; then echo "ALERT: restore produced only $N_TABLES l1 tables"; exit 1; fi
echo "restore-test ok: $N_TABLES tables, $N_AUDIT audit rows ($(date))"
