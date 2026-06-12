-- 0003: nothing exists without a typecheck. Kind vocab triggers, jsonb shape validators
-- (hand-rolled, no extension dependency), links endpoint validation, and the security helpers.
set role claudio_core;

-- ---------- clearance: THE truth, keyed on session_user ----------
-- session_user, never current_user: inside SECURITY DEFINER, current_user is the function
-- owner — a guard reading it would be a no-op (red-team finding).
create or replace function l1.clearance() returns smallint
language sql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
  select coalesce((select clearance from l1.role_clearances where role_name = session_user::text), 0)
$$;
comment on function l1.clearance() is
  'Clearance of the CONNECTING role (session_user) from role_clearances; absent => 0. '
  'Examples: as w_filer => 1; as claudio_panel => 2; as anything unknown => 0. Self-raise is impossible: the table is core-writable only.';

-- ---------- audit + rate ceiling ----------
create or replace function l1._audit(p_fn text, p_table text, p_row_id text, p_op text, p_diff jsonb default null)
returns void language sql security definer set search_path = pg_catalog, l1, pg_temp as $$
  insert into l1.audit (actor, fn, table_name, row_id, op, diff)
  values (session_user::text, p_fn, p_table, p_row_id, p_op, p_diff)
$$;

create or replace function l1._rate_check() returns void
language plpgsql security definer set search_path = pg_catalog, l1, pg_temp as $$
declare ceiling integer;
        n integer;
begin
  ceiling := coalesce((select (value #>> '{}')::integer from l1.parameters where key = 'write_rate_ceiling_per_min'), 240);
  select count(*) into n from l1.audit where actor = session_user::text and at > now() - interval '1 minute';
  if n >= ceiling then
    raise exception 'claudio.rate_limited: % writes in the trailing minute (ceiling %)', n, ceiling;
  end if;
end $$;

-- ---------- sensitivity clamp ----------
create or replace function l1._clamp_sensitivity(p_passed smallint, p_role_id text default null, p_adapter text default null)
returns smallint language plpgsql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
declare role_floor smallint := 0; window_floor smallint := 0;
begin
  if p_role_id is not null then
    select coalesce(default_sensitivity, 0) into role_floor from l1.roles where id = p_role_id;
  end if;
  if p_adapter is not null then
    select coalesce((config->>'default_sensitivity')::smallint, 0) into window_floor from l1.components where id = p_adapter;
  end if;
  return greatest(coalesce(p_passed, 0), coalesce(role_floor, 0), coalesce(window_floor, 0));
end $$;
comment on function l1._clamp_sensitivity(smallint, text, text) is
  'Write floor, server-clamped: greatest(passed, window_default, role_default). Only panel/core may lower (they pass what they mean).';

-- ---------- kind vocab triggers ----------
create or replace function l1._assert_kind(p_domain text, p_key text) returns void
language plpgsql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
begin
  if not exists (select 1 from l1.kinds where domain = p_domain and key = p_key and status = 'active') then
    raise exception 'claudio.unknown_kind: % is not an active kind in domain %', p_key, p_domain;
  end if;
end $$;

create or replace function l1.tg_kind_atoms() returns trigger language plpgsql as $$
begin perform l1._assert_kind('atom', new.kind); return new; end $$;
create or replace function l1.tg_kind_documents() returns trigger language plpgsql as $$
begin perform l1._assert_kind('page', new.kind); return new; end $$;
create or replace function l1.tg_kind_messages() returns trigger language plpgsql as $$
begin perform l1._assert_kind('message', new.kind); return new; end $$;
create or replace function l1.tg_kind_purpose() returns trigger language plpgsql as $$
begin perform l1._assert_kind('purpose', new.kind); return new; end $$;
create or replace function l1.tg_kind_links() returns trigger language plpgsql as $$
begin
  if not exists (select 1 from l1.kinds where domain in ('link','relationship') and key = new.kind and status = 'active') then
    raise exception 'claudio.unknown_kind: % is not an active link/relationship kind', new.kind;
  end if;
  return new;
end $$;

create or replace function l1.tg_kind_notable() returns trigger language plpgsql as $$
begin
  if new.notable_reason is not null then perform l1._assert_kind('notable_reason', new.notable_reason); end if;
  return new;
end $$;

create trigger kind_atoms     before insert or update of kind on l1.atoms     for each row execute function l1.tg_kind_atoms();
create trigger kind_notable   before insert or update of notable_reason on l1.atoms for each row execute function l1.tg_kind_notable();
create trigger kind_documents before insert or update of kind on l1.documents for each row execute function l1.tg_kind_documents();
create trigger kind_messages  before insert or update of kind on l1.messages  for each row execute function l1.tg_kind_messages();
create trigger kind_purpose   before insert or update of kind on l1.purpose   for each row execute function l1.tg_kind_purpose();
create trigger kind_links     before insert or update of kind on l1.links     for each row execute function l1.tg_kind_links();

-- ---------- jsonb shape validators (schema-by-function; no extension dependency) ----------
create or replace function l1._validate_refs(p jsonb) returns void
language plpgsql immutable as $$
declare r jsonb;
begin
  if p is null then return; end if;
  if jsonb_typeof(p) <> 'array' then raise exception 'claudio.bad_shape: refs must be an array'; end if;
  for r in select * from jsonb_array_elements(p) loop
    if jsonb_typeof(r) <> 'object' or r->>'source' is null or r->>'locator' is null then
      raise exception 'claudio.bad_shape: each ref needs {source, locator[, tool]} — got %', r;
    end if;
  end loop;
end $$;

create or replace function l1._validate_quotes(p jsonb) returns void
language plpgsql immutable as $$
declare e jsonb;
begin
  if p is null then return; end if;
  if jsonb_typeof(p) <> 'array' then raise exception 'claudio.bad_shape: quotes must be an array of strings'; end if;
  for e in select * from jsonb_array_elements(p) loop
    if jsonb_typeof(e) <> 'string' then raise exception 'claudio.bad_shape: quotes must be verbatim STRINGS — got %', e; end if;
  end loop;
end $$;

create or replace function l1._validate_sender(p jsonb) returns void
language plpgsql immutable as $$
begin
  if p is null then return; end if;
  if jsonb_typeof(p) <> 'object' or p->>'source' is null or p->>'handle' is null then
    raise exception 'claudio.bad_shape: sender needs {source, handle, ...} — got %', p;
  end if;
end $$;

create or replace function l1._validate_actions(p jsonb) returns void
language plpgsql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
declare a jsonb; cap integer;
begin
  cap := coalesce((select (value->>'batch_max_actions')::integer from l1.parameters where key = 'caps'), 20);
  if p is null or jsonb_typeof(p) <> 'array' then
    raise exception 'claudio.bad_shape: actions must be an array of {fn, args}';
  end if;
  if jsonb_array_length(p) > cap then
    raise exception 'claudio.batch_too_large: % actions (cap %)', jsonb_array_length(p), cap;
  end if;
  for a in select * from jsonb_array_elements(p) loop
    if jsonb_typeof(a) <> 'object' or a->>'fn' is null or jsonb_typeof(a->'args') <> 'object' then
      raise exception 'claudio.bad_shape: each action needs {fn, args{}} — got %', a;
    end if;
  end loop;
end $$;

create or replace function l1.tg_shape_atoms() returns trigger language plpgsql as $$
begin
  perform l1._validate_refs(new.refs);
  perform l1._validate_quotes(new.quotes);
  return new;
end $$;
create trigger shape_atoms before insert or update on l1.atoms for each row execute function l1.tg_shape_atoms();

create or replace function l1.tg_shape_intake() returns trigger language plpgsql as $$
begin
  perform l1._validate_sender(new.sender);
  perform l1._validate_refs(new.raw_ref);
  return new;
end $$;
create trigger shape_intake before insert or update on l1.intake for each row execute function l1.tg_shape_intake();

-- ---------- links endpoint validation ----------
-- Function-layer (add_link) re-checks with the caller's clearance so "missing" and "above
-- clearance" raise identically (no existence oracle). This trigger is the core-write backstop.
create or replace function l1._endpoint_exists(p_type text, p_id text) returns boolean
language plpgsql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
declare ok boolean;
begin
  if p_type = 'document' then
    select exists (select 1 from l1.documents where path = p_id) into ok;     -- PK is path
  elsif p_type in ('task','expectation') then
    -- one obligations table; the endpoint type must match the row's kind
    select exists (select 1 from l1.obligations where id::text = p_id and kind = p_type) into ok;
  else
    execute format(
      'select exists (select 1 from l1.%I where id::text = $1)',
      case p_type
        when 'person' then 'people' when 'role' then 'roles' when 'purpose' then 'purpose'
        when 'atom' then 'atoms'
        when 'component' then 'components' when 'directive' then 'directives'
      end) into ok using p_id;
  end if;
  return coalesce(ok, false);
end $$;

create or replace function l1.tg_links_endpoints() returns trigger language plpgsql as $$
begin
  if not l1._endpoint_exists(new.from_type, new.from_id) then
    raise exception 'claudio.endpoint_not_found: %/%', new.from_type, new.from_id;
  end if;
  if not l1._endpoint_exists(new.to_type, new.to_id) then
    raise exception 'claudio.endpoint_not_found: %/%', new.to_type, new.to_id;
  end if;
  return new;
end $$;
create trigger links_endpoints before insert on l1.links for each row execute function l1.tg_links_endpoints();

-- ---------- dictation gate ----------
create or replace function l1._dictation_check(p_intake_id uuid) returns l1.intake
language plpgsql stable security definer set search_path = pg_catalog, l1, pg_temp as $$
declare row_intake l1.intake; window_min integer;
begin
  -- panel and core satisfy the gate by role: their writes are physically the user's
  if session_user::text in ('claudio_panel', 'claudio_core') then
    if p_intake_id is not null then
      select * into row_intake from l1.intake where id = p_intake_id;
    end if;
    return row_intake;
  end if;
  window_min := coalesce((select (value #>> '{}')::integer from l1.parameters where key = 'dictation_window_min'), 10);
  if p_intake_id is null then
    raise exception 'claudio.dictation_required: user-set functions need a verified-user intake citation';
  end if;
  select * into row_intake from l1.intake where id = p_intake_id;
  if row_intake.id is null then
    raise exception 'claudio.dictation_required: cited intake not found';
  end if;
  if coalesce((row_intake.sender->>'verified_user')::boolean, false) is not true then
    raise exception 'claudio.dictation_required: cited intake is not from the verified user';
  end if;
  if row_intake.received_at < now() - make_interval(mins => window_min) then
    raise exception 'claudio.dictation_stale: cited intake older than % min (a recency token, not a bearer token)', window_min;
  end if;
  return row_intake;
end $$;
comment on function l1._dictation_check(uuid) is
  'The dictation gate: verified user handle on the verified channel, <=10 min. CHANNEL proof only — '
  'taste writes additionally need the INTENT binding (verbatim-in-raw or edge read-back-confirm). Panel/core satisfy by role.';

-- documents chapter check (the eleven chapters; core-ring parameter)
create or replace function l1.tg_documents_chapter() returns trigger language plpgsql as $$
declare chapters jsonb;
begin
  chapters := (select value from l1.parameters where key = 'wiki_chapters');
  if chapters is not null and not (chapters ? new.chapter) then
    raise exception 'claudio.unknown_chapter: % (must be one of %)', new.chapter, chapters;
  end if;
  return new;
end $$;
create trigger documents_chapter before insert or update of chapter on l1.documents
  for each row execute function l1.tg_documents_chapter();

reset role;
