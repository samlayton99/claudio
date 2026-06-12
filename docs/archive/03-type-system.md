# Type System

What agents should track in a person's life, and the types that hold it.

## The five questions

Any assistant operating a life needs answers to: **who** (people), **what happened** (log), **what's next / what's owed** (tasks, expectations), **why** (roles, goals, directives), **what do we know** (documents). Plus staging (`intake`).

## Compaction tiers (passive data flow)

| Tier | What | Where | Example |
|------|------|-------|---------|
| 0 — raw | source-of-truth data | stays in Gmail/gcal/chat.db/files; staging copies get a TTL | the actual email thread |
| 1 — atoms | summary + pointer | scaffold tables | log entry: "Lunch w/ Jane re: Acme seed" + refs |
| 2 — rollups | gardener-maintained digests | wiki pages via `documents` | person page, role brief, weekly digest |

**Pointers, not mirrors:** if data has an authoritative home, claudio stores a reference and a compaction, never a copy. Refs are typed `{source, locator, tool}` — not just an ID but how to fetch it ("full thread: gmail MCP, this query").

Consumption order: rollups first, drill into atoms, follow pointers to raw rarely. This is where token efficiency lives. The principle: **flow through summaries, dive into granularity when needed.**

## Entities

- **`roles`** — the organizing spine. `name, status (active/retired), summary, doc_id`. Retire, never delete. Adapters, workflows, goals, and directives all attach to roles. Collectives (ward, lab, PROD, family) are encoded by people↔role membership — there is deliberately **no groups table** (group inference is high-friction, low-value; tags and summaries cover the rest).
- **`people`** — one conceptual entity, two tables: `people` (`name, status, summary, doc_id, meta`) and `person_handles` (`person_id, source, handle` — unique per source, so the DB itself enforces "this email belongs to exactly one person"). Ingestion matches on handles; unmatched handles queue merge proposals. Manual edits set `verified`; automation never overwrites verified fields. A person's **history is a query, not a table**: log atoms linked to them, rendered as a timeline on their page.
- **`goals`** — `statement, horizon, status, doc_id` + role links. Long-horizon; the doc carries the prose, the row gives traversal. With directives, the heavyweight carrier of user taste.
- **`directives`** — user taste as data. `statement, scope (global/role/workflow/person), status`. Injected into every context packet and workflow run they scope. The latest user statement is law; gardeners surface conflicts, never resolve them.
- **`tasks`** — what I owe / must do. `description, due?, status, person_id? (a commitment to someone), primary_role_id, source_ref` + secondary role links. Due dates optional.
- **`expectations`** — what I'm owed / waiting on: a reply from a person, a job done by a date, a delivery arriving. `description, person_id?, due?, follow_up (policy), status (pending/met/missed), source_ref` + role links. A missed expectation proposes a follow-up task. Over time enables calibration ("this person replies in ~6 days").
- **`log`** — append-only atoms of what happened. `ts, kind, summary, refs, meta` + links to people/roles/tasks/expectations. One human-meaningful episode = one atom (a meeting, a working session, a trip, a conversation-as-a-whole — never forty message rows); the raw stays at tier 0 behind refs.
- **`documents`** — index of wiki pages (see `05-wiki-and-memory.md`): `path, kind, title, freshness`, plus `document_links` mirroring the wikilink graph for cheap SQL graph queries (backlinks, orphans, hubs).
- **`intake`** — staging for raw captures and sync deltas before the filer structures them. `ts, adapter, raw, status (pending/filed/discarded), filed_refs`. Not user-facing.

## Link semantics

- Every link is **asserted** (user) or **inferred** (automation, with confidence). Asserted wins forever; automation never overwrites it.
- Many-to-many where reality demands it, but entities carry a **primary** link (`primary_role_id`) for inheritance and display; secondaries live in link tables.
- **Inheritance = defaulting at filing time**, never a hard cascade: adapter role mapping (prod Slack → prod) → person's role memberships → content inference, applied in order of cost.

## Stronger typing

- Kind vocabularies are rows (a `kinds` table), not hardcoded enums — extensible by proposal, no migration needed.
- Refs CHECK-constrained to the `{source, locator, tool}` shape.
- TypeScript/Python types generated from the schema, so custom automations type-check against the scaffold.
- Contract tests on L1 functions: a migration cannot silently break a consumer.

## Conventions (the primitives)

- Every table: `id`, `created_at`, `updated_at`, `meta jsonb`.
- Summary columns are `CHECK`-length-bounded (~500 chars): compaction enforced by the type system, depth pushed to the wiki (see `05`).
- Provenance on every row: `created_by` (actor), `source`. Enforced by trigger, not discipline.
- Status everywhere; retire, never delete.
- New attributes start in `meta`; promotion via gardener proposal (protocol 7).

## Deliberately absent (promote on demonstrated need)

Groups (dropped — roles encode the collectives), health, possessions, places, a calendar mirror, a message archive, values (profile doc + directives). All start as tagged log entries or stay in their source systems. The schema's shape is an output of actual life, not foresight.

**Future high-sensitivity domains** — bank accounts/purchases, medical history — will roll in eventually. The security tier they need is designed: sensitivity labels on rows + worker clearances enforced by Row-Level Security (see `08-security.md`). The domains themselves remain future.
