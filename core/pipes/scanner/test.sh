#!/usr/bin/env bash
# Scanner component tests. Run after dev.sh reset.
set -uo pipefail
source "$(dirname "$0")/../red-team/lib.sh"
SCANNER="$(dirname "$0")/main.sh"

echo "== scanner: seed fixtures (panel) =="
expect_ok "seed-role" claudio_panel "select l1.upsert_role('disciple', 'Disciple', 1.5, 1::smallint)"
T1=$(sql claudio_panel "select (l1.create_task('Send agenda', now() + interval '2 hours'))->>'id'")
E1=$(sql claudio_panel "select (l1.create_expectation('Deck from Daniel', null, null, 'remind', now() - interval '1 hour'))->>'id'")
E2=$(sql claudio_panel "select (l1.create_expectation('Venue quote from Marco', null, null, 'auto_task', now() - interval '1 hour'))->>'id'")
E3=$(sql claudio_panel "select (l1.create_expectation('RSVP from the Hansens', null, now() - interval '5 days'))->>'id'")
# the clearance regression: a sensitivity-1 (disciple-floor) task due now MUST still get its reminder
TS=$(sql claudio_panel "select (l1.create_task('Print sacrament agenda', now() + interval '1 hour', null, 'disciple'))->>'id'")
expect_eq "s1-task-is-s1" claudio_panel "select sensitivity from l1.obligations where id = '$TS'::uuid" "1"

echo "== scanner: first sweep fires everything once =="
"$SCANNER" >/dev/null || { echo "FAIL scanner-run"; exit 1; }
expect_eq "due-reminders"      claudio_core "select count(*) from l1.messages where kind = 'notification' and payload->>'trigger' = 'due'" "3"
expect_eq "s1-reminder-fired"  claudio_core "select count(*) from l1.messages where payload->>'obligation_id' = '$TS'" "1"
expect_eq "followup-reminder"  claudio_core "select count(*) from l1.messages where payload->>'trigger' = 'follow_up'" "1"
expect_eq "auto-task-created"  claudio_core "select count(*) from l1.obligations where kind = 'task' and description = 'Follow up: Venue quote from Marco'" "1"
expect_eq "auto-task-linked"   claudio_core "select count(*) from l1.links where kind = 'derived_from' and to_id = '$E2'" "1"
expect_eq "missed-nudge"       claudio_core "select count(*) from l1.messages where kind = 'question' and payload->>'trigger' = 'missed'" "1"

echo "== scanner: second sweep is a no-op (idempotent) =="
N_BEFORE=$(sql claudio_core "select count(*) from l1.messages")
"$SCANNER" >/dev/null
expect_eq "idempotent-messages" claudio_core "select count(*) from l1.messages" "$N_BEFORE"
expect_eq "idempotent-autotask" claudio_core "select count(*) from l1.obligations where description like 'Follow up: Venue quote%'" "1"

echo "== scanner: a moved due date re-arms its reminder =="
expect_ok "move-due" claudio_panel "select l1.amend_obligation('$T1'::uuid, jsonb_build_object('due', (now() + interval '3 hours')::text))"
"$SCANNER" >/dev/null
expect_eq "re-armed" claudio_core "select count(*) from l1.messages where payload->>'obligation_id' = '$T1'" "2"

echo "== scanner: resolved obligations go quiet =="
expect_ok "resolve" claudio_panel "select l1.resolve_obligation('$E3'::uuid, 'missed')"
N_BEFORE=$(sql claudio_core "select count(*) from l1.messages")
"$SCANNER" >/dev/null
expect_eq "quiet-after-resolve" claudio_core "select count(*) from l1.messages" "$N_BEFORE"

echo ""
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
