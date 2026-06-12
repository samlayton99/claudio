-- 0001: cluster roles + database hardening.
-- Runs as the cluster superuser; everything after 0001 runs SET ROLE claudio_core so
-- every object (and every SECURITY DEFINER function) is owned by a NON-superuser that
-- FORCE RLS binds. OS-user/.pgpass mapping arrives with deploy (P1 stage: two OS users).

do $$
declare r text;
begin
  -- core, panel, base
  if not exists (select 1 from pg_roles where rolname = 'claudio_core') then
    create role claudio_core login createrole;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'claudio_panel') then
    create role claudio_panel login;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'claudio_agent') then
    create role claudio_agent nologin;  -- the base set; every w_* inherits it
  end if;
  -- workers (clearance via l1.role_clearances, NOT via role attributes)
  foreach r in array array[
    'w_edge','w_reconciler',
    'w_filer','w_merge','w_wiki','w_verifier','w_lint','w_orchestrator','w_mirror',
    'w_brief','w_scanner','w_watchdog','w_catalog','w_hygiene','w_approver',
    'w_test'
  ] loop
    if not exists (select 1 from pg_roles where rolname = r) then
      execute format('create role %I login in role claudio_agent', r);
    end if;
  end loop;
end $$;

-- text never escalates; neither do leftover defaults
revoke create on database claudio from public;
revoke temp   on database claudio from public;
revoke all    on schema public from public;

alter schema l1 owner to claudio_core;
grant usage on schema l1 to claudio_agent, claudio_panel, w_edge, w_reconciler;
