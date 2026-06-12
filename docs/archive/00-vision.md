# Claudio — Vision

A personal life orchestrator: a typed, agent-operable scaffold of one person's life, and the agents that act on it. Built to outlive every tool it is built with.

## Guiding principles (in priority order)

1. **Stand the test of time.** Grows with the person and with new tools. Agents, models, and harnesses churn every few months; the data and its contracts last decades. Own the data, rent the agents.
2. **Simplicity.** No over-engineering. Every component must justify its existence against the decay test below.
3. **Lowest friction.** ADHD-first. Immediate benefit, never a chore. Capture is one text. The system reaches out; the user is never required to come to it.
4. **Enhance, don't replace.** Claudio is the context layer, never the harness. Claude Code, Cowork, OpenClaw, Hermes-like assistants, and whatever comes next are consumers to feed, not competitors to rebuild. Boundary test, applied at every decision: *does this component feed an agent, or is it the agent?* If it runs the loop, routes the messages, or schedules the work, it is not ours to build. Re-check this constantly — it is the failure mode of both prior attempts. Corollary: **reuse over build, always** — the best external MCP servers and tools before anything custom, and pointers to authoritative data stores instead of mirrors.
5. **User taste is king.** Agents own summaries, search, plumbing, and serving ideas; the user owns priorities, direction, and emphasis. Taste is stored as data (directives) and injected as law into every automation it scopes. The user never fights the system to get what they want.
6. **Reliability is king.** Reminders, schedules, and plumbing must be 100% dependable: deterministic scheduling, every run logged, a watchdog that catches misses. One silent failure costs more trust than a hundred successes earn.

## The decay test

> A brand-new agent, given only this repo and the database, must be able to orient itself and operate the system correctly within one session.

Every design decision is checked against this. Hardcoded agent knowledge fails it; self-description passes it.

## What this is not

- Not a custom agent harness, LLM-calling layer, orchestration engine, message gateway, or scheduler — stock harnesses (Claude Code today) run everything.
- Not an assistant product. Claudio feeds assistants; the better external agents get, the more valuable claudio becomes.
- Not a load-bearing UI. Interfaces are disposable views over the scaffold.
- Not a pre-specified catalog of agents. Workers plug in and swap out as tools improve.

## Lineage

Two prior attempts, both over-complicated and hardcoded:

- **First Principles Dashboard** (`~/Desktop/my-repos/profile/dashboard`) — Next.js + Supabase. Hand-rolled LLM harness (YAML agent configs, prompt builders, `/api/agents/*` routes). App was load-bearing.
- **Hermes plan** (`~/Desktop/claude`) — VPS + Telegram gateway + 14 pre-specified sub-agents. Never built; would have ossified immediately.

Worth keeping from them: the append-only event log ("if it didn't write an event, it didn't happen"), draft-don't-send, one-text capture with no confirmation prompts, the approval queue.

## Environment

Always-on Mac mini is home base: database, repo, scheduled agents, iMessage access, files. Local-first; cloud only where it earns its place.
