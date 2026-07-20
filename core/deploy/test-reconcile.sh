#!/usr/bin/env bash
# Reconciler dry-run tests: the J3 rehearsal. Enables the P2 roster in the registry and
# asserts the reconciler would schedule every component with the RIGHT db role and cadence.
# Dry-run only — touches no launchd state, writes no plists. Run after dev.sh reset.
set -uo pipefail
source "$(dirname "$0")/../pipes/red-team/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== reconcile: enable the P2 roster (panel) =="
for c in edge-imessage window-imessage filer brief scanner watchdog; do
  expect_ok "enable-$c" claudio_panel "select l1.set_component_status('$c', 'enabled')"
done

echo "== reconcile: dry-run schedules every component correctly =="
"$DIR/reconcile.sh" --dry-run >"$TMP/dry" 2>&1 || { echo "FAIL dry-run-exits-zero"; cat "$TMP/dry"; exit 1; }
check() { local name="$1" pat="$2"
  if grep -q "$pat" "$TMP/dry"; then PASS=$((PASS+1)); echo "PASS  $name"; else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$name"); echo "FAIL  $name (missing /$pat/)"; cat "$TMP/dry"; fi }
check "edge-as-w_edge"      'com.claudio.edge-imessage.plist as w_edge (every 60s)'
check "window-as-w_edge"    'com.claudio.window-imessage.plist as w_edge (daily at 5:15)'
check "filer-as-w_filer"    'com.claudio.filer.plist as w_filer (every 60s)'
check "brief-as-w_brief"    'com.claudio.brief.plist as w_brief (daily at 7:00)'
check "scanner-as-w_scanner" 'com.claudio.scanner.plist as w_scanner (hourly at :00)'
check "watchdog-as-w_watchdog" 'com.claudio.watchdog.plist as w_watchdog (every 900s)'
if ! grep -q "com.claudio.catalog" "$TMP/dry"; then PASS=$((PASS+1)); echo "PASS  manual-not-scheduled"; else
  FAIL=$((FAIL+1)); FAILED_NAMES+=("manual-not-scheduled"); echo "FAIL  manual-not-scheduled"; fi

echo "== reconcile: a disabled component is not scheduled (and critical refuses panel disable, P6) =="
expect_fail "critical-panel-disable-refused" claudio_panel "select l1.set_component_status('brief', 'disabled')" "critical_component"
expect_ok "disable-window" claudio_panel "select l1.set_component_status('window-imessage', 'disabled')"
"$DIR/reconcile.sh" --dry-run >"$TMP/dry2" 2>&1
# absence of a RENDER plan only: on a live-deployed machine the orphan sweep may correctly
# print "would bootout com.claudio.window-imessage" (launchd is machine-global)
if ! grep -q "would render+load.*window-imessage" "$TMP/dry2"; then PASS=$((PASS+1)); echo "PASS  disabled-dropped"; else
  FAIL=$((FAIL+1)); FAILED_NAMES+=("disabled-dropped"); echo "FAIL  disabled-dropped"; fi

echo "== reconcile: the rendered plist is valid launchd XML and carries the cluster env =="
schedule_xml="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer></dict>"
sed -e "s|__ID__|brief|g" -e "s|__SCHEDULE__|$schedule_xml|g" -e "s|__REPO__|$DIR/../..|g" \
    -e "s|__HOME__|$HOME|g" -e "s|__DB_ROLE__|w_brief|g" \
    -e "s|__PGHOST__|$HOME/.claudio/sock-live|g" -e "s|__PGPORT__|5434|g" -e "s|__EDGE_SEND__|imessage|g" \
    "$DIR/launchd/com.claudio.template.plist" > "$TMP/render.plist"
if plutil -lint "$TMP/render.plist" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "PASS  plist-lints"; else
  FAIL=$((FAIL+1)); FAILED_NAMES+=("plist-lints"); echo "FAIL  plist-lints"; plutil -lint "$TMP/render.plist"; fi
if grep -q "<key>CLAUDIO_PGPORT</key><string>5434</string>" "$TMP/render.plist" \
   && grep -q "$HOME/.local/bin" "$TMP/render.plist" \
   && ! grep -q "__PGHOST__\|__EDGE_SEND__" "$TMP/render.plist"; then
  PASS=$((PASS+1)); echo "PASS  plist-env-rendered"; else
  FAIL=$((FAIL+1)); FAILED_NAMES+=("plist-env-rendered"); echo "FAIL  plist-env-rendered"; fi

echo "== reconcile: kill switch refuses =="
mkdir -p "$TMP/home/.claudio" && touch "$TMP/home/.claudio/STOPPED"
if HOME="$TMP/home" "$DIR/reconcile.sh" --dry-run >"$TMP/killed" 2>&1; then
  FAIL=$((FAIL+1)); FAILED_NAMES+=("kill-switch-refuses"); echo "FAIL  kill-switch-refuses (ran anyway)"; else
  PASS=$((PASS+1)); echo "PASS  kill-switch-refuses"; fi
if grep -q "kill-switch marker present" "$TMP/killed"; then PASS=$((PASS+1)); echo "PASS  kill-switch-named"; else
  FAIL=$((FAIL+1)); FAILED_NAMES+=("kill-switch-named"); echo "FAIL  kill-switch-named"; fi

summary
