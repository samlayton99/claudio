# Trust & Automation

How the system builds and runs itself without ever being able to break itself.

## Trust circles

- **Inner circle** — system artifacts the system cannot change: protocols, L1 function definitions, schema migrations, system prompts, built-in workflows and gardeners, the orchestrator slot.
- **Outer circle** — the sandbox where claudio extends itself: custom workflows, adapters, dashboards, prompts. Agent-buildable, user-approved, fully swappable.

Enforcement is **deterministic infrastructure, not prompts**:

1. **Two Postgres roles.** `claudio_core` (DDL, migrations, core registry writes — held only by human-driven sessions) vs `claudio_agent` (can call L1 functions, write life-plane data, register outer-circle components; no DDL, no core mutations). `GRANT`s make the line unbreakable — no agent can talk its way past a permission it does not hold.
2. **Repo split.** `core/` (writable only by human-driven sessions) vs `custom/` (the sandbox). File permissions + a git hook enforce it.
3. **Optional passphrase** gating core-mutating operations.

Spawned agents always receive the agent credential and the sandbox. A coding agent building claudio itself (human at the keyboard) uses core credentials; an agent spawned *by* the system never does.

## The workflow unit

workflow = **trigger** (schedule / event / user request) + **pipeline of steps**, each step either deterministic code or a declared model call (model + cost ceiling). Registered with role links, runs under its own permissions. Every run logs outcome, duration, tokens. The orchestrator is not in the loop for scheduled workflows — e.g. X feed → relevance-vs-priorities summary (cheap model) → dashboard tab, living under the prod role, no conversation involved.

## Provisioning pipeline (the system building itself)

need (user request or hygiene proposal) → proposal → **user approves** → coding agent builds in `custom/` → registered → observable in the panel.

- Nothing is created, altered, or deleted without user approval.
- Everything built is viewable, editable, and replaceable by the user. Plug and play; every piece swappable.
- **Build failures escalate to the user** — no infinite silent retries. Some plumbing gets hand-wired; the system saying "I couldn't wire this, over to you" is correct behavior.

## Adapters

Every edge connection is an adapter (protocol 8): it owns 100% of the translation between an unstructured outside (custom dashboard, odd source, third-party agent) and L1. Inbound: mess → `intake` rows or typed L1 calls. Outbound: L1 views → whatever shape the surface needs. Registered with direction, role mappings, sync state, usage. The old dashboard enters here: first as an input adapter (a pipe syncs its Supabase), later as an output surface.

## Core baseline (inner circle, ships with the system)

**Workflows:** morning brief · per-window daily summaries · todo manager (scans tasks + expectations for deadlines and follow-ups) · meeting setter (proposes times, never books) · query-what-happened.

**Gardeners:**
- **filer** — the keystone agent: turns each `intake` item into typed L1 calls + links (one note can yield a new person + an expectation-with-follow-up + a task). Low-confidence extractions become proposals, not writes. Built against an eval corpus of 20–30 real labeled examples collected *before* implementation.
- **merge** — person dedup proposals from unmatched handles.
- **wiki** — person/role pages, summaries, backlinks, orphan detection (see `05`).
- **catalog sync** — schema ↔ `SCHEMA.md`, always true.
- **tool scout** — watches for better MCP servers/tools, proposes them into `tools`.
- **hygiene** — usage review, promote/demote proposals, token-spend review ("this digest costs X/mo and goes unread").

**Pipes:** per-adapter syncs · the watchdog.

## Reliability (principle 6)

- launchd does the scheduling — never agent memory.
- Every scheduled run writes a `runs` row.
- The **watchdog** is a deterministic pipe: expected runs vs actual runs, alert on any miss. Dead-man's-switch, zero LLM.
- One silently missed morning brief costs more trust than the rest of the system earns.

## Token economy

Workflows declare a model and cost ceiling; runs log tokens; hygiene reviews spend. The system knows what tools to use and what is overkill — cheap models for routine judgment, frontier models only where reasoning earns it.
