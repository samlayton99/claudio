#!/usr/bin/env bash
# Watchdog component tests. Run after dev.sh reset.
set -uo pipefail
source "$(dirname "$0")/../red-team/lib.sh"
WD="$(dirname "$0")/main.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# never touch the real ~/.claudio markers from a test
export CLAUDIO_BACKUP_MARKER="$TMP/backup-FAILED" CLAUDIO_WATCHDOG_HEARTBEAT="$TMP/heartbeat"

echo "== watchdog: expired claims reaped (the backstop, 02) =="
sql w_filer "select l1.post_message('orchestrator', 'handoff', '{\"summary\":\"do the thing\"}')" >/dev/null
MID=$(sql claudio_core "select id from l1.messages where queue = 'orchestrator'")
sql claudio_core "select l1.claim_message('orchestrator')" >/dev/null
sql claudio_core "update l1.messages set claimed_at = now() - interval '1 hour' where id = '$MID'::uuid" >/dev/null
"$WD" >/dev/null || { echo "FAIL watchdog-run"; exit 1; }
expect_eq "claim-reaped" claudio_core "select status from l1.messages where id = '$MID'::uuid" "posted"

echo "== watchdog: schedule miss -> one alert, deduped across sweeps =="
sql claudio_panel "select l1.set_component_status('scanner', 'enabled')" >/dev/null
"$WD" >/dev/null
expect_eq "miss-alert" claudio_core \
  "select count(*) from l1.messages where queue = 'user' and kind = 'notification' and payload->>'check' = 'miss' and payload->>'component_id' = 'scanner'" "1"
"$WD" >/dev/null
expect_eq "miss-dedup" claudio_core \
  "select count(*) from l1.messages where payload->>'check' = 'miss' and payload->>'component_id' = 'scanner'" "1"

echo "== watchdog: recovery goes quiet; a NEW silence is a NEW incident =="
RID=$(sql w_scanner "select (l1.start_run('scanner'))->>'id'")
sql w_scanner "select l1.finish_run('$RID'::uuid, 'ok', null, null, null, null, null)" >/dev/null
"$WD" >/dev/null
expect_eq "quiet-after-run" claudio_core \
  "select count(*) from l1.messages where payload->>'check' = 'miss' and payload->>'component_id' = 'scanner'" "1"
sql claudio_core "update l1.runs set started_at = now() - interval '4 hours', finished_at = now() - interval '4 hours' where id = '$RID'::uuid" >/dev/null
"$WD" >/dev/null
expect_eq "new-incident" claudio_core \
  "select count(*) from l1.messages where payload->>'check' = 'miss' and payload->>'component_id' = 'scanner'" "2"

echo "== watchdog: stuck run (> 2x trailing median, floored) =="
sql claudio_core "insert into l1.runs (component_id, started_at, finished_at, outcome) values
  ('brief', now() - interval '1 day', now() - interval '1 day' + interval '60 seconds', 'ok'),
  ('brief', now() - interval '2 days', now() - interval '2 days' + interval '80 seconds', 'ok')" >/dev/null
SID=$(sql claudio_core "with s as (insert into l1.runs (component_id, started_at) values ('brief', now() - interval '45 minutes') returning id) select id from s")
"$WD" >/dev/null
expect_eq "stuck-alert" claudio_core \
  "select count(*) from l1.messages where payload->>'check' = 'stuck' and payload->>'component_id' = 'brief'" "1"
"$WD" >/dev/null
expect_eq "stuck-dedup" claudio_core \
  "select count(*) from l1.messages where payload->>'check' = 'stuck'" "1"
expect_eq "fresh-run-not-stuck" claudio_core \
  "select count(*) from l1.messages where payload->>'check' = 'stuck' and payload->>'component_id' = 'scanner'" "0"

echo "== watchdog: stale posted messages, per queue =="
sql w_filer "select l1.post_message('filer', 'handoff', '{\"summary\":\"forgotten\"}')" >/dev/null
sql claudio_core "update l1.messages set posted_at = now() - interval '3 days' where queue = 'filer'" >/dev/null
"$WD" >/dev/null
expect_eq "stale-alert" claudio_core \
  "select count(*) from l1.messages where payload->>'check' = 'stale' and payload->>'queue' = 'filer'" "1"
"$WD" >/dev/null
expect_eq "stale-dedup" claudio_core \
  "select count(*) from l1.messages where payload->>'check' = 'stale' and payload->>'queue' = 'filer'" "1"
expect_eq "own-alerts-never-stale" claudio_core \
  "select count(*) from l1.messages where payload->>'check' = 'stale' and payload->>'queue' = 'user'" "0"

echo "== watchdog: backup-FAILED marker surfaces =="
date > "$CLAUDIO_BACKUP_MARKER"
"$WD" >/dev/null
expect_eq "backup-alert" claudio_core \
  "select count(*) from l1.messages where payload->>'check' = 'backup'" "1"
"$WD" >/dev/null
expect_eq "backup-dedup" claudio_core \
  "select count(*) from l1.messages where payload->>'check' = 'backup'" "1"
rm -f "$CLAUDIO_BACKUP_MARKER"
"$WD" >/dev/null
expect_eq "backup-quiet-after-clear" claudio_core \
  "select count(*) from l1.messages where payload->>'check' = 'backup'" "1"

echo "== watchdog: heartbeat for the external dead-man; alerts are s0 user notifications =="
if [ -f "$CLAUDIO_WATCHDOG_HEARTBEAT" ]; then PASS=$((PASS+1)); echo "PASS  heartbeat-file";
else FAIL=$((FAIL+1)); FAILED_NAMES+=("heartbeat-file"); echo "FAIL  heartbeat-file"; fi
expect_eq "alerts-are-s0-user-notifications" claudio_core \
  "select count(*) from l1.messages where payload->>'trigger' = 'watchdog' and not (queue = 'user' and kind = 'notification' and sensitivity = 0)" "0"

summary
