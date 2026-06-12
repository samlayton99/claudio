#!/usr/bin/env bash
# Applies core/l1/migrations/*.sql in filename order, once each (tracked in l1.migrations).
# Runs the catalog hook after any new migration applies — schema changes only happen here,
# so SCHEMA.md regeneration is a migration-runner hook, not a poller (P9).
set -euo pipefail

PG_BIN="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
PGDATA="${CLAUDIO_PGDATA:-$HOME/.claudio/pg}"
export PGHOST="${PGHOST:-$HOME/.claudio/sock}" PGPORT="${CLAUDIO_PGPORT:-5433}"
DB="claudio"
DIR="$(cd "$(dirname "$0")" && pwd)"
PSQL=("$PG_BIN/psql" -U postgres -d "$DB" -v ON_ERROR_STOP=1 -q)

"${PSQL[@]}" -c "create schema if not exists l1;
create table if not exists l1.migrations (name text primary key, applied_at timestamptz not null default now());" >/dev/null

applied_any=0
for f in "$DIR"/migrations/*.sql; do
  name="$(basename "$f")"
  done_already="$("${PSQL[@]}" -tA -c "select 1 from l1.migrations where name = '$name'")"
  if [ "$done_already" != "1" ]; then
    echo "applying $name"
    "${PSQL[@]}" -f "$f"
    "${PSQL[@]}" -c "insert into l1.migrations(name) values ('$name')" >/dev/null
    applied_any=1
  fi
done

if [ "$applied_any" = "1" ]; then
  "$DIR/../pipes/catalog/generate.sh" || echo "catalog hook failed (non-fatal in dev)"
else
  echo "migrations up to date"
fi
