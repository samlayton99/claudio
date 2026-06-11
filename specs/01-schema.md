# 01 — Schema

One Postgres database (`claudio`) on the Mac mini. Two planes, one graph. Every table gets `COMMENT ON`; the catalog gardener keeps `SCHEMA.md` generated from live schema + comments (decay test).

## Conventions

- `id`: `uuid default gen_random_uuid()` for volume tables; human-readable text slugs for `roles`, `goals`, `components`.
- Every table: `created_at`, `updated_at` (trigger), `meta jsonb not null default '{}'`.
- `sensitivity smallint not null default 0` — 0 normal, 1 sensitive, 2 restricted. RLS on every table that carries it: `sensitivity <= l1.clearance()` where `l1.clearance()` is a `STABLE SECURITY DEFINER` lookup of `role_clearances` by **`session_user`** (no GUC — a session cannot raise itself). All RLS tables get `FORCE ROW LEVEL SECURITY`; all worker-facing views are `WITH (security_invoker = true)`. **Write floor**: L1 computes `sensitivity = greatest(passed, adapter_default, role_default)` server-side; only panel/core may lower.
- **Statuses** = `CHECK` constraints (closed sets). **Kinds** = rows in `kinds` (extensible by proposal), trigger-validated.
- Provenance: `created_by text` trigger-set to **`session_user`** (per-worker roles ⇒ real attribution). `source_ref jsonb` shape `{"source","locator","tool"}`, CHECK-validated.
- **Deletion**: entity tables soft-delete via `status`; edge/junction tables (`links`, `person_handles`) hard-delete via L1 with the diff audited; `purge()` (core-only) is the privacy override.
- Every `SECURITY DEFINER` function pins `SET search_path = pg_catalog, l1`; `REVOKE TEMP ON DATABASE claudio FROM PUBLIC`; `REVOKE CREATE ON SCHEMA public FROM PUBLIC`.

```sql
create table kinds (
  domain      text not null,   -- 'log' | 'link' | 'relationship' | 'page' | 'message' | 'metric'
  key         text not null,
  description text not null,
  status      text not null default 'active' check (status in ('active','retired')),
  primary key (domain, key)
);
```

Seed vocab: `log`: meeting, conversation, session, trip, capture, communication, observation, artifact, agent_action · `link`: member, participant, about, advances, scoped_to, part_of, derived_from, blocks · `relationship`: knows, family, introduced_by, colleague · `page`: person, role, topic, event, index, digest · `message`: handoff, proposal, notification, alert, question · `metric`: unanswered_count, median_reply_lag_s, messages_in, messages_out.

`about` = generic aboutness (atom→secondary role, task→person-as-subject). `advances` = the taste edge (role/task/atom → goal); `get_context.taste.goals` traverses it.

## Life plane

```sql
create table roles (
  id        text primary key,            -- 'prod', 'disciple', 'husband-father', 'student'
  name      text not null,
  status    text not null default 'active' check (status in ('active','retired')),
  summary   text check (char_length(summary) <= 500),
  default_sensitivity smallint not null default 0,   -- church role => 1
  ...conventions
);
-- pages resolve via documents.entity anchor; no doc_path columns anywhere (one pointer, one owner)

create table people (
  id        uuid primary key,
  name      text not null,
  status    text not null default 'active' check (status in ('active','archived')),
  summary   text check (char_length(summary) <= 500),
  verified_fields text[] not null default '{}',   -- L1 rejects agent writes touching these
  ...conventions
);

create table person_handles (
  person_id uuid not null references people(id),
  source    text not null,               -- 'imessage' | 'gmail' | 'slack' | 'alias' | ...
  handle    text not null,
  verified  boolean not null default false,
  primary key (source, handle)           -- a handle belongs to exactly one person: the dedup law
);
-- aliases are handle rows with source='alias' (search + wiki dedup use them)

create table goals (
  id        text primary key,
  statement text not null,
  horizon   text not null check (horizon in ('life','year','quarter')),
  status    text not null default 'active' check (status in ('active','achieved','retired')),
  summary   text check (char_length(summary) <= 500),
  ...conventions
);

create table directives (
  id         uuid primary key,
  statement  text not null,
  scope_type text not null check (scope_type in ('global','role','workflow','person','approval_class')),
  scope_id   text check (scope_id is not null or scope_type = 'global'),
  status     text not null default 'active' check (status in ('active','expired','retired')),
  expires_at timestamptz,
  ...conventions
);
-- scope_type='approval_class': a standing approval — the panel auto-applies proposals of that
-- server-derived class (e.g. 'gcal_solo_block'). Granted/revoked only via the dictation gate or panel.

create table tasks (
  id              uuid primary key,
  description     text not null,
  status          text not null default 'open' check (status in ('open','done','dropped')),
  due             timestamptz,
  person_id       uuid references people(id),    -- counterparty/beneficiary; whom it's owed to when a commitment
  primary_role_id text references roles(id),
  source_ref      jsonb,
  ...conventions
);

create table expectations (
  id              uuid primary key,
  description     text not null,
  person_id       uuid references people(id),    -- owed TO me (nullable: deliveries etc.)
  due             timestamptz,
  follow_up       text not null default 'none' check (follow_up in ('none','remind','auto_task')),
  follow_up_at    timestamptz,
  status          text not null default 'pending' check (status in ('pending','met','missed','dropped')),
  resolved_by     uuid references log(id),
  primary_role_id text references roles(id),
  source_ref      jsonb,
  ...conventions
);

create table log (
  id              uuid primary key,
  ts              timestamptz not null,
  ts_end          timestamptz,
  kind            text not null,                 -- vocab 'log'
  summary         text not null check (char_length(summary) <= 500),
  detail          text check (char_length(detail) <= 2000),
  refs            jsonb not null default '[]',
  primary_role_id text references roles(id),
  canonical_of    uuid references log(id),       -- non-null ⇒ merged INTO that atom. Canonical ≡ canonical_of IS NULL.
  ...conventions
);
create unique index log_source_locator on log ((refs->0->>'locator'), kind)
  where refs->0->>'locator' is not null;          -- idempotent re-sync cannot duplicate atoms

create table intake (
  id          uuid primary key,
  received_at timestamptz not null default now(),
  adapter     text not null references components(id),
  sender      jsonb,                     -- {"source","handle","service"}
  raw         text not null,
  raw_ref     jsonb,
  status      text not null default 'pending'
              check (status in ('pending','filed','discarded','held')),
  filed_refs  jsonb not null default '[]',
  locator     text,                       -- source locator for dedup
  ...conventions
);
create unique index intake_dedup on intake (adapter, locator) where locator is not null;
-- Disposition transitions are conditional: ... WHERE id=$1 AND status='pending' — a concurrent
-- filer loses cleanly. resolve_held_intake records the user's answer AND flips held → pending,
-- which is how held rows re-enter the filer's sweep. Adapter capture defaults are capped at
-- sensitivity 1 (the filer's clearance); anything captured restricted routes to the panel.

create table documents (
  path        text primary key,
  kind        text not null,             -- vocab 'page'
  title       text not null,
  entity_type text, entity_id text,      -- anchor; for kind='digest', entity_id='<component>/<period>'
  freshness   timestamptz,
  status      text not null default 'active' check (status in ('active','archived')),
  ...conventions
);
create unique index documents_anchor on documents(kind, entity_type, entity_id)
  where entity_id is not null;
-- No document_links table: [[wikilinks]] in files are authoritative; lint parses, validates,
-- and maintains backlink sections. Promote to a table only when a real SQL graph query appears.
```

## The graph: `links`

One polymorphic edge table for many-to-many; real FK columns (`person_id`, `primary_role_id`) for the 1-many spine (inheritance rides the FKs).

```sql
create table links (
  id          uuid primary key,
  from_type   text not null check (from_type in ('person','role','goal','task','expectation','log','component','directive')),
  to_type     text not null check (to_type   in ('person','role','goal','task','expectation','log','component','directive')),
  from_id     text not null,
  to_id       text not null,
  kind        text not null,            -- vocab 'link' or 'relationship'
  origin      text not null check (origin in ('asserted','inferred')),
  confidence  real check ((origin='asserted') or (confidence between 0 and 1)),
  description text,
  ...conventions,
  unique (from_type, from_id, to_type, to_id, kind)
);
create index links_from on links(from_type, from_id);
create index links_to   on links(to_type, to_id);
```

- Endpoint validation trigger: static branches over the CHECKed type list (no dynamic SQL on input); raises the same generic error for "missing" and "above your clearance" (no existence oracle).
- **Asserted beats inferred**: agents create/remove `inferred` only; `asserted` requires user-set/panel/core. Inferring over an asserted edge is a no-op.
- Person↔person relationships: `relationship` vocab + `description`. Creation (P7): asserted, or explicit evidence (a literal intro message) at confidence ≥ 0.9; otherwise propose.

## Atoms (the precise definition)

An atom is **one human-meaningful episode**: bounded time × coherent purpose × stable participants, from one source. Rules:

| Source pattern | Atomization |
|---|---|
| Meeting / call / calendar event (ended) | 1 atom |
| Chat thread (iMessage/Slack) | 1 atom per thread per local-day with activity; window closed by the adapter, atom written by the filer. (The user↔claudio command thread is exempt — captured per message at the edge, never re-atomized.) |
| Email thread | 1 atom per thread-beat; new beat when the thread revives after >7 days or purpose shifts |
| Working session / focus block | 1 atom |
| Trip / multi-day event | 1 umbrella atom + child atoms linked `part_of` (created after it happens — future events live in gcal, never here) |
| Published artifact (post, paper, note dump) | 1 atom, kind `artifact` + wiki placement |
| Agent action | 1 atom per run with side effects |

- **Never per-message.** Per-message stats (ignored counts, response lag) are computed deterministically by adapters during sync into `metrics` — granular analytics without atom explosion.
- **Cross-source merge**: the same episode seen by two adapters → merge gardener **proposes** a canonical atom; on approval `merge_atoms` accumulates refs and sets `canonical_of` on the losers. Auto-merge only at confidence ≥ 0.9 with identical time + participants (rare by design, P7).
- `merge_atoms` invariants: target must be canonical (`canonical_of IS NULL`); duplicates must not themselves be merge targets; self/cycle rejected.
- Atom updates only via `amend_log` (prior version snapshotted to audit; sensitivity can never be lowered by agents).

## System plane

```sql
create table components (
  id              text primary key,
  kind            text not null check (kind in ('pipe','gardener','workflow','adapter','tool','surface')),
  circle          text not null check (circle in ('inner','outer')),
  status          text not null default 'enabled' check (status in ('enabled','disabled','retired')),
  definition_path text,
  trigger         jsonb not null default '{"type":"manual"}',
    -- {"type":"cron","expr":...} | {"type":"queue","name":...} | {"type":"query","predicate":...,"cursor":...} | {"type":"manual"}
  config          jsonb not null default '{}',   -- role_map, semantics, model, cost ceiling, batch caps (clearance lives ONLY in role_clearances)
  reliability     text not null default 'standard' check (reliability in ('standard','critical')),
  ...conventions
);
-- role scoping via links (component → role, kind 'scoped_to')

create table role_clearances (
  role_name text primary key,            -- DB role (session_user values)
  clearance smallint not null check (clearance in (0,1,2))
);
-- written only by core; read by l1.clearance(). The single source of read-ceiling truth.

create table runs (
  id           uuid primary key,
  component_id text not null references components(id),
  started_at   timestamptz not null,
  finished_at  timestamptz,
  outcome      text check (outcome in ('ok','failed','degraded','skipped')),
  tokens_in    integer, tokens_out integer, cost_usd numeric(8,4),
  summary      text, error text,
  meta         jsonb not null default '{}'       -- query-trigger cursors live here
);

create table metrics (
  component_id text not null references components(id),
  day          date not null,
  scope        text not null,            -- role id, thread, or 'all'
  key          text not null,            -- vocab 'metric': unanswered_count, median_reply_lag_s, ...
  value        numeric not null,
  primary key (component_id, day, scope, key)
);
-- upserted deterministically by sync pipes; powers dashboards and the alignment gardener.

create table messages (
  id                uuid primary key,
  queue             text not null,       -- 'user' | component id | topic
  kind              text not null,       -- vocab 'message'
  from_actor        text not null,       -- trigger-set to session_user
  payload           jsonb not null,      -- proposals: {"summary","actions":[batch shape],"evidence":[...],"quoted":[...]}
  privilege_class   text,                -- DERIVED server-side from actions[].fn at insert; never trusted from payload
  requires_approval boolean not null default false,
  status            text not null default 'posted'
                    check (status in ('posted','claimed','read','done','approved','rejected','expired')),
  posted_at         timestamptz not null default now(),
  claimed_by        text, claimed_at timestamptz, read_at timestamptz, resolved_at timestamptz,
  sensitivity       smallint not null default 0,   -- floor: max sensitivity of cited rows; RLS applies
  ...conventions
);
-- Approval trigger: → approved/rejected only when session_user in (claudio_panel, claudio_core).
-- Queue scoping: a worker may claim/read only its own queue; 'user' readable by edge + panel.
-- Leases: claimed_at older than the queue's lease (default 15 min; critical 5) ⇒ watchdog returns it
-- to 'posted' and alerts. Delivery ≠ read: the edge resolves a user message only after the send API
-- succeeds; failures retry with backoff and never expire silently.

create table audit (
  id         bigserial primary key,
  at         timestamptz not null default now(),
  actor      text not null,              -- session_user
  fn         text, table_name text, row_id text, op text,
  diff       jsonb
);
-- Append-only: no UPDATE/DELETE granted to any routine role. Purge facts land here.
-- Write-rate ceilings are enforced inside L1 by counting the actor's trailing-minute audit rows
-- (committed writes only — known residual: rolled-back attempts don't count; batch caps bound it).
```

## What is deliberately absent

Groups (roles encode collectives) · calendar mirror (gcal authoritative; ended events only) · message archive (tier 0 + `metrics`) · health/finance/places (future; sensitivity tier ready) · pgvector (promote-on-need) · `document_links` (lint parses files) · `rate_counters` (audit-derived) · `memory/` prose store (lessons promote to directives or component config/docs) · separate proposals/notifications tables (unified in `messages`) · separate sources/tools/workflows registries (unified in `components`) · dispatcher daemon · `doc_path` columns (documents anchor is the one pointer).
