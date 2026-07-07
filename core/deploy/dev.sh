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

# destructive verbs refuse when env points at the live cluster (leaked live.sh exports);
# the same CLAUDIO_LIVE_CONFIRM=DROP-LIVE that live.sh requires overrides here too
if [ "$cmd" = "reset" ] || [ "$cmd" = "test" ]; then
  if { [ "$PORT" = "5434" ] || [[ "$PGDATA" == *-live* ]] || [[ "$SOCKDIR" == *-live* ]]; } \
     && [ "${CLAUDIO_LIVE_CONFIRM:-}" != "DROP-LIVE" ]; then
    echo "refusing '$cmd': env points at the LIVE cluster ($PGDATA, port $PORT — real life data)"
    exit 1
  fi
fi

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
    if err="$("$PG_BIN/createdb" -U postgres "$DB" 2>&1)"; then echo "created db $DB"
    elif [[ "$err" == *"already exists"* ]]; then echo "db $DB exists"
    else echo "createdb failed: $err (is the cluster running? $0 start)"; exit 1; fi
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
    echo "usage: dev.sh {init|start|stop|status|createdb|migrate|test|reset|psql}  (psql honors PGUSER_OVERRIDE)"; exit 1
    ;;
esac
