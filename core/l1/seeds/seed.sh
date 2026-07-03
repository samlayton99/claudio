#!/usr/bin/env bash
# Apply the signed purpose contract + roles as claudio_core, one transaction.
# Idempotent; refuses an unsigned contract; DRAFT rows never seed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PG_BIN="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
export PGHOST="${PGHOST:-$HOME/.claudio/sock}" PGPORT="${CLAUDIO_PGPORT:-5433}"

python3 "$HERE/seed.py" "$@" | "$PG_BIN/psql" -U claudio_core -d claudio -tAq -v ON_ERROR_STOP=1
echo "seeded: $("$PG_BIN/psql" -U claudio_core -d claudio -tAq -c \
  "select count(*) || ' purpose rows, v' || (select max(version) from l1.purpose_versions) || ' priorities, ' ||
          (select count(*) from l1.roles) || ' roles' from l1.purpose")"
