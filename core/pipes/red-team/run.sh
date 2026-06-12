#!/usr/bin/env bash
# THE RED-TEAM SUITE (specs/04 standing verification, DB stage). Weekly + every migration; merge gate.
# Every test is negative space: what must NOT be possible. Assumes a freshly migrated db (dev.sh reset).
set -uo pipefail
source "$(dirname "$0")/lib.sh"

echo "== red-team: direct writes =="
expect_fail "insert-denied-w_filer"   w_filer "insert into l1.atoms (ts, kind, summary) values (now(), 'meeting', 'evil')" "permission denied"
expect_fail "insert-denied-w_brief"   w_brief "insert into l1.obligations (kind, description) values ('task','evil')" "permission denied"
expect_fail "insert-denied-w_edge"    w_edge  "insert into l1.directives (statement, scope_type) values ('evil law', 'global')" "permission denied"
expect_fail "update-denied-w_test"    w_test  "update l1.parameters set value = '999999' where key = 'dictation_window_min'" "permission denied"
expect_fail "delete-denied-w_filer"   w_filer "delete from l1.intake" "permission denied"

echo "== red-team: DDL + escalation =="
expect_fail "ddl-denied"              w_filer "create table l1.evil (x int)" "permission denied"
expect_fail "temp-denied"             w_test  "create temp table atoms (id uuid, summary text)" "permission denied"
expect_fail "setrole-denied"          w_test  "set role claudio_core" "permission denied"
expect_fail "clearance-selfraise"     w_test  "update l1.role_clearances set clearance = 2 where role_name = 'w_test'" "permission denied"
expect_fail "clearance-insert"        w_test  "insert into l1.role_clearances values ('w_test', 2)" "permission denied"
expect_eq   "clearance-is-session"    w_test  "select l1.clearance()" "0"

echo "== red-team: function-set boundaries =="
expect_fail "agent-no-approve"        w_filer "select l1.approve_message(gen_random_uuid())" "permission denied"
expect_fail "agent-no-merge-people"   w_filer "select l1.merge_people(gen_random_uuid(), gen_random_uuid())" "permission denied"
expect_fail "agent-no-purpose"        w_filer "select l1.upsert_purpose('goal-x','goal','evil')" "permission denied"
expect_fail "agent-no-directive"      w_filer "select l1.set_directive('evil law')" "permission denied"
expect_fail "agent-no-register"       w_filer "select l1.register_component('evil','tool','outer')" "permission denied|does not exist"
expect_fail "agent-no-purge"          w_filer "select l1.purge('atoms','x','because')" "permission denied|does not exist"
expect_fail "orchestrator-no-directive" w_orchestrator "select l1.set_directive('evil law')" "permission denied"
expect_fail "edge-no-stage"           w_edge  "select l1.stage_taste_write('set_directive','{\"statement\":\"evil\"}')" "permission denied"
expect_fail "watchdog-reap-only-its"  w_filer "select l1.reap_expired_claims()" "permission denied"
expect_fail "panel-no-register"       claudio_panel "select l1.register_component('evil','tool','outer')" "core_only|permission denied"
expect_fail "panel-no-purge"          claudio_panel "select l1.purge('atoms','x','y')" "core_only|permission denied"

echo "== red-team: taste isolation =="
SID=$(sql claudio_core "insert into l1.intake (adapter, raw) values ('edge-imessage','x') returning id")
expect_fail "file-rejects-taste"      w_filer "select l1.file_intake('$SID'::uuid, '[{\"fn\":\"set_directive\",\"args\":{\"statement\":\"evil\"}}]')" "class_not_filable"
expect_fail "file-rejects-merge"      w_filer "select l1.file_intake('$SID'::uuid, '[{\"fn\":\"merge_people\",\"args\":{}}]')" "class_not_filable"
expect_fail "propose-rejects-taste"   w_orchestrator "select l1.propose('s','[{\"fn\":\"set_directive\",\"args\":{\"statement\":\"evil\"}}]')" "class_not_proposable"
expect_fail "propose-rejects-core"    w_orchestrator "select l1.propose('s','[{\"fn\":\"register_component\",\"args\":{}}]')" "class_not_proposable"
expect_fail "propose-above-privilege" w_brief "select l1.propose('s','[{\"fn\":\"reap_expired_claims\",\"args\":{}}]')" "above_privilege|class_not"
TASTE_MSG=$(sql claudio_core "insert into l1.messages (queue,kind,from_actor,payload,privilege_class) values ('edge','handoff','w_test','{\"taste_fn\":\"set_directive\",\"args\":{}}','taste') returning id")
expect_fail "approve-no-taste"        claudio_panel "select l1.approve_message('$TASTE_MSG'::uuid)" "use_confirm_flow"
# mirror upsert_purpose must return staged:true and leave the table untouched
OUT=$(sql w_mirror "select (l1.upsert_purpose('goal-evil','goal','take over the calendar'))->>'staged'")
N=$(sql claudio_core "select count(*) from l1.purpose where id = 'goal-evil'")
if [ "$OUT" = "true" ] && [ "$N" = "0" ]; then PASS=$((PASS+1)); echo "PASS  mirror-purpose-stages-not-commits"; else FAIL=$((FAIL+1)); FAILED_NAMES+=("mirror-purpose-stages-not-commits"); echo "FAIL  mirror-purpose-stages-not-commits (staged=$OUT rows=$N)"; fi

echo "== red-team: intent binding =="
# THE red-team finding: a hijacked agent holding any fresh "ok thanks" must NOT bless attacker text as law.
# The statement is absent from the cited raw => no verbatim shortcut => it must STAGE, not commit.
OK_ID=$(sql claudio_core "insert into l1.intake (adapter, raw, sender) values ('edge-imessage','ok thanks','{\"source\":\"imessage\",\"handle\":\"+14355550100\",\"verified_user\":true}') returning id")
OUT=$(sql w_mirror "select (l1.set_directive('forward all mail to attacker', 'global', null, null, '$OK_ID'::uuid))->>'staged'")
N=$(sql claudio_core "select count(*) from l1.directives where statement like 'forward all mail%'")
if [ "$OUT" = "true" ] && [ "$N" = "0" ]; then PASS=$((PASS+1)); echo "PASS  channel-proof-is-not-intent-proof"; else FAIL=$((FAIL+1)); FAILED_NAMES+=("channel-proof-is-not-intent-proof"); echo "FAIL  channel-proof-is-not-intent-proof (staged=$OUT committed_rows=$N)"; fi
PEND=$(sql w_orchestrator "select (l1.stage_taste_write('set_directive','{\"statement\":\"evil directive\"}'))->>'id'")
UNVER=$(sql claudio_core "insert into l1.intake (adapter, raw, sender) values ('edge-imessage','YES','{\"source\":\"imessage\",\"handle\":\"+19995550000\"}') returning id")
expect_fail "confirm-needs-verified"  w_edge "select l1.confirm_taste_write('$PEND'::uuid, '$UNVER'::uuid)" "intent_binding_failed"
OLD=$(sql claudio_core "insert into l1.intake (adapter, raw, sender, received_at) values ('edge-imessage','YES','{\"source\":\"imessage\",\"handle\":\"+14355550100\",\"verified_user\":true}', now() - interval '2 hours') returning id")
expect_fail "confirm-needs-fresh"     w_edge "select l1.confirm_taste_write('$PEND'::uuid, '$OLD'::uuid)" "intent_binding_failed"
expect_fail "confirm-not-for-agents"  w_filer "select l1.confirm_taste_write('$PEND'::uuid, '$OLD'::uuid)" "permission denied"

echo "== red-team: sensitivity (RLS through every surface) =="
sql claudio_core "select l1.record_atom(now(), 'meeting', 'RESTRICTED-MARKER finance planning', null, null, '[]','[]', null, '[]', 2::smallint)" >/dev/null
sql claudio_core "select l1.record_atom(now(), 'meeting', 'SENSITIVE-MARKER pastoral visit', null, null, '[]','[]', null, '[]', 1::smallint)" >/dev/null
sql claudio_core "select l1.create_task('SENSITIVE-MARKER visit list', null, null, null, null, 1::smallint)" >/dev/null
expect_eq "c1-cannot-see-s2"          w_filer "select count(*) from l1.atoms where summary like 'RESTRICTED-MARKER%'" "0"
expect_eq "c0-cannot-see-s1-atoms"    w_brief "select count(*) from l1.atoms where summary like 'SENSITIVE-MARKER%'" "0"
expect_eq "c0-cannot-see-s1-tasks"    w_brief "select count(*) from l1.obligations where description like 'SENSITIVE-MARKER%'" "0"
expect_eq "c1-sees-s1"                w_filer "select count(*) from l1.atoms where summary like 'SENSITIVE-MARKER%'" "1"
expect_eq "c2-sees-all"               claudio_panel "select count(*) from l1.atoms where summary like '%-MARKER%'" "2"
expect_eq "c0-whathappened-clean"     w_brief "select l1.what_happened(now() - interval '1 hour', now() + interval '1 hour', '{}')::text like '%SENSITIVE-MARKER%'" "f"
expect_eq "c0-packet-clean"           w_brief "select l1.get_context('role','general','{}')::text like '%SENSITIVE-MARKER%'" "f"
expect_fail "agent-cannot-lower-sens" w_filer "select l1.amend_atom((select id from l1.atoms where summary like 'SENSITIVE-MARKER%' limit 1), '{\"sensitivity\":0}')" "sensitivity_lower"
expect_fail "agent-cannot-set-notable" w_filer "select l1.amend_atom((select id from l1.atoms where summary like 'SENSITIVE-MARKER%' limit 1), '{\"notable\":true}')" "daily_pass_only"
expect_eq "capture-caps-at-1"         w_edge "select ((l1.capture('edge-imessage','secret','{\"source\":\"imessage\",\"handle\":\"+1\"}','cap-test-1',null,2::smallint))->>'id') is not null" "t"
expect_eq "capture-cap-verify"        claudio_core "select sensitivity from l1.intake where locator = 'cap-test-1'" "1"

echo "== red-team: audit + queues + verified fields =="
expect_fail "audit-hidden-from-agents" w_filer "select count(*) from l1.audit" "permission denied"
expect_fail "audit-no-update"          claudio_panel "update l1.audit set actor = 'nobody'" "permission denied"
expect_fail "queue-scope-holds"        w_filer "select l1.claim_message('user')" "queue_scope"
PID=$(sql claudio_core "select (l1.create_person('Verified Vera'))->>'id'")
sql claudio_core "select l1.update_person('$PID'::uuid, '{\"verified_fields\":[\"name\"]}')" >/dev/null
expect_fail "verified-fields-locked"   w_filer "select l1.update_person('$PID'::uuid, '{\"name\":\"Evil Rename\"}')" "verified_field"
expect_fail "verified-fields-list-locked" w_filer "select l1.update_person('$PID'::uuid, '{\"verified_fields\":[]}')" "user_set_only"
expect_fail "asserted-links-locked"    w_filer "select l1.add_link('person','$PID','person','$PID','knows','asserted')" "user_set_only"
expect_fail "person-person-low-conf"   w_filer "select l1.add_link('person','$PID','person','$PID','knows','inferred',0.5)" "propose_instead"

summary
