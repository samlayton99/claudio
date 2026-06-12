# 00 — Constitution

The law. `docs/` is the brainstorm; `specs/` governs the build. Conflicts resolve in favor of this file.

## What claudio is

A self-describing relational scaffold of one person's life, plus the protocols for reading and writing it — **the life-harness for your agents**. Everything else is a replaceable client. Claudio is the context layer, never the harness: as external agents get better, claudio gets more valuable, because it is what hands them your life.

The apex of the system is the **purpose contract**: the user's stated goals, values, and attributes, maintained with the user by one taste-owning agent, against which the whole recorded life is continuously typechecked. Life purpose as a typecheck against reality — every automation, page, and packet is downstream of it.

## The five functions (the product, as a pipeline)

1. **Ingest** — windows bring every data stream of the life into the scaffold. Capture is durable before anything judges it. (`06`, `01 intake`)
2. **Distill** — gardeners maintain skinny typed rows + a clean, cited biography (the wiki). Raw becomes atoms; atoms become narrative. (`01 atoms`, `05`)
3. **Serve** — *the context is the API.* `get_context` hands any agent the right slice — state, taste, obligations, capabilities — cited, clearance-bounded, token-budgeted. (`02`)
4. **Align** — everything maps to the purpose contract through roles and `advances` edges. Claudio is the **system of record and the system of alignment, not the system of engagement** — todo-list UX and execution surfaces are outsourceable adapters. Drift between proclaimed and lived becomes the mirror's questions. (`01 purpose`, `03 mirror`)
5. **Maintain** — self-maintaining and proactive: hygiene (which also proposes new tools and windows from usage signals), watchdog, catalog, promote/demote. The system helps you use the system better. (`03`, `04`)

Every spec section serves one of these; anything serving none is cut.

## Principles

- **P1 Time.** Outlives every tool it's built with. Own the data; rent the agents.
- **P2 Simplicity.** Every component justifies its weight. Complexity is removed before capability is added. Occam's razor is king.
- **P3 Friction.** ADHD-first. Capture is one text. The system reaches out; the user never has to come to it. Effortless is the bar (`docs/ux-rings.md`).
- **P4 Enhance, don't replace.** Never build a loop, gateway, or scheduler. Reuse over build; pointers over mirrors.
- **P5 Taste is king.** Agents own summaries, search, plumbing; the user owns priorities, direction, emphasis. User statements are law (directives) — only through channels that prove they are the user's (dictation gate). Exactly one agent (the mirror) is licensed to model taste, never to own it. LLM confidence is poorly calibrated, so confidence defaults LOW unless glaringly obvious — when unsure, the system asks taste, not itself.
- **P6 Reliability.** Reminders, schedules, queues, and plumbing are 100% dependable: deterministic scheduling, every run logged, watchdog on misses, an alarm independent of the alarm channel, leases on every claim. LLMs are never in the critical path of a reminder. Critical components are never auto-disabled.
- **P7 False-positive aversion.** A wrong proactive action costs more than a missed one. When unsure: do less, hold, or ask. The user will tell claudio the most important things. (Exception: P6 surfaces must never false-negative.)
- **P8 The fundamental law of LLMs.** *Quality decays exponentially with the number of nested summaries.* Mechanical rules, not vibes: compaction depth is capped at two (raw → atom → rollup); every rollup re-derives from atoms, never from prior rollups; absolute dates only; load-bearing facts (commitments, dates, amounts, names) are stored as verbatim quotes, not paraphrase; any irreversible or external action re-grounds from tier-0 refs first; prose edits are deltas, never full-page regeneration. (Each rule is independently evidenced — `docs/research-traversal.md`, `docs/research-wiki.md`.)
- **P9 Gardeners are downstream failures.** Every gardener run is evidence of an upstream design gap. The design does everything to deny gardeners work (constraints, idempotent pipes, typed gates); the system does everything to ensure they run dutifully anyway. Build inside this minimax tension; a shrinking gardener workload is the health metric.
- **P10 Nothing scattered.** Parameters live in ONE registry (core/outer rings); every agent's prompt and context-construction spec lives in ITS OWN folder under one tree (`core/agents/` inner, `custom/agents/` outer). Tweaking the system never means hunting through code.

## The decay test (P1's enforcement)

> A brand-new agent, given only this repo and the database, must orient itself and operate the system correctly within one session.

External agents get the same property via the **handshake protocol** (`06`): read the catalog, declare *requested* scopes, propose registration; the user approves; capability is **issued, never declared** — an agent has nothing to hide because it has nothing until granted.

## Principle → decision map

| Decision | Principles |
|---|---|
| Postgres scaffold; schema + `COMMENT ON` (with example calls) + generated catalog (with sample rows) | P1, research |
| **The type system is the skeleton; the purpose contract is its apex.** Nothing exists without a typecheck: statuses CHECKed, kinds vocab-validated, jsonb payloads schema-validated by trigger, refs shape-checked, contract tests (generated TS types arrive with the panel, P3) | P1, P2 |
| L1 typed functions as the only write surface; free reads only via invoker views (raw SQL agents: 21% solve rate + injection incidents — research) | P6, security |
| One registry, one message fabric, one links table, one parameters registry (core/outer) | P2 |
| Pipes vs judgment; deterministic skeleton fallback when an LLM step fails | P6, P2 |
| Workers are stock harnesses under launchd; orchestrator/agents configurable slots, never hardcoded | P4, P1 |
| Capture-first entry on a required, claudio-owned ground-zero channel | P3, P6, security |
| Purpose plane readable by every agent (mission alignment — the user's call); writable only via dictation gate / panel / mirror sessions with read-back | P5, security |
| Two-lane scoring: obligations score by importance × urgency (never recency); context by importance × recency. Role weights are user-set taste | P5, research |
| Directives injected into every scoped context; taste never truncated from packets | P5 |
| Filer confidence thresholds (default low); held intake; proposals over writes | P7, P5 |
| One send-capable edge, destinations hardwired; approval acts on claudio-owned surfaces; approved external work handed off to owning agents | P6, security |
| Sensitivity via RLS (forced, invoker views); clearance from `session_user`; OS-user tiers | security, privacy |
| Weighted-sum packet scoring (recency-decay + due-ness + importance), timestamps rendered inline | research |
| Supersedence over deletion for inferred facts (point-in-time queries survive) | P8, research |
| Grow by promotion / shrink by demotion; outer circle starts empty; workers never write code paths | P1, P2, security |
| Windows are a first-class category (data-ingesting, role-assigned), distinct from agents/automations | P2, his review |

## Vocabulary

- **Purpose plane** — the apex contract: goals (horizons + types), values/beliefs (behavior drivers + key truths), attributes (identity-based goals + goalposts), and the **priorities document** (versioned prose: what matters most and why). Readable by every agent — the system is mission-aligned; writable only by the user. **The mirror** — the agent that elicits/maintains the contract and monitors the life against it. It owns exactly one judgment (lived-vs-proclaimed) and hands taste to no one — taste reaches agents only as user-set data (directives, weights, the contract itself).
- **Plane** — life (content) vs system (the system's model of itself) vs purpose (the contract above both).
- **Tier** — compaction: 0 raw (stays at source), 1 atoms, 2 rollups. Depth capped by P8.
- **Atom** — one human-meaningful episode in `atoms` (`01`). The morning brief doubles as the daily rollup (one reflect-organ, not four — over-engineering pass).
- **Window** — a data-ingesting adapter with role mappings. **Surface** — an outbound adapter. **Edge** — the required, claudio-owned ground-zero channel (TCC-bound pipe in the user's session).
- **L1** — the syscall layer; function sets: agent, user (dictation-gated), panel, core (`02`). **Internal writes** (L1, to the scaffold) vs **external writes** (sends/posts to the world — never claudio's; owned by external agents after handoff).
- **Circle** — inner (immutable to the system) vs outer (agent-authored, user-approved, core-deployed; starts empty).
- **Chapters** — the fixed top-level wiki MOCs (the eleven biography chapters incl. `cadences`, `05`).
- **Clearance / sensitivity** — 0 normal, 1 sensitive, 2 restricted (purpose, future finance/medical).
- **Packet** — the `get_context` result. **Batch shape** — `[{"fn","args"}, ...]` with `{"$ref": i}`; the one action encoding.
- **Standing approval** — user-granted directive auto-approving a named, server-classified proposal class. **Dictation gate** — user-set functions demand a verified-user message on the verified channel (≤10 min); the panel satisfies by role.
- **Handshake** — the external-agent onboarding protocol (`06`).

## Portability rule

The Mac mini is the proving ground, never a load-bearing assumption: core is POSIX + Postgres + cron semantics; every macOS-specific dependency (TCC, launchd, keychain, pf) is quarantined in the edge + deploy layer with a documented Linux/VPS mapping. Nothing in the design prevents future hosting elsewhere.

## Spec tree

`01-schema.md` (DDL, purpose plane, atoms, links, RLS) · `02-l1-api.md` (function sets, packet, ergonomics) · `03-runtime.md` (workers, triggers, reliability, budget) · `04-security.md` (tiers, grants, enforcement) · `05-wiki.md` (the biography) · `06-surfaces.md` (windows, edge, panel, handshake) · `07-build-plan.md` (phases, gates, evals).

Open items: `docs/questions-queue.md`. Honesty conditions: `docs/honesty-audit.md` — P2-in-two-weeks; value at every stop; and the governing trio: **kill criterion + effort slider + usage monitoring**. Research: `docs/research-traversal.md`, `docs/research-wiki.md`. History and reasoning in prose: `CONTEXT.md` (repo root); archived brainstorm in `docs/archive/`.
