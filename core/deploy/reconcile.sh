#!/usr/bin/env bash
# THE RECONCILER (core-session script at P1-P2; a sam-LaunchAgent at P3): converges launchd
# to the registry. Registry is truth — enabled components get plists, everything else gets
# booted out. Refuses to run while the kill-switch marker exists.
set -euo pipefail

PG_BIN="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
export PGHOST="${PGHOST:-$HOME/.claudio/sock}" PGPORT="${CLAUDIO_PGPORT:-5433}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PSQL=("$PG_BIN/psql" -U w_reconciler -d claudio -tAq -v ON_ERROR_STOP=1)
PLIST_DIR="$HOME/Library/LaunchAgents"
DRY="${1:-}"

[ -f "$HOME/.claudio/STOPPED" ] && { echo "kill-switch marker present; reconciler refuses"; exit 1; }
mkdir -p "$HOME/.claudio/logs"

# desired: enabled cron/queue/query components
"${PSQL[@]}" -c "select id || '|' || coalesce((trigger->>'interval_min')::int * 60,
                        case trigger->>'type' when 'queue' then 60 when 'query' then 60 else 900 end)
                 from l1.components
                 where status = 'enabled' and (trigger->>'type') in ('cron','queue','query')" |
while IFS='|' read -r id interval; do
  plist="$PLIST_DIR/com.claudio.$id.plist"
  if [ "$DRY" = "--dry-run" ]; then echo "would render+load $plist (every ${interval}s)"; continue; fi
  sed -e "s|__ID__|$id|g" -e "s|__INTERVAL__|$interval|g" -e "s|__REPO__|$REPO|g" \
      -e "s|__HOME__|$HOME|g" -e "s|__DB_ROLE__|w_$id|g" \
      "$REPO/core/deploy/launchd/com.claudio.template.plist" > "$plist"
  launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  echo "loaded com.claudio.$id (every ${interval}s)"
done

# undesired: loaded com.claudio.* jobs with no enabled registry row
launchctl list 2>/dev/null | awk '/com\.claudio\./ {print $3}' | while read -r label; do
  id="${label#com.claudio.}"
  enabled="$("${PSQL[@]}" -c "select count(*) from l1.components where id = '$id' and status = 'enabled'")"
  if [ "$enabled" = "0" ]; then
    if [ "$DRY" = "--dry-run" ]; then echo "would bootout $label"; else
      launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
      rm -f "$PLIST_DIR/$label.plist"
      echo "booted out $label"
    fi
  fi
done
echo "reconcile done"
