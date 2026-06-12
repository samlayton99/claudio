# The Core

The product is the **contract**, not the agents: a self-describing relational scaffold of a life, plus the protocols for reading and writing it. Everything else — agents, automations, interfaces — is a replaceable client.

## Layers, by half-life

| Layer | Half-life | Contents | Build posture |
|-------|-----------|----------|---------------|
| L0 Scaffold | decades | relational DB (two planes), type system + catalog, protocols | carefully |
| L1 Access | years | the API: typed DB functions, views, one thin MCP veneer | thin |
| L2 Workers | months–years | pipes, gardeners, workflows, adapters | disposable |
| L3 Surfaces | disposable* | entry points, custom dashboards; *one permanent control panel | regenerable from catalog |

## Two planes, one database

**Life plane** (the content — full definitions in `03-type-system.md`):
`roles` (the organizing spine), `people` + handles, `goals`, `directives` (user taste as data), `tasks` (what I owe), `expectations` (what I'm owed / waiting on), `log` (append-only atoms of what happened), `documents` (wiki index), `intake` (staging).

**System plane** (the system's model of itself), in two divisions:

*Self-awareness / hygiene* — what the gardeners read and maintain:
- `adapters` — every edge connection (in, out, or both): gmail, gcal, imessage, slack, transcripts, the old dashboard, custom dashboards. Carries direction, role mappings (the inheritance defaults), sync state, usage history.
- `tools` — registered capabilities (MCP servers, connectors): what's available, where used, last evaluated. Feeds the tool-scout loop.
- `runs` — execution history of every pipe/workflow/agent (incl. Claude Code sessions): outcome, duration, tokens.

*Custom automations*:
- `workflows` — registered automations: trigger + steps + role links + cost ceiling + enabled flag (unit defined in `04-trust-and-automation.md`).
- `proposals` — queue of pending agent suggestions awaiting approval.

**The registry triple:** every component = definition in git + registry row + run/usage history. Definitions are swappable when tools improve; the registry and history survive. Hygiene agents operate by querying this plane.

## The type system

Postgres schema is half the type system (types, constraints, foreign keys as traversal edges). The other half is semantic: `COMMENT ON` every table/column, plus a generated catalog (`SCHEMA.md`) explaining purpose, write conventions, and canonical examples. Gardeners keep the catalog in sync with the schema. This is what makes the scaffold walkable by agents that don't exist yet (see decay test).

## Protocols

1. **Single write path.** All writes go through typed Postgres functions (`create_task(...)`, `log_entry(...)`, `propose_merge(...)`). Validation lives in the DB; nothing can bypass it.
2. **Provenance by trigger.** Audit triggers record actor + source on every mutation. Agents cannot forget to log — the database does it.
3. **Intake pattern.** Capture is dumb and instant: any adapter does one insert into `intake` (raw + source). Structuring is asynchronous, done by the filer. Capture never waits on classification.
4. **Proposals + trust circles.** Risky actions (merges, migrations, outbound, deletions, new automations) become proposal rows requiring approval; routine actions run free. The inner/outer-circle line is enforced deterministically (see `04`).
5. **Pipes vs judgment.** Moving data is deterministic code; deciding about data is agents. Never spend tokens on plumbing.
6. **Draft, don't send.** The core has no outbound capability at all. Outbound lives only in consuming agents holding that permission, and never sends without explicit approval.
7. **Grow by promotion, shrink by demotion.** New domains start as JSONB + tags in `log` (zero schema cost). Gardeners propose promotions when structure recurs and demotions when data goes unused. Schema shape is an output of actual life, not foresight.
8. **Messiness dies at the mouth.** Every unstructured edge — a custom dashboard, an odd input source, a third-party agent — connects through an adapter that owns all of the translation. Inward, it speaks only L1. The core never bends to fit an edge.

## The API (L1)

The API is the database: stored functions for writes, views for reads. Agents on the mini may query directly; the in-DB contract holds either way. No HTTP API layer — that was v1's mistake, needed only because its agent runtime was remote.

The MCP server wrapping these functions is the **front door** for external agents — the main way Claude Code, Cowork, and future tools consume claudio.

**The context packet** is the heart of the product. `get_context(anchor, ...)` — anchored on a role most often, but any entity (person, workflow, goal) can anchor — returns four things: **state** (relevant rollups and atoms), **taste** (directives and goals in scope), **obligations** (due tasks, pending expectations, time-sensitive items), and **capabilities** (workflows and tools available in scope). The consumer is handed a briefing, not a database dump.

Consumption order (cache hierarchy): tier-2 rollups first, tier-1 atoms to drill, tier-0 pointers rarely.

## Worker taxonomy (L2)

- **Pipes** — deterministic sync scripts. No LLM.
- **Adapters** — edge translators (protocol 8); registered, role-mapped, built by coding agents on request.
- **Gardeners** — the only agents claudio defines, serving the scaffold itself. Roster in `04`: filer, merge, wiki, catalog sync, tool scout, hygiene.
- **Workflows** — scheduled automations (trigger + steps); the orchestrator is not in their loop. Defined in `04`.
- **Assistants / orchestrator** — assembled, never built (principle 4). Claudio defines the **orchestrator slot** (inner circle: consumes context packets, calls L1, reachable via entry points) and ships a default occupant (Claude Code / Agent SDK today); the occupant — Codex, a Hermes-like assistant, whatever wins — is swappable.

Invariant: gardeners keep the scaffold cheap for consumers to query — summaries, freshness, indexes. That is where token efficiency comes from.

## Surfaces (L3)

One **permanent control panel** — the single exception to "surfaces are disposable." The audit and control center for everything: approvals, registries (all automations visible), run log, people/role editing, wiki browsing. Its v1 is modest — plain and fast; greatness comes iteratively, after the data proves itself.

One designated **primary entry point** for conversational in/out — iMessage today. Entry points are registered adapters with permissions; there can be several, but one is primary.

Everything else — custom dashboards, metric views, an X-feed tab — is generated, disposable, connected through adapters, and regenerable from the catalog.
