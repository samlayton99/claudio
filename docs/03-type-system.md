# Type System (draft)

What agents should track in a person's life, and the types that hold it.

## The five questions

Any assistant operating a life needs answers to: **who** (people, groups), **what happened** (log), **what's next / what's owed** (commitments), **why** (roles, goals), **what do we know** (documents/wiki). The life plane is exactly these five, plus staging.

## Compaction tiers (passive data flow)

| Tier | What | Where | Example |
|------|------|-------|---------|
| 0 — raw | source-of-truth data | stays in Gmail/gcal/chat.db/files; staging copies get a TTL | the actual email thread |
| 1 — atoms | summary + pointer | scaffold tables | log entry: "Lunch w/ Jane re: Acme seed" + gmail/gcal refs |
| 2 — rollups | gardener-maintained digests | `documents` | person summary, role brief, weekly digest |

**Pointers, not mirrors:** if data has an authoritative home, claudio stores a reference and a compaction, never a copy. Reuse-over-build applies to data too.

Consumption order: agents read tier 2 first, drill into tier 1, follow pointers to tier 0 rarely. This is where token efficiency lives.

## Entities (life plane)

- **`roles`** — disciple, husband+father, student, PROD, ... `name, status (active/retired), description, doc_id`. Retire, never delete. The context-partition key: nearly everything links to roles.
- **`groups`** — ward, Hazy Lab, PROD, family. `name, kind (family/church/lab/community/company), doc_id`. Membership edges to people. Relationships and roles often attach to collectives; "everyone in my PROD context" is a membership query.
- **`people`** — `name, status, summary (tier-1 compaction, gardener-maintained), doc_id, meta`. Manual edits set `verified`; automation never overwrites verified fields.
- **`identities`** — `person_id, source, handle` (phone, email, slack id; unique per source). The entire dedup mechanism: ingestion matches handles, unmatched handles queue merge proposals.
- **`goals`** — `statement, horizon, status, doc_id` + role links. Long-horizon, mostly narrative; the doc carries the prose, the row makes it traversable.
- **`commitments`** — generalization of tasks. `description, kind (task/promise/follow_up), direction (by_me/to_me/none), person_id?, due, status, source_ref` + role links. Direction + person link turns the task list into a ledger of what I owe people and what they owe me.
- **`log`** — append-only atoms of what happened. `ts, kind (meeting/session/trip/communication/capture/agent_action/...), summary, refs (jsonb pointers to tier 0), meta` + links to people/roles/commitments. One conversation = one atom, not forty message rows.
- **`documents`** — index of every wiki page. `path, kind (person/role/goal/topic/digest/profile), title, freshness`. Prose stays markdown-in-git; the row keeps it traversable so the graph never dead-ends at the file boundary.
- **`inbox`** — staging. `ts, source, raw, status (pending/filed/discarded), filed_refs`.

## Conventions (the primitives)

- Every table: `id`, `created_at`, `updated_at`, `meta jsonb`.
- Provenance on every row: `created_by` (actor), `source`. Enforced by trigger, not discipline.
- Status enums everywhere; retire, never delete.
- Many-to-many via join tables (the traversal edges).
- New attributes start in `meta`; promotion to columns via gardener proposal (see protocol 7).

## Deliberately absent (promote on demonstrated need)

Health, finances, possessions, places, a calendar mirror, a message archive, values (live in the profile doc). All start as tagged log entries or stay in their source systems. The schema's shape is an output of actual life, not foresight.
