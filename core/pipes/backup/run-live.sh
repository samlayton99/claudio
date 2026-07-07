#!/usr/bin/env bash
# Live-backup entrypoint (launchd runs this daily): live-cluster env + restic destination,
# then backup.sh. Destination defaults to the LOCAL layer (~/.claudio/backup-local);
# ~/.claudio/backup.env overrides — that is where B2 goes when configured (queue item 4).
# First run bootstraps: generates the password file (0600) and inits the restic repo.
# A nonzero exit leaves ~/.claudio/backup-FAILED for the watchdog/panel to surface.
set -euo pipefail

[ -f "$HOME/.claudio/STOPPED" ] && { echo "claudio is STOPPED (kill switch marker); backup refuses"; exit 1; }

export PGHOST="$HOME/.claudio/sock-live" CLAUDIO_PGPORT=5434
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-$HOME/.claudio/backup-local}"
export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-$HOME/.claudio/restic.pass}"
[ -f "$HOME/.claudio/backup.env" ] && source "$HOME/.claudio/backup.env"

command -v restic >/dev/null || { echo "restic not installed (brew install restic)"; date > "$HOME/.claudio/backup-FAILED"; exit 1; }
if [ ! -f "$RESTIC_PASSWORD_FILE" ]; then
  if [ "$RESTIC_PASSWORD_FILE" = "$HOME/.claudio/restic.pass" ]; then
    (umask 177; openssl rand -base64 32 > "$RESTIC_PASSWORD_FILE")
    echo "generated $RESTIC_PASSWORD_FILE — BACK THIS FILE UP SEPARATELY (no password, no restore)"
  else
    echo "RESTIC_PASSWORD_FILE $RESTIC_PASSWORD_FILE missing"; date > "$HOME/.claudio/backup-FAILED"; exit 1
  fi
fi
restic snapshots >/dev/null 2>&1 || restic init

if "$(dirname "$0")/backup.sh"; then
  rm -f "$HOME/.claudio/backup-FAILED"
else
  date > "$HOME/.claudio/backup-FAILED"
  echo "backup FAILED: see ~/.claudio/logs/backup.err"; exit 1
fi
