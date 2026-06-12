#!/usr/bin/env bash
# The todo & expectation scanner (P6 CRITICAL): pure SQL, no LLM, deterministic.
# Due reminders, follow-up firing, auto-task creation, missed nudges — all idempotent via
# meta markers. A changed due date re-arms its reminder on purpose (new due = new reminder).
# Runs as w_scanner (clearance 1 — see 0008: reminders must never false-negative under RLS).
set -euo pipefail

PG_BIN="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
export PGHOST="${PGHOST:-$HOME/.claudio/sock}" PGPORT="${CLAUDIO_PGPORT:-5433}"
ROLE="${CLAUDIO_DB_ROLE:-w_scanner}"

"$PG_BIN/psql" -U "$ROLE" -d claudio -v ON_ERROR_STOP=1 -tAq <<'SQL'
do $$
declare
  lead_h  integer := coalesce((select (value->>'due_lead_hours')::integer  from l1.parameters where key = 'scanner'), 24);
  grace_h integer := coalesce((select (value->>'missed_grace_hours')::integer from l1.parameters where key = 'scanner'), 72);
  r record; v_task jsonb;
begin
  -- 1. due reminders (both kinds): fire once per due value, inside the lead window
  for r in select id, kind, description, due, sensitivity from l1.obligations
           where status = 'open' and due is not null and due <= now() + make_interval(hours => lead_h)
             and coalesce(meta->>'scanner_reminded_for','') <> due::text
  loop
    perform l1.post_message('user', 'notification',
      jsonb_build_object('summary', initcap(r.kind) || ' due ' || to_char(r.due, 'Dy HH24:MI') || ': ' || r.description,
                         'obligation_id', r.id, 'kind', r.kind, 'due', r.due, 'trigger', 'due'),
      r.sensitivity, null);
    perform l1.amend_obligation(r.id, jsonb_build_object('meta', jsonb_build_object('scanner_reminded_for', r.due::text)));
  end loop;

  -- 2. follow-up reminders (expectations, follow_up='remind'): fire once per follow_up_at
  for r in select id, description, follow_up_at, sensitivity from l1.obligations
           where status = 'open' and kind = 'expectation' and follow_up = 'remind'
             and follow_up_at is not null and follow_up_at <= now()
             and coalesce(meta->>'scanner_followup_done','') <> follow_up_at::text
  loop
    perform l1.post_message('user', 'notification',
      jsonb_build_object('summary', 'Follow up: ' || r.description,
                         'obligation_id', r.id, 'kind', 'expectation', 'trigger', 'follow_up'),
      r.sensitivity, null);
    perform l1.amend_obligation(r.id, jsonb_build_object('meta', jsonb_build_object('scanner_followup_done', r.follow_up_at::text)));
  end loop;

  -- 3. auto-task (expectations, follow_up='auto_task'): create the follow-up task exactly once
  for r in select id, description, person_id, primary_role_id, follow_up_at, sensitivity from l1.obligations
           where status = 'open' and kind = 'expectation' and follow_up = 'auto_task'
             and follow_up_at is not null and follow_up_at <= now()
             and meta->>'scanner_auto_task_id' is null
  loop
    v_task := l1.create_task('Follow up: ' || r.description, null, r.person_id, r.primary_role_id,
                             jsonb_build_object('source', 'scanner', 'locator', r.id::text), r.sensitivity, '{}');
    perform l1.add_link('task', v_task->>'id', 'expectation', r.id::text, 'derived_from', 'inferred', 1.0, 'scanner auto_task');
    perform l1.amend_obligation(r.id, jsonb_build_object('meta', jsonb_build_object('scanner_auto_task_id', v_task->>'id')));
  end loop;

  -- 4. missed nudge (expectations well past due): ASK, never auto-resolve (P7)
  for r in select id, description, due, sensitivity from l1.obligations
           where status = 'open' and kind = 'expectation' and due is not null
             and due < now() - make_interval(hours => grace_h)
             and coalesce(meta->>'scanner_missed_nudged','') <> due::text
  loop
    perform l1.post_message('user', 'question',
      jsonb_build_object('summary', 'Still waiting on: ' || r.description || ' (due ' || to_char(r.due, 'Mon DD') || '). Met, missed, or drop?',
                         'obligation_id', r.id, 'kind', 'expectation', 'trigger', 'missed'),
      r.sensitivity, null);
    perform l1.amend_obligation(r.id, jsonb_build_object('meta', jsonb_build_object('scanner_missed_nudged', r.due::text)));
  end loop;
end $$;
SQL

echo "scanner: swept"
