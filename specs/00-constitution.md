# 00 — Constitution

The law. `docs/` was the brainstorm; `specs/` governs the build. Conflicts resolve in favor of this file.

## What claudio is

A self-describing relational scaffold of one person's life, plus the protocols for reading and writing it. Everything else — agents, automations, interfaces — is a replaceable client. Claudio is the context layer, never the harness.

## Principles

- **P1 Time.** Outlives every tool it's built with. Own the data; rent the agents.
- **P2 Simplicity.** Every component justifies its weight. Complexity is removed before capability is added.
- **P3 Friction.** ADHD-first. Capture is one text. The system reaches out; the user never has to come to it.
- **P4 Enhance, don't replace.** Never build a loop, gateway, or scheduler. Reuse over build, always; pointers over mirrors.
- **P5 Taste is king.** Agents own summaries, search, plumbing; the user owns priorities, direction, emphasis. User statements are law (directives).
- **P6 Reliability.** Reminders, schedules, and plumbing are 100% dependable. Deterministic scheduling, every run logged, watchdog on misses. LLMs are never in the critical path of a reminder.
- **P7 False-positive aversion.** A wrong proactive action costs more than a missed one. When unsure: do less, hold, or ask. The user will tell claudio the most important things. (Exception: P6 surfaces — reminders/jobs must never false-negative.)

## The decay test (P1's enforcement)

> A brand-new agent, given only this repo and the database, must orient itself and operate the system correctly within one session.

Checked at every design decision. Hardcoded agent knowledge fails it; self-description passes it.

## Principle → decision map

| Decision | Principles |
|---|---|
| Postgres as scaffold; schema + `COMMENT ON` + generated catalog | P1 |
| L1 = `SECURITY DEFINER` functions; zero direct table writes for agents | P6, security |
| One `components` registry, one `messages` table, one polymorphic `links` table | P2 |
| Pipes (code) vs judgment (agents); deterministic skeleton fallback on LLM failure | P6, P2 |
| Workers are `claude -p` under launchd; orchestrator slot filled by stock harness | P4 |
| Directives table injected into every scoped context | P5 |
| Intake → filer asynchronous split; one-text capture | P3 |
| Filer confidence thresholds; held intake; proposals over writes when unsure | P7 |
| Notifier is the only sender; destination hardwired to the user | P6, P7, security |
| Sensitivity tiers via RLS; clearance per worker | security, privacy |
| Grow by promotion / shrink by demotion; outer circle starts empty | P1, P2 |

## Vocabulary

- **Plane** — life plane (the content) vs system plane (the system's model of itself).
- **Tier** — compaction: 0 raw (stays at source), 1 atoms (summary+pointer), 2 rollups (wiki).
- **Atom** — one human-meaningful episode in `log` (defined precisely in `01-schema.md` §Atoms).
- **L1** — the syscall layer: typed Postgres functions; the only write path.
- **Circle** — inner (immutable to the system) vs outer (the sandbox; starts empty).
- **Component** — anything registered: pipe, gardener, workflow, adapter, tool, surface.
- **Pipe** — deterministic script. No LLM. **Gardener** — inner-circle agent serving the scaffold. **Workflow** — triggered pipeline (deterministic steps + declared model steps). **Adapter** — edge translator; messiness dies at the mouth.
- **Clearance / sensitivity** — worker read ceiling vs row label (0 normal, 1 sensitive, 2 restricted), enforced by RLS.
- **Packet** — the `get_context` result: state + taste + obligations + capabilities, all cited.

## Spec tree

- `01-schema.md` — DDL, atoms, links, RLS, audit. The heart.
- `02-l1-api.md` — functions, context packet, MCP surface.
- `03-runtime.md` — workers, queues, scheduling, reliability.
- `04-security.md` — boundaries, grants matrix, enforcement, verification.
- `05-wiki.md` — the portrait: page kinds, rules, lint.
- `06-surfaces.md` — adapters, entry point, panel.
- `07-build-plan.md` — phases, acceptance gates, eval suites.

Open items live in `docs/questions-queue.md`; resolved answers get folded back here.
