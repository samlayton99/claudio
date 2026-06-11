# 00 — Constitution

The law. `docs/` was the brainstorm; `specs/` governs the build. Conflicts resolve in favor of this file.

## What claudio is

A self-describing relational scaffold of one person's life, plus the protocols for reading and writing it. Everything else — agents, automations, interfaces — is a replaceable client. Claudio is the context layer, never the harness. **It is the life-harness for your agents**: as external agents get better, claudio gets more valuable, because it is what hands them your life.

## The five functions (the product, as a pipeline)

1. **Ingest** — through windows (adapters), every data point and context stream of the life lands in the scaffold. Capture is durable before anything judges it. (`06`, `01 intake`)
2. **Distill** — gardeners maintain a clean, healthy, cited wiki + skinny typed rows: the portrait. Raw becomes atoms; atoms become narrative. (`01 atoms`, `05`)
3. **Serve** — *the context is the API.* The scaffold + portrait power `get_context`: the best context builder there is, handing any agent or automation the perfect slice — state, taste, obligations, capabilities — cited and clearance-bounded. (`02`)
4. **Align** — everything maps to goals and roles (`advances` edges); the system is how the life is organized and tracked. Claudio is the **system of record and the system of alignment, not the system of engagement**: it tracks what happened, what's owed, what's expected, and how it serves the goals — todo-list UX and execution surfaces are outsourceable adapters. The alignment gardener turns drift between record and goals into questions. (`01 links`, `03 alignment`)
5. **Maintain** — self-maintaining and proactive: hygiene, watchdog, catalog, tool scouting, promote/demote. The system helps you use the system better. (A tooling marketplace is a someday-extension of the same registry.) (`03`, `04 verification`)

Every spec section serves one of these five; anything that serves none of them is cut.

## Principles

- **P1 Time.** Outlives every tool it's built with. Own the data; rent the agents.
- **P2 Simplicity.** Every component justifies its weight. Complexity is removed before capability is added.
- **P3 Friction.** ADHD-first. Capture is one text. The system reaches out; the user never has to come to it.
- **P4 Enhance, don't replace.** Never build a loop, gateway, or scheduler. Reuse over build, always; pointers over mirrors.
- **P5 Taste is king.** Agents own summaries, search, plumbing; the user owns priorities, direction, emphasis. User statements are law (directives) — but only when the channel proves they are the user's (the dictation gate, `02`).
- **P6 Reliability.** Reminders, schedules, and plumbing are 100% dependable. Deterministic scheduling, every run logged, watchdog on misses, an alarm path independent of the thing it alarms about. LLMs are never in the critical path of a reminder. Critical components are never auto-disabled.
- **P7 False-positive aversion.** A wrong proactive action costs more than a missed one. When unsure: do less, hold, or ask. The user will tell claudio the most important things. (Exception: P6 surfaces — reminders/jobs must never false-negative.)

## The decay test (P1's enforcement)

> A brand-new agent, given only this repo and the database, must orient itself and operate the system correctly within one session.

Checked at every design decision. Hardcoded agent knowledge fails it; self-description passes it.

## Principle → decision map

| Decision | Principles |
|---|---|
| Postgres as scaffold; schema + `COMMENT ON` + generated catalog | P1 |
| L1 = `SECURITY DEFINER` functions (search_path-pinned); agents hold zero direct table writes | P6, security |
| One `components` registry, one `messages` fabric, one polymorphic `links` table | P2 |
| Pipes (code) vs judgment (agents); deterministic skeleton fallback when an LLM step fails | P6, P2 |
| Workers are `claude -p` under launchd; no dispatcher daemon — each event worker claims its own queue | P4, P2 |
| Capture-first entry: every inbound message lands durably in `intake` before any LLM sees it | P3, P6 |
| Directives table injected into every scoped context; writable only through the dictation gate | P5 |
| Filer confidence thresholds; `held` intake; proposals over writes when unsure | P7 |
| One send-capable component (the iMessage edge), destination hardwired to the user | P6, P7, security |
| Sensitivity tiers via RLS (invoker views, FORCE RLS); clearance derived from `session_user`, OS-user tiers underneath | security, privacy |
| Approve applies synchronously under the panel role; privilege class of a proposal derived server-side, never trusted from the proposer | security |
| Grow by promotion / shrink by demotion; outer circle starts empty; workers cannot write code paths at runtime | P1, P2, security |

## Vocabulary

- **Plane** — life plane (the content) vs system plane (the system's model of itself).
- **Tier** — compaction: 0 raw (stays at source), 1 atoms (summary+pointer), 2 rollups (wiki).
- **Atom** — one human-meaningful episode in `log` (defined precisely in `01-schema.md` §Atoms).
- **L1** — the syscall layer: typed Postgres functions; the only write path. Function sets by privilege: agent-set, user-set (dictation-gated), panel-set, core-set (`02`).
- **Circle** — inner (immutable to the system) vs outer (agent-authored, user-approved, deployed by core; starts empty).
- **Component** — anything registered: pipe, gardener, workflow, adapter, tool, surface.
- **Pipe** — deterministic script, no LLM. **Gardener** — inner-circle agent serving the scaffold. **Workflow** — triggered pipeline (deterministic steps + declared model steps). **Adapter** — edge translator; messiness dies at the mouth. **Edge** — the TCC-bound iMessage pipe running in the user's GUI session (read + send).
- **Clearance / sensitivity** — worker read ceiling vs row label (0 normal, 1 sensitive, 2 restricted), enforced by RLS; clearance tiers are also OS users.
- **Packet** — the `get_context` result: state + taste + obligations + capabilities, all cited.
- **Batch shape** — the one canonical action encoding: `[{"fn": <L1 name>, "args": {...}}, ...]` with `{"$ref": i}` for intra-batch ids. Used by `file_intake`, proposals, `apply_actions`.
- **Standing approval** — a user-granted directive (`scope_type='approval_class'`) that lets the panel auto-apply a named, server-classified proposal class (e.g. solo calendar blocks). Revocable like any directive.
- **Dictation gate** — user-set L1 functions require a `dictation_intake_id` whose sender is a verified user handle on the iMessage service, received within 10 minutes. Text from anyone else can never become law.

## Spec tree

- `01-schema.md` — DDL, atoms, links, RLS, audit. The heart.
- `02-l1-api.md` — function sets, batch shape, context packet, MCP surface.
- `03-runtime.md` — workers, triggers, queues, reliability.
- `04-security.md` — identity tiers, grants, enforcement, verification.
- `05-wiki.md` — the portrait: page kinds, rules, lint.
- `06-surfaces.md` — adapters, the edge, panel.
- `07-build-plan.md` — phases, acceptance gates, eval suites.

Open items live in `docs/questions-queue.md`; resolved answers fold back here.
