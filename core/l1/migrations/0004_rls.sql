-- 0004: RLS — forced (binds the owner too, which is why claudio_core is not a superuser),
-- policies keyed on l1.clearance() (session_user), invoker views. Reads are free under RLS;
-- writes have NO grants — they exist only inside SECURITY DEFINER functions, and even those
-- writes pass WITH CHECK (you cannot create a row you could not read).
set role claudio_core;

do $$
declare t text;
begin
  foreach t in array array['purpose','roles','people','directives','obligations','atoms',
                           'intake','documents','links','messages'] loop
    execute format('alter table l1.%I enable row level security', t);
    execute format('alter table l1.%I force row level security', t);
    execute format('create policy read_by_clearance on l1.%I for select using (sensitivity <= l1.clearance())', t);
    execute format('create policy write_by_clearance on l1.%I for insert with check (sensitivity <= l1.clearance())', t);
    execute format('create policy update_by_clearance on l1.%I for update using (sensitivity <= l1.clearance()) with check (sensitivity <= l1.clearance())', t);
    execute format('create policy delete_core_only on l1.%I for delete using (l1.clearance() >= 2)', t);
  end loop;
end $$;

-- person_handles: no sensitivity column; visibility follows the person row
alter table l1.person_handles enable row level security;
alter table l1.person_handles force row level security;
create policy handles_follow_person_read on l1.person_handles for select
  using (exists (select 1 from l1.people p where p.id = person_id and p.sensitivity <= l1.clearance()));
create policy handles_follow_person_write on l1.person_handles for insert
  with check (exists (select 1 from l1.people p where p.id = person_id and p.sensitivity <= l1.clearance()));
create policy handles_follow_person_update on l1.person_handles for update
  using (exists (select 1 from l1.people p where p.id = person_id and p.sensitivity <= l1.clearance()))
  with check (exists (select 1 from l1.people p where p.id = person_id and p.sensitivity <= l1.clearance()));
create policy handles_delete_core on l1.person_handles for delete using (l1.clearance() >= 2);

-- system registries: readable by everyone with a seat, write via functions only (no grants)
-- (kinds, role_clearances, parameters, components, runs: no RLS — row visibility is not
-- sensitivity-scoped; column of record. audit: NO read grant below panel/core at all.)

-- ---------- invoker views (the supported read surface) ----------
create or replace view l1.v_unfiled_intake with (security_invoker = true) as
  select id, received_at, adapter, sender, raw, status, locator, sensitivity,
         now() - received_at as age
  from l1.intake where status in ('pending','held') order by received_at;
comment on view l1.v_unfiled_intake is 'The filer''s worklist. Held rows show too (TTL aging is the sweep''s job).';

create or replace view l1.v_open_proposals with (security_invoker = true) as
  select id, queue, kind, from_actor, payload, privilege_class, requires_approval,
         posted_at, expires_at, now() - posted_at as age, sensitivity
  from l1.messages
  where kind = 'proposal' and status in ('posted','claimed') order by posted_at;

create or replace view l1.v_run_misses with (security_invoker = true) as
  select c.id as component_id, c.reliability, c.trigger,
         max(r.started_at) as last_run,
         now() - max(r.started_at) as silence
  from l1.components c left join l1.runs r on r.component_id = c.id
  where c.status = 'enabled' and (c.trigger->>'type') in ('cron','queue','query')
  group by c.id, c.reliability, c.trigger
  having max(r.started_at) is null
      or now() - max(r.started_at) > coalesce((c.trigger->>'max_silence_min')::int, 120) * interval '1 minute';
comment on view l1.v_run_misses is 'Watchdog raw material: enabled scheduled components silent past their declared max_silence_min (default 120).';

create or replace view l1.v_component_health with (security_invoker = true) as
  select c.id, c.kind, c.circle, c.status, c.reliability, c.trigger, c.config->'role_map' as role_map,
         count(r.id) filter (where r.started_at > now() - interval '7 days') as runs_7d,
         count(r.id) filter (where r.outcome = 'failed' and r.started_at > now() - interval '7 days') as failures_7d,
         sum(r.cost_usd) filter (where r.started_at > now() - interval '30 days') as cost_30d,
         max(r.started_at) as last_run
  from l1.components c left join l1.runs r on r.component_id = c.id
  group by c.id;

create or replace view l1.v_stale_expectations with (security_invoker = true) as
  select e.id, e.description, e.person_id, p.name as person_name, e.due, e.follow_up, e.follow_up_at,
         e.status, e.sensitivity, now() - coalesce(e.due, e.created_at) as overdue_by
  from l1.obligations e left join l1.people p on p.id = e.person_id
  where e.kind = 'expectation' and e.status = 'open' and (e.due < now() or e.follow_up_at < now());

create or replace view l1.v_purpose_alignment with (security_invoker = true) as
  with advance_links as (
    select to_id as purpose_id, count(*) as advancing_links, max(created_at) as last_advanced
    from l1.links
    where to_type = 'purpose' and kind = 'advances' and invalidated_at is null
    group by to_id
  )
  select pu.id, pu.kind, pu.statement, pu.status,
         coalesce(al.advancing_links, 0) as advancing_links,
         al.last_advanced,
         (select max(created_at) from l1.purpose_versions) as priorities_updated_at,
         now() - (select max(created_at) from l1.purpose_versions) as priorities_age,
         (coalesce(al.advancing_links,0) = 0) as never_advanced
  from l1.purpose pu left join advance_links al on al.purpose_id = pu.id
  where pu.status = 'active';
comment on view l1.v_purpose_alignment is
  'Lived-vs-proclaimed, DERIVED never stored: per purpose row, advancing-link share and recency; priorities-doc age. '
  'An empty or stale contract surfaces here — the mirror''s first finding.';

reset role;
