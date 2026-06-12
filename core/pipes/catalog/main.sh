#!/usr/bin/env bash
# run-worker entrypoint convention: every component folder exposes main.sh.
exec "$(dirname "$0")/generate.sh"
