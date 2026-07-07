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
- **P3 Friction.** ADHD-first. Capture is one text. The system reaches out; the user never has to come to it. Effortless is the bar (`docs/archive/ux-rings.md`).
- **P4 Enhance, don't replace.** Never build a loop, gateway, or scheduler. Reuse over build. Pointers over mirrors for *live external state* (calendar futures, mailbox state); the *historical stream* is owned in-house — external refs rot (servers down, tokens renewed, agents lose context), so the record never depends on them.
- **P5 Taste is king.** Agents own summaries, search, plumbing; the user owns priorities, direction, emphasis. User statements are law (directives) — only through channels that prove they are the user's (dictation gate). Exactly one agent (the mirror) is licensed to model taste, never to own it. LLM confidence is poorly calibrated, so confidence defaults LOW unless glaringly obvious — when unsure, the system asks taste, not itself.
- **P6 Reliability.** Reminders, schedules, queues, and plumbing are 100% dependable: deterministic scheduling, every run logged, watchdog on misses, an alarm independent of the alarm channel, leases on every claim. LLMs are never in the critical path of a reminder. Critical components are never auto-disabled.
- **P7 False-positive aversion.** A wrong proactive action costs more than a missed one. When unsure: do less, hold, or ask. The user will tell claudio the most important things. (Exception: P6 surfaces must never false-negative.)
- **P8 The fundamental law of LLMs.** *Quality decays exponentially with the number of nested summaries.* Mechanical rules, not vibes: compaction depth is capped at two (raw → atom → rollup); every rollup re-derives from atoms, never from prior rollups; absolute dates only; load-bearing facts (commitments, dates, amounts, names) are stored as verbatim quotes, not paraphrase; any irreversible or external action re-grounds from tier-0 refs first; prose edits are deltas, never full-page regeneration. (Each rule is independently evidenced — `docs/archive/research-traversal.md`, `docs/archive/research-wiki.md`.)
- **P9 Gardeners are downstream failures.** Every gardener run is evidence of an upstream design gap. The design does everything to deny gardeners work (constraints, idempotent pipes, typed gates); the system does everything to ensure they run dutifully anyway. Build inside this minimax tension; a shrinking gardener workload is the health metric.
- **P10 Nothing scattered.** Parameters live in ONE registry (core/outer rings); every agent's prompt and context-construction spec lives in ITS OWN folder under one tree (`core/agents/` inner, `custom/agents/` outer). Tweaking the system never means hunting through code.
- **P11 Type over term.** The life-harness is the **type** (shippable, general); a life is the **term** (one user's configuration and data). The standing question at every decision: *what are we assuming about how the user lives or uses this?* Any such assumption belongs in the term (config, seeds, regimes) — never in the type (schema, functions, normative spec). Occam's razor on user assumptions when building the type. The type must handle independent terms gracefully AND the same term changing over time: term values that interpret data are **regime-dated**, and interpretation always uses the regime in force at capture time. Sam's life is the reference term — the test case that hardens the type, never the spec. (Audit + packaging path: `docs/archive/type-term-audit.md`.)
  **The standard library.** Between type and term sits shipped, term-shaped content: default windows and workflows (the edge channel, gcal/gmail adapters, the brief, the scanner), starter vocabularies (atom kinds, notable reasons), the `general` role, the wiki chapters, default parameters, an anonymized starter corpus. These are *technically terms of the type* — instances, not law — but they are maintained and shipped WITH the type, so a fresh install is useful from minute one. Stdlib is usable as-is, overridable, and disableable by the term; **user overrides are term and survive updates**. The three-way line: **type** = invariants (schema, functions, protocols); **stdlib** = shipped defaults anyone can run on day one; **term** = this user's values and data. Don't confuse stdlib with a type/term leak — it is the reason a new user gets benefit immediately (P3).
  **The type is installed by default; forking is a choice, not the path.** Three artifacts: the **type release** (versioned, core-owned, read-only to every non-core uid *including the user's own interactive sessions* — even the dumbest term-building agent structurally cannot touch it); the **term workspace** (the user's own repo: window instances, custom dashboards, custom agents, seeds, wiki — fully theirs); the **dev checkout** (maintainers; type changes land upstream as PRs and propagate to installs as tagged releases + append-only migrations, term untouched). Forking is permitted — but **the fork test** holds: every legitimate customization is expressible in the term; a customization that requires editing the type is a type bug, so installing + term-building should beat forking on effort, even for a senior dev. (Whether the type is ever publicly maintained is undecided — this clause preserves that option cheaply, not commits to it.)
- **P12 Judgments are selections.** Any LLM judgment the scaffold acts on is a **binary or closed-vocabulary selection, typechecked at write time** (CHECK / FK / vocab trigger) — never free prose. The model picks from a list it didn't write; nuance goes in prose fields (`detail`, descriptions) that drive nothing. If a judgment can't be enumerated, it isn't automated — it becomes a question to the user (P5/P7), and recurring answers grow the vocabulary by promotion. Canonical instance: `notable` is a boolean whose `notable_reason` must be an active kind in the `notable_reason` vocab, CHECK-paired and trigger-validated; "felt important" is unwritable.

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
| Type/term split: assumptions about the user live in config/seeds/regimes, never schema/functions/spec; per-source meaning (`semantics`) is term, regime-dated | P11, P1 |
| LLM judgments land as typechecked selections (vocab kinds, `notable_reason`, server-classified proposal classes); prose annotates, never drives | P12, P5 |

## Vocabulary

- **Purpose plane** — the apex contract: goals (horizons + types), values/beliefs (behavior drivers + key truths), attributes (identity-based goals + goalposts), and the **priorities document** (versioned prose: what matters most and why). Readable by every agent — the system is mission-aligned; writable only by the user. **The mirror** — the agent that elicits/maintains the contract and monitors the life against it. It owns exactly one judgment (lived-vs-proclaimed) and hands taste to no one — taste reaches agents only as user-set data (directives, weights, the contract itself).
- **Plane** — life (content) vs system (the system's model of itself) vs purpose (the contract above both).
- **Tier** — compaction: 0 raw (the in-house historical record: `intake` rows + `archive/` payloads, tagged by rawness; the external source is the origin, never the custodian), 1 atoms (the accounting/directory over raw), 2 rollups. Depth capped by P8.
- **Atom** — one human-meaningful episode in `atoms` (`01`). The morning brief doubles as the daily rollup (one reflect-organ, not four — over-engineering pass).
- **Window** — a data-ingesting adapter with role mappings; `mode` **passive** (copies the constant stream: texts, email, slack) or **probing** (inquiry-based — an MCP server or external agent wearing the window hat; polled on cadence or orchestrator-triggered). **Surface** — an outbound adapter. **Edge** — the required, claudio-owned ground-zero channel (TCC-bound pipe in the user's session).
- **L1** — the syscall layer; function sets: agent, user (dictation-gated), panel, core (`02`). **Internal writes** (L1, to the scaffold) vs **external writes** (sends/posts to the world — never claudio's; owned by external agents after handoff).
- **Circle** — inner (immutable to the system) vs outer (agent-authored, user-approved, core-deployed; starts empty).
- **Chapters** — the fixed top-level wiki MOCs (the eleven biography chapters incl. `cadences`, `05`).
- **Clearance / sensitivity** — 0 normal, 1 sensitive, 2 restricted (purpose, future finance/medical).
- **Packet** — the `get_context` result. **Batch shape** — `[{"fn","args"}, ...]` with `{"$ref": i}`; the one action encoding.
- **Standing approval** — user-granted directive auto-approving a named, server-classified proposal class. **Dictation gate** — user-set functions demand a verified-user message on the verified channel (≤10 min); the panel satisfies by role.
- **Handshake** — the external-agent onboarding protocol (`06`).
- **Type / Term** — the life-harness (general, shippable) vs one user's life configured into it (roles, weights, purpose contract, window instances + semantics + filters, directives, data). P11. Onboarding a new user IS term-authoring: elicitation → roles + contract; window registration → their life's meaning.
- **Regime** — how term values that interpret data change over time. `semantics` is SCALAR until the first real regime change (grow by promotion — the audit log already keeps config history); at that point it promotes to a dated list `[{"effective_from": ts, ...}]` and captures are interpreted under the regime in force at `received_at`.

## Portability rule

The Mac mini is the proving ground, never a load-bearing assumption: core is POSIX + Postgres + cron semantics; every macOS-specific dependency (TCC, launchd, keychain, pf) is quarantined in the edge + deploy layer with a documented Linux/VPS mapping. Nothing in the design prevents future hosting elsewhere.

## Spec tree

`01-schema.md` (DDL, purpose plane, atoms, links, RLS) · `02-l1-api.md` (function sets, packet, ergonomics) · `03-runtime.md` (workers, triggers, reliability, budget) · `04-security.md` (tiers, grants, enforcement) · `05-wiki.md` (the biography) · `06-surfaces.md` (windows, edge, panel, handshake) · `07-build-plan.md` (phases, gates, evals).

Open items: `docs/questions-queue.md`. Honesty conditions: `docs/archive/honesty-audit.md` — P2-in-two-weeks; value at every stop; and the governing trio: **kill criterion + effort slider + usage monitoring**. Research: `docs/archive/research-traversal.md`, `docs/archive/research-wiki.md`. History and reasoning in prose: `CONTEXT.md` (repo root); archived brainstorm in `docs/archive/`.
