-- 0006: user set (dictation-gated + INTENT-BOUND), edge confirm flow, panel set, core set.
-- The law in one line: a channel proof is not an intent proof — the LLM that drafted a taste
-- write is never in its commit path.
set role claudio_core;

-- ---------- the taste committer (internal; every gate funnels here) ----------
create or replace function l1._commit_taste(p_fn text, p_args jsonb, p_binding text, p_evidence jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_id text; v_version integer; v_meta jsonb; r jsonb;
begin
  v_meta := jsonb_build_object('binding', p_binding) || p_evidence;
  case p_fn
    when 'set_directive' then
      insert into l1.directives (statement, scope_type, scope_id, expires_at, meta)
      values (p_args->>'statement', coalesce(p_args->>'scope_type','global'), p_args->>'scope_id',
              (p_args->>'expires_at')::timestamptz, v_meta)
      returning id::text into v_id;
      r := jsonb_build_object('id', v_id, 'name', left(p_args->>'statement', 80));
    when 'retire_directive' then
      update l1.directives set status = 'retired', meta = meta || v_meta
      where id = (p_args->>'directive_id')::uuid and status = 'active' returning id::text into v_id;
      if v_id is null then raise exception 'claudio.bad_transition: directive not active'; end if;
      r := jsonb_build_object('id', v_id, 'status', 'retired');
    when 'upsert_purpose' then
      insert into l1.purpose (id, kind, statement, horizon, goalposts, status, meta)
      values (p_args->>'id', p_args->>'kind', p_args->>'statement', p_args->>'horizon',
              coalesce(p_args->'goalposts','[]'), coalesce(p_args->>'status','active'), v_meta)
      on conflict (id) do update
        set kind = excluded.kind, statement = excluded.statement, horizon = excluded.horizon,
            goalposts = excluded.goalposts, status = excluded.status, meta = l1.purpose.meta || v_meta
      returning id into v_id;
      r := jsonb_build_object('id', v_id, 'name', left(p_args->>'statement', 80));
    when 'new_purpose_version' then
      select coalesce(max(version), 0) + 1 into v_version from l1.purpose_versions;
      insert into l1.purpose_versions (version, body, created_by) values (v_version, p_args->>'body', session_user::text)
      returning id::text into v_id;
      r := jsonb_build_object('id', v_id, 'version', v_version);
    when 'upsert_role' then
      insert into l1.roles (id, name, weight, default_sensitivity, summary, meta)
      values (p_args->>'id', coalesce(p_args->>'name', p_args->>'id'),
              coalesce((p_args->>'weight')::real, 1.0), coalesce((p_args->>'default_sensitivity')::smallint, 0),
              p_args->>'summary', v_meta)
      on conflict (id) do update
        set name = coalesce(excluded.name, l1.roles.name),
            weight = coalesce((p_args->>'weight')::real, l1.roles.weight),
            default_sensitivity = coalesce((p_args->>'default_sensitivity')::smallint, l1.roles.default_sensitivity),
            summary = coalesce(excluded.summary, l1.roles.summary),
            status = coalesce(p_args->>'status', l1.roles.status),
            meta = l1.roles.meta || v_meta
      returning id into v_id;
      r := jsonb_build_object('id', v_id, 'name', p_args->>'id');
    when 'retire_role' then
      r := l1._retire_role_proposal(p_args->>'role_id');
    when 'add_link_asserted' then
      insert into l1.links (from_type, from_id, to_type, to_id, kind, origin, description)
      values (p_args->>'from_type', p_args->>'from_id', p_args->>'to_type', p_args->>'to_id',
              p_args->>'kind', 'asserted', p_args->>'description')
      on conflict (from_type, from_id, to_type, to_id, kind)
      do update set origin = 'asserted', invalidated_at = null, description = coalesce(excluded.description, l1.links.description)
      returning id::text into v_id;
      r := jsonb_build_object('id', v_id, 'origin', 'asserted');
    else
      raise exception 'claudio.unknown_fn: % is not a taste-class committer', p_fn;
  end case;
  perform l1._audit(p_fn, 'taste', coalesce(v_id, '-'), 'commit', jsonb_build_object('binding', p_binding, 'args', p_args));
  return r;
end $$;
comment on function l1._commit_taste(text, jsonb, text, jsonb) is
  'INTERNAL. The single funnel for taste-class row writes; callers gate, this commits + records the binding '
  '(by_role | verbatim | read_back_confirm) in meta and audit. The taste ledger the monthly provenance review reads.';

-- ---------- user set ----------
create or replace function l1.set_directive(p_statement text, p_scope_type text default 'global',
                                            p_scope_id text default null, p_expires_at timestamptz default null,
                                            p_source_intake_id uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_intake l1.intake; v_args jsonb;
begin
  perform l1._rate_check();
  v_args := jsonb_build_object('statement', p_statement, 'scope_type', p_scope_type,
                               'scope_id', p_scope_id, 'expires_at', p_expires_at);
  if session_user::text in ('claudio_panel','claudio_core') then
    return l1._commit_taste('set_directive', v_args, 'by_role');
  end if;
  -- the verbatim shortcut: channel proof (dictation gate) AND the load-bearing payload
  -- appearing VERBATIM in the cited raw — the user literally said it
  if p_source_intake_id is not null then
    begin
      v_intake := l1._dictation_check(p_source_intake_id);
      if position(p_statement in v_intake.raw) > 0 then
        return l1._commit_taste('set_directive', v_args, 'verbatim',
                                jsonb_build_object('source_intake_id', p_source_intake_id));
      end if;
    exception when others then
      null;  -- stale/unverified citation: no shortcut — fall through to staging
    end;
  end if;
  -- paraphrase, no citation, or failed gate => stage for the edge's read-back-confirm
  -- (staging is inert; channel + intent both prove at confirm time)
  return l1.stage_taste_write('set_directive', v_args, p_source_intake_id);
end $$;
comment on function l1.set_directive(text, text, text, timestamptz, uuid) is
  'User taste as law. Panel/core: by role. Mirror: verbatim-in-raw commits; a paraphrase AUTO-STAGES for the edge''s '
  'read-back-confirm (returns {staged:true, render}). Examples: set_directive(''never schedule before 9am'') as panel; '
  'set_directive(''During finals week...'', ''workflow'', ''morning-brief'', ''2026-06-20'', intake_id) as mirror with the user''s literal text.';

create or replace function l1.retire_directive(p_directive_id uuid, p_source_intake_id uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
begin
  perform l1._rate_check();
  if session_user::text in ('claudio_panel','claudio_core') then
    return l1._commit_taste('retire_directive', jsonb_build_object('directive_id', p_directive_id), 'by_role');
  end if;
  -- removing law is taste too: stage for read-back (verbatim is meaningless for a retirement)
  return l1.stage_taste_write('retire_directive', jsonb_build_object('directive_id', p_directive_id), p_source_intake_id);
end $$;

create or replace function l1.upsert_purpose(p_id text, p_kind text, p_statement text,
                                             p_horizon text default null, p_goalposts jsonb default '[]',
                                             p_status text default 'active', p_source_intake_id uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_args jsonb; v_prior l1.purpose; v_diff text;
begin
  perform l1._rate_check();
  v_args := jsonb_build_object('id', p_id, 'kind', p_kind, 'statement', p_statement,
                               'horizon', p_horizon, 'goalposts', p_goalposts, 'status', p_status);
  if session_user::text in ('claudio_panel','claudio_core') then
    return l1._commit_taste('upsert_purpose', v_args, 'by_role');
  end if;
  -- THE APEX CONTRACT: every non-panel write read-backs with a diff — session-active alone never authorizes
  select * into v_prior from l1.purpose where id = p_id;
  v_diff := case when v_prior.id is null then 'NEW: ' || p_statement
                 else 'WAS: ' || v_prior.statement || E'\nNOW: ' || p_statement end;
  v_args := v_args || jsonb_build_object('diff', v_diff);
  return l1.stage_taste_write('upsert_purpose', v_args, p_source_intake_id);
end $$;
comment on function l1.upsert_purpose(text, text, text, text, jsonb, text, uuid) is
  'The contract changes through the user, period. Panel/core commit by role; the MIRROR always stages with a diff against '
  'the prior version for read-back-confirm — there is no verbatim shortcut for the apex contract.';

create or replace function l1.new_purpose_version(p_body text, p_source_intake_id uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
begin
  perform l1._rate_check();
  if session_user::text in ('claudio_panel','claudio_core') then
    return l1._commit_taste('new_purpose_version', jsonb_build_object('body', p_body), 'by_role');
  end if;
  return l1.stage_taste_write('new_purpose_version', jsonb_build_object('body', p_body), p_source_intake_id);
end $$;

create or replace function l1.upsert_role(p_id text, p_name text default null, p_weight real default null,
                                          p_default_sensitivity smallint default null, p_summary text default null,
                                          p_status text default null, p_source_intake_id uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_args jsonb;
begin
  perform l1._rate_check();
  v_args := jsonb_strip_nulls(jsonb_build_object('id', p_id, 'name', p_name, 'weight', p_weight,
                              'default_sensitivity', p_default_sensitivity, 'summary', p_summary, 'status', p_status));
  if session_user::text in ('claudio_panel','claudio_core') then
    return l1._commit_taste('upsert_role', v_args, 'by_role');
  end if;
  return l1.stage_taste_write('upsert_role', v_args, p_source_intake_id);  -- weight is taste
end $$;

create or replace function l1._retire_role_proposal(p_role_id text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_components jsonb; v_tasks jsonb; v_windows jsonb; v_id uuid;
begin
  if not exists (select 1 from l1.roles where id = p_role_id and status = 'active') then
    raise exception 'claudio.endpoint_not_found: active role %', p_role_id;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind)), '[]') into v_components
  from l1.components where status = 'enabled' and (config->'role_map') ? p_role_id;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', left(description, 60))), '[]') into v_tasks
  from l1.tasks where status = 'open' and primary_role_id = p_role_id;
  insert into l1.messages (queue, kind, from_actor, payload, privilege_class, requires_approval)
  values ('user', 'proposal', session_user::text,
          jsonb_build_object(
            'summary', format('Retire role %s: suspend %s component(s), re-home %s open task(s). Wiki pages and atoms are NEVER touched.',
                              p_role_id, jsonb_array_length(v_components), jsonb_array_length(v_tasks)),
            'actions', jsonb_build_array(jsonb_build_object('fn', '_execute_role_cascade',
                                                            'args', jsonb_build_object('role_id', p_role_id))),
            'cascade_preview', jsonb_build_object('suspend_components', v_components, 'rehome_tasks', v_tasks)),
          'panel', true)
  returning id into v_id;
  perform l1._audit('retire_role', 'messages', v_id::text, 'propose', jsonb_build_object('role', p_role_id));
  return jsonb_build_object('id', v_id, 'proposal', true, 'name', 'retire ' || p_role_id);
end $$;

create or replace function l1.retire_role(p_role_id text, p_source_intake_id uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
begin
  perform l1._rate_check();
  if session_user::text in ('claudio_panel','claudio_core') then
    return l1._retire_role_proposal(p_role_id);  -- even the user path is cascade-PREVIEW first
  end if;
  return l1.stage_taste_write('retire_role', jsonb_build_object('role_id', p_role_id), p_source_intake_id);
end $$;

create or replace function l1._execute_role_cascade(p_role_id text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare n_comp integer; n_task integer;
begin
  if session_user::text not in ('claudio_panel','claudio_core') then
    raise exception 'claudio.user_set_only: cascade executes only via approval';
  end if;
  update l1.components set status = 'disabled', meta = meta || jsonb_build_object('disabled_by_role_retire', p_role_id)
  where status = 'enabled' and (config->'role_map') ? p_role_id;
  get diagnostics n_comp = row_count;
  update l1.tasks set primary_role_id = 'general', meta = meta || jsonb_build_object('rehomed_from', p_role_id)
  where status = 'open' and primary_role_id = p_role_id;
  get diagnostics n_task = row_count;
  update l1.roles set status = 'retired' where id = p_role_id;
  perform l1._audit('retire_role', 'roles', p_role_id, 'cascade',
                    jsonb_build_object('components_suspended', n_comp, 'tasks_rehomed', n_task));
  return jsonb_build_object('id', p_role_id, 'components_suspended', n_comp, 'tasks_rehomed', n_task);
end $$;

create or replace function l1.resolve_held_intake(p_intake_id uuid, p_answer text, p_answer_intake_id uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare n integer;
begin
  perform l1._rate_check();
  if session_user::text not in ('claudio_panel','claudio_core') then
    perform l1._dictation_check(p_answer_intake_id);  -- the answer is a user statement: prove the channel
  end if;
  update l1.intake set status = 'pending', meta = meta || jsonb_build_object('hold_answer', p_answer)
  where id = p_intake_id and status = 'held';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'claudio.bad_transition: intake % is not held', p_intake_id; end if;
  perform l1._audit('resolve_held_intake', 'intake', p_intake_id::text, 'update', jsonb_build_object('answer', p_answer));
  return jsonb_build_object('id', p_intake_id, 'status', 'pending');
end $$;

create or replace function l1.add_link_asserted(p_from_type text, p_from_id text, p_to_type text, p_to_id text,
                                                p_kind text, p_description text default null,
                                                p_source_intake_id uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_args jsonb; v_intake l1.intake;
begin
  perform l1._rate_check();
  v_args := jsonb_build_object('from_type', p_from_type, 'from_id', p_from_id, 'to_type', p_to_type,
                               'to_id', p_to_id, 'kind', p_kind, 'description', p_description);
  if session_user::text in ('claudio_panel','claudio_core') then
    return l1._commit_taste('add_link_asserted', v_args, 'by_role');
  end if;
  v_intake := l1._dictation_check(p_source_intake_id);
  return l1.stage_taste_write('add_link_asserted', v_args, p_source_intake_id);
end $$;

-- ---------- edge confirm (deterministic; NO LLM in this context, ever) ----------
create or replace function l1.confirm_taste_write(p_pending_id uuid, p_confirming_intake_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_msg l1.messages; v_confirm l1.intake; window_min integer; r jsonb;
begin
  if session_user::text not in ('w_edge','claudio_core') then
    raise exception 'claudio.edge_only: confirm_taste_write is the edge''s narrow grant';
  end if;
  select * into v_msg from l1.messages where id = p_pending_id;
  if v_msg.id is null or v_msg.privilege_class <> 'taste' or v_msg.status not in ('posted','claimed','read') then
    raise exception 'claudio.bad_transition: % is not a pending taste write', p_pending_id;
  end if;
  if v_msg.expires_at is not null and v_msg.expires_at < now() then
    update l1.messages set status = 'expired' where id = p_pending_id;
    raise exception 'claudio.stale_staging: pending taste write expired — re-stage';
  end if;
  window_min := coalesce((select (value #>> '{}')::integer from l1.parameters where key = 'dictation_window_min'), 10);
  select * into v_confirm from l1.intake where id = p_confirming_intake_id;
  if v_confirm.id is null
     or coalesce((v_confirm.sender->>'verified_user')::boolean, false) is not true
     or v_confirm.received_at <= v_msg.posted_at
     or v_confirm.received_at < now() - make_interval(mins => window_min) then
    raise exception 'claudio.intent_binding_failed: confirmation must be a FRESH verified-user message, after the read-back';
  end if;
  r := l1._commit_taste(v_msg.payload->>'taste_fn', v_msg.payload->'args', 'read_back_confirm',
                        jsonb_build_object('pending_id', p_pending_id,
                                           'confirming_intake_id', p_confirming_intake_id,
                                           'source_intake_id', v_msg.payload->'source_intake_id'));
  update l1.messages set status = 'approved', resolved_at = now() where id = p_pending_id;
  return r;
end $$;
comment on function l1.confirm_taste_write(uuid, uuid) is
  'The edge''s narrow grant: commits a staged taste write after verifying the confirming message (verified user, after the '
  'read-back, fresh). Deterministic code — the drafting LLM is not in this path. Example: edge renders payload.render '
  '("Set directive: ... — reply YES"), user replies "yes", edge calls confirm_taste_write(pending, that_reply_intake).';

-- ---------- panel set ----------
create or replace function l1._render_what_will_execute(p_actions jsonb)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
declare a jsonb; rendered jsonb := '[]'; args jsonb; nm text;
begin
  for a in select * from jsonb_array_elements(p_actions) loop
    args := a->'args';
    rendered := rendered || jsonb_build_array(jsonb_build_object(
      'fn', a->>'fn',
      'privilege_class', l1._privilege_class(a->>'fn'),
      'args', args,
      'resolved_names', (
        select coalesce(jsonb_object_agg(k, coalesce(
          case when v ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
               then (select name from l1.people where id = v::uuid)
               else null end, v)), '{}')
        from jsonb_each_text(args) as t(k, v)
        where k in ('person_id','keep_id','drop_id')
      )))::jsonb;
  end loop;
  return rendered;
end $$;
comment on function l1._render_what_will_execute(jsonb) is
  'The server-rendered approval view: per-action derived class, ids resolved to names. The agent summary is decoration; '
  'approval binds to THIS.';

create or replace function l1.approve_message(p_message_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_msg l1.messages; results jsonb; low_risk jsonb; a jsonb;
begin
  select * into v_msg from l1.messages where id = p_message_id;
  if v_msg.id is null or v_msg.status not in ('posted','claimed','read') then
    raise exception 'claudio.bad_transition: message % is not approvable', p_message_id;
  end if;
  if v_msg.expires_at is not null and v_msg.expires_at < now() then
    update l1.messages set status = 'expired' where id = p_message_id;
    raise exception 'claudio.stale_approval: % expired — a stale approval must not fire late; re-propose', p_message_id;
  end if;
  if session_user::text in ('claudio_panel','claudio_core') then
    null;  -- full approval authority
  elsif session_user::text = 'w_edge' then
    low_risk := coalesce((select value from l1.parameters where key = 'edge_approvable_classes'), '["routine"]');
    if not (low_risk ? coalesce(v_msg.privilege_class, 'routine')) then
      raise exception 'claudio.class_not_phone_approvable: % needs the panel', v_msg.privilege_class;
    end if;
  else
    raise exception 'claudio.approver_only: approve_message is panel/core (+edge for low-risk)';
  end if;
  if v_msg.privilege_class = 'taste' then
    raise exception 'claudio.use_confirm_flow: taste commits only via confirm_taste_write''s intent binding';
  end if;
  -- execute: panel-class sub-actions run under the approver's session guards
  results := '[]';
  for a in select * from jsonb_array_elements(coalesce(v_msg.payload->'actions', '[]')) loop
    if a->>'fn' = '_execute_role_cascade' then
      results := results || jsonb_build_array(jsonb_build_object('fn', a->>'fn',
                   'result', l1._execute_role_cascade(a->'args'->>'role_id')));
    elsif a->>'fn' = 'merge_people' then
      results := results || jsonb_build_array(jsonb_build_object('fn', a->>'fn',
                   'result', l1.merge_people((a->'args'->>'keep_id')::uuid, (a->'args'->>'drop_id')::uuid)));
    elsif a->>'fn' = 'merge_atoms' then
      results := results || jsonb_build_array(jsonb_build_object('fn', a->>'fn',
                   'result', l1.merge_atoms((a->'args'->>'canonical_id')::uuid,
                              (select array_agg(x::uuid) from jsonb_array_elements_text(a->'args'->'dup_ids') x))));
    else
      results := results || l1._apply_actions(jsonb_build_array(a), 'approve');
    end if;
  end loop;
  update l1.messages set status = 'approved', resolved_at = now(),
                         meta = meta || jsonb_build_object('approved_by', session_user::text, 'results', results)
  where id = p_message_id;
  perform l1._audit('approve_message', 'messages', p_message_id::text, 'approve',
                    jsonb_build_object('class', v_msg.privilege_class));
  return jsonb_build_object('id', p_message_id, 'status', 'approved', 'results', results);
end $$;
comment on function l1.approve_message(uuid) is
  'Approval binds to the server-rendered view (_render_what_will_execute), never the agent summary. L1 actions apply '
  'synchronously in-transaction. Expired proposals never fire (re-propose). Edge may approve low-risk classes only '
  '(edge_approvable_classes, core-ring). Taste NEVER approves here — confirm_taste_write owns it.';

create or replace function l1.reject_message(p_message_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare n integer;
begin
  if session_user::text not in ('claudio_panel','claudio_core','w_edge') then
    raise exception 'claudio.approver_only: reject_message';
  end if;
  update l1.messages set status = 'rejected', resolved_at = now(), meta = meta || jsonb_build_object('reject_reason', p_reason)
  where id = p_message_id and status in ('posted','claimed','read');
  get diagnostics n = row_count;
  if n = 0 then raise exception 'claudio.bad_transition: message % not rejectable', p_message_id; end if;
  perform l1._audit('reject_message', 'messages', p_message_id::text, 'reject', jsonb_build_object('reason', p_reason));
  return jsonb_build_object('id', p_message_id, 'status', 'rejected');
end $$;

create or replace function l1.apply_actions(p_actions jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
begin
  if session_user::text not in ('claudio_panel','claudio_core') then
    raise exception 'claudio.panel_only: apply_actions';
  end if;
  perform l1._validate_actions(p_actions);
  return l1._apply_actions(p_actions, 'apply_actions');
end $$;

create or replace function l1.merge_people(p_keep_id uuid, p_drop_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_keep l1.people; v_drop l1.people; first_id uuid; second_id uuid;
begin
  if session_user::text not in ('claudio_panel','claudio_core') then
    raise exception 'claudio.panel_only: merge_people is identity-class — never agent-direct, never standing-approvable';
  end if;
  if p_keep_id = p_drop_id then raise exception 'claudio.bad_args: cannot merge a person into themselves'; end if;
  -- lock in id order (deadlock-free under concurrent merges)
  first_id := least(p_keep_id, p_drop_id); second_id := greatest(p_keep_id, p_drop_id);
  perform 1 from l1.people where id = first_id for update;
  perform 1 from l1.people where id = second_id for update;
  select * into v_keep from l1.people where id = p_keep_id and status = 'active';
  select * into v_drop from l1.people where id = p_drop_id and status = 'active';
  if v_keep.id is null or v_drop.id is null then
    raise exception 'claudio.bad_transition: both people must be active (re-merge rejected)';
  end if;
  update l1.person_handles ph set person_id = p_keep_id where person_id = p_drop_id
    and not exists (select 1 from l1.person_handles k where k.source = ph.source and k.handle = ph.handle and k.person_id = p_keep_id);
  delete from l1.person_handles where person_id = p_drop_id;  -- collisions resolve to keep
  update l1.tasks set person_id = p_keep_id where person_id = p_drop_id;
  update l1.expectations set person_id = p_keep_id where person_id = p_drop_id;
  update l1.links set from_id = p_keep_id::text where from_type = 'person' and from_id = p_drop_id::text
    and not exists (select 1 from l1.links k where k.from_type = 'person' and k.from_id = p_keep_id::text
                    and k.to_type = l1.links.to_type and k.to_id = l1.links.to_id and k.kind = l1.links.kind);
  update l1.links set to_id = p_keep_id::text where to_type = 'person' and to_id = p_drop_id::text
    and not exists (select 1 from l1.links k where k.to_type = 'person' and k.to_id = p_keep_id::text
                    and k.from_type = l1.links.from_type and k.from_id = l1.links.from_id and k.kind = l1.links.kind);
  update l1.people set status = 'archived', meta = meta || jsonb_build_object('merged_into', p_keep_id) where id = p_drop_id;
  perform l1._audit('merge_people', 'people', p_keep_id::text, 'merge', jsonb_build_object('dropped', p_drop_id));
  return jsonb_build_object('id', p_keep_id, 'name', v_keep.name, 'merged', p_drop_id);
end $$;

create or replace function l1.merge_atoms(p_canonical_id uuid, p_dup_ids uuid[], p_confidence real default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_bar real; d uuid;
begin
  if session_user::text = 'w_merge' then
    v_bar := coalesce((select (value #>> '{}')::real from l1.parameters where key = 'merge_auto_bar'), 0.9);
    if p_confidence is null or p_confidence < v_bar then
      raise exception 'claudio.propose_instead: below the auto-bar (%) the merge gardener proposes', v_bar;
    end if;
  elsif session_user::text not in ('claudio_panel','claudio_core') then
    raise exception 'claudio.panel_only: merge_atoms (w_merge above the auto-bar excepted)';
  end if;
  if exists (select 1 from l1.atoms where id = p_canonical_id and canonical_of is not null) then
    raise exception 'claudio.bad_args: target must be canonical (no merge chains)';
  end if;
  foreach d in array p_dup_ids loop
    if d = p_canonical_id then raise exception 'claudio.bad_args: self-merge'; end if;
    if exists (select 1 from l1.atoms where canonical_of = d) then
      raise exception 'claudio.bad_args: % is itself a merge target (duplicates may not be targets)', d;
    end if;
  end loop;
  update l1.atoms set canonical_of = p_canonical_id where id = any(p_dup_ids) and canonical_of is null;
  perform l1._audit('merge_atoms', 'atoms', p_canonical_id::text, 'merge', jsonb_build_object('dups', to_jsonb(p_dup_ids)));
  return jsonb_build_object('id', p_canonical_id, 'merged', to_jsonb(p_dup_ids));
end $$;

create or replace function l1.set_component_status(p_component_id text, p_status text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_rel text; n integer;
begin
  if session_user::text not in ('claudio_panel','claudio_core') then
    raise exception 'claudio.panel_only: set_component_status';
  end if;
  select reliability into v_rel from l1.components where id = p_component_id;
  if v_rel is null then raise exception 'claudio.endpoint_not_found: component/%', p_component_id; end if;
  if v_rel = 'critical' and p_status = 'disabled' and session_user::text <> 'claudio_core' then
    raise exception 'claudio.critical_component: % disables only from a core session', p_component_id;
  end if;
  update l1.components set status = p_status where id = p_component_id;
  get diagnostics n = row_count;
  perform l1._audit('set_component_status', 'components', p_component_id, 'update', jsonb_build_object('status', p_status));
  return jsonb_build_object('id', p_component_id, 'status', p_status);
end $$;

-- ---------- core set ----------
create or replace function l1.register_component(p_id text, p_kind text, p_circle text,
                                                 p_definition_path text default null,
                                                 p_trigger jsonb default '{"type":"manual"}',
                                                 p_config jsonb default '{}',
                                                 p_reliability text default 'standard')
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
begin
  if session_user::text <> 'claudio_core' then
    raise exception 'claudio.core_only: registration is a core-deploy act (capability is issued, never declared)';
  end if;
  insert into l1.components (id, kind, circle, definition_path, trigger, config, reliability)
  values (p_id, p_kind, p_circle, p_definition_path, p_trigger, p_config, p_reliability)
  on conflict (id) do update
    set kind = excluded.kind, circle = excluded.circle, definition_path = excluded.definition_path,
        trigger = excluded.trigger, config = excluded.config, reliability = excluded.reliability;
  perform l1._audit('register_component', 'components', p_id, 'upsert', jsonb_build_object('kind', p_kind, 'circle', p_circle));
  return jsonb_build_object('id', p_id, 'name', p_id);
end $$;

create or replace function l1.purge(p_table text, p_row_id text, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare n integer;
begin
  if session_user::text <> 'claudio_core' then
    raise exception 'claudio.core_only: purge is the privacy override';
  end if;
  if p_table not in ('atoms','intake','tasks','expectations','links','messages','documents','people','person_handles') then
    raise exception 'claudio.bad_args: % is not purgeable', p_table;
  end if;
  execute format('delete from l1.%I where id::text = $1', p_table) using p_row_id;
  get diagnostics n = row_count;
  perform l1._audit('purge', p_table, p_row_id, 'delete', jsonb_build_object('reason', p_reason, 'rows', n));
  return jsonb_build_object('purged', n, 'table', p_table);
end $$;
comment on function l1.purge(text, text, text) is 'Core-only, fact-audited (the deletion is recorded; the content is gone). Backups age out <= retention.';

-- ---------- watchdog narrow ----------
create or replace function l1.reap_expired_claims()
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare lease_min integer; n integer;
begin
  if session_user::text not in ('w_watchdog','claudio_core') then
    raise exception 'claudio.watchdog_only: reap_expired_claims';
  end if;
  lease_min := coalesce((select (value #>> '{}')::integer from l1.parameters where key = 'claim_lease_min'), 10);
  update l1.messages set status = 'posted', claimed_by = null, claimed_at = null
  where status = 'claimed' and claimed_at < now() - make_interval(mins => lease_min);
  get diagnostics n = row_count;
  update l1.messages set status = 'expired' where status in ('posted','claimed') and expires_at < now();
  perform l1._audit('reap_expired_claims', 'messages', '-', 'reap', jsonb_build_object('reaped', n));
  return jsonb_build_object('reaped', n);
end $$;

reset role;
