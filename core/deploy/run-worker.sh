#!/usr/bin/env bash
# THE WORKER RUNNER (core-owned, flock-guarded): resolve component -> read its parameters ->
# check for work (NEVER spawn a model on an empty queue) -> start_run -> assemble context from
# the agent's own folder (P10) -> exec the harness -> finish_run.
#
# P1 STATUS: the contract is real (context assembly + run accounting work end-to-end);
# the harness exec is wired at P2 with the first LLM worker (filer). Pipes (no-LLM) run now.
set -euo pipefail

PG_BIN="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
export PGHOST="${PGHOST:-$HOME/.claudio/sock}" PGPORT="${CLAUDIO_PGPORT:-5433}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
COMPONENT="${1:?usage: run-worker.sh <component-id> [db-role]}"
DB_ROLE="${2:-w_${COMPONENT}}"
PSQL=("$PG_BIN/psql" -U "$DB_ROLE" -d claudio -tAq -v ON_ERROR_STOP=1)

[ -f "$HOME/.claudio/STOPPED" ] && { echo "claudio is STOPPED (kill switch marker); refusing to run"; exit 1; }

# atomic mkdir lock (flock is Linux-only; this is the documented POSIX mapping)
LOCK="$HOME/.claudio/locks/$COMPONENT.lock.d"
mkdir -p "$(dirname "$LOCK")"
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -f "$LOCK/pid" ] && ! kill -0 "$(cat "$LOCK/pid")" 2>/dev/null; then
    rm -rf "$LOCK"; mkdir "$LOCK" || { echo "$COMPONENT lock race; skipping"; exit 0; }
  else
    echo "$COMPONENT already running"; exit 0
  fi
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT

# 1. resolve the component (registry is truth)
ROW="$("${PSQL[@]}" -c "select status || '|' || coalesce(definition_path,'') || '|' || (trigger->>'type') from l1.components where id = '$COMPONENT'")"
[ -n "$ROW" ] || { echo "unknown component $COMPONENT"; exit 1; }
STATUS="${ROW%%|*}"
[ "$STATUS" = "enabled" ] || { echo "$COMPONENT is $STATUS; not running"; exit 0; }
DEF_PATH="$(echo "$ROW" | cut -d'|' -f2)"

# 2. check for work via the component's own predicate (exit 'skipped' if none)
case "$("${PSQL[@]}" -c "select trigger->>'type' from l1.components where id = '$COMPONENT'")" in
  queue)
    N="$("${PSQL[@]}" -c "select count(*) from l1.messages where queue = '$COMPONENT' and status = 'posted'")"
    [ "$N" -gt 0 ] || exit 0 ;;
  query)
    N="$("${PSQL[@]}" -c "select count(*) from l1.intake where status = 'pending'")"  # v0: the filer predicate; per-component predicates land with their components
    [ "$N" -gt 0 ] || exit 0 ;;
esac

# 3. run accounting
RUN_ID="$("${PSQL[@]}" -c "select (l1.start_run('$COMPONENT'))->>'id'")"

# 4. assemble context from the agent's folder: context.md with {l1_call(...)} pulls resolved inline
CONTEXT=""
if [ -n "$DEF_PATH" ] && [ -f "$REPO/$DEF_PATH/context.md" ]; then
  while IFS= read -r line; do
    if [[ "$line" =~ \{([a-z_]+\([^}]*\))\} ]]; then
      call="${BASH_REMATCH[1]}"
      resolved="$("${PSQL[@]}" -c "select l1.$call" 2>/dev/null || echo "(unavailable: $call)")"
      CONTEXT+="${line//\{$call\}/$resolved}"$'\n'
    else
      CONTEXT+="$line"$'\n'
    fi
  done < "$REPO/$DEF_PATH/context.md"
fi

# 5. exec the harness (P2: claude -p / any headless MCP runner, per config.harness + prompt.md).
#    Until then: pipes implement main.sh in their folder; LLM workers are not yet wired.
OUTCOME="ok"; ERR=""
if [ -n "$DEF_PATH" ] && [ -x "$REPO/$DEF_PATH/main.sh" ]; then
  if ! CLAUDIO_CONTEXT="$CONTEXT" CLAUDIO_RUN_ID="$RUN_ID" CLAUDIO_DB_ROLE="$DB_ROLE" "$REPO/$DEF_PATH/main.sh"; then
    OUTCOME="failed"; ERR="main.sh exited nonzero"
  fi
else
  OUTCOME="skipped"; ERR="no executable for $COMPONENT yet (LLM harness wiring is P2)"
fi

"${PSQL[@]}" -c "select l1.finish_run('$RUN_ID'::uuid, '$OUTCOME', null, null, null, null, $([ -n "$ERR" ] && echo "'$ERR'" || echo null))" >/dev/null
echo "$COMPONENT: $OUTCOME"
