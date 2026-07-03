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

# desired: enabled cron/queue/query components. db_role comes from config (w_<id> fallback);
# a plain daily cron ("M H * * *") renders StartCalendarInterval, anything else an interval.
"${PSQL[@]}" -c "select id || '|' || coalesce(config->>'db_role', 'w_' || id) || '|' ||
                        coalesce(trigger->>'schedule', '') || '|' ||
                        coalesce((trigger->>'interval_min')::int * 60,
                        case trigger->>'type' when 'queue' then 60 when 'query' then 60 else 900 end)
                 from l1.components
                 where status = 'enabled' and (trigger->>'type') in ('cron','queue','query')" |
while IFS='|' read -r id db_role sched interval; do
  if [[ "$sched" =~ ^([0-9]{1,2})[[:space:]]([0-9]{1,2})[[:space:]]\*[[:space:]]\*[[:space:]]\*$ ]]; then
    when="daily at ${BASH_REMATCH[2]}:$(printf '%02d' "${BASH_REMATCH[1]}")"
    schedule_xml="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>${BASH_REMATCH[2]}</integer><key>Minute</key><integer>${BASH_REMATCH[1]}</integer></dict>"
  elif [[ "$sched" =~ ^([0-9]{1,2})[[:space:]]\*[[:space:]]\*[[:space:]]\*[[:space:]]\*$ ]]; then
    when="hourly at :$(printf '%02d' "${BASH_REMATCH[1]}")"
    schedule_xml="<key>StartCalendarInterval</key><dict><key>Minute</key><integer>${BASH_REMATCH[1]}</integer></dict>"
  else
    when="every ${interval}s"
    schedule_xml="<key>StartInterval</key><integer>$interval</integer>"
  fi
  plist="$PLIST_DIR/com.claudio.$id.plist"
  if [ "$DRY" = "--dry-run" ]; then echo "would render+load $plist as $db_role ($when)"; continue; fi
  sed -e "s|__ID__|$id|g" -e "s|__SCHEDULE__|$schedule_xml|g" -e "s|__REPO__|$REPO|g" \
      -e "s|__HOME__|$HOME|g" -e "s|__DB_ROLE__|$db_role|g" \
      "$REPO/core/deploy/launchd/com.claudio.template.plist" > "$plist"
  launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  echo "loaded com.claudio.$id as $db_role ($when)"
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
