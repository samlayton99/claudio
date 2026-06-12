-- 0007: the read surface. The context is the API. No bare UUIDs ({id,name} pairs), timestamps + age
-- inline, token-cap defaults, two-lane scoring with floors. Pure SQL — no LLM at query time.
set role claudio_core;

create or replace function l1._scoring() returns jsonb
language sql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
  select coalesce((select value from l1.parameters where key = 'scoring'),
    '{"alpha":1.0,"beta":1.0,"gamma":1.5,"halflife_days":7,"floor":0.05,"urgency_horizon_days":7,"default_budget_tokens":3000}')
$$;

-- obligations lane: importance x urgency. Recency of creation is IRRELEVANT to something due now
-- (the dueness bug: important + assigned-long-ago + due-now must score at the top).
create or replace function l1._score_obligation(p_role_weight real, p_importance real, p_due timestamptz)
returns real language plpgsql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
declare s jsonb := l1._scoring(); urgency real; horizon_s real; fl real;
begin
  fl := (s->>'floor')::real;
  horizon_s := (s->>'urgency_horizon_days')::real * 86400;
  urgency := case
    when p_due is null then fl
    when p_due <= now() then 1.0
    else greatest(fl, 1.0 - (extract(epoch from p_due - now())::real / horizon_s))
  end;
  return power(greatest(fl, p_role_weight * p_importance), (s->>'beta')::real)
       * power(urgency, (s->>'gamma')::real);
end $$;

-- context lane: importance x recency. Fresh and important wins; old fades unless important.
create or replace function l1._score_context(p_role_weight real, p_importance real, p_ts timestamptz)
returns real language plpgsql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
declare s jsonb := l1._scoring(); rec real; fl real;
begin
  fl := (s->>'floor')::real;
  rec := greatest(fl, exp(-ln(2) * extract(epoch from now() - p_ts)::real / ((s->>'halflife_days')::real * 86400)));
  return power(greatest(fl, p_role_weight * p_importance), (s->>'beta')::real)
       * power(rec, (s->>'alpha')::real);
end $$;
comment on function l1._score_context(real, real, timestamptz) is
  'Two-lane scoring, both Cobb-Douglas WITH FLOORS (a raw product zeroes old-but-critical items; floored, it is a weighted '
  'sum in log space). Importance is STRUCTURAL: notable + obligations + links + user assertions, x user-set role weight. '
  'Volume is never an input. Exponents tune at P2 against real packets.';

create or replace function l1._atom_importance(p_atom l1.atoms) returns real
language plpgsql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
declare link_n integer;
begin
  select count(*) into link_n from l1.links
  where ((from_type = 'atom' and from_id = p_atom.id::text) or (to_type = 'atom' and to_id = p_atom.id::text))
    and invalidated_at is null;
  return 1.0 + (case when p_atom.notable then 1.0 else 0 end) + 0.2 * least(link_n, 3);
end $$;

-- ---------- fetch_ref: ONE call, no thinking ----------
create or replace function l1.fetch_ref(p_ref jsonb)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
declare v_intake l1.intake; v_atom l1.atoms; v_doc l1.documents;
begin
  if p_ref is null or p_ref->>'source' is null then
    raise exception 'claudio.bad_shape: fetch_ref needs {source, locator[, tool]}';
  end if;
  case p_ref->>'source'
    when 'intake' then
      select * into v_intake from l1.intake where id = (p_ref->>'locator')::uuid;
      if v_intake.id is null then raise exception 'claudio.endpoint_not_found: %', p_ref; end if;
      return jsonb_build_object('content', v_intake.raw, 'sender', v_intake.sender,
                                'received_at', v_intake.received_at, 'adapter', v_intake.adapter);
    when 'atom' then
      select * into v_atom from l1.atoms where id = (p_ref->>'locator')::uuid;
      if v_atom.id is null then raise exception 'claudio.endpoint_not_found: %', p_ref; end if;
      return to_jsonb(v_atom);
    when 'document' then
      select * into v_doc from l1.documents where path = p_ref->>'locator';
      if v_doc.path is null then raise exception 'claudio.endpoint_not_found: %', p_ref; end if;
      return to_jsonb(v_doc) || jsonb_build_object('read_file', v_doc.path);
    else
      -- external tier-0: the MCP layer routes via the named tool; this envelope IS the routing
      return jsonb_build_object('external', true, 'route_via', coalesce(p_ref->>'tool', p_ref->>'source'), 'ref', p_ref);
  end case;
end $$;
comment on function l1.fetch_ref(jsonb) is
  'One-call pointer dereference — hand it any {source, locator, tool} ref, get tier-0 content (or the routing envelope for '
  'external sources). Pulling things in must be dead simple. Examples: fetch_ref(''{"source":"intake","locator":"<uuid>"}'') '
  '=> {content: raw}; fetch_ref(''{"source":"gmail","locator":"thread:x","tool":"window-gmail"}'') => {external:true, route_via:...}.';

-- ---------- search & timeline ----------
create or replace function l1.search_people(p_q text)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
declare r jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'name', p.name, 'role', p.primary_role_id, 'status', p.status,
           'handles', (select coalesce(jsonb_agg(source || ':' || handle), '[]') from l1.person_handles h where h.person_id = p.id))), '[]')
  into r
  from l1.people p
  where p.name ilike '%' || p_q || '%'
     or exists (select 1 from l1.person_handles h where h.person_id = p.id and h.handle ilike '%' || p_q || '%')
     or exists (select 1 from jsonb_array_elements_text(coalesce(p.meta->'aliases','[]')) a where a ilike '%' || p_q || '%');
  if r = '[]'::jsonb then
    perform l1._audit('search_people', 'people', '-', 'miss', jsonb_build_object('q', p_q));  -- the embeddings promotion trigger counts these
  end if;
  return r;
end $$;

create or replace function l1.what_happened(p_from timestamptz, p_to timestamptz, p_filters jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
declare r jsonb; lim integer;
begin
  lim := coalesce((p_filters->>'limit')::integer, 50);
  select coalesce(jsonb_agg(item order by ts), '[]') into r from (
    select a.ts, jsonb_build_object(
      'id', a.id, 'name', left(a.summary, 80), 'summary', a.summary, 'kind', a.kind,
      'ts', a.ts, 'age', date_trunc('minute', now() - a.ts)::text,
      'role', a.primary_role_id, 'notable', a.notable, 'refs', a.refs) as item
    from l1.atoms a
    where a.canonical_of is null  -- canonical only
      and a.ts >= p_from and a.ts < p_to
      and (p_filters->>'role' is null or a.primary_role_id = p_filters->>'role')
      and (p_filters->>'kind' is null or a.kind = p_filters->>'kind')
      and (p_filters->>'person_id' is null or exists (
            select 1 from l1.links lk
            where lk.invalidated_at is null and lk.kind = 'participant'
              and ((lk.from_type = 'atom' and lk.from_id = a.id::text and lk.to_type = 'person' and lk.to_id = p_filters->>'person_id')
                or (lk.to_type = 'atom' and lk.to_id = a.id::text and lk.from_type = 'person' and lk.from_id = p_filters->>'person_id'))))
    order by a.ts limit lim) t;
  if r = '[]'::jsonb then
    perform l1._audit('what_happened', 'atoms', '-', 'miss', jsonb_build_object('from', p_from, 'to', p_to, 'filters', p_filters));
  end if;
  return r;
end $$;
comment on function l1.what_happened(timestamptz, timestamptz, jsonb) is
  'Canonical atoms only, absolute timestamps + age inline. Filters: {role, kind, person_id, limit}. Misses are logged '
  '(the embeddings promotion trigger). Example: what_happened(''2026-06-11'', ''2026-06-12'', ''{"role":"husband-father"}'').';

create or replace function l1.due_tasks(p_scope jsonb default '{}')
returns jsonb language sql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'name', left(t.description, 80), 'due', t.due,
    'age', date_trunc('minute', now() - t.created_at)::text,
    'overdue', t.due is not null and t.due < now(),
    'person', (select jsonb_build_object('id', p.id, 'name', p.name) from l1.people p where p.id = t.person_id),
    'role', t.primary_role_id,
    'blocked_by', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'name', left(e.description, 60))), '[]')
                   from l1.links lk join l1.expectations e on e.id::text = lk.to_id and e.status = 'pending'
                   where lk.from_type = 'task' and lk.from_id = t.id::text and lk.to_type = 'expectation'
                     and lk.kind = 'blocks' and lk.invalidated_at is null))
    order by t.due asc nulls last), '[]')
  from l1.tasks t
  where t.status = 'open'
    and (p_scope->>'role' is null or t.primary_role_id = p_scope->>'role')
    and (p_scope->>'person_id' is null or t.person_id = (p_scope->>'person_id')::uuid)
$$;

create or replace function l1.pending_expectations(p_scope jsonb default '{}')
returns jsonb language sql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id, 'name', left(e.description, 80), 'due', e.due, 'follow_up', e.follow_up, 'follow_up_at', e.follow_up_at,
    'age', date_trunc('minute', now() - e.created_at)::text,
    'person', (select jsonb_build_object('id', p.id, 'name', p.name) from l1.people p where p.id = e.person_id),
    'role', e.primary_role_id)
    order by e.due asc nulls last), '[]')
  from l1.expectations e
  where e.status = 'pending'
    and (p_scope->>'role' is null or e.primary_role_id = p_scope->>'role')
    and (p_scope->>'person_id' is null or e.person_id = (p_scope->>'person_id')::uuid)
$$;

create or replace function l1.queue_status(p_queue text default null)
returns jsonb language sql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
  select coalesce(jsonb_object_agg(q, counts), '{}') from (
    select queue as q, jsonb_object_agg(status, n) as counts from (
      select queue, status, count(*) as n from l1.messages
      where (p_queue is null or queue = p_queue)
        and status in ('posted','claimed','read')
      group by queue, status) s
    group by queue) t
$$;

-- ---------- the packet ----------
create or replace function l1.get_context(p_anchor_type text, p_anchor_id text, p_opts jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
declare
  v_anchor jsonb; v_taste jsonb; v_obl jsonb; v_state jsonb; v_caps jsonb; v_people jsonb;
  v_role l1.roles; v_person l1.people; v_weight real := 1.0; v_budget integer; v_est integer;
  v_digest text; s jsonb := l1._scoring();
begin
  v_budget := coalesce((p_opts->>'budget_tokens')::integer, (s->>'default_budget_tokens')::integer, 3000);

  -- anchor
  case p_anchor_type
    when 'role' then
      select * into v_role from l1.roles where id = p_anchor_id;
      if v_role.id is null then raise exception 'claudio.endpoint_not_found: role/%', p_anchor_id; end if;
      v_weight := v_role.weight;
      v_anchor := jsonb_build_object('type', 'role', 'id', v_role.id, 'name', v_role.name,
                                     'summary', v_role.summary, 'weight', v_role.weight,
                                     'page', (select path from l1.documents where entity_type = 'role' and entity_id = v_role.id limit 1));
    when 'person' then
      select * into v_person from l1.people where id = p_anchor_id::uuid;
      if v_person.id is null then raise exception 'claudio.endpoint_not_found: person/%', p_anchor_id; end if;
      select coalesce(weight, 1.0) into v_weight from l1.roles where id = v_person.primary_role_id;
      v_anchor := jsonb_build_object('type', 'person', 'id', v_person.id, 'name', v_person.name,
                                     'summary', v_person.summary, 'role', v_person.primary_role_id,
                                     'page', (select path from l1.documents where entity_type = 'person' and entity_id = v_person.id::text limit 1));
    when 'purpose' then
      v_anchor := (select jsonb_build_object('type', 'purpose', 'id', id, 'name', left(statement, 80), 'kind', kind, 'status', status)
                   from l1.purpose where id = p_anchor_id);
      if v_anchor is null then raise exception 'claudio.endpoint_not_found: purpose/%', p_anchor_id; end if;
    when 'component' then
      v_anchor := (select jsonb_build_object('type', 'component', 'id', id, 'name', id, 'kind', kind, 'status', status, 'config', config)
                   from l1.components where id = p_anchor_id);
      if v_anchor is null then raise exception 'claudio.endpoint_not_found: component/%', p_anchor_id; end if;
    else
      raise exception 'claudio.bad_args: anchor_type must be role|person|purpose|component';
  end case;

  -- taste: NEVER truncated
  v_taste := jsonb_build_object(
    'directives', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'statement', d.statement,
                            'scope', d.scope_type || coalesce(':' || d.scope_id, ''), 'expires_at', d.expires_at)
                            order by d.created_at), '[]')
                   from l1.directives d
                   where d.status = 'active' and (d.expires_at is null or d.expires_at > now())
                     and (d.scope_type = 'global'
                          or (d.scope_type = p_anchor_type and d.scope_id = p_anchor_id)
                          or (p_anchor_type = 'role' and d.scope_type = 'role' and d.scope_id = p_anchor_id))),
    'purpose', (select coalesce(jsonb_agg(jsonb_build_object('id', pu.id, 'kind', pu.kind, 'statement', pu.statement,
                         'horizon', pu.horizon) order by pu.kind), '[]')
                from l1.purpose pu
                where pu.status = 'active'
                  and (coalesce((p_opts->>'all_purpose')::boolean, false)
                       or exists (select 1 from l1.links lk
                                  where lk.to_type = 'purpose' and lk.to_id = pu.id and lk.kind = 'advances'
                                    and lk.invalidated_at is null
                                    and lk.from_type = p_anchor_type and lk.from_id = p_anchor_id))));

  -- obligations lane
  v_obl := jsonb_build_object(
    'tasks_due', (select coalesce(jsonb_agg(item order by score desc), '[]') from (
        select jsonb_build_object('id', t.id, 'name', left(t.description, 80), 'due', t.due,
                 'age', date_trunc('minute', now() - t.created_at)::text, 'source_ref', t.source_ref,
                 'person', (select jsonb_build_object('id', p.id, 'name', p.name) from l1.people p where p.id = t.person_id)) as item,
               l1._score_obligation(v_weight, 1.0, t.due) as score
        from l1.tasks t where t.status = 'open'
          and (p_anchor_type <> 'role' or t.primary_role_id = p_anchor_id)
          and (p_anchor_type <> 'person' or t.person_id = p_anchor_id::uuid)
        order by score desc limit 20) x),
    'expectations_pending', (select coalesce(jsonb_agg(item order by score desc), '[]') from (
        select jsonb_build_object('id', e.id, 'name', left(e.description, 80), 'due', e.due, 'follow_up', e.follow_up,
                 'age', date_trunc('minute', now() - e.created_at)::text,
                 'person', (select jsonb_build_object('id', p.id, 'name', p.name) from l1.people p where p.id = e.person_id)) as item,
               l1._score_obligation(v_weight, 1.0, coalesce(e.due, e.follow_up_at)) as score
        from l1.expectations e where e.status = 'pending'
          and (p_anchor_type <> 'role' or e.primary_role_id = p_anchor_id)
          and (p_anchor_type <> 'person' or e.person_id = p_anchor_id::uuid)
        order by score desc limit 20) x));

  -- context lane
  select path into v_digest from l1.documents where chapter = 'cadences' and kind = 'digest'
  order by freshness desc nulls last limit 1;
  v_state := jsonb_build_object(
    'recent_atoms', (select coalesce(jsonb_agg(item order by score desc), '[]') from (
        select jsonb_build_object('id', a.id, 'name', left(a.summary, 80), 'summary', a.summary, 'kind', a.kind,
                 'ts', a.ts, 'age', date_trunc('minute', now() - a.ts)::text, 'notable', a.notable, 'refs', a.refs) as item,
               l1._score_context(v_weight, l1._atom_importance(a), a.ts) as score
        from l1.atoms a
        where a.canonical_of is null and a.ts > now() - interval '14 days'
          and (p_anchor_type <> 'role' or a.primary_role_id = p_anchor_id)
          and (p_anchor_type <> 'person' or exists (
                select 1 from l1.links lk where lk.kind = 'participant' and lk.invalidated_at is null
                  and ((lk.from_type = 'atom' and lk.from_id = a.id::text and lk.to_type = 'person' and lk.to_id = p_anchor_id)
                    or (lk.to_type = 'atom' and lk.to_id = a.id::text and lk.from_type = 'person' and lk.from_id = p_anchor_id))))
        order by score desc limit 15) x),
    'daily_digest', v_digest,
    'rollups', (select coalesce(jsonb_agg(path order by freshness desc), '[]')
                from (select path, freshness from l1.documents
                      where chapter = 'cadences' and status = 'active' order by freshness desc nulls last limit 5) d));

  -- capabilities + people
  v_caps := (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'kind', c.kind, 'trigger', c.trigger->>'type')), '[]')
             from l1.components c where c.status = 'enabled'
               and (p_anchor_type <> 'role' or c.config->'role_map' ? p_anchor_id or c.config->'role_map' ? 'general'));
  v_people := (select coalesce(jsonb_agg(jsonb_build_object('id', pid, 'name', pname, 'atoms_14d', n)), '[]') from (
      select p.id as pid, p.name as pname, count(*) as n
      from l1.links lk
      join l1.atoms a on a.id::text = case when lk.from_type = 'atom' then lk.from_id else lk.to_id end
      join l1.people p on p.id::text = case when lk.from_type = 'person' then lk.from_id else lk.to_id end
      where lk.kind = 'participant' and lk.invalidated_at is null
        and ((lk.from_type = 'atom' and lk.to_type = 'person') or (lk.from_type = 'person' and lk.to_type = 'atom'))
        and a.ts > now() - interval '14 days' and a.canonical_of is null
        and (p_anchor_type <> 'role' or a.primary_role_id = p_anchor_id)
      group by p.id, p.name order by n desc limit 10) t);

  -- budget: estimate, then trim in order capabilities -> people -> state -> obligations. Taste never trims.
  v_est := (length(v_anchor::text) + length(v_taste::text) + length(v_obl::text)
            + length(v_state::text) + length(v_caps::text) + length(v_people::text)) / 4;
  if v_est > v_budget then v_caps := jsonb_build_array(jsonb_build_object('trimmed', true)); end if;
  v_est := (length(v_anchor::text) + length(v_taste::text) + length(v_obl::text)
            + length(v_state::text) + length(v_caps::text) + length(v_people::text)) / 4;
  if v_est > v_budget then v_people := '[]'; end if;
  v_est := (length(v_anchor::text) + length(v_taste::text) + length(v_obl::text)
            + length(v_state::text) + length(v_caps::text) + length(v_people::text)) / 4;
  if v_est > v_budget then
    v_state := jsonb_set(v_state, '{recent_atoms}',
      (select coalesce(jsonb_agg(e), '[]') from (select e from jsonb_array_elements(v_state->'recent_atoms') e limit 5) t));
  end if;
  v_est := (length(v_anchor::text) + length(v_taste::text) + length(v_obl::text)
            + length(v_state::text) + length(v_caps::text) + length(v_people::text)) / 4;

  return jsonb_build_object(
    'anchor', v_anchor, 'taste', v_taste, 'obligations', v_obl, 'state', v_state,
    'capabilities', v_caps, 'people', v_people,
    'budget', jsonb_build_object('requested', v_budget, 'spent_estimate', v_est));
end $$;
comment on function l1.get_context(text, text, jsonb) is
  'THE packet. Anchors: role|person|purpose|component. Two-phase protocol: packet first, then agentic drill-down (views, '
  'fetch_ref, wiki). Two-lane scoring; taste never truncates; rollup PATHS not contents (progressive disclosure). '
  'Examples: get_context(''role'',''prod''); get_context(''person'',''<uuid>'', ''{"budget_tokens":2000}'').';

reset role;
