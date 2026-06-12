#!/usr/bin/env bash
# Run every suite from a clean db, each in isolation. The one command that proves the stack.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SUITES=(
  "core/pipes/red-team/run.sh"
  "evals/contract/run.sh"
  "core/pipes/scanner/test.sh"
  "core/pipes/edge/test.sh"
  "core/pipes/windows/imessage/test.sh"
  "core/agents/filer/test.sh"
  "core/agents/brief/test.sh"
)
FAILED=()
for s in "${SUITES[@]}"; do
  echo "=== $s ==="
  "$REPO/core/deploy/dev.sh" reset >/dev/null 2>&1 || { echo "reset failed"; exit 1; }
  if ! "$REPO/$s" 2>&1 | tail -1; then FAILED+=("$s"); fi
done
echo ""
if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "FAILED SUITES: ${FAILED[*]}"; exit 1
fi
echo "ALL SUITES GREEN"
