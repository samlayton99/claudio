-- 0008: seeds (kind vocab, clearances, the parameter registry, the v0 component roster, the
-- catch-all role) + THE GRANTS MATRIX. Every write surface is EXECUTE; zero direct DML anywhere.
set role claudio_core;

-- ---------- kinds (small; grows only by proposal) ----------
insert into l1.kinds (domain, key, description) values
  ('atom','meeting','A meeting/call/ended calendar event. One atom each. e.g. advisor meeting; PROD ops sync.'),
  ('atom','conversation','A coherent conversational episode (chat-thread day or a beat of one). e.g. planning Dad''s 60th with siblings.'),
  ('atom','session','A work/study/focus/leisure block. e.g. 3h RL ablations; an evening of TV (the record is honest).'),
  ('atom','trip','Umbrella atom for a multi-day event; children link part_of. e.g. Utah Jul 3-7.'),
  ('atom','capture','A quick user capture preserved as-is. e.g. "remember the thing about the guy from the lab".'),
  ('atom','communication','A message/thread-day/email-beat episode. e.g. Jamie''s flight-confirmation forward; a banter day with Tyler.'),
  ('atom','observation','A system or mirror observation recorded as life data. e.g. "topology notes cluster has no advances links".'),
  ('atom','idea','A captured thought/insight/research direction. e.g. "evals should bias false-negative".'),
  ('atom','milestone','A goal achieved or marker passed; usually advances-linked. e.g. first paper submission.'),
  ('atom','artifact','A published/produced thing. e.g. a substack post (refs carry the canonical URL).'),
  ('atom','agent_action','An agent run with side effects, one atom per run. e.g. "merged two Mikes after approval".'),
  ('atom','unknown','The honest default when the filer cannot classify. Aged-out holds file as this.'),
  ('link','member','Membership. e.g. person -> role.'),
  ('link','participant','Was there. e.g. atom -> person.'),
  ('link','about','Generic aboutness incl. secondary roles. e.g. atom -> role; task -> document.'),
  ('link','advances','THE alignment edge. e.g. atom -> purpose; role -> purpose.'),
  ('link','scoped_to','Component scoping. e.g. component -> role.'),
  ('link','part_of','Composition. e.g. atom -> trip atom.'),
  ('link','derived_from','Provenance. e.g. task -> atom it came from.'),
  ('link','blocks','Dependency. e.g. task -> expectation it waits on.'),
  ('link','unknown','Honest default for unclassifiable edges.'),
  ('relationship','knows','Default person<->person. Conservative: asserted or evidence >= 0.9.'),
  ('relationship','family','Family tie. e.g. Jamie <-> Sam.'),
  ('relationship','introduced_by','Provenance of a connection. e.g. Priya -> Alex.'),
  ('relationship','colleague','Works-with. e.g. lab mates.'),
  ('relationship','unknown','Honest default.'),
  ('page','person','A person page. e.g. wiki/people/daniel-cho.md.'),
  ('page','topic','A topic/interest page. e.g. wiki/interests/agent-evals.md.'),
  ('page','significant_event','A wedding, a death, a move — NOT routine meetings.'),
  ('page','digest','A summary-ladder page (daily/monthly/biannual) under cadences.'),
  ('page','index','A chapter MOC.'),
  ('page','unknown','Honest default.'),
  ('message','handoff','Approved external work or staged commits passing between components.'),
  ('message','proposal','An action set awaiting approval. Always via propose().'),
  ('message','notification','FYI push to the user queue.'),
  ('message','alert','Something is wrong; watchdog/red-team raise these.'),
  ('message','question','A held-intake or mirror question awaiting the user.'),
  ('purpose','goal','An aim with a horizon (life/year/quarter).'),
  ('purpose','value','A core driver of behavior or key truth held.'),
  ('purpose','attribute','An identity-based goal: who I am becoming, with goalposts.')
on conflict do nothing;

-- ---------- clearances ----------
insert into l1.role_clearances (role_name, clearance) values
  ('claudio_core', 2), ('claudio_panel', 2),
  ('w_edge', 1), ('w_filer', 1), ('w_merge', 1), ('w_wiki', 1), ('w_verifier', 1),
  ('w_lint', 1), ('w_orchestrator', 1), ('w_mirror', 1),
  ('w_brief', 0), ('w_scanner', 0), ('w_watchdog', 0), ('w_catalog', 0),
  ('w_hygiene', 0), ('w_approver', 0), ('w_reconciler', 0), ('w_test', 0)
on conflict (role_name) do update set clearance = excluded.clearance;

-- ---------- parameters (seeded minimally; knobs migrate here on first tuning) ----------
insert into l1.parameters (key, value, ring, description) values
  ('fn_privilege_class', '{
      "set_directive":"taste","retire_directive":"taste","upsert_purpose":"taste","new_purpose_version":"taste",
      "upsert_role":"taste","retire_role":"taste","add_link_asserted":"taste",
      "merge_people":"identity","merge_atoms":"identity",
      "_execute_role_cascade":"panel","set_component_status":"panel","apply_actions":"panel","reject_message":"panel",
      "approve_message":"core","register_component":"core","purge":"core",
      "resolve_held_intake":"user_relay"
    }', 'core', 'fn -> privilege class; absent => routine. DERIVED server-side, never trusted from payload. Taste/core are never proposable; identity never standing-approvable.'),
  ('fn_sets', '{
      "agent": ["capture","file_intake","hold_intake","discard_intake","create_person","add_handle","update_person",
                "create_task","complete_task","drop_task","amend_task","create_expectation","resolve_expectation",
                "record_atom","amend_atom","add_link","invalidate_link","register_page","move_page",
                "post_message","claim_message","read_message","resolve_message","propose","start_run","finish_run",
                "get_context","fetch_ref","search_people","what_happened","due_tasks","pending_expectations","queue_status"]
    }', 'core', 'The base agent function set (propose-time executability check reads this).'),
  ('narrow_grants', '{
      "w_merge": ["merge_atoms"],
      "w_watchdog": ["reap_expired_claims"],
      "w_orchestrator": ["stage_taste_write"],
      "w_mirror": ["stage_taste_write","set_directive","retire_directive","upsert_purpose","new_purpose_version",
                   "upsert_role","retire_role","add_link_asserted","update_person"],
      "w_edge": ["confirm_taste_write","approve_message","reject_message","resolve_held_intake"]
    }', 'core', 'Per-role function-set extras beyond the agent base.'),
  ('caps', '{"batch_max_actions": 20, "batch_max_rows": 100}', 'core', 'Batch shape ceilings.'),
  ('dictation_window_min', '10', 'core', 'The dictation gate freshness window (a recency token, not a bearer token).'),
  ('claim_lease_min', '10', 'core', 'Queue claim lease; reaped at claim time, watchdog backstops.'),
  ('hold_ttl_days', '7', 'core', 'Unanswered holds age out by auto-filing as kind=unknown low-confidence atoms.'),
  ('proposal_ttl_days', '14', 'core', 'Proposals auto-expire; user absence never produces a duplicate pile.'),
  ('merge_auto_bar', '0.9', 'core', 'w_merge may merge_atoms directly only at/above this confidence with identical time+participants; below it proposes.'),
  ('write_rate_ceiling_per_min', '240', 'core', 'Per-actor trailing-minute write ceiling (counted over audit).'),
  ('edge_approvable_classes', '["routine"]', 'core', 'Phone-approvable classes. NEVER core, taste, write-capable registrations, or identity.'),
  ('queue_acl', '{
      "user": ["w_edge","claudio_panel","claudio_core"],
      "edge": ["w_edge","claudio_core"],
      "orchestrator": ["w_orchestrator","claudio_core"],
      "filer": ["w_filer","claudio_core"]
    }', 'core', 'Who may CLAIM from which queue (posting is open; claiming is scoped).'),
  ('wiki_chapters', '["people","personal-life","significant-events","professional","purpose","progress","interests","lessons-learned","pitfalls","how-to-work-with-sam","cadences"]',
   'core', 'The eleven fixed chapter MOCs. Every page reachable from a chapter in <= 2 hops.'),
  ('scoring', '{"alpha":1.0,"beta":1.0,"gamma":1.5,"halflife_days":7,"floor":0.05,"urgency_horizon_days":7,"default_budget_tokens":3000}',
   'outer', 'Two-lane scoring elasticities + floors. Deliberately v0; tuned at P2 against the first week of real packets.'),
  ('verified_user_handles', '[]', 'core', 'The dictation gate''s allowlist: [{"source":"imessage","handle":"+1..."}]. Seeded at P2 with the edge.'),
  ('retention_days', '90', 'outer', 'Backup/purge retention bound.'),
  ('effort_slider', '"standard"', 'outer', 'ONE dial on system proactivity: question frequency, digest depth, model-tier defaults. minimal|standard|eager.'),
  ('budget_monthly_ceiling_usd', 'null', 'outer', 'Global monthly spend ceiling. DEFAULT: none (the user''s call). Set it when wanted; runs records cost regardless.')
on conflict (key) do nothing;

-- ---------- the catch-all role + v0 component roster (disabled until their phase ships code) ----------
insert into l1.roles (id, name, summary, weight) values
  ('general', 'General', 'The catch-all role every window may map to.', 1.0)
on conflict (id) do nothing;

insert into l1.components (id, kind, circle, status, definition_path, trigger, config, reliability) values
  ('edge-imessage', 'pipe', 'inner', 'disabled', 'core/pipes/edge',
   '{"type":"resident"}', '{"role_map":["general"],"replayable":false,"default_sensitivity":0}', 'critical'),
  ('window-gcal', 'window', 'inner', 'disabled', 'core/pipes/windows/gcal',
   '{"type":"cron","schedule":"*/15 * * * *"}', '{"role_map":["general"],"replayable":true,"semantics":{"commitment_strength":"tentative"}}', 'standard'),
  ('filer', 'gardener', 'inner', 'disabled', 'core/agents/filer',
   '{"type":"query","interval_min":1}', '{"model_tier":"frontier"}', 'critical'),
  ('brief', 'workflow', 'inner', 'disabled', 'core/agents/brief',
   '{"type":"cron","schedule":"0 7 * * *"}', '{"model_tier":"cheap","degraded_mode":"deterministic_skeleton"}', 'critical'),
  ('scanner', 'workflow', 'inner', 'disabled', 'core/pipes/scanner',
   '{"type":"cron","schedule":"0 * * * *"}', '{"no_llm":true}', 'critical'),
  ('watchdog', 'pipe', 'inner', 'disabled', 'core/pipes/watchdog',
   '{"type":"cron","schedule":"*/15 * * * *"}', '{}', 'critical'),
  ('orchestrator', 'workflow', 'inner', 'disabled', 'core/agents/orchestrator',
   '{"type":"queue","poll_seconds":10}', '{"harness":"claude -p","model_tier":"frontier","slot":"configurable"}', 'standard'),
  ('mirror', 'workflow', 'inner', 'disabled', 'core/agents/mirror',
   '{"type":"manual"}', '{"model_tier":"frontier","isolation":"no connectors, no send, fixed-endpoint model API"}', 'standard'),
  ('catalog', 'pipe', 'inner', 'enabled', 'core/pipes/catalog',
   '{"type":"manual","note":"migration-runner hook"}', '{}', 'standard')
on conflict (id) do nothing;

-- ---------- THE GRANTS MATRIX ----------
-- default-deny: strip PUBLIC from everything, then grant per set.
revoke execute on all functions in schema l1 from public;
alter default privileges for role claudio_core in schema l1 revoke execute on functions from public;

-- reads: SELECT on tables under FORCE RLS + the invoker views. audit stays panel/core-only.
do $$
declare t text;
begin
  foreach t in array array['kinds','role_clearances','parameters','purpose','purpose_versions','roles','people',
                           'person_handles','directives','tasks','expectations','atoms','intake','documents',
                           'links','components','runs','messages'] loop
    execute format('grant select on l1.%I to claudio_agent, claudio_panel, w_edge, w_reconciler', t);
  end loop;
  grant select on l1.audit to claudio_panel;  -- diffs can carry sensitive content: panel/core only
  foreach t in array array['v_unfiled_intake','v_open_proposals','v_run_misses','v_component_health',
                           'v_stale_expectations','v_purpose_alignment'] loop
    execute format('grant select on l1.%I to claudio_agent, claudio_panel, w_edge, w_reconciler', t);
  end loop;
end $$;

-- EXECUTE per function set
do $$
declare fn text;
begin
  -- agent base (claudio_agent; all w_* inherit)
  foreach fn in array array[
    'capture(text,text,jsonb,text,jsonb,smallint,text)',
    'file_intake(uuid,jsonb)','hold_intake(uuid,uuid)','discard_intake(uuid,text)',
    'create_person(text,text,text,smallint,jsonb,jsonb)','add_handle(uuid,text,text,boolean)','update_person(uuid,jsonb)',
    'create_task(text,timestamptz,uuid,text,jsonb,smallint,jsonb)','complete_task(uuid)','drop_task(uuid,text)','amend_task(uuid,jsonb)',
    'create_expectation(text,uuid,timestamptz,text,timestamptz,text,jsonb,smallint,jsonb)',
    'resolve_expectation(uuid,text,uuid)',
    'record_atom(timestamptz,text,text,timestamptz,text,jsonb,jsonb,text,jsonb,smallint,jsonb)','amend_atom(uuid,jsonb)',
    'add_link(text,text,text,text,text,text,real,text)','invalidate_link(uuid,uuid)',
    'register_page(text,text,text,text,text,text,text,smallint)','move_page(text,text)',
    'post_message(text,text,jsonb,smallint,timestamptz)','claim_message(text)','read_message(uuid)','resolve_message(uuid,jsonb)',
    'propose(text,jsonb,jsonb,text,text)','start_run(text)',
    'finish_run(uuid,text,integer,integer,numeric,text,text)',
    'get_context(text,text,jsonb)','fetch_ref(jsonb)','search_people(text)','what_happened(timestamptz,timestamptz,jsonb)',
    'due_tasks(jsonb)','pending_expectations(jsonb)','queue_status(text)','clearance()'
  ] loop
    -- the panel holds the agent set too (it is the user's hands); w_* inherit via claudio_agent
    execute format('grant execute on function l1.%s to claudio_agent, claudio_panel', fn);
  end loop;

  -- user set: panel always; mirror via narrow grants (its writes gate internally: verbatim/stage/read-back)
  foreach fn in array array[
    'set_directive(text,text,text,timestamptz,uuid)','retire_directive(uuid,uuid)',
    'upsert_purpose(text,text,text,text,jsonb,text,uuid)','new_purpose_version(text,uuid)',
    'upsert_role(text,text,real,smallint,text,text,uuid)','retire_role(text,uuid)',
    'add_link_asserted(text,text,text,text,text,text,uuid)','resolve_held_intake(uuid,text,uuid)'
  ] loop
    execute format('grant execute on function l1.%s to claudio_panel, w_mirror', fn);
  end loop;

  -- panel set
  foreach fn in array array[
    'approve_message(uuid)','reject_message(uuid,text)','apply_actions(jsonb)',
    'merge_people(uuid,uuid)','merge_atoms(uuid,uuid[],real)','set_component_status(text,text)',
    '_render_what_will_execute(jsonb)'
  ] loop
    execute format('grant execute on function l1.%s to claudio_panel', fn);
  end loop;
end $$;

-- narrow extras
grant execute on function l1.stage_taste_write(text,jsonb,uuid) to w_orchestrator, w_mirror;
grant execute on function l1.confirm_taste_write(uuid,uuid) to w_edge;
grant execute on function l1.approve_message(uuid) to w_edge;          -- low-risk classes only (guarded inside)
grant execute on function l1.reject_message(uuid,text) to w_edge;
grant execute on function l1.resolve_held_intake(uuid,text,uuid) to w_edge;
grant execute on function l1.merge_atoms(uuid,uuid[],real) to w_merge; -- auto-bar enforced inside
grant execute on function l1.reap_expired_claims() to w_watchdog;

reset role;
