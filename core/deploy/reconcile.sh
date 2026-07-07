#!/usr/bin/env bash
# THE RECONCILER (core-session script at P1-P2; a sam-LaunchAgent at P3): converges launchd
# to the registry. Registry is truth — enabled components get plists, everything else gets
# booted out. Refuses to run while the kill-switch marker exists.
# Modes: --dry-run (prints the plan, touches nothing) | --apply (renders + loads for real).
# --apply against the dev cluster is almost always a mistake (plists bake in PGHOST/PGPORT);
# the J3 path is ./core/deploy/live.sh reconcile --apply.
set -euo pipefail

PG_BIN="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
export PGHOST="${PGHOST:-$HOME/.claudio/sock}" PGPORT="${CLAUDIO_PGPORT:-5433}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PSQL=("$PG_BIN/psql" -U w_reconciler -d claudio -tAq -v ON_ERROR_STOP=1)
PLIST_DIR="$HOME/Library/LaunchAgents"

case "${1:-}" in
  --dry-run) MODE=dry ;;
  --apply)   MODE=apply ;;
  *) echo "usage: reconcile.sh --dry-run | --apply"; exit 1 ;;
esac

[ -f "$HOME/.claudio/STOPPED" ] && { echo "kill-switch marker present; reconciler refuses"; exit 1; }
echo "reconcile target: $PGHOST:$PGPORT (edge send: ${CLAUDIO_EDGE_SEND:-echo})"
if [ "$MODE" = "apply" ] && [ "$PGPORT" = "5433" ] && [ "${CLAUDIO_ALLOW_DEV_RECONCILE:-}" != "1" ]; then
  echo "refusing --apply against the dev cluster: plists would permanently point workers at dev"
  echo "and CLAUDIO_EDGE_SEND=echo silently drops outbound messages. The live deploy path is:"
  echo "  ./core/deploy/live.sh reconcile --apply"
  echo "(dev-cluster apply for debugging only: CLAUDIO_ALLOW_DEV_RECONCILE=1)"
  exit 1
fi
mkdir -p "$HOME/.claudio/logs"

# sed replacement escaping: & recalls the match, | is our delimiter, \ escapes
esc() { local v="$1"; v="${v//\\/\\\\}"; v="${v//&/\\&}"; v="${v//|/\\|}"; printf '%s' "$v"; }

# desired: enabled cron/queue/query components. db_role comes from config (w_<id> fallback);
# a plain daily cron ("M H * * *") renders StartCalendarInterval, hourly ("M * * * *") too;
# any other non-empty cron string is a hard error (a silent 900s fallback ran weeklies 670x).
"${PSQL[@]}" -c "select id || '|' || coalesce(config->>'db_role', 'w_' || id) || '|' ||
                        coalesce(trigger->>'schedule', '') || '|' ||
                        coalesce((trigger->>'interval_min')::int * 60,
                        case trigger->>'type' when 'queue' then 60 when 'query' then 60 else 900 end)
                 from l1.components
                 where status = 'enabled' and (trigger->>'type') in ('cron','queue','query')" |
while IFS='|' read -r id db_role sched interval; do
  if [[ "$sched" =~ ^([0-9]{1,2})[[:space:]]+([0-9]{1,2})[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*$ ]]; then
    when="daily at ${BASH_REMATCH[2]}:$(printf '%02d' "${BASH_REMATCH[1]}")"
    schedule_xml="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>${BASH_REMATCH[2]}</integer><key>Minute</key><integer>${BASH_REMATCH[1]}</integer></dict>"
  elif [[ "$sched" =~ ^([0-9]{1,2})[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*$ ]]; then
    when="hourly at :$(printf '%02d' "${BASH_REMATCH[1]}")"
    schedule_xml="<key>StartCalendarInterval</key><dict><key>Minute</key><integer>${BASH_REMATCH[1]}</integer></dict>"
  elif [ -n "$sched" ]; then
    echo "unparseable schedule '$sched' for $id (only 'M H * * *' and 'M * * * *' render); refusing" >&2
    exit 1
  else
    when="every ${interval}s"
    schedule_xml="<key>StartInterval</key><integer>$interval</integer>"
  fi
  plist="$PLIST_DIR/com.claudio.$id.plist"
  if [ "$MODE" = "dry" ]; then echo "would render+load $plist as $db_role ($when)"; continue; fi
  rendered="$(mktemp)"
  sed -e "s|__ID__|$(esc "$id")|g" -e "s|__SCHEDULE__|$schedule_xml|g" -e "s|__REPO__|$(esc "$REPO")|g" \
      -e "s|__HOME__|$(esc "$HOME")|g" -e "s|__DB_ROLE__|$(esc "$db_role")|g" \
      -e "s|__PGHOST__|$(esc "$PGHOST")|g" -e "s|__PGPORT__|$PGPORT|g" \
      -e "s|__EDGE_SEND__|$(esc "${CLAUDIO_EDGE_SEND:-echo}")|g" \
      "$REPO/core/deploy/launchd/com.claudio.template.plist" > "$rendered"
  plutil -lint "$rendered" >/dev/null || { echo "rendered plist for $id fails lint; refusing" >&2; rm -f "$rendered"; exit 1; }
  if cmp -s "$rendered" "$plist" && launchctl print "gui/$(id -u)/com.claudio.$id" >/dev/null 2>&1; then
    rm -f "$rendered"; echo "unchanged com.claudio.$id"; continue
  fi
  mv "$rendered" "$plist"
  launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist" || { sleep 1; launchctl bootstrap "gui/$(id -u)" "$plist"; }
  echo "loaded com.claudio.$id as $db_role ($when)"
done

# undesired: loaded com.claudio.* jobs with no enabled registry row
launchctl list 2>/dev/null | awk '/com\.claudio\./ {print $3}' | while read -r label; do
  id="${label#com.claudio.}"
  enabled="$("${PSQL[@]}" -c "select count(*) from l1.components where id = '$id' and status = 'enabled'")"
  if [ "$enabled" = "0" ]; then
    if [ "$MODE" = "dry" ]; then echo "would bootout $label"; else
      launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
      rm -f "$PLIST_DIR/$label.plist"
      echo "booted out $label"
    fi
  fi
done
echo "reconcile done"
