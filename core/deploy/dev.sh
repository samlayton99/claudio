#!/usr/bin/env bash
# Dev Postgres for claudio. Cluster lives OUTSIDE iCloud (~/Desktop and ~/Documents
# are synced; a synced data dir gets evicted). Port 5433 to avoid colliding with
# any default Postgres. Trust auth on the local socket only — dev cluster, dev data.
set -euo pipefail

PG_BIN="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
PGDATA="${CLAUDIO_PGDATA:-$HOME/.claudio/pg}"
PORT="${CLAUDIO_PGPORT:-5433}"
DB="claudio"
SOCKDIR="${CLAUDIO_PGSOCK:-$HOME/.claudio/sock}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"

export PGHOST="$SOCKDIR" PGPORT="$PORT"

cmd="${1:-status}"
case "$cmd" in
  init)
    [ -d "$PGDATA/base" ] && { echo "cluster exists at $PGDATA"; exit 0; }
    mkdir -p "$PGDATA" "$SOCKDIR"
    "$PG_BIN/initdb" -D "$PGDATA" -E UTF8 --locale=en_US.UTF-8 -U postgres >/dev/null
    {
      echo "port = $PORT"
      echo "unix_socket_directories = '$SOCKDIR'"
      echo "listen_addresses = ''"          # socket only; nothing on TCP
      echo "log_min_messages = warning"
    } >> "$PGDATA/postgresql.conf"
    echo "initialized $PGDATA (socket-only, port $PORT)"
    ;;
  start)
    "$PG_BIN/pg_ctl" -D "$PGDATA" -l "$PGDATA/server.log" start >/dev/null
    echo "started (socket $SOCKDIR)"
    ;;
  stop)
    "$PG_BIN/pg_ctl" -D "$PGDATA" stop >/dev/null && echo "stopped"
    ;;
  status)
    "$PG_BIN/pg_ctl" -D "$PGDATA" status || true
    ;;
  createdb)
    "$PG_BIN/createdb" -U postgres "$DB" 2>/dev/null && echo "created db $DB" || echo "db $DB exists"
    ;;
  migrate)
    "$REPO/core/l1/migrate.sh"
    ;;
  test)
    "$REPO/core/pipes/red-team/run.sh" && "$REPO/evals/contract/run.sh"
    ;;
  reset)
    # db-level reset (the cluster stays; migrations re-apply from zero)
    "$PG_BIN/psql" -U postgres -d postgres -c "drop database if exists $DB" >/dev/null
    "$0" createdb && "$0" migrate
    ;;
  psql)
    shift
    "$PG_BIN/psql" -U "${PGUSER_OVERRIDE:-postgres}" -d "$DB" "$@"
    ;;
  *)
    echo "usage: dev.sh {init|start|stop|status|createdb|migrate|test|reset|psql}"; exit 1
    ;;
esac
