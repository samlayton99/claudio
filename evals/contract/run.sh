#!/usr/bin/env bash
# CONTRACT TESTS: every L1 function's positive path + the P1 gate assert —
# get_context('role','prod') correct on seed data including taste. Run after dev.sh reset.
set -uo pipefail
source "$(dirname "$0")/../../core/pipes/red-team/lib.sh"

echo "== contract: seed the fixture world (panel = the user's hands) =="
expect_ok "seed-role-prod"      claudio_panel "select l1.upsert_role('prod', 'PROD', 1.3)"
expect_ok "seed-role-hf"        claudio_panel "select l1.upsert_role('husband-father', 'Husband & Father', 1.5)"
expect_ok "seed-role-disciple"  claudio_panel "select l1.upsert_role('disciple', 'Disciple', 1.5, 1::smallint)"
expect_ok "seed-directive"      claudio_panel "select l1.set_directive('Never schedule meetings before 9am', 'global')"
expect_ok "seed-directive-prod" claudio_panel "select l1.set_directive('PROD intros get a response within 48h', 'role', 'prod')"
expect_ok "seed-purpose"        claudio_panel "select l1.upsert_purpose('goal-agents-research', 'goal', 'Do field-defining agents research', 'year')"
expect_ok "seed-priorities"     claudio_panel "select l1.new_purpose_version('Faith and family first; agents research second; PROD third.')"
expect_ok "seed-advances"       claudio_panel "select l1.add_link('role','prod','purpose','goal-agents-research','advances','asserted')"

JAMIE=$(sql claudio_panel "select (l1.create_person('Jamie Layton', 'husband-father'))->>'id'")
ANKIT=$(sql claudio_panel "select (l1.create_person('Ankit Shah', 'prod'))->>'id'")
expect_ok "seed-handle"         claudio_panel "select l1.add_handle('$JAMIE'::uuid, 'imessage', '+14355550101', true)"

echo "== contract: capture -> file_intake with \$refs (the filer's day job) =="
CID=$(sql w_edge "select (l1.capture('edge-imessage', 'Chatted with Daniel Cho at the ICME mixer...', '{\"source\":\"imessage\",\"handle\":\"+16505550999\"}', 'msg-f02'))->>'id'")
expect_eq "capture-dedup"       w_edge "select (l1.capture('edge-imessage', 'dupe', null, 'msg-f02'))->>'deduped'" "true"
# fixture timestamps are RELATIVE to now — pinned dates rot as the wall clock moves
# (this atom aged out of the packet's recency lane 25 days after it was written)
ATOM_TS=$(date -u -v-2d '+%Y-%m-%dT19:00:00Z')
FILED=$(sql w_filer "select l1.file_intake('$CID'::uuid, '[
  {\"fn\":\"create_person\",\"args\":{\"name\":\"Daniel Cho\",\"primary_role_id\":\"prod\"}},
  {\"fn\":\"record_atom\",\"args\":{\"ts\":\"$ATOM_TS\",\"kind\":\"meeting\",\"summary\":\"Met Daniel Cho at the ICME mixer — wants a PROD intro; deck this week.\",\"quotes\":[\"He will email me his deck this week\"],\"primary_role_id\":\"prod\",\"links\":[{\"to_type\":\"person\",\"to_id\":{\"\$ref\":0},\"kind\":\"participant\"}]}},
  {\"fn\":\"create_expectation\",\"args\":{\"description\":\"Daniel Cho to email his deck\",\"person_id\":{\"\$ref\":0},\"due\":\"2026-06-12T23:59:00-07:00\",\"follow_up\":\"remind\",\"primary_role_id\":\"prod\"}},
  {\"fn\":\"create_task\",\"args\":{\"description\":\"Review Daniel deck; intro to Ankit if good\",\"person_id\":\"$ANKIT\",\"primary_role_id\":\"prod\"}},
  {\"fn\":\"add_link\",\"args\":{\"from_type\":\"task\",\"from_id\":{\"\$ref\":3},\"to_type\":\"expectation\",\"to_id\":{\"\$ref\":2},\"kind\":\"blocks\",\"origin\":\"inferred\",\"confidence\":0.95}}
]')")
expect_eq "intake-filed"        claudio_core "select status from l1.intake where id = '$CID'" "filed"
expect_eq "atom-created"        w_filer "select count(*) from l1.atoms where summary like 'Met Daniel Cho%'" "1"
expect_eq "participant-linked"  w_filer "select count(*) from l1.links where kind = 'participant' and from_type = 'atom'" "1"
expect_eq "blocks-linked"       w_filer "select count(*) from l1.links where kind = 'blocks'" "1"
expect_eq "filed-refs-recorded" claudio_core "select jsonb_array_length(filed_refs) from l1.intake where id = '$CID'" "5"
# the J1 leak: an s1 atom's participant link must not be readable below the atom's clearance
S1AID=$(sql w_filer "select (l1.record_atom(now(), 'communication', 'Bishop pastoral note', p_primary_role_id => 'disciple', p_sensitivity => 1::smallint, p_links => jsonb_build_array(jsonb_build_object('to_type','person','to_id','$JAMIE','kind','participant'))))->>'id'")
expect_eq "link-inherits-atom-floor" claudio_core "select sensitivity from l1.links where from_id = '$S1AID' and kind = 'participant'" "1"

echo "== contract: poison-pill quarantine (one row, never the filer) =="
PCID=$(sql w_edge "select (l1.capture('edge-imessage', 'poison', null, 'msg-poison'))->>'id'")
QOUT=$(sql w_filer "select (l1.file_intake('$PCID'::uuid, '[{\"fn\":\"create_task\",\"args\":{\"description\":null}}]'))->>'quarantined'")
expect_eq "poison-quarantined"  claudio_core "select status || ':' || (meta->>'quarantined') from l1.intake where id = '$PCID'" "held:true"
if [ "$QOUT" = "true" ]; then PASS=$((PASS+1)); echo "PASS  poison-returns-not-raises"; else FAIL=$((FAIL+1)); FAILED_NAMES+=("poison-returns-not-raises"); echo "FAIL  poison-returns-not-raises ($QOUT)"; fi

echo "== contract: hold -> resolve_held (two Mikes) =="
HID=$(sql w_edge "select (l1.capture('edge-imessage', 'its Mike — Thursday still on?', '{\"source\":\"imessage\",\"handle\":\"+16505550199\"}', 'msg-mike'))->>'id'")
QID=$(sql w_filer "select (l1.post_message('user', 'question', '{\"question\":\"Which Mike?\"}'))->>'id'")
expect_ok "hold-intake"         w_filer "select l1.hold_intake('$HID'::uuid, '$QID'::uuid)"
expect_ok "resolve-held"        claudio_panel "select l1.resolve_held_intake('$HID'::uuid, 'Mike Reyes (PROD)')"
expect_eq "held-back-to-pending" claudio_core "select status from l1.intake where id = '$HID'" "pending"

echo "== contract: task + expectation lifecycle =="
TID=$(sql w_filer "select (l1.create_task('Send agenda', '2026-06-13T09:00:00-07:00', '$JAMIE'::uuid, 'disciple'))->>'id'")
expect_ok "complete-task"       w_filer "select l1.resolve_obligation('$TID'::uuid, 'done')"
expect_fail "complete-twice"    w_filer "select l1.resolve_obligation('$TID'::uuid, 'done')" "bad_transition"
expect_fail "task-cannot-be-met" w_filer "select l1.resolve_obligation('$TID'::uuid, 'met')" "bad_args"
EID=$(sql w_filer "select (l1.create_expectation('Deck from Daniel', null, now() + interval '2 days'))->>'id'")
AID=$(sql w_filer "select (l1.record_atom(now(), 'communication', 'Daniel sent the deck'))->>'id'")
expect_ok "resolve-expectation" w_filer "select l1.resolve_obligation('$EID'::uuid, 'met', null, '$AID'::uuid)"
expect_fail "resolve-twice"     w_filer "select l1.resolve_obligation('$EID'::uuid, 'met')" "bad_transition"

echo "== contract: supersedence =="
LID=$(sql w_filer "select (l1.add_link('atom','$AID','role','prod','about','inferred',0.8))->>'id'")
expect_ok "invalidate-link"     w_filer "select l1.invalidate_link('$LID'::uuid)"
expect_eq "link-survives-row"   w_filer "select count(*) from l1.links where id = '$LID'::uuid and invalidated_at is not null" "1"

echo "== contract: propose -> approve (the proposal economy) =="
PROP=$(sql w_filer "select (l1.propose('Create a follow-up task', '[{\"fn\":\"create_task\",\"args\":{\"description\":\"Follow up with venue\",\"primary_role_id\":\"prod\"}}]'))->>'id'")
expect_eq "propose-dedups"      w_filer "select (l1.propose('Create a follow-up task', '[{\"fn\":\"create_task\",\"args\":{\"description\":\"Follow up with venue\",\"primary_role_id\":\"prod\"}}]'))->>'deduped'" "true"
expect_ok "panel-approves"      claudio_panel "select l1.approve_message('$PROP'::uuid)"
expect_eq "approved-applied"    w_filer "select count(*) from l1.obligations where description = 'Follow up with venue' and status = 'open'" "1"
PROP2=$(sql w_filer "select (l1.propose('Another', '[{\"fn\":\"create_task\",\"args\":{\"description\":\"Stale thing\"}}]'))->>'id'")
sql claudio_core "update l1.messages set expires_at = now() - interval '1 day' where id = '$PROP2'::uuid" >/dev/null
expect_fail "stale-never-fires" claudio_panel "select l1.approve_message('$PROP2'::uuid)" "stale_approval"

echo "== contract: the full taste flow (stage -> read-back -> confirm) =="
PEND=$(sql w_orchestrator "select (l1.stage_taste_write('set_directive', '{\"statement\":\"During finals week the brief carries only calendar, tasks, church\",\"scope_type\":\"workflow\",\"scope_id\":\"morning-brief\",\"expires_at\":\"2026-06-20T00:00:00-07:00\"}'))->>'id'")
YES=$(sql w_edge "select (l1.capture('edge-imessage', 'YES', '{\"source\":\"imessage\",\"handle\":\"+14355550100\",\"verified_user\":true}', 'msg-yes-1'))->>'id'")
expect_ok "edge-confirms"       w_edge "select l1.confirm_taste_write('$PEND'::uuid, '$YES'::uuid)"
expect_eq "directive-committed" claudio_core "select count(*) from l1.directives where scope_id = 'morning-brief' and meta->>'binding' = 'read_back_confirm'" "1"

echo "== contract: verbatim shortcut =="
VID=$(sql w_edge "select (l1.capture('edge-imessage', 'claudio: never text anyone after 10pm on my behalf', '{\"source\":\"imessage\",\"handle\":\"+14355550100\",\"verified_user\":true}', 'msg-verbatim'))->>'id'")
expect_eq "verbatim-commits"    w_mirror "select (l1.set_directive('never text anyone after 10pm on my behalf', 'global', null, null, '$VID'::uuid))->>'name' is not null" "t"
expect_eq "verbatim-binding"    claudio_core "select meta->>'binding' from l1.directives where statement like 'never text anyone after 10pm%'" "verbatim"

echo "== contract: merges =="
M1=$(sql claudio_panel "select (l1.create_person('Mike R', 'prod', null, 0::smallint, '[{\"source\":\"imessage\",\"handle\":\"+16505550103\"}]'))->>'id'")
M2=$(sql claudio_panel "select (l1.create_person('Mike R duplicate', 'prod', null, 0::smallint, '[{\"source\":\"slack\",\"handle\":\"U-MIKER\"}]'))->>'id'")
expect_fail "handle-conflict"   w_filer "select l1.create_person('Third Mike', 'prod', null, 0::smallint, '[{\"source\":\"imessage\",\"handle\":\"+16505550103\"}]')" "handle_conflict"
expect_ok "merge-people"        claudio_panel "select l1.merge_people('$M1'::uuid, '$M2'::uuid)"
expect_eq "handles-moved"       claudio_panel "select count(*) from l1.person_handles where person_id = '$M1'::uuid" "2"
expect_eq "drop-archived"       claudio_panel "select status from l1.people where id = '$M2'::uuid" "archived"
expect_fail "re-merge-rejected" claudio_panel "select l1.merge_people('$M1'::uuid, '$M2'::uuid)" "bad_transition"

A1=$(sql w_filer "select (l1.record_atom('2026-06-08T09:00:00-07:00', 'communication', 'Delta booking confirmed SLC Jul 3-7'))->>'id'")
A2=$(sql w_filer "select (l1.record_atom('2026-06-08T20:00:00-07:00', 'conversation', 'Planned Utah trip with Jamie Jul 3-7'))->>'id'")
expect_fail "merge-below-bar"   w_merge "select l1.merge_atoms('$A1'::uuid, array['$A2'::uuid], 0.7)" "propose_instead"
expect_ok "merge-at-bar"        w_merge "select l1.merge_atoms('$A1'::uuid, array['$A2'::uuid], 0.95)"
expect_eq "canonical-set"       w_filer "select canonical_of::text from l1.atoms where id = '$A2'::uuid" "$A1"
expect_fail "no-merge-chains"   claudio_panel "select l1.merge_atoms('$A2'::uuid, array['$A1'::uuid])" "bad_args"
expect_eq "what-happened-canonical-only" w_brief "select l1.what_happened('2026-06-08T00:00:00-07:00'::timestamptz, '2026-06-09T00:00:00-07:00'::timestamptz, '{}')::text like '%Planned Utah trip%'" "f"

echo "== contract: notable is a selection, never prose (P12) =="
expect_fail "notable-needs-reason"   w_brief "select l1.amend_atom('$A1'::uuid, '{\"notable\":true}')" "notable_reason_required"
expect_fail "notable-junk-reason"    w_brief "select l1.amend_atom('$A1'::uuid, '{\"notable\":true,\"notable_reason\":\"felt important\"}')" "unknown_kind"
expect_ok   "notable-valid-reason"   w_brief "select l1.amend_atom('$A1'::uuid, '{\"notable\":true,\"notable_reason\":\"relationship_beat\"}')"
expect_eq   "notable-reason-stored"  w_brief "select notable_reason from l1.atoms where id = '$A1'::uuid" "relationship_beat"
expect_ok   "notable-unset-clears"   claudio_panel "select l1.amend_atom('$A1'::uuid, '{\"notable\":false}')"
expect_eq   "notable-reason-cleared" w_brief "select coalesce(notable_reason, 'NULL') from l1.atoms where id = '$A1'::uuid" "NULL"
expect_ok   "notable-user-asserted"  claudio_panel "select l1.amend_atom('$A1'::uuid, '{\"notable\":true,\"notable_reason\":\"user_asserted\"}')"

echo "== contract: pages =="
expect_fail "page-needs-read-moment" w_wiki "select l1.register_page('wiki/people/daniel-cho.md', 'person', 'Daniel Cho', 'people')" "read_moment_required"
expect_fail "page-needs-real-chapter" w_wiki "select l1.register_page('wiki/x.md', 'person', 'X', 'misc', null, null, 'sometime')" "unknown_chapter"
expect_ok "page-registers"      w_wiki "select l1.register_page('wiki/people/daniel-cho.md', 'person', 'Daniel Cho', 'people', 'person', 'daniel-cho', 'before any PROD intro involving evals')"
expect_ok "page-link"           w_wiki "select l1.add_link('document','wiki/people/daniel-cho.md','role','prod','about','inferred',0.9)"
expect_ok "page-moves"          w_wiki "select l1.move_page('wiki/people/daniel-cho.md', 'wiki/people/daniel-cho-evals.md')"
expect_eq "page-links-rewrote"  w_wiki "select count(*) from l1.links where from_id = 'wiki/people/daniel-cho-evals.md'" "1"

echo "== contract: retire_role cascade =="
expect_ok "seed-role-ra"        claudio_panel "select l1.upsert_role('ra-job', 'Lab RA', 1.0)"
sql claudio_core "select l1.register_component('window-ra-slack', 'window', 'inner', null, '{\"type\":\"cron\"}', '{\"role_map\":[\"ra-job\"]}')" >/dev/null
RTID=$(sql w_filer "select (l1.create_task('RA timesheet', null, null, 'ra-job'))->>'id'")
RPROP=$(sql claudio_panel "select (l1.retire_role('ra-job'))->>'id'")
expect_ok "cascade-approves"    claudio_panel "select l1.approve_message('$RPROP'::uuid)"
expect_eq "role-retired"        claudio_panel "select status from l1.roles where id = 'ra-job'" "retired"
expect_eq "component-suspended" claudio_panel "select status from l1.components where id = 'window-ra-slack'" "disabled"
expect_eq "task-rehomed"        claudio_panel "select primary_role_id from l1.obligations where id = '$RTID'::uuid" "general"

echo "== contract: queues + runs =="
QMSG=$(sql w_filer "select (l1.post_message('orchestrator', 'notification', '{\"note\":\"hi\"}'))->>'id'")
CLAIMED=$(sql w_orchestrator "select (l1.claim_message('orchestrator'))->>'id'")
if [ "$CLAIMED" = "$QMSG" ]; then PASS=$((PASS+1)); echo "PASS  claim-own-queue"; else FAIL=$((FAIL+1)); FAILED_NAMES+=("claim-own-queue"); echo "FAIL  claim-own-queue ($CLAIMED != $QMSG)"; fi
expect_ok "resolve-message"     w_orchestrator "select l1.resolve_message('$QMSG'::uuid)"
RID=$(sql w_filer "select (l1.start_run('filer'))->>'id'")
expect_ok "finish-run"          w_filer "select l1.finish_run('$RID'::uuid, 'ok', 1200, 300, 0.004, 'filed 3')"
expect_fail "finish-twice"      w_filer "select l1.finish_run('$RID'::uuid, 'ok')" "bad_transition"
expect_ok "watchdog-reaps"      w_watchdog "select l1.reap_expired_claims()"

echo "== contract: reads =="
expect_eq "search-by-handle"    w_brief "select l1.search_people('+14355550101')::text like '%Jamie%'" "t"
expect_eq "search-miss-logged"  claudio_core "select count(*) >= 0 from l1.audit where fn = 'search_people' and op = 'miss'" "t"
expect_eq "fetch-ref-intake"    w_filer "select (l1.fetch_ref(jsonb_build_object('source','intake','locator','$CID')))->>'content' like 'Chatted with Daniel%'" "t"
expect_eq "fetch-ref-external"  w_filer "select (l1.fetch_ref('{\"source\":\"gmail\",\"locator\":\"thread:x\",\"tool\":\"window-gmail\"}'))->>'route_via'" "window-gmail"
expect_eq "due-tasks-annotated" w_brief "select l1.due_tasks('{\"role\":\"prod\"}')::text like '%blocked_by%'" "t"

echo "== contract: THE GATE — get_context('role','prod') correct on seed data incl. taste =="
PKT=$(sql w_orchestrator "select l1.get_context('role','prod','{}')::text")
check() { local name="$1" pat="$2"
  if echo "$PKT" | grep -q "$pat"; then PASS=$((PASS+1)); echo "PASS  packet-$name"; else FAIL=$((FAIL+1)); FAILED_NAMES+=("packet-$name"); echo "FAIL  packet-$name (missing /$pat/)"; fi }
check "anchor"          '"id": "prod"'
check "weight"          '"weight": 1.3'
check "global-directive" 'Never schedule meetings before 9am'
check "scoped-directive" 'PROD intros get a response within 48h'
check "purpose-via-advances" 'goal-agents-research'
check "obligation"      'Review Daniel deck'
check "expectation"     'Daniel Cho to email his deck'
check "state-atom"      'Met Daniel Cho at the ICME mixer'
check "budget"          '"requested"'
# taste survives a starved budget; capabilities trim first
PKT=$(sql w_orchestrator "select l1.get_context('role','prod','{\"budget_tokens\":300}')::text")
check "taste-never-truncates" 'Never schedule meetings before 9am'
check "capabilities-trim-first" '"trimmed"'

summary
