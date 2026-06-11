# Trust & Automation

How the system builds and runs itself without ever being able to break itself.

## Trust circles

- **Inner circle** — system artifacts the system cannot change: protocols, L1 function definitions, schema migrations, system prompts, built-in workflows and gardeners, the orchestrator slot.
- **Outer circle** — the sandbox where claudio extends itself: custom workflows, adapters, dashboards, prompts. Agent-buildable, user-approved, fully swappable. **Starts empty** — it fills only through the provisioning pipeline.

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
- All proposals surface in the panel; time-sensitive or blocking ones also push via the primary entry point.

## Agent coordination (queues)

The queue is **data**; the waking is the harness's job. A system-plane `messages` table: `queue` (a topic or an agent id), `from_actor`, `payload/ref`, lifecycle as timestamps (`posted_at, claimed_at, read_at, done_at`), `status`, `result_ref`.

- **Public queues** are topics any qualified agent claims (`FOR UPDATE SKIP LOCKED` — race-free claiming is a solved Postgres problem). **Personal queues** are addressed to an agent id.
- **Pings are Postgres `LISTEN/NOTIFY`** — native, in-database, no message bus built. A tiny deterministic dispatcher pipe listens and launches the target agent via the harness; scheduled agents also check their queue on wake.
- Read-receipts and completion-pings are queryable state: the poster sees posted→read→done as timestamps; the watchdog flags stale rows; "why is this held up" is a SQL query. The diagnostic trail is the table itself.
- **Guardrail (principle 4):** queues coordinate handoffs between components and waits — never control flow. A workflow's internal steps stay in its own pipeline; no retry logic or DAG machinery lives in the queue. The moment it grows those, we have rebuilt the harness.

## Adapters

Every edge connection is an adapter (protocol 8): it owns 100% of the translation between an unstructured outside (custom dashboard, odd source, third-party agent) and L1. Inbound: mess → `intake` rows or typed L1 calls. Outbound: L1 views → whatever shape the surface needs. Registered with direction, role mappings, sync state, usage. The old dashboard enters here: first as an input adapter (a pipe syncs its Supabase), later as an output surface.

## Core baseline (inner circle, ships with the system)

**Workflows:** morning brief · per-window daily summaries · todo manager (scans tasks + expectations for deadlines and follow-ups) · meeting setter (proposes times, never books) · query-what-happened.

**Gardeners:**
- **filer** — the write-side keystone: turns each `intake` item into typed L1 calls + links (one note can yield a new person + an expectation-with-follow-up + a task). Low-confidence extractions become proposals, not writes. Built against an eval corpus of 20–30 real labeled examples collected *before* implementation.
- **assembler** — the read-side keystone: executes `get_context` (procedure in `05`): budgeted SQL graph expansion, LLM relevance only at the frontier, synthesis with citations. Its own eval corpus.
- **merge** — person dedup proposals from unmatched handles.
- **wiki** — person/role pages, summaries, backlinks, orphan detection (see `05`).
- **verifier** — independently fact-checks wiki pages against their cited sources, in a fresh context that is never the page's author. Unsourced or contradicted claims become proposals for the user (see `05`, The portrait).
- **catalog sync** — schema ↔ `SCHEMA.md`, always true.
- **tool scout** — watches for better MCP servers/tools, proposes them into `tools`.
- **hygiene** — usage review, promote/demote proposals, token-spend review ("this digest costs X/mo and goes unread").

**Pipes:** per-adapter syncs · the watchdog.

## Reliability (principle 6)

- launchd does the scheduling — never agent memory.
- Every scheduled run writes a `runs` row.
- The **watchdog** is a deterministic pipe: expected runs vs actual runs, alert on any miss. Dead-man's-switch, zero LLM.
- One silently missed morning brief costs more trust than the rest of the system earns.

## Backups (tiered to match data volume)

- **Structured data** (tiny — years of atoms is tens of MB): nightly `pg_dump` + monthly snapshots.
- **Raw archive** (the volume — transcripts, exports, anything stored at tier 0 by claudio itself): content-addressed `archive/` dir, backed up incrementally with restic to encrypted cloud storage; refs point into it so it stays callable.
- **Prose + code** (wiki, memory, repo): git, pushed to a private remote — the cross-link web is just text.
- **Restore test** is a scheduled pipe: load the latest dump into a scratch DB, sanity-query it. A backup never restored is a hope, not a backup.

## Token economy

Workflows declare a model and cost ceiling; runs log tokens; hygiene reviews spend. The system knows what tools to use and what is overkill — cheap models for routine judgment, frontier models only where reasoning earns it.
