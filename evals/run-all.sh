#!/usr/bin/env bash
# Run every suite from a clean db, each in isolation. The one command that proves the stack.
# Free — no model calls anywhere in these suites. Needs the dev cluster: ./core/deploy/dev.sh start
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SUITES=(
  "core/pipes/red-team/run.sh"
  "evals/contract/run.sh"
  "core/l1/seeds/test.sh"
  "core/pipes/scanner/test.sh"
  "core/pipes/edge/test.sh"
  "core/pipes/windows/imessage/test.sh"
  "core/agents/filer/test.sh"
  "core/agents/brief/test.sh"
  "core/deploy/test-reconcile.sh"
  "evals/e2e/run.sh"
)
FAILED=()
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
for s in "${SUITES[@]}"; do
  echo "=== $s ==="
  if ! "$REPO/core/deploy/dev.sh" reset >"$LOG" 2>&1; then
    echo "reset failed — is the dev cluster running? (./core/deploy/dev.sh start)"
    tail -3 "$LOG"; exit 1
  fi
  if "$REPO/$s" >"$LOG" 2>&1; then
    tail -1 "$LOG"
  else
    FAILED+=("$s")
    cat "$LOG"   # full output only for the failing suite
  fi
done
echo ""
if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "FAILED SUITES: ${FAILED[*]}"; exit 1
fi
echo "ALL SUITES GREEN"
