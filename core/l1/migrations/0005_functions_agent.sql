-- 0005: the agent function set + the batch dispatcher.
-- Every write function: validate -> rate ceiling -> sensitivity clamp -> write -> audit (session_user) -> return.
-- All SECURITY DEFINER, owned by claudio_core (non-superuser; FORCE RLS binds it), search_path pinned.
set role claudio_core;

-- ---------- privilege classes ----------
create or replace function l1._privilege_class(p_fn text) returns text
language sql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
  select coalesce(
    (select value->>p_fn from l1.parameters where key = 'fn_privilege_class'),
    'routine')
$$;
comment on function l1._privilege_class(text) is
  'DERIVED server-side from the core-ring fn_privilege_class map; never trusted from payload. '
  'Classes: routine | identity | panel | taste | core. Examples: create_task=>routine, merge_people=>identity, set_directive=>taste.';

create or replace function l1._fn_in_callers_set(p_fn text) returns boolean
language sql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
  select (select value->'agent' ? p_fn from l1.parameters where key = 'fn_sets')
      or coalesce((select value->(session_user::text) ? p_fn from l1.parameters where key = 'narrow_grants'), false)
$$;

-- ---------- $ref resolution ----------
create or replace function l1._resolve_refs(p jsonb, p_results jsonb) returns jsonb
language plpgsql immutable as $$
declare k text; v jsonb; out jsonb; i integer; arr jsonb := '[]';
begin
  if p is null then return null; end if;
  case jsonb_typeof(p)
    when 'object' then
      if p ? '$ref' and (select count(*) from jsonb_object_keys(p)) = 1 then
        i := (p->>'$ref')::integer;
        if p_results->i is null then
          raise exception 'claudio.bad_ref: {"$ref": %} points past the results so far', i;
        end if;
        return p_results->i->'result'->'id';
      end if;
      out := '{}';
      for k, v in select * from jsonb_each(p) loop
        out := jsonb_set(out, array[k], l1._resolve_refs(v, p_results));
      end loop;
      return out;
    when 'array' then
      for v in select * from jsonb_array_elements(p) loop
        arr := arr || jsonb_build_array(l1._resolve_refs(v, p_results));
      end loop;
      return arr;
    else
      return p;
  end case;
end $$;

-- ---------- intake ----------
create or replace function l1.capture(p_adapter text, p_raw text, p_sender jsonb default null,
                                      p_locator text default null, p_raw_ref jsonb default null,
                                      p_sensitivity smallint default 0, p_rawness text default 'verbatim')
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_id uuid; v_sens smallint;
begin
  perform l1._rate_check();
  if not exists (select 1 from l1.components where id = p_adapter) then
    raise exception 'claudio.unknown_adapter: %', p_adapter;
  end if;
  if p_rawness not in ('verbatim','derived') then
    raise exception 'claudio.invalid_rawness: %', p_rawness;
  end if;
  v_sens := least(l1._clamp_sensitivity(p_sensitivity, null, p_adapter), 1);  -- captures cap at 1; restricted routes to the panel
  insert into l1.intake (adapter, sender, raw, raw_ref, locator, sensitivity, rawness)
  values (p_adapter, p_sender, p_raw, p_raw_ref, p_locator, v_sens, p_rawness)
  on conflict (adapter, locator) where locator is not null do nothing
  returning id into v_id;
  if v_id is null then  -- idempotent: durable capture, exactly once (race-safe under concurrent replays)
    select id into v_id from l1.intake where adapter = p_adapter and locator = p_locator;
    return jsonb_build_object('id', v_id, 'deduped', true);
  end if;
  perform l1._audit('capture', 'intake', v_id::text, 'insert', jsonb_build_object('adapter', p_adapter, 'locator', p_locator));
  return jsonb_build_object('id', v_id, 'deduped', false);
end $$;
comment on function l1.capture(text, text, jsonb, text, jsonb, smallint, text) is
  'Dumb, instant, durable. Dedup on (adapter, locator) — replays are free. Examples: '
  'capture(''edge-imessage'', ''t: pick up...'', ''{"source":"imessage","handle":"+14355550100","verified_user":true}'', ''msg-9912''); '
  'capture(''window-gcal'', ''{"event":...}'', null, ''gcal-evt-4411''). Sensitivity hard-capped at 1 here. '
  'rawness: verbatim (default) | derived — probing windows that summarize upstream MUST tag derived (P8).';

create or replace function l1.hold_intake(p_intake_id uuid, p_question_message_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare n integer;
begin
  perform l1._rate_check();
  update l1.intake set status = 'held', meta = meta || jsonb_build_object('question_message_id', p_question_message_id)
  where id = p_intake_id and status = 'pending';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'claudio.bad_transition: intake % is not pending', p_intake_id; end if;
  perform l1._audit('hold_intake', 'intake', p_intake_id::text, 'update', null);
  return jsonb_build_object('id', p_intake_id, 'status', 'held');
end $$;

create or replace function l1.discard_intake(p_intake_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare n integer;
begin
  perform l1._rate_check();
  update l1.intake set status = 'discarded', meta = meta || jsonb_build_object('discard_reason', p_reason)
  where id = p_intake_id and status in ('pending','held');
  get diagnostics n = row_count;
  if n = 0 then raise exception 'claudio.bad_transition: intake % is not pending/held', p_intake_id; end if;
  perform l1._audit('discard_intake', 'intake', p_intake_id::text, 'update', jsonb_build_object('reason', p_reason));
  return jsonb_build_object('id', p_intake_id, 'status', 'discarded');
end $$;

-- ---------- people ----------
create or replace function l1.create_person(p_name text, p_primary_role_id text default null,
                                            p_summary text default null, p_sensitivity smallint default 0,
                                            p_handles jsonb default '[]', p_meta jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_id uuid; h jsonb; v_owner uuid; v_sens smallint;
begin
  perform l1._rate_check();
  for h in select * from jsonb_array_elements(p_handles) loop
    select person_id into v_owner from l1.person_handles where source = h->>'source' and handle = h->>'handle';
    if v_owner is not null then
      raise exception 'claudio.handle_conflict: %/% belongs to person % — match, don''t create', h->>'source', h->>'handle', v_owner;
    end if;
  end loop;
  v_sens := l1._clamp_sensitivity(p_sensitivity, p_primary_role_id, null);
  insert into l1.people (name, primary_role_id, summary, sensitivity, meta)
  values (p_name, p_primary_role_id, p_summary, v_sens, p_meta)
  returning id into v_id;
  for h in select * from jsonb_array_elements(p_handles) loop
    insert into l1.person_handles (person_id, source, handle) values (v_id, h->>'source', h->>'handle');
  end loop;
  perform l1._audit('create_person', 'people', v_id::text, 'insert', jsonb_build_object('name', p_name));
  return jsonb_build_object('id', v_id, 'name', p_name);
end $$;
comment on function l1.create_person(text, text, text, smallint, jsonb, jsonb) is
  'claudio.handle_conflict if any handle is owned — match, don''t create. Examples: '
  'create_person(''Daniel Cho'', ''prod''); create_person(''Priya Nair'', ''prod'', p_handles=>''[{"source":"slack","handle":"U-NEW"}]''). '
  'Edge case: an existing handle means you wanted add_handle or nothing at all.';

create or replace function l1.add_handle(p_person_id uuid, p_source text, p_handle text, p_verified boolean default false)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_owner uuid; v_name text;
begin
  perform l1._rate_check();
  if p_verified and session_user::text not in ('claudio_panel','claudio_core') then
    raise exception 'claudio.user_set_only: verified handles are user-asserted (panel/core)';
  end if;
  select person_id into v_owner from l1.person_handles where source = p_source and handle = p_handle;
  if v_owner is not null then
    if v_owner = p_person_id then return jsonb_build_object('id', p_person_id, 'deduped', true); end if;
    raise exception 'claudio.handle_conflict: %/% belongs to person %', p_source, p_handle, v_owner;
  end if;
  select name into v_name from l1.people where id = p_person_id;
  if v_name is null then raise exception 'claudio.endpoint_not_found: person/%', p_person_id; end if;
  insert into l1.person_handles (person_id, source, handle, verified) values (p_person_id, p_source, p_handle, p_verified);
  perform l1._audit('add_handle', 'person_handles', p_handle, 'insert', jsonb_build_object('person', p_person_id, 'source', p_source));
  return jsonb_build_object('id', p_person_id, 'name', v_name);
end $$;

create or replace function l1.update_person(p_person_id uuid, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_row l1.people; k text; is_user_path boolean;
begin
  perform l1._rate_check();
  is_user_path := session_user::text in ('claudio_panel','claudio_core');
  select * into v_row from l1.people where id = p_person_id;
  if v_row.id is null then raise exception 'claudio.endpoint_not_found: person/%', p_person_id; end if;
  if not is_user_path then
    if p_patch ? 'verified_fields' then
      raise exception 'claudio.user_set_only: verified_fields is user-asserted';
    end if;
    for k in select unnest(v_row.verified_fields) loop
      if p_patch ? k then
        raise exception 'claudio.verified_field: % was user-asserted; agents cannot touch it', k;
      end if;
    end loop;
    if p_patch ? 'sensitivity' and (p_patch->>'sensitivity')::smallint < v_row.sensitivity then
      raise exception 'claudio.sensitivity_lower: agents cannot lower sensitivity';
    end if;
  end if;
  update l1.people set
    name        = coalesce(p_patch->>'name', name),
    summary     = coalesce(p_patch->>'summary', summary),
    status      = coalesce(p_patch->>'status', status),
    primary_role_id = coalesce(p_patch->>'primary_role_id', primary_role_id),
    sensitivity = coalesce((p_patch->>'sensitivity')::smallint, sensitivity),
    verified_fields = case when is_user_path and p_patch ? 'verified_fields'
                           then (select array_agg(x) from jsonb_array_elements_text(p_patch->'verified_fields') x)
                           else verified_fields end,
    meta        = meta || coalesce(p_patch->'meta', '{}')
  where id = p_person_id;
  perform l1._audit('update_person', 'people', p_person_id::text, 'update', p_patch);
  return jsonb_build_object('id', p_person_id, 'name', coalesce(p_patch->>'name', v_row.name));
end $$;

-- ---------- atoms ----------
create or replace function l1.record_atom(p_ts timestamptz, p_kind text, p_summary text,
                                          p_ts_end timestamptz default null, p_detail text default null,
                                          p_quotes jsonb default '[]', p_refs jsonb default '[]',
                                          p_primary_role_id text default null, p_links jsonb default '[]',
                                          p_sensitivity smallint default 0, p_meta jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_id uuid; lk jsonb; v_sens smallint;
begin
  perform l1._rate_check();
  v_sens := l1._clamp_sensitivity(p_sensitivity, p_primary_role_id, null);
  insert into l1.atoms (ts, ts_end, kind, summary, detail, quotes, refs, primary_role_id, sensitivity, meta)
  values (p_ts, p_ts_end, p_kind, p_summary, p_detail, p_quotes, p_refs, p_primary_role_id, v_sens, p_meta)
  returning id into v_id;
  for lk in select * from jsonb_array_elements(p_links) loop
    perform l1.add_link(coalesce(lk->>'from_type','atom'),
                        coalesce(lk->>'from_id', v_id::text),
                        lk->>'to_type', lk->>'to_id', lk->>'kind',
                        coalesce(lk->>'origin','inferred'),
                        coalesce((lk->>'confidence')::real, 0.9),
                        lk->>'description');
  end loop;
  perform l1._audit('record_atom', 'atoms', v_id::text, 'insert', jsonb_build_object('kind', p_kind, 'ts', p_ts));
  return jsonb_build_object('id', v_id, 'name', left(p_summary, 80));
end $$;
comment on function l1.record_atom(timestamptz, text, text, timestamptz, text, jsonb, jsonb, text, jsonb, smallint, jsonb) is
  'The atom writer. Quote-at-write: load-bearing facts go in p_quotes VERBATIM (P8). links: [{"to_type":"person","to_id":"...","kind":"participant"}]. '
  'Examples: record_atom(''2026-06-09T14:00-07'', ''meeting'', ''Advisor meeting: ...'', p_quotes=>''["I''''ll have the draft by Tuesday"]''); '
  'a thread-day: record_atom(ts, ''communication'', ''Day of banter with Tyler...''). Edge case: per-message atoms are WRONG — one per episode.';

create or replace function l1.amend_atom(p_atom_id uuid, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_row l1.atoms;
begin
  perform l1._rate_check();
  select * into v_row from l1.atoms where id = p_atom_id;
  if v_row.id is null then raise exception 'claudio.endpoint_not_found: atom/%', p_atom_id; end if;
  if session_user::text not in ('claudio_panel','claudio_core') then
    if p_patch ? 'sensitivity' and (p_patch->>'sensitivity')::smallint < v_row.sensitivity then
      raise exception 'claudio.sensitivity_lower: agents cannot lower sensitivity';
    end if;
    if p_patch ? 'notable' and session_user::text <> 'w_brief' then
      raise exception 'claudio.daily_pass_only: notable is assigned at the daily pass (use meta.notable_candidate)';
    end if;
  end if;
  if session_user::text in ('claudio_panel','claudio_core','w_brief')
     and p_patch ? 'notable' and (p_patch->>'notable')::boolean
     and (p_patch->>'notable_reason') is null then
    raise exception 'claudio.notable_reason_required: notable is a selection, not prose (P12) — pass notable_reason from the notable_reason vocabulary';
  end if;
  -- prior version snapshotted to audit
  perform l1._audit('amend_atom', 'atoms', p_atom_id::text, 'update',
                    jsonb_build_object('prior', to_jsonb(v_row), 'patch', p_patch));
  update l1.atoms set
    summary = coalesce(p_patch->>'summary', summary),
    detail  = coalesce(p_patch->>'detail', detail),
    kind    = coalesce(p_patch->>'kind', kind),
    ts      = coalesce((p_patch->>'ts')::timestamptz, ts),
    ts_end  = coalesce((p_patch->>'ts_end')::timestamptz, ts_end),
    quotes  = coalesce(p_patch->'quotes', quotes),
    refs    = coalesce(p_patch->'refs', refs),
    notable = case when session_user::text in ('claudio_panel','claudio_core','w_brief') and p_patch ? 'notable'
                   then (p_patch->>'notable')::boolean else notable end,
    notable_reason = case when session_user::text in ('claudio_panel','claudio_core','w_brief') and p_patch ? 'notable'
                          then (case when (p_patch->>'notable')::boolean then p_patch->>'notable_reason' else null end)
                          else notable_reason end,
    primary_role_id = coalesce(p_patch->>'primary_role_id', primary_role_id),
    sensitivity = coalesce((p_patch->>'sensitivity')::smallint, sensitivity),
    meta    = meta || coalesce(p_patch->'meta', '{}')
  where id = p_atom_id;
  return jsonb_build_object('id', p_atom_id, 'name', left(coalesce(p_patch->>'summary', v_row.summary), 80));
end $$;
comment on function l1.amend_atom(uuid, jsonb) is
  'Prior version snapshots to audit. Agents cannot lower sensitivity or set notable (the brief''s daily pass and the user can). '
  'Setting notable=true requires notable_reason from the closed vocabulary (P12: judgments are selections, never prose). '
  'Examples: amend_atom(id, ''{"detail":"..."}''); amend_atom(id, ''{"meta":{"notable_candidate":true}}''); '
  'amend_atom(id, ''{"notable":true,"notable_reason":"purpose_advance"}'') [daily pass/panel only].';

-- ---------- tasks & expectations ----------
create or replace function l1.create_task(p_description text, p_due timestamptz default null,
                                          p_person_id uuid default null, p_primary_role_id text default null,
                                          p_source_ref jsonb default null, p_sensitivity smallint default 0,
                                          p_meta jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_id uuid; v_sens smallint;
begin
  perform l1._rate_check();
  v_sens := l1._clamp_sensitivity(p_sensitivity, p_primary_role_id, null);
  insert into l1.tasks (description, due, person_id, primary_role_id, source_ref, sensitivity, meta)
  values (p_description, p_due, p_person_id, p_primary_role_id, p_source_ref, v_sens, p_meta)
  returning id into v_id;
  perform l1._audit('create_task', 'tasks', v_id::text, 'insert', jsonb_build_object('description', p_description, 'due', p_due));
  return jsonb_build_object('id', v_id, 'name', left(p_description, 80));
end $$;

create or replace function l1.complete_task(p_task_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare n integer;
begin
  perform l1._rate_check();
  update l1.tasks set status = 'done' where id = p_task_id and status = 'open';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'claudio.bad_transition: task % is not open', p_task_id; end if;
  perform l1._audit('complete_task', 'tasks', p_task_id::text, 'update', null);
  return jsonb_build_object('id', p_task_id, 'status', 'done');
end $$;

create or replace function l1.drop_task(p_task_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare n integer;
begin
  perform l1._rate_check();
  update l1.tasks set status = 'dropped', meta = meta || jsonb_build_object('drop_reason', p_reason)
  where id = p_task_id and status = 'open';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'claudio.bad_transition: task % is not open', p_task_id; end if;
  perform l1._audit('drop_task', 'tasks', p_task_id::text, 'update', jsonb_build_object('reason', p_reason));
  return jsonb_build_object('id', p_task_id, 'status', 'dropped');
end $$;

create or replace function l1.amend_task(p_task_id uuid, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_row l1.tasks;
begin
  perform l1._rate_check();
  select * into v_row from l1.tasks where id = p_task_id;
  if v_row.id is null then raise exception 'claudio.endpoint_not_found: task/%', p_task_id; end if;
  if session_user::text not in ('claudio_panel','claudio_core')
     and p_patch ? 'sensitivity' and (p_patch->>'sensitivity')::smallint < v_row.sensitivity then
    raise exception 'claudio.sensitivity_lower: agents cannot lower sensitivity';
  end if;
  perform l1._audit('amend_task', 'tasks', p_task_id::text, 'update',
                    jsonb_build_object('prior', to_jsonb(v_row), 'patch', p_patch));
  update l1.tasks set
    description = coalesce(p_patch->>'description', description),
    due         = coalesce((p_patch->>'due')::timestamptz, due),
    person_id   = coalesce((p_patch->>'person_id')::uuid, person_id),
    primary_role_id = coalesce(p_patch->>'primary_role_id', primary_role_id),
    sensitivity = coalesce((p_patch->>'sensitivity')::smallint, sensitivity),
    meta        = meta || coalesce(p_patch->'meta', '{}')
  where id = p_task_id;
  return jsonb_build_object('id', p_task_id, 'name', left(coalesce(p_patch->>'description', v_row.description), 80));
end $$;

create or replace function l1.create_expectation(p_description text, p_person_id uuid default null,
                                                 p_due timestamptz default null, p_follow_up text default 'none',
                                                 p_follow_up_at timestamptz default null,
                                                 p_primary_role_id text default null, p_source_ref jsonb default null,
                                                 p_sensitivity smallint default 0, p_meta jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_id uuid; v_sens smallint;
begin
  perform l1._rate_check();
  v_sens := l1._clamp_sensitivity(p_sensitivity, p_primary_role_id, null);
  insert into l1.expectations (description, person_id, due, follow_up, follow_up_at, primary_role_id, source_ref, sensitivity, meta)
  values (p_description, p_person_id, p_due, p_follow_up, p_follow_up_at, p_primary_role_id, p_source_ref, v_sens, p_meta)
  returning id into v_id;
  perform l1._audit('create_expectation', 'expectations', v_id::text, 'insert', jsonb_build_object('description', p_description));
  return jsonb_build_object('id', v_id, 'name', left(p_description, 80));
end $$;

create or replace function l1.resolve_expectation(p_expectation_id uuid, p_status text default 'met',
                                                  p_resolved_by uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare n integer;
begin
  perform l1._rate_check();
  if p_status not in ('met','missed','dropped') then
    raise exception 'claudio.bad_args: resolve status must be met|missed|dropped';
  end if;
  update l1.expectations set status = p_status, resolved_by = p_resolved_by
  where id = p_expectation_id and status = 'pending';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'claudio.bad_transition: expectation % is not pending', p_expectation_id; end if;
  perform l1._audit('resolve_expectation', 'expectations', p_expectation_id::text, 'update',
                    jsonb_build_object('status', p_status, 'resolved_by', p_resolved_by));
  return jsonb_build_object('id', p_expectation_id, 'status', p_status);
end $$;

-- ---------- links ----------
create or replace function l1.add_link(p_from_type text, p_from_id text, p_to_type text, p_to_id text,
                                       p_kind text, p_origin text default 'inferred',
                                       p_confidence real default null, p_description text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_id uuid; v_vis boolean;
begin
  perform l1._rate_check();
  if p_origin = 'asserted' and session_user::text not in ('claudio_panel','claudio_core') then
    raise exception 'claudio.user_set_only: asserted links are user-set (agents infer)';
  end if;
  if p_origin = 'inferred' and p_confidence is null then
    raise exception 'claudio.bad_args: inferred links carry confidence';
  end if;
  -- person<->person: asserted, or explicit evidence >= 0.9 — else propose (P7)
  if p_from_type = 'person' and p_to_type = 'person' and p_origin = 'inferred' and p_confidence < 0.9 then
    raise exception 'claudio.propose_instead: person-person below 0.9 goes through a proposal';
  end if;
  -- clearance-bounded existence check: missing and above-clearance raise IDENTICALLY (no oracle)
  v_vis := l1._endpoint_visible(p_from_type, p_from_id) and l1._endpoint_visible(p_to_type, p_to_id);
  if not v_vis then
    raise exception 'claudio.endpoint_not_found: link endpoints must exist (%/% -> %/%)', p_from_type, p_from_id, p_to_type, p_to_id;
  end if;
  insert into l1.links (from_type, from_id, to_type, to_id, kind, origin, confidence, description)
  values (p_from_type, p_from_id, p_to_type, p_to_id, p_kind, p_origin, p_confidence, p_description)
  on conflict (from_type, from_id, to_type, to_id, kind)
  do update set invalidated_at = null, confidence = excluded.confidence, description = coalesce(excluded.description, l1.links.description)
  returning id into v_id;
  perform l1._audit('add_link', 'links', v_id::text, 'insert',
                    jsonb_build_object('from', p_from_type || '/' || p_from_id, 'to', p_to_type || '/' || p_to_id, 'kind', p_kind, 'origin', p_origin));
  return jsonb_build_object('id', v_id, 'name', p_kind);
end $$;

create or replace function l1._endpoint_visible(p_type text, p_id text) returns boolean
language plpgsql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v boolean;
begin
  if p_type = 'component' then
    select exists (select 1 from l1.components where id = p_id) into v;       -- no sensitivity column
  elsif p_type = 'document' then
    select exists (select 1 from l1.documents where path = p_id and sensitivity <= l1.clearance()) into v;
  else
    execute format(
      'select exists (select 1 from l1.%I where id::text = $1 and sensitivity <= l1.clearance())',
      case p_type
        when 'person' then 'people' when 'role' then 'roles' when 'purpose' then 'purpose'
        when 'task' then 'tasks' when 'expectation' then 'expectations' when 'atom' then 'atoms'
        when 'directive' then 'directives'
        else null end) into v using p_id;
  end if;
  return coalesce(v, false);
exception when others then
  return false;
end $$;

create or replace function l1.invalidate_link(p_link_id uuid, p_superseded_by uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_row l1.links;
begin
  perform l1._rate_check();
  select * into v_row from l1.links where id = p_link_id;
  if v_row.id is null then raise exception 'claudio.endpoint_not_found: link/%', p_link_id; end if;
  if v_row.origin = 'asserted' and session_user::text not in ('claudio_panel','claudio_core') then
    raise exception 'claudio.user_set_only: asserted links are invalidated by the user only';
  end if;
  update l1.links set invalidated_at = now(), superseded_by = p_superseded_by
  where id = p_link_id and invalidated_at is null;
  perform l1._audit('invalidate_link', 'links', p_link_id::text, 'update', jsonb_build_object('superseded_by', p_superseded_by));
  return jsonb_build_object('id', p_link_id, 'invalidated', true);
end $$;
comment on function l1.invalidate_link(uuid, uuid) is
  'Supersedence, not deletion: history stays queryable for point-in-time questions. Asserted links: user-set only.';

-- ---------- documents ----------
create or replace function l1.register_page(p_path text, p_kind text, p_title text, p_chapter text,
                                            p_entity_type text default null, p_entity_id text default null,
                                            p_read_moment text default null, p_sensitivity smallint default 0)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
begin
  perform l1._rate_check();
  if p_read_moment is null or btrim(p_read_moment) = '' then
    raise exception 'claudio.read_moment_required: when will this page be read — by Sam or his agents? Can''t name one => no page';
  end if;
  insert into l1.documents (path, kind, title, chapter, entity_type, entity_id, read_moment, sensitivity, freshness)
  values (p_path, p_kind, p_title, p_chapter, p_entity_type, p_entity_id, p_read_moment, least(p_sensitivity, 1), now());
  perform l1._audit('register_page', 'documents', p_path, 'insert', jsonb_build_object('chapter', p_chapter, 'title', p_title));
  return jsonb_build_object('id', p_path, 'name', p_title);
end $$;

create or replace function l1.move_page(p_old_path text, p_new_path text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare n integer;
begin
  perform l1._rate_check();
  update l1.documents set path = p_new_path where path = p_old_path;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'claudio.endpoint_not_found: document/%', p_old_path; end if;
  update l1.links set from_id = p_new_path where from_type = 'document' and from_id = p_old_path;
  update l1.links set to_id = p_new_path where to_type = 'document' and to_id = p_old_path;
  perform l1._audit('move_page', 'documents', p_new_path, 'update', jsonb_build_object('from', p_old_path));
  return jsonb_build_object('id', p_new_path, 'moved_from', p_old_path);
end $$;
comment on function l1.move_page(text, text) is 'Atomic: inbound link rows rewrite with the move (the file half is wiki-tool''s).';

-- ---------- messages ----------
create or replace function l1.post_message(p_queue text, p_kind text, p_payload jsonb,
                                           p_sensitivity smallint default 0, p_expires_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_id uuid;
begin
  perform l1._rate_check();
  if p_kind = 'proposal' then
    raise exception 'claudio.use_propose: proposals go through propose() — class derivation is not optional';
  end if;
  insert into l1.messages (queue, kind, from_actor, payload, sensitivity, expires_at)
  values (p_queue, p_kind, session_user::text, p_payload, p_sensitivity, p_expires_at)
  returning id into v_id;
  perform l1._audit('post_message', 'messages', v_id::text, 'insert', jsonb_build_object('queue', p_queue, 'kind', p_kind));
  return jsonb_build_object('id', v_id, 'queue', p_queue);
end $$;

create or replace function l1.claim_message(p_queue text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_row l1.messages; acl jsonb; lease_min integer;
begin
  acl := (select value from l1.parameters where key = 'queue_acl');
  if acl is not null and acl ? p_queue
     and not (acl->p_queue ? session_user::text) and session_user::text not in ('claudio_core') then
    raise exception 'claudio.queue_scope: % may not claim from queue %', session_user, p_queue;
  end if;
  lease_min := coalesce((select (value #>> '{}')::integer from l1.parameters where key = 'claim_lease_min'), 10);
  -- reap expired leases at claim time (race-safe; the watchdog reaper is the backstop)
  update l1.messages set status = 'posted', claimed_by = null, claimed_at = null
  where queue = p_queue and status = 'claimed' and claimed_at < now() - make_interval(mins => lease_min);
  select * into v_row from l1.messages
  where queue = p_queue and status = 'posted' and (expires_at is null or expires_at > now())
  order by posted_at limit 1 for update skip locked;
  if v_row.id is null then return null; end if;
  update l1.messages set status = 'claimed', claimed_by = session_user::text, claimed_at = now() where id = v_row.id;
  return to_jsonb(v_row) || jsonb_build_object('status', 'claimed');
end $$;

create or replace function l1.read_message(p_message_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_row l1.messages;
begin
  update l1.messages set status = 'read', read_at = now()
  where id = p_message_id and status in ('posted','claimed') returning * into v_row;
  if v_row.id is null then raise exception 'claudio.bad_transition: message % not readable', p_message_id; end if;
  return to_jsonb(v_row);
end $$;

create or replace function l1.resolve_message(p_message_id uuid, p_resolution jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare n integer;
begin
  update l1.messages set status = 'done', resolved_at = now(), meta = meta || jsonb_build_object('resolution', p_resolution)
  where id = p_message_id and status in ('posted','claimed','read');
  get diagnostics n = row_count;
  if n = 0 then raise exception 'claudio.bad_transition: message % not resolvable', p_message_id; end if;
  perform l1._audit('resolve_message', 'messages', p_message_id::text, 'update', p_resolution);
  return jsonb_build_object('id', p_message_id, 'status', 'done');
end $$;

-- ---------- propose ----------
create or replace function l1.propose(p_summary text, p_actions jsonb, p_evidence jsonb default '[]',
                                      p_quoted text default null, p_queue text default 'user')
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare a jsonb; v_class text; worst text := 'routine'; v_id uuid; v_hash text; v_sens smallint := 0;
        rank_map jsonb := '{"routine":0,"identity":1,"panel":1,"user_relay":1,"taste":3,"core":3}';
begin
  perform l1._rate_check();
  perform l1._validate_actions(p_actions);
  for a in select * from jsonb_array_elements(p_actions) loop
    v_class := l1._privilege_class(a->>'fn');
    if v_class in ('taste','core') then
      raise exception 'claudio.class_not_proposable: % is %-class — taste goes through stage_taste_write + the confirm flow; core is a human act', a->>'fn', v_class;
    end if;
    if v_class = 'routine' and not l1._fn_in_callers_set(a->>'fn') then
      raise exception 'claudio.above_privilege: % is not in %''s own function set', a->>'fn', session_user;
    end if;
    if (rank_map->>v_class)::int > (rank_map->>worst)::int then worst := v_class; end if;
  end loop;
  v_hash := md5(p_actions::text);
  -- regeneration dedup: user absence never produces a duplicate pile
  select id into v_id from l1.messages
  where from_actor = session_user::text and privilege_class = worst and content_hash = v_hash
    and status in ('posted','claimed');
  if v_id is not null then
    return jsonb_build_object('id', v_id, 'deduped', true);
  end if;
  insert into l1.messages (queue, kind, from_actor, payload, privilege_class, requires_approval, content_hash,
                           expires_at, sensitivity)
  values (p_queue, 'proposal', session_user::text,
          jsonb_build_object('summary', p_summary, 'actions', p_actions, 'evidence', p_evidence, 'quoted', p_quoted),
          worst, true, v_hash,
          now() + coalesce((select (value #>> '{}')::integer from l1.parameters where key = 'proposal_ttl_days'), 14) * interval '1 day',
          v_sens)
  returning id into v_id;
  perform l1._audit('propose', 'messages', v_id::text, 'insert', jsonb_build_object('class', worst, 'summary', p_summary));
  return jsonb_build_object('id', v_id, 'privilege_class', worst);
end $$;
comment on function l1.propose(text, jsonb, jsonb, text, text) is
  'privilege_class DERIVED server-side per action (worst wins); taste/core are NOT proposable at all (taste: stage_taste_write; '
  'core: human act). routine actions must lie in the proposer''s own set — no staging above privilege. identity/panel-class '
  '(merge_people, ...) ARE proposable, always requires_approval, never standing-approvable. Dedup on (actor, class, content_hash).';

-- ---------- taste staging (the orchestrator's only taste path; the mirror's read-back path) ----------
create or replace function l1.stage_taste_write(p_fn text, p_args jsonb, p_source_intake_id uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_id uuid; v_render text; v_class text;
begin
  perform l1._rate_check();
  v_class := l1._privilege_class(p_fn);
  if v_class <> 'taste' then
    raise exception 'claudio.bad_args: % is not taste-class (use propose)', p_fn;
  end if;
  -- the edge renders EXACTLY this text back to the verified channel; a fresh user reply commits
  v_render := case p_fn
    when 'set_directive' then format('Set directive (%s%s): "%s"%s',
                                     coalesce(p_args->>'scope_type','global'),
                                     coalesce(' ' || (p_args->>'scope_id'), ''),
                                     p_args->>'statement',
                                     coalesce(' — expires ' || (p_args->>'expires_at'), ''))
    when 'retire_directive' then format('Retire directive %s', p_args->>'directive_id')
    when 'upsert_purpose' then format('Purpose %s (%s): "%s"', p_args->>'id', p_args->>'kind', p_args->>'statement')
    when 'new_purpose_version' then format('New priorities document version: "%s"', left(p_args->>'body', 400))
    when 'upsert_role' then format('Role %s: weight %s', p_args->>'id', coalesce(p_args->>'weight','(unchanged)'))
    when 'retire_role' then format('Retire role %s (cascade preview will follow)', p_args->>'role_id')
    else p_fn || ' ' || p_args::text
  end;
  insert into l1.messages (queue, kind, from_actor, payload, privilege_class, requires_approval, expires_at)
  values ('edge', 'handoff', session_user::text,
          jsonb_build_object('taste_fn', p_fn, 'args', p_args, 'source_intake_id', p_source_intake_id,
                             'render', v_render),
          'taste', true, now() + interval '1 hour')
  returning id into v_id;
  perform l1._audit('stage_taste_write', 'messages', v_id::text, 'insert', jsonb_build_object('fn', p_fn, 'render', v_render));
  return jsonb_build_object('id', v_id, 'render', v_render, 'staged', true);
end $$;
comment on function l1.stage_taste_write(text, jsonb, uuid) is
  'Stages a taste-class write for the edge''s read-back-confirm flow (deterministic, no LLM in the commit path). '
  'The LLM that drafted the write is NEVER in its commit path. Non-bundlable by construction: one staged write per message. '
  'Example: stage_taste_write(''set_directive'', ''{"statement":"...","scope_type":"global"}'', intake_id) => {render: ''Set directive: ... — reply YES''}.';

-- ---------- file_intake (the filer's one verb) ----------
create or replace function l1.file_intake(p_intake_id uuid, p_actions jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_results jsonb; a jsonb; v_class text; n integer;
begin
  perform l1._rate_check();
  perform l1._validate_actions(p_actions);
  for a in select * from jsonb_array_elements(p_actions) loop
    v_class := l1._privilege_class(a->>'fn');
    if v_class <> 'routine' then
      raise exception 'claudio.class_not_filable: % (%-class) cannot ride a filing batch — the filer never writes taste', a->>'fn', v_class;
    end if;
  end loop;
  -- conditional open: concurrent filers lose cleanly
  update l1.intake set status = 'filed' where id = p_intake_id and status = 'pending';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'claudio.bad_transition: intake % is not pending', p_intake_id; end if;
  begin
    v_results := l1._apply_actions(p_actions, 'file_intake');
  exception when others then
    -- poison-pill quarantine: this ROW is held with the error; the filer lives on
    update l1.intake set status = 'held',
      meta = meta || jsonb_build_object('quarantined', true, 'error', sqlerrm)
    where id = p_intake_id;
    perform l1._audit('file_intake', 'intake', p_intake_id::text, 'quarantine', jsonb_build_object('error', sqlerrm));
    return jsonb_build_object('id', p_intake_id, 'quarantined', true, 'error', sqlerrm);
  end;
  update l1.intake set filed_refs = coalesce(v_results, '[]') where id = p_intake_id;
  perform l1._audit('file_intake', 'intake', p_intake_id::text, 'update', jsonb_build_object('actions', jsonb_array_length(p_actions)));
  return jsonb_build_object('id', p_intake_id, 'status', 'filed', 'results', v_results);
end $$;
comment on function l1.file_intake(uuid, jsonb) is
  'Atomic batch with {"$ref":i}; conditional pending->filed; rollback restores pending — EXCEPT a poison row, which quarantines '
  'individually (held + error in meta) so head-of-queue poison costs one row, never the filer. No taste-class sub-actions, ever. '
  'Example: file_intake(id, ''[{"fn":"create_person","args":{...}},{"fn":"record_atom","args":{"links":[{"to_type":"person","to_id":{"$ref":0},"kind":"participant"}]}}]'').';

-- ---------- the dispatcher ----------
create or replace function l1._apply_actions(p_actions jsonb, p_source text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare results jsonb := '[]'; a jsonb; args jsonb; fn text; r jsonb;
begin
  for a in select * from jsonb_array_elements(p_actions) loop
    fn := a->>'fn';
    args := l1._resolve_refs(a->'args', results);
    r := case fn
      when 'create_person' then l1.create_person(args->>'name', args->>'primary_role_id', args->>'summary',
                                                 coalesce((args->>'sensitivity')::smallint, 0::smallint),
                                                 coalesce(args->'handles','[]'), coalesce(args->'meta','{}'))
      when 'add_handle' then l1.add_handle((args->>'person_id')::uuid, args->>'source', args->>'handle',
                                           coalesce((args->>'verified')::boolean, false))
      when 'update_person' then l1.update_person((args->>'person_id')::uuid, args->'patch')
      when 'record_atom' then l1.record_atom((args->>'ts')::timestamptz, args->>'kind', args->>'summary',
                                             (args->>'ts_end')::timestamptz, args->>'detail',
                                             coalesce(args->'quotes','[]'), coalesce(args->'refs','[]'),
                                             args->>'primary_role_id', coalesce(args->'links','[]'),
                                             coalesce((args->>'sensitivity')::smallint, 0::smallint), coalesce(args->'meta','{}'))
      when 'amend_atom' then l1.amend_atom((args->>'atom_id')::uuid, args->'patch')
      when 'create_task' then l1.create_task(args->>'description', (args->>'due')::timestamptz,
                                             (args->>'person_id')::uuid, args->>'primary_role_id',
                                             args->'source_ref', coalesce((args->>'sensitivity')::smallint, 0::smallint),
                                             coalesce(args->'meta','{}'))
      when 'complete_task' then l1.complete_task((args->>'task_id')::uuid)
      when 'drop_task' then l1.drop_task((args->>'task_id')::uuid, args->>'reason')
      when 'amend_task' then l1.amend_task((args->>'task_id')::uuid, args->'patch')
      when 'create_expectation' then l1.create_expectation(args->>'description', (args->>'person_id')::uuid,
                                                           (args->>'due')::timestamptz, coalesce(args->>'follow_up','none'),
                                                           (args->>'follow_up_at')::timestamptz, args->>'primary_role_id',
                                                           args->'source_ref', coalesce((args->>'sensitivity')::smallint, 0::smallint),
                                                           coalesce(args->'meta','{}'))
      when 'resolve_expectation' then l1.resolve_expectation((args->>'expectation_id')::uuid,
                                                             coalesce(args->>'status','met'), (args->>'resolved_by')::uuid)
      when 'add_link' then l1.add_link(args->>'from_type', args->>'from_id', args->>'to_type', args->>'to_id',
                                       args->>'kind', coalesce(args->>'origin','inferred'),
                                       (args->>'confidence')::real, args->>'description')
      when 'invalidate_link' then l1.invalidate_link((args->>'link_id')::uuid, (args->>'superseded_by')::uuid)
      when 'register_page' then l1.register_page(args->>'path', args->>'kind', args->>'title', args->>'chapter',
                                                 args->>'entity_type', args->>'entity_id', args->>'read_moment',
                                                 coalesce((args->>'sensitivity')::smallint, 0::smallint))
      when 'move_page' then l1.move_page(args->>'old_path', args->>'new_path')
      when 'post_message' then l1.post_message(args->>'queue', args->>'kind', args->'payload',
                                               coalesce((args->>'sensitivity')::smallint, 0::smallint),
                                               (args->>'expires_at')::timestamptz)
      when 'hold_intake' then l1.hold_intake((args->>'intake_id')::uuid, (args->>'question_message_id')::uuid)
      when 'discard_intake' then l1.discard_intake((args->>'intake_id')::uuid, args->>'reason')
      when 'capture' then l1.capture(args->>'adapter', args->>'raw', args->'sender', args->>'locator',
                                     args->'raw_ref', coalesce((args->>'sensitivity')::smallint, 0::smallint),
                                     coalesce(args->>'rawness', 'verbatim'))
      else null
    end;
    if r is null then
      -- user/panel/core-set fns are dispatched by the approval path's own dispatcher — never here
      raise exception 'claudio.unknown_fn: % is not dispatchable in this batch', fn;
    end if;
    results := results || jsonb_build_array(jsonb_build_object('fn', fn, 'result', r));
  end loop;
  return results;
end $$;
comment on function l1._apply_actions(jsonb, text) is
  'THE batch shape executor: [{"fn","args"}] with {"$ref":i} resolving to results[i].id. Sub-actions run the same functions '
  'with the same guards — atomicity, never privilege. Internal only (file_intake, apply_actions, approve_message call it).';

-- ---------- runs ----------
create or replace function l1.start_run(p_component_id text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_id uuid;
begin
  insert into l1.runs (component_id) values (p_component_id) returning id into v_id;
  return jsonb_build_object('id', v_id, 'component', p_component_id);
end $$;

create or replace function l1.finish_run(p_run_id uuid, p_outcome text, p_tokens_in integer default null,
                                         p_tokens_out integer default null, p_cost_usd numeric default null,
                                         p_summary text default null, p_error text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare n integer;
begin
  update l1.runs set finished_at = now(), outcome = p_outcome, tokens_in = p_tokens_in,
                     tokens_out = p_tokens_out, cost_usd = p_cost_usd, summary = p_summary, error = p_error
  where id = p_run_id and finished_at is null;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'claudio.bad_transition: run % already finished or unknown', p_run_id; end if;
  return jsonb_build_object('id', p_run_id, 'outcome', p_outcome);
end $$;

reset role;
