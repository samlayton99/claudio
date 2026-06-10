# Claudio — Vision

A personal life orchestrator: a typed, agent-operable scaffold of one person's life, and the agents that act on it. Built to outlive every tool it is built with.

## Guiding principles (in priority order)

1. **Stand the test of time.** Grows with the person and with new tools. Agents, models, and harnesses churn every few months; the data and its contracts last decades. Own the data, rent the agents.
2. **Simplicity.** No over-engineering. Every component must justify its existence against the decay test below.
3. **Lowest friction.** ADHD-first. Immediate benefit, never a chore. Capture is one text. The system reaches out; the user is never required to come to it.

## The decay test

> A brand-new agent, given only this repo and the database, must be able to orient itself and operate the system correctly within one session.

Every design decision is checked against this. Hardcoded agent knowledge fails it; self-description passes it.

## What this is not

- Not a custom agent harness, LLM-calling layer, or orchestration engine — stock harnesses (Claude Code today) run everything.
- Not a load-bearing UI. Interfaces are disposable views over the scaffold.
- Not a pre-specified catalog of agents. Workers plug in and swap out as tools improve.

## Lineage

Two prior attempts, both over-complicated and hardcoded:

- **First Principles Dashboard** (`~/Desktop/my-repos/profile/dashboard`) — Next.js + Supabase. Hand-rolled LLM harness (YAML agent configs, prompt builders, `/api/agents/*` routes). App was load-bearing.
- **Hermes plan** (`~/Desktop/claude`) — VPS + Telegram gateway + 14 pre-specified sub-agents. Never built; would have ossified immediately.

Worth keeping from them: the append-only event log ("if it didn't write an event, it didn't happen"), draft-don't-send, one-text capture with no confirmation prompts, the approval queue.

## Environment

Always-on Mac mini is home base: database, repo, scheduled agents, iMessage access, files. Local-first; cloud only where it earns its place.
