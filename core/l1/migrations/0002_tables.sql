-- 0002: the three planes. Purpose (the contract) / life (the record) / system (the self-model).
-- Conventions (specs/01): id uuid for volume tables, slugs where agents type names;
-- created_at/updated_at/meta everywhere; sensitivity 0|1|2 where labeled; created_by = session_user.
set role claudio_core;

-- ---------- registries ----------

create table l1.kinds (
  domain      text not null,
  key         text not null,
  description text not null,
  status      text not null default 'active' check (status in ('active','retired')),
  primary key (domain, key)
);
comment on table l1.kinds is
  'Closed vocabularies, OS-edited only (core sessions). Domains: atom|link|relationship|page|message|metric|purpose|notable_reason. '
  'Examples: (''atom'',''meeting''), (''link'',''advances''), (''purpose'',''goal''). Filterable flags are expensive — create reluctantly.';

create table l1.role_clearances (
  role_name text primary key,
  clearance smallint not null check (clearance in (0,1,2))
);
comment on table l1.role_clearances is
  'THE clearance truth, keyed on session_user via l1.clearance(). Examples: (''w_filer'',1), (''w_brief'',0), (''claudio_panel'',2). No GUC, ever.';

create table l1.parameters (
  key         text primary key,
  value       jsonb not null,
  ring        text not null check (ring in ('core','outer')),
  description text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  meta        jsonb not null default '{}'
);
comment on table l1.parameters is
  'THE unified knob registry (P10). Core ring (fn->class map, predicates, security thresholds) is core-writable only; '
  'outer ring is panel-editable. Examples: (''dictation_window_min'',''10''), (''fn_privilege_class'',{...}), (''effort_slider'',''"standard"'').';

-- ---------- purpose plane ----------

create table l1.purpose (
  id          text primary key,
  kind        text not null,
  statement   text not null,
  horizon     text check (horizon in ('life','year','quarter')),
  goalposts   jsonb not null default '[]',
  status      text not null default 'active' check (status in ('active','achieved','retired')),
  sensitivity smallint not null default 0 check (sensitivity in (0,1,2)),
  created_by  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  meta        jsonb not null default '{}'
);
comment on table l1.purpose is
  'THE APEX CONTRACT: goals (horizons), values/beliefs, attributes (+goalposts). Readable by every agent (sensitivity 0 — '
  'mission alignment, the user''s call); writable by NO agent ever: user-set functions only, intent-bound. '
  'Examples: id=''goal-agents-research'' kind=''goal'' horizon=''year''; id=''value-family-first'' kind=''value''; id=''attr-high-agency'' kind=''attribute''.';
comment on column l1.purpose.goalposts is 'Attributes only: observable markers of becoming. Example: ["ships weekly", "asks for help within a day of being stuck"].';

create table l1.purpose_versions (
  id         uuid primary key default gen_random_uuid(),
  version    integer not null unique,
  body       text not null,
  created_by text,
  created_at timestamptz not null default now()
);
comment on table l1.purpose_versions is
  'THE PRIORITIES DOCUMENT: versioned prose — what matters most and why. Append-only via new_purpose_version (user-set, read-back bound). '
  'The latest version is the live document; history is the record of how priorities moved.';

-- ---------- life plane ----------

create table l1.roles (
  id                  text primary key,
  name                text not null,
  status              text not null default 'active' check (status in ('active','retired')),
  summary             text check (char_length(summary) <= 750),
  weight              real not null default 1.0,
  default_sensitivity smallint not null default 0 check (default_sensitivity in (0,1,2)),
  sensitivity         smallint not null default 0 check (sensitivity in (0,1,2)),
  created_by          text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  meta                jsonb not null default '{}'
);
comment on table l1.roles is
  'The organizing spine of the life. Examples: ''prod'', ''disciple'', ''husband-father'', ''student'', ''general'' (the catch-all every window may map to). '
  'Retiring a role suspends its components; it NEVER archives wiki pages or atoms — active-roles is a default filter, not a wall.';
comment on column l1.roles.weight is
  'USER-SET (asserted) taste multiplier in scoring. Never inferred, never model-adjusted. Examples: general=1.0, husband-father=1.5.';
comment on column l1.roles.default_sensitivity is 'Write floor for content under this role: server clamps to greatest(passed, window_default, role_default).';

create table l1.people (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  status          text not null default 'active' check (status in ('active','archived')),
  summary         text check (char_length(summary) <= 750),
  primary_role_id text references l1.roles(id),
  verified_fields text[] not null default '{}',
  sensitivity     smallint not null default 0 check (sensitivity in (0,1,2)),
  created_by      text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  meta            jsonb not null default '{}'
);
comment on table l1.people is
  'Who. One primary role (FK spine); extra roles via links(about); person<->person via relationship links. '
  'Duplicate creations across windows are expected — the merge gardener proposes; merge_people (panel) resolves. '
  'Examples: create_person(name=>''Daniel Cho'', primary_role_id=>''prod'').';
comment on column l1.people.verified_fields is
  'Fields the USER asserted (e.g. {name,summary}); agents cannot touch them (update_person rejects). User-set path only.';

create table l1.person_handles (
  person_id  uuid not null references l1.people(id),
  source     text not null,
  handle     text not null,
  verified   boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (source, handle)
);
comment on table l1.person_handles is
  'THE DEDUP LAW: a handle belongs to exactly one person. Examples: (''imessage'',''+14355550101''), (''gmail'',''jamie.layton@example.com''). '
  'create_person with an owned handle raises claudio.handle_conflict — match, don''t create. May hard-delete via L1 (audited).';

create table l1.directives (
  id          uuid primary key default gen_random_uuid(),
  statement   text not null,
  scope_type  text not null check (scope_type in ('global','role','workflow','person','approval_class')),
  scope_id    text check (scope_id is not null or scope_type = 'global'),
  status      text not null default 'active' check (status in ('active','expired','retired')),
  expires_at  timestamptz,
  sensitivity smallint not null default 0 check (sensitivity in (0,1,2)),
  created_by  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  meta        jsonb not null default '{}'
);
comment on table l1.directives is
  'User taste as operational law. Written ONLY through the dictation gate + intent binding (set_directive). '
  'Examples: scope global ''never schedule before 9am''; scope workflow=morning-brief ''no news during finals''. '
  'Injected into every scoped context packet; never truncated from packets.';

create table l1.tasks (
  id              uuid primary key default gen_random_uuid(),
  description     text not null,
  status          text not null default 'open' check (status in ('open','done','dropped')),
  due             timestamptz,
  person_id       uuid references l1.people(id),
  primary_role_id text references l1.roles(id),
  source_ref      jsonb,
  sensitivity     smallint not null default 0 check (sensitivity in (0,1,2)),
  created_by      text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  meta            jsonb not null default '{}'
);
comment on table l1.tasks is
  'What I owe. person_id = primary counterparty/beneficiary (extras via links). '
  'Examples: create_task(description=>''Send Brother Hansen the agenda'', due=>''2026-06-13T09:00-07'', person_id=>..., primary_role_id=>''disciple'').';

create table l1.expectations (
  id              uuid primary key default gen_random_uuid(),
  description     text not null,
  person_id       uuid references l1.people(id),
  due             timestamptz,
  follow_up       text not null default 'none' check (follow_up in ('none','remind','auto_task')),
  follow_up_at    timestamptz,
  status          text not null default 'pending' check (status in ('pending','met','missed','dropped')),
  resolved_by     uuid,
  primary_role_id text references l1.roles(id),
  source_ref      jsonb,
  sensitivity     smallint not null default 0 check (sensitivity in (0,1,2)),
  created_by      text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  meta            jsonb not null default '{}'
);
comment on table l1.expectations is
  'What I''m owed. person_id = who owes it (nullable). resolved_by = the atom that resolved it. '
  'Examples: ''Daniel Cho to email his deck'' due Friday follow_up=remind. The scanner (pure SQL, critical) drives reminders.';

create table l1.atoms (
  id              uuid primary key default gen_random_uuid(),
  ts              timestamptz not null,
  ts_end          timestamptz,
  kind            text not null,
  summary         text not null check (char_length(summary) <= 750),
  detail          text check (char_length(detail) <= 2000),
  quotes          jsonb not null default '[]',
  notable         boolean not null default false,
  notable_reason  text,
  refs            jsonb not null default '[]',
  primary_role_id text references l1.roles(id),
  canonical_of    uuid references l1.atoms(id),
  sensitivity     smallint not null default 0 check (sensitivity in (0,1,2)),
  created_by      text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  meta            jsonb not null default '{}',
  constraint atoms_notable_reason_pairing check ((notable and notable_reason is not null) or (not notable and notable_reason is null))
);
comment on table l1.atoms is
  'UNITS OF LIFE EXPERIENCE — compact index cards (summary <=750), never documents. One meaningful chunk: bounded time x coherent '
  'purpose x stable participants. Bias toward thoughtful, larger chunks; never per-message. Examples: a meeting; a thread-day; '
  'an idea (kind=idea); an evening of TV (the record is honest). Depth scales by destination (P8): summary -> +detail -> +quotes -> +wiki page.';
comment on column l1.atoms.quotes is 'VERBATIM spans for load-bearing facts (commitments, dates, amounts, names) — never paraphrased (P8). Example: ["I''ll have the draft to you by Tuesday"].';
comment on column l1.atoms.notable is 'Binary, assigned ONLY at the daily pass (longitudinal context) or by the user. A structural importance input; volume never is. Setting true requires notable_reason (CHECK-paired).';
comment on column l1.atoms.notable_reason is 'P12: the judgment is a SELECTION, never prose — must be an active kind in domain notable_reason (trigger-validated). The model picks from the list or notable stays false; nuance goes in detail, where it drives nothing.';
comment on column l1.atoms.canonical_of is 'Non-null => merged into that atom. Canonical atoms have NULL. what_happened reads canonical only.';
comment on column l1.atoms.refs is 'Tier-0 pointers [{source,locator,tool}] — one fetch_ref call from raw, always.';

alter table l1.expectations
  add constraint expectations_resolved_by_fkey foreign key (resolved_by) references l1.atoms(id);

create unique index atoms_source_locator on l1.atoms ((refs->0->>'locator'), kind)
  where refs->0->>'locator' is not null;
create index atoms_role_ts on l1.atoms (primary_role_id, ts desc) where canonical_of is null;
create index atoms_ts on l1.atoms (ts desc) where canonical_of is null;
create index tasks_open_due on l1.tasks (due) where status = 'open';
create index expectations_pending_due on l1.expectations (due) where status = 'pending';

-- ---------- system plane ----------

create table l1.components (
  id              text primary key,
  kind            text not null check (kind in ('pipe','gardener','workflow','window','surface','tool')),
  circle          text not null check (circle in ('inner','outer')),
  status          text not null default 'enabled' check (status in ('enabled','disabled','retired')),
  definition_path text,
  trigger         jsonb not null default '{"type":"manual"}',
  config          jsonb not null default '{}',
  reliability     text not null default 'standard' check (reliability in ('standard','critical')),
  created_by      text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  meta            jsonb not null default '{}'
);
comment on table l1.components is
  'The system''s parts: windows, gardeners, workflows, pipes, surfaces, tools. Registry is truth; the reconciler converges launchd to it. '
  'Examples: (''filer'',''gardener'',''inner'',reliability=''critical''), (''window-gcal'',''window'',config.role_map=[...]). '
  'definition_path = the component''s own folder (P10): core/agents/<id>/ or custom/agents/<id>/.';
comment on column l1.components.trigger is 'jsonb {"type": "cron"|"queue"|"query"|"manual"|"resident", ...}. Query-trigger cursors live in runs.meta.';

create table l1.intake (
  id          uuid primary key default gen_random_uuid(),
  received_at timestamptz not null default now(),
  adapter     text not null references l1.components(id),
  sender      jsonb,
  raw         text not null,
  raw_ref     jsonb,
  rawness     text not null default 'verbatim' check (rawness in ('verbatim','derived')),
  status      text not null default 'pending' check (status in ('pending','filed','discarded','held')),
  filed_refs  jsonb not null default '[]',
  locator     text,
  sensitivity smallint not null default 0 check (sensitivity in (0,1)),
  created_by  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  meta        jsonb not null default '{}'
);
comment on table l1.intake is
  'THE TIER-0 RECORD, not disposable staging (P4: the historical stream is owned in-house — external refs rot). Rows are '
  'never deleted; discarded = no atom extracted, raw remains. rawness: verbatim = truly raw; derived = AI/agent-summarized '
  'upstream (P8: already one summary deep — context, never ground truth). Large payloads live in archive/ via raw_ref. '
  'Scannable without atoms: SQL by day (intake_by_day), grep over archive/. '
  'ADVERSARY-WRITABLE BY CONSTRUCTION (assume hijacked senders). Captures cap at sensitivity 1. '
  'Conditional transitions (where status=''pending'') make concurrent filers lose cleanly. Holds carry a TTL: aged-out holds '
  'auto-file as kind=unknown low-confidence atoms — visible, correctable, never parked forever. '
  'Example: capture(adapter=>''edge-imessage'', raw=>''t: pick up...'', sender=>{"source":"imessage","handle":"+1..."}, locator=>''msg-123'').';
comment on column l1.intake.rawness is
  'How raw is raw: verbatim (the source''s own bytes/text) or derived (summarized upstream by an AI/agent window — P8 counts it '
  'as one summary level; prefer a verbatim feed as the record whenever the source can deliver one).';
create unique index intake_dedup on l1.intake (adapter, locator) where locator is not null;
create index intake_pending on l1.intake (received_at) where status = 'pending';
create index intake_by_day on l1.intake (received_at);

create table l1.documents (
  path        text primary key,
  kind        text not null,
  title       text not null,
  chapter     text not null,
  entity_type text,
  entity_id   text,
  freshness   timestamptz,
  read_moment text,
  status      text not null default 'active' check (status in ('active','demoted','archived')),
  sensitivity smallint not null default 0 check (sensitivity in (0,1)),
  created_by  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  meta        jsonb not null default '{}'
);
comment on table l1.documents is
  'The 1:1 index row for every wiki page (incl. the summary ladder under chapter=cadences). The file half is wiki-tool''s; '
  'DB first, file second, lint reconciles drift. Page creation demands chapter + read_moment (anti-accretion). '
  'Example: register_page(path=>''wiki/people/daniel-cho.md'', kind=>''person'', chapter=>''people'', read_moment=>''before any PROD intro involving evals'').';
comment on column l1.documents.read_moment is 'WHEN will this be read — by Sam (journaling joy) or his agents (a future query). Can''t name one => no page.';
create unique index documents_anchor on l1.documents (kind, entity_type, entity_id) where entity_id is not null;

create table l1.links (
  id             uuid primary key default gen_random_uuid(),
  from_type      text not null check (from_type in ('person','role','purpose','task','expectation','atom','component','directive','document')),
  to_type        text not null check (to_type   in ('person','role','purpose','task','expectation','atom','component','directive','document')),
  from_id        text not null,
  to_id          text not null,
  kind           text not null,
  origin         text not null check (origin in ('asserted','inferred')),
  confidence     real check ((origin = 'asserted') or (confidence between 0 and 1)),
  description    text,
  invalidated_at timestamptz,
  superseded_by  uuid references l1.links(id),
  sensitivity    smallint not null default 0 check (sensitivity in (0,1,2)),
  created_by     text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  meta           jsonb not null default '{}',
  unique (from_type, from_id, to_type, to_id, kind)
);
comment on table l1.links is
  'THE graph: one polymorphic edge table. advances = the alignment edge (role/task/atom -> purpose); about = generic aboutness. '
  'Asserted beats inferred; agents create/invalidate INFERRED only; person<->person needs assertion or explicit evidence >=0.9 — else propose (P7). '
  'Supersedence over deletion: invalidated_at + superseded_by — point-in-time queries survive. '
  'Example: add_link(from=>(''atom'',id), to=>(''purpose'',''goal-agents-research''), kind=>''advances'', origin=>''inferred'', confidence=>0.8).';
create index links_from on l1.links (from_type, from_id) where invalidated_at is null;
create index links_to   on l1.links (to_type, to_id)     where invalidated_at is null;

create table l1.runs (
  id           uuid primary key default gen_random_uuid(),
  component_id text not null references l1.components(id),
  started_at   timestamptz not null default now(),
  finished_at  timestamptz,
  outcome      text check (outcome in ('ok','failed','degraded','skipped')),
  tokens_in    integer,
  tokens_out   integer,
  cost_usd     numeric(8,4),
  summary      text,
  error        text,
  meta         jsonb not null default '{}'
);
comment on table l1.runs is
  'Every run logged (P6) — the watchdog''s raw material and the spend record. Query-trigger cursors live in meta. '
  'Example: start_run(''filer'') ... finish_run(id, ''ok'', tokens_in=>1200, tokens_out=>300, cost_usd=>0.004, summary=>''filed 3'').';
create index runs_component on l1.runs (component_id, started_at desc);

create table l1.messages (
  id                uuid primary key default gen_random_uuid(),
  queue             text not null,
  kind              text not null,
  from_actor        text not null,
  payload           jsonb not null,
  privilege_class   text,
  requires_approval boolean not null default false,
  status            text not null default 'posted' check (status in ('posted','claimed','read','done','approved','rejected','expired')),
  posted_at         timestamptz not null default now(),
  expires_at        timestamptz,
  claimed_by        text,
  claimed_at        timestamptz,
  read_at           timestamptz,
  resolved_at       timestamptz,
  content_hash      text,
  sensitivity       smallint not null default 0 check (sensitivity in (0,1,2)),
  created_by        text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  meta              jsonb not null default '{}'
);
comment on table l1.messages is
  'THE one coordination fabric: handoffs, proposals, questions, notifications, alerts. privilege_class is DERIVED server-side '
  'per action — never trusted from payload. Queue scoping: own queue only (''user'' readable by edge + panel). '
  'Leases reaped at claim time; watchdog backstops. Proposals dedup on (from_actor, privilege_class, content_hash).';
create index messages_queue on l1.messages (queue, status, posted_at);
create unique index messages_proposal_dedup on l1.messages (from_actor, privilege_class, content_hash)
  where status in ('posted','claimed') and content_hash is not null;

create table l1.audit (
  id         bigserial primary key,
  at         timestamptz not null default now(),
  actor      text not null,
  fn         text,
  table_name text,
  row_id     text,
  op         text,
  diff       jsonb
);
comment on table l1.audit is
  'Append-only. actor = session_user, always. Write-rate ceilings count trailing-minute rows per actor. '
  'Readable by panel/core only (diffs can carry sensitive content).';
create index audit_actor_at on l1.audit (actor, at desc);

-- ---------- generic triggers ----------

create or replace function l1.tg_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create or replace function l1.tg_created_by() returns trigger
language plpgsql as $$
begin
  if new.created_by is null then
    new.created_by := session_user::text;
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['purpose','roles','people','directives','tasks','expectations','atoms',
                           'intake','documents','links','components','parameters','messages'] loop
    execute format('create trigger touch_%s before update on l1.%I for each row execute function l1.tg_touch()', t, t);
    if t <> 'parameters' then
      execute format('create trigger createdby_%s before insert on l1.%I for each row execute function l1.tg_created_by()', t, t);
    end if;
  end loop;
end $$;

reset role;
