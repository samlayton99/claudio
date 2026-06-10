# The Core

The product is the **contract**, not the agents: a self-describing relational scaffold of a life, plus the protocols for reading and writing it. Everything else — agents, automations, interfaces — is a replaceable client.

## Layers, by half-life

| Layer | Half-life | Contents | Build posture |
|-------|-----------|----------|---------------|
| L0 Scaffold | decades | relational DB (two planes), type system + catalog, protocols | carefully |
| L1 Access | years | the API: typed DB functions, views, one thin MCP veneer | thin |
| L2 Workers | months–years | pipes (deterministic sync), gardeners (hygiene), assistants (life), orchestrator | disposable |
| L3 Surfaces | disposable | chat (iMessage), browser management UI, dashboards | regenerable from catalog |

## Two planes, one database

**Life plane** (the content):
- `roles` — disciple, husband+father, student, ... Add/remove over time. The primary context-partition key: agents pull role-scoped slices, never the whole life.
- `people` + `identities` — person rows plus per-source handles (phone, email, Slack ID). Identity matching happens on handles; unmatched handles queue for merge proposals. Manual edits set `verified` and are never overwritten by automation.
- `goals` — long-horizon aims, linked to roles.
- `tasks` — actionable items, linked to roles/people/goals.
- `log` — append-only stream of what happened: meetings, sessions, trips, captures, agent actions. Typed kinds; links to people/roles/tasks. The heart of the system; everything lands here first or references something that did.
- `documents` — index of every wiki page, so prose is traversable from the graph. Wiki = narrative (markdown in git); DB = facts. Goals and people link to their pages.
- `inbox` — staging for all raw input before structuring.

**System plane** (the system's model of itself):
- `sources` — registered windows (gmail, gcal, imessage, slack, transcripts, ...) + sync state.
- `workflows` — registered automations + schedule + enabled flag.
- `interfaces` — registered touchpoints + usage events.
- `runs` — execution history of every pipe/agent/workflow (incl. Claude Code sessions).
- `proposals` — queue of pending agent suggestions awaiting approval.

**The registry triple:** every component = definition in git + registry row + run/usage history. Definitions are swappable when tools improve; the registry and history survive. Hygiene agents operate by querying this plane.

## The type system

Postgres schema is half the type system (types, constraints, foreign keys as traversal edges). The other half is semantic: `COMMENT ON` every table/column, plus a generated catalog (`SCHEMA.md`) explaining purpose, write conventions, and canonical examples. Gardeners keep the catalog in sync with the schema. This is what makes the scaffold walkable by agents that don't exist yet (see decay test).

## Protocols

1. **Single write path.** All writes go through typed Postgres functions (`create_task(...)`, `log_entry(...)`, `propose_merge(...)`). Validation lives in the DB; nothing can bypass it.
2. **Provenance by trigger.** Audit triggers record actor + source on every mutation. Agents cannot forget to log — the database does it.
3. **Inbox pattern.** Capture is dumb and instant (one insert, any interface). Structuring is asynchronous, done by gardeners. Capture never waits on classification.
4. **Proposals + autonomy levels.** Risky actions (people merges, schema migrations, outbound sends, deletions) become proposal rows requiring approval. Routine actions (filing inbox items) run free. Autonomy is per action type and can widen as trust grows.
5. **Pipes vs judgment.** Moving data is deterministic code (launchd scripts: sync gmail/gcal/imessage into staging). Deciding about data is agents (triage, filing, merging, summarizing). Never spend tokens on plumbing.
6. **Draft, don't send.** No outbound communication without explicit approval.
7. **Grow by promotion, shrink by demotion.** New domains start as JSONB + tags in `log` (zero schema cost). Gardeners propose promotions when structure recurs ("30 church-agenda entries with the same shape — table?") and demotions when data goes unused. Schema shape is an output of actual life, not foresight.

## The API (L1)

The API is the database: stored functions for writes, views for reads. One thin MCP server wraps the same functions for consumers that can't speak SQL (remote interfaces, future tools). Agents on the mini may query directly; the in-DB contract holds either way. No HTTP API layer — that was v1's mistake, needed only because its agent runtime was remote.

Consequence: this requires Postgres (stored functions, comments, triggers). SQLite is ruled out.

## Worker taxonomy (L2)

- **Pipes** — deterministic sync scripts. No LLM.
- **Gardeners** — maintain the scaffold: file inbox, dedup people, refresh wiki, sync catalog, propose promotions/demotions, system hygiene ("X digest unread 6 weeks — kill it?").
- **Assistants** — use the scaffold to improve the life: briefs, planning, triage, drafting, nudges, procrastination checks.
- **Orchestrator** — the conversational front (iMessage primary): routes intent, dispatches workflows and Claude Code sessions, answers from role-scoped context.

Invariant: gardeners keep the scaffold cheap for assistants to query — summaries, freshness, indexes. That is where token efficiency comes from.

## Surfaces (L3)

Dashboards and management UIs are generated, read-only-plus-L1-writes views. Because the catalog describes what exists, "build me a dashboard with meetings, metrics, and the X digest" is an afternoon agent task; throw it away when wants change. Browsable wiki, editable people/roles, approval queue — all the same pattern, available equally via chat and browser.
