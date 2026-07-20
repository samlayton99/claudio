#!/usr/bin/env bash
# THE LIVE CLUSTER — real life data, separate from dev so test suites can never touch it.
#   dev:  ~/.claudio/pg       port 5433 (dev.sh default; run-all.sh resets it freely)
#   live: ~/.claudio/pg-live  port 5434 (this wrapper; nothing defaults here)
# Both failure directions are guarded: forgotten env hits dev, and the destructive verbs
# (reset here, plus dev.sh's own live check) refuse without CLAUDIO_LIVE_CONFIRM=DROP-LIVE.
# Safe commands delegate to dev.sh under live env: ./live.sh init|start|stop|status|
# createdb|migrate|psql. `test` never runs against live. Extra: ./live.sh reconcile
# (the J3 deploy path — reconcile.sh with live env + real edge send) and ./live.sh
# autostart (one-time, loads the postgres + daily-backup LaunchAgents; the com.claudio-pg /
# com.claudio-backup labels avoid the reconciler's com.claudio.* namespace).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PG_BIN="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
export CLAUDIO_PGDATA="$HOME/.claudio/pg-live"
export CLAUDIO_PGPORT=5434
export CLAUDIO_PGSOCK="$HOME/.claudio/sock-live"
export PGHOST="$CLAUDIO_PGSOCK" PGPORT="$CLAUDIO_PGPORT"

case "${1:-}" in
  autostart)
    [ -d "$CLAUDIO_PGDATA/base" ] || { echo "live cluster not initialized; run ./live.sh init first"; exit 1; }
    if "$PG_BIN/pg_ctl" -D "$CLAUDIO_PGDATA" status >/dev/null 2>&1; then
      echo "live postgres already running under pg_ctl; ./live.sh stop first (KeepAlive would fight it)"; exit 1
    fi
    mkdir -p "$HOME/.claudio/logs"
    pg_plist="$HOME/Library/LaunchAgents/com.claudio-pg.plist"
    cat > "$pg_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.claudio-pg</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PG_BIN/postgres</string>
    <string>-D</string>
    <string>$CLAUDIO_PGDATA</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/.claudio/logs/pg-live.log</string>
  <key>StandardErrorPath</key><string>$HOME/.claudio/logs/pg-live.err</string>
</dict>
</plist>
EOF
    bk_plist="$HOME/Library/LaunchAgents/com.claudio-backup.plist"
    cat > "$bk_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.claudio-backup</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HERE/../pipes/backup/run-live.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>2</integer><key>Minute</key><integer>30</integer></dict>
  <key>StandardOutPath</key><string>$HOME/.claudio/logs/backup.log</string>
  <key>StandardErrorPath</key><string>$HOME/.claudio/logs/backup.err</string>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
EOF
    for p in "$pg_plist" "$bk_plist"; do
      launchctl bootout "gui/$(id -u)" "$p" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$p"
      echo "loaded $(basename "$p")"
    done
    ;;
  harden)
    # peer + pg_ident on the live socket (Sam's call, 2026-07-19): the OS uid is the
    # credential — no passwords, no secret files. Closes the initdb-trust hole where any
    # local staff-group uid could connect as claudio_core. Dev stays trust (suites need it).
    # P1-P2: everything runs as the GUI user (LaunchAgents), so it maps to all runtime roles;
    # claudio-w0 is pre-mapped to the worker roles for the P3 split. Re-runnable.
    [ -d "$CLAUDIO_PGDATA/base" ] || { echo "live cluster not initialized; run ./live.sh init first"; exit 1; }
    ME="$(id -un)"
    W_ROLES="w_filer w_merge w_wiki w_verifier w_lint w_orchestrator w_mirror w_brief w_scanner w_watchdog w_catalog w_hygiene w_approver"
    {
      echo "# claudio live — written by live.sh harden; the map IS the auth model"
      for role in postgres claudio_core claudio_panel w_edge w_reconciler $W_ROLES; do
        printf 'claudio  %s  %s\n' "$ME" "$role"
      done
      for role in $W_ROLES; do
        printf 'claudio  %s  %s\n' "claudio-w0" "$role"
      done
    } > "$CLAUDIO_PGDATA/pg_ident.conf"
    {
      echo "# claudio live — peer-only on the local socket (no TCP listener exists; w_test never maps)"
      echo "local  all  all  peer map=claudio"
    } > "$CLAUDIO_PGDATA/pg_hba.conf"
    if "$PG_BIN/pg_ctl" -D "$CLAUDIO_PGDATA" status >/dev/null 2>&1; then
      "$PG_BIN/pg_ctl" -D "$CLAUDIO_PGDATA" reload >/dev/null && echo "reloaded live auth: peer map=claudio"
    else
      echo "written; applies when the live cluster starts"
    fi
    ;;
  reconcile)
    shift
    export CLAUDIO_EDGE_SEND="${CLAUDIO_EDGE_SEND:-imessage}"
    exec "$HERE/reconcile.sh" "$@"
    ;;
  stop)
    # after autostart, pg_ctl stop is undone by KeepAlive within seconds — bootout instead
    if launchctl print "gui/$(id -u)/com.claudio-pg" >/dev/null 2>&1; then
      launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.claudio-pg.plist"
      echo "booted out com.claudio-pg (launchd-managed live postgres)"
    else
      exec "$HERE/dev.sh" stop
    fi
    ;;
  reset)
    if [ "${CLAUDIO_LIVE_CONFIRM:-}" != "DROP-LIVE" ]; then
      echo "refusing: 'reset' DROPS THE LIVE DATABASE (real life data, no undo)."
      echo "dev resets are ./core/deploy/dev.sh reset. If you truly mean live:"
      echo "  CLAUDIO_LIVE_CONFIRM=DROP-LIVE $0 reset"
      exit 1
    fi
    exec "$HERE/dev.sh" reset
    ;;
  test)
    echo "refusing: suites insert fixtures and assume a fresh db; they never run against live."
    echo "use ./core/deploy/dev.sh test (or ./evals/run-all.sh) on the dev cluster."
    exit 1
    ;;
  init|start|status|createdb|migrate|psql)
    exec "$HERE/dev.sh" "$@"
    ;;
  *)
    echo "usage: live.sh {init|start|stop|status|createdb|migrate|psql|harden|reconcile|autostart}"
    exit 1
    ;;
esac
