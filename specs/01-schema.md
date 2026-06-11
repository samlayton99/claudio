# 01 — Schema

One Postgres database (`claudio`) on the Mac mini. Two planes, one graph. Every table gets `COMMENT ON`; the catalog gardener keeps `SCHEMA.md` generated from live schema + comments (decay test).

## Conventions

- `id`: `uuid default gen_random_uuid()` for volume tables; human-readable text slugs for `roles`, `goals`, `components` (stable, agent-legible).
- Every table: `created_at`, `updated_at` (trigger), `meta jsonb not null default '{}'`.
- `sensitivity smallint not null default 0` — 0 normal, 1 sensitive, 2 restricted. RLS enforces `sensitivity <= current_setting('claudio.clearance')::int` on every life-plane table. Writers may **raise** sensitivity above the contextual default, never lower it.
- **Statuses** are small closed sets → `CHECK` constraints. **Kinds** are extensible vocabularies → rows in `kinds`, validated by trigger; new kinds enter by proposal.
- Provenance: `created_by text` set by trigger to `current_user` (per-worker DB roles make this real attribution). `source_ref jsonb` where a row traces to tier-0: `{"source": "gmail", "locator": "<thread-id>", "tool": "gmail-mcp"}` — CHECK-validated shape.
- Soft delete everywhere (`status`), except `purge()` (core-only, audited; see `04-security.md`).

```sql
create table kinds (
  domain      text not null,   -- 'log' | 'link' | 'page' | 'message' | 'component' | 'relationship'
  key         text not null,
  description text not null,
  status      text not null default 'active' check (status in ('active','retired')),
  primary key (domain, key)
);
```

Seed vocab (extensible by proposal): `log`: meeting, conversation, session, trip, capture, communication, observation, agent_action · `link`: member, participant, about, scoped_to, part_of, derived_from, blocks · `relationship`: knows, family, introduced_by, colleague · `page`: person, role, topic, event, index, digest · `message`: handoff, proposal, notification, alert, question.

## Life plane

```sql
create table roles (
  id        text primary key,            -- 'prod', 'disciple', 'husband-father', 'student'
  name      text not null,
  status    text not null default 'active' check (status in ('active','retired')),
  summary   text check (char_length(summary) <= 500),
  doc_path  text,                         -- wiki page
  default_sensitivity smallint not null default 0,   -- e.g. church role => 1
  ...conventions
);

create table people (
  id        uuid primary key,
  name      text not null,
  status    text not null default 'active' check (status in ('active','archived')),
  summary   text check (char_length(summary) <= 500),
  doc_path  text,
  verified_fields text[] not null default '{}',   -- automation may never overwrite listed fields
  ...conventions
);

create table person_handles (
  person_id uuid not null references people(id),
  source    text not null,               -- 'imessage' | 'gmail' | 'slack' | ...
  handle    text not null,
  verified  boolean not null default false,
  primary key (source, handle)           -- a handle belongs to exactly one person: the dedup law
);

create table goals (
  id        text primary key,            -- slug
  statement text not null,
  horizon   text not null check (horizon in ('life','year','quarter')),
  status    text not null default 'active' check (status in ('active','achieved','retired')),
  summary   text check (char_length(summary) <= 500),
  doc_path  text,
  ...conventions
);

create table directives (
  id         uuid primary key,
  statement  text not null,
  scope_type text not null check (scope_type in ('global','role','workflow','person')),
  scope_id   text,                       -- null iff global
  status     text not null default 'active' check (status in ('active','expired','retired')),
  expires_at timestamptz,                -- "during finals week"
  ...conventions
);

create table tasks (
  id              uuid primary key,
  description     text not null,
  status          text not null default 'open' check (status in ('open','done','dropped')),
  due             timestamptz,
  person_id       uuid references people(id),    -- commitment-to (owed BY me)
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
  follow_up_at    timestamptz,                   -- "remind me the day before"
  status          text not null default 'pending' check (status in ('pending','met','missed','dropped')),
  resolved_by     uuid,                          -- log atom that resolved it
  primary_role_id text references roles(id),
  source_ref      jsonb,
  ...conventions
);

create table log (
  id              uuid primary key,
  ts              timestamptz not null,          -- episode start
  ts_end          timestamptz,
  kind            text not null,                 -- vocab domain 'log'
  summary         text not null check (char_length(summary) <= 500),
  detail          text check (char_length(detail) <= 2000),   -- optional; depth belongs in wiki/tier-0
  refs            jsonb not null default '[]',   -- array of source_ref shapes
  primary_role_id text references roles(id),
  canonical_of    uuid references log(id),       -- set on atoms merged INTO this one (see Atoms)
  ...conventions
);

create table intake (
  id          uuid primary key,
  received_at timestamptz not null default now(),
  adapter     text not null references components(id),
  sender      jsonb,                     -- {"source","handle"} — pre-handle-match identity
  raw         text not null,
  raw_ref     jsonb,                     -- pointer into archive/ for large payloads
  status      text not null default 'pending'
              check (status in ('pending','filed','discarded','held')),
  filed_refs  jsonb not null default '[]',
  ...conventions
);

create table documents (
  path        text primary key,          -- 'wiki/people/jane-doe.md'
  kind        text not null,             -- vocab 'page'
  title       text not null,
  entity_type text, entity_id text,      -- anchor (unique where present)
  freshness   timestamptz,
  status      text not null default 'active' check (status in ('active','archived')),
  ...conventions
);
create unique index documents_anchor on documents(kind, entity_type, entity_id)
  where entity_id is not null;

create table document_links (
  from_path text not null references documents(path) on update cascade,
  to_path   text not null references documents(path) on update cascade,
  primary key (from_path, to_path)
);
```

## The graph: `links`

One polymorphic edge table for many-to-many; real FK columns (`person_id`, `primary_role_id`) for the 1-many spine (Sam: "1-to-many where we can swing it — makes inheritance easier").

```sql
create table links (
  id          uuid primary key,
  from_type   text not null,  from_id text not null,
  to_type     text not null,  to_id   text not null,
  kind        text not null,            -- vocab 'link' or 'relationship'
  origin      text not null check (origin in ('asserted','inferred')),
  confidence  real check (confidence >= 0 and confidence <= 1),  -- required when inferred
  description text,                      -- relationship terms (person↔person)
  ...conventions,
  unique (from_type, from_id, to_type, to_id, kind)
);
create index links_from on links(from_type, from_id);
create index links_to   on links(to_type, to_id);
```

- A validation trigger asserts both endpoints exist (compensates for no polymorphic FK).
- **Asserted beats inferred**: agents may create/remove `inferred` links; only user-privileged roles touch `asserted`. Re-inferring over an asserted edge is a no-op.
- Person↔person relationships use `relationship` vocab + `description`. Creation rule (P7): user-asserted, or explicitly evidenced (a literal intro message) at confidence ≥ 0.9; otherwise propose.

## Atoms (the precise definition)

An atom is **one human-meaningful episode**: bounded time × coherent purpose × stable participants, from one source. Rules:

| Source pattern | Atomization |
|---|---|
| Meeting / call / calendar event (ended) | 1 atom |
| Chat thread (iMessage/Slack) | 1 atom per thread per local-day with activity; adapter-configurable window |
| Email thread | 1 atom per thread-beat; new beat when thread revives after >7 days or purpose shifts |
| Working session / focus block | 1 atom |
| Trip / multi-day event | 1 umbrella atom + child atoms linked `part_of` |
| Published artifact (post, paper, note dump) | 1 atom + wiki placement |
| Agent action | 1 atom per run with side effects (kind `agent_action`) |

- **Never per-message.** Per-message stats (ignored-message counts, response lag) are computed *deterministically by adapters* during sync and stored as component metrics (`03-runtime.md`) — granular analytics without atom explosion.
- **Cross-source merge**: the same episode seen by two adapters (airline email + spouse texts about the same flight) → merge gardener proposes a canonical atom; losers get `canonical_of` set and drop out of default views; all refs accumulate on the canonical atom. Merges are proposals (P7), auto-applied only at confidence ≥ 0.9 with identical time+participants.
- Atom updates happen only via `amend_log` (L1), which snapshots the prior version to audit.

## System plane

```sql
create table components (
  id              text primary key,      -- 'filer', 'imessage-adapter', 'morning-brief'
  kind            text not null check (kind in ('pipe','gardener','workflow','adapter','tool','surface')),
  circle          text not null check (circle in ('inner','outer')),
  status          text not null default 'enabled' check (status in ('enabled','disabled','retired')),
  definition_path text,                  -- git path; external tools may be null
  trigger         jsonb not null default '{"type":"manual"}',  -- {"type":"cron","expr":...} | {"type":"event","filter":...} | {"type":"manual"}
  config          jsonb not null default '{}',  -- role mappings, source semantics, model, cost ceiling, clearance, allowlist
  reliability     text not null default 'standard' check (reliability in ('standard','critical')),
  ...conventions
);
-- role scoping via links (component → role, kind 'scoped_to')

create table runs (
  id           uuid primary key,
  component_id text not null references components(id),
  started_at   timestamptz not null,
  finished_at  timestamptz,
  outcome      text check (outcome in ('ok','failed','degraded','skipped')),
  tokens_in    integer, tokens_out integer, cost_usd numeric(8,4),
  summary      text, error text,
  meta         jsonb not null default '{}'
);

create table messages (
  id                uuid primary key,
  queue             text not null,       -- 'user' | component id | topic
  kind              text not null,       -- vocab 'message'
  from_actor        text not null,
  payload           jsonb not null,      -- proposals: {"action":{"fn":...,"args":...},"evidence":[...],"quoted":[...],"requires_core":bool}
  requires_approval boolean not null default false,
  status            text not null default 'posted'
                    check (status in ('posted','claimed','read','done','approved','rejected','expired')),
  posted_at         timestamptz not null default now(),
  claimed_by        text, claimed_at timestamptz, read_at timestamptz, resolved_at timestamptz,
  ...conventions
);
-- Trigger: transitions to 'approved'/'rejected' permitted only for roles claudio_panel, claudio_core.
-- Unifies agent handoffs, user proposals, notifications: one diagnostic trail, one watchdog surface.

create table audit (
  id         bigserial primary key,
  at         timestamptz not null default now(),
  actor      text not null,              -- current_user
  fn         text,                       -- L1 function name
  table_name text, row_id text, op text,
  diff       jsonb
);
-- Append-only: no UPDATE/DELETE granted to any routine role. Purge facts land here.

create table rate_counters (              -- deterministic blast-radius bound (04-security)
  actor text not null, window_start timestamptz not null,
  writes int not null default 0, reads int not null default 0,
  primary key (actor, window_start)
);
```

## What is deliberately absent

Groups (roles encode collectives) · calendar mirror (gcal is authoritative; only ended events become atoms) · message archive (tier 0 + adapter metrics) · health/finance/places (future; sensitivity tier is ready) · embeddings/pgvector (promote-on-need) · separate proposals/queues/notifications tables (unified in `messages`) · separate sources/tools/workflows registries (unified in `components`).
