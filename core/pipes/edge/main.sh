#!/usr/bin/env bash
# The edge — the required ground-zero channel (specs/06). Capture-first inbound from chat.db;
# the ONLY outbound sender. One cycle = spool replay + inbound sweep + outbound drain + heartbeat.
# Resolves a message only after send success; a failed send stays claimed and the lease re-arms it.
# --loop [seconds] for resident mode (launchd at deploy).
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PG_BIN="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
export PGHOST="${PGHOST:-$HOME/.claudio/sock}" PGPORT="${CLAUDIO_PGPORT:-5433}"
ROLE="${CLAUDIO_DB_ROLE:-w_edge}"
STATE_DIR="${CLAUDIO_STATE_DIR:-$HOME/.claudio/state}"; mkdir -p "$STATE_DIR"
SEND_MODE="${CLAUDIO_EDGE_SEND:-echo}"   # echo (dev: log only) | imessage (deploy: Messages.app via osascript)
PSQL=("$PG_BIN/psql" -U "$ROLE" -d claudio -tAq -v ON_ERROR_STOP=1)

send_one() {  # send_one <to> <text> — returns nonzero on failure; caller leaves the claim
  local to="$1" text="$2"
  case "$SEND_MODE" in
    echo)
      printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$to" "$text" >> "$STATE_DIR/sent.log" ;;
    imessage)
      [ -n "$to" ] || { echo "edge: no user_handle configured for send"; return 1; }
      local esc="${text//\\/\\\\}"; esc="${esc//\"/\\\"}"
      osascript -e "tell application \"Messages\" to send \"$esc\" to buddy \"$to\" of (service 1 whose service type is iMessage)" ;;
    *)
      echo "edge: unknown send mode $SEND_MODE"; return 1 ;;
  esac
}

cycle() {
  # 1+2. spool replay + inbound sweep (never blocks outbound)
  python3 "$DIR/inbound.py" || true

  # 3. outbound drain: claim -> render (deterministic: payload.summary) -> send -> resolve
  local to line id text
  to="$("${PSQL[@]}" -c "select coalesce(config->'user_handles'->>0, '') from l1.components where id = 'edge-imessage'" 2>/dev/null)" || to=""
  while :; do
    line="$("${PSQL[@]}" -c "select (s.m->>'id') || e'\\x1f' || coalesce(s.m->'payload'->>'summary', '(no summary)') from (select l1.claim_message('user') as m) s where s.m is not null" 2>/dev/null)" || break
    [ -n "$line" ] || break
    id="${line%%$'\x1f'*}"; text="${line#*$'\x1f'}"
    if send_one "$to" "$text"; then
      "${PSQL[@]}" -c "select l1.resolve_message('$id'::uuid, jsonb_build_object('delivered', true, 'via', '$SEND_MODE'))" >/dev/null || true
    else
      echo "edge outbound: send failed; message stays claimed (lease re-arms it)"
      break
    fi
  done

  # 4. external dead-man heartbeat after a successful cycle (the alarm must not depend on the alarm channel)
  if [ -n "${CLAUDIO_DEADMAN_URL:-}" ]; then
    curl -fsS -m 10 "$CLAUDIO_DEADMAN_URL" >/dev/null 2>&1 || true
  fi
}

if [ "${1:-}" = "--loop" ]; then
  while :; do
    [ -f "$HOME/.claudio/STOPPED" ] && { echo "edge: STOPPED marker present; exiting"; exit 0; }
    cycle
    sleep "${2:-5}"
  done
else
  cycle
fi
