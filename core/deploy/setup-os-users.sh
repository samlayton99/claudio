#!/usr/bin/env bash
# STAGED HARDENING — OS users as trust tiers. DO NOT RUN BEFORE ITS STAGE (specs/04):
#   P1-P2 operative form: TWO users — `sam` + ONE worker uid (claudio-w0), everything <= c1.
#   P3: full split (claudio-p, claudio-w1, claudio-w0) + pf + Tailscale.
# Requires sudo; run interactively from a core session at the right phase gate.
set -euo pipefail

STAGE="${1:?usage: setup-os-users.sh p1|p3}"

make_user() {  # hidden, no-login-window service account
  local name="$1"; local uid="$2"
  if id "$name" >/dev/null 2>&1; then echo "$name exists"; return; fi
  sudo dscl . -create "/Users/$name"
  sudo dscl . -create "/Users/$name" UserShell /usr/bin/false
  sudo dscl . -create "/Users/$name" UniqueID "$uid"
  sudo dscl . -create "/Users/$name" PrimaryGroupID 20
  sudo dscl . -create "/Users/$name" NFSHomeDirectory "/var/claudio/$name"
  sudo dscl . -create "/Users/$name" IsHidden 1
  sudo mkdir -p "/var/claudio/$name"
  sudo chown "$name" "/var/claudio/$name"
  sudo chmod 700 "/var/claudio/$name"
  echo "created $name (uid $uid)"
}

case "$STAGE" in
  p1)
    make_user claudio-w0 510
    echo "P1 stage: one worker uid. Per-uid .pgpass (0600) is a manual core-session step."
    ;;
  p3)
    make_user claudio-w0 510
    make_user claudio-w1 511
    make_user claudio-p  512
    echo "P3 stage: full tier split. Next (manual, core session): per-uid .pgpass, pf anchors"
    echo "(core/deploy/pf/ — written at P3), Tailscale, tripwire cron, panel under claudio-p."
    ;;
  *) echo "stage must be p1 or p3"; exit 1 ;;
esac
