#!/usr/bin/env bash
# edge-gv — the GV channel edge. Thin wrapper: run-worker.sh handles lock, STOPPED marker,
# registry status, and run accounting; the cycle itself is main.py (deterministic, no LLM).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$DIR/main.py"
