# 02 — L1 API

The syscall layer: `SECURITY DEFINER` Postgres functions in schema `l1`. Agents hold `EXECUTE` on these plus `SELECT` on granted views — zero direct table writes. Every function: validates args → checks rate counter → writes → audits → returns ids. Errors raise with structured messages (`claudio.*` SQLSTATE classes); callers never need to parse prose.

## Write functions

| Function | Notes |
|---|---|
| `capture(adapter, raw, sender jsonb) → intake_id` | The universal entry. Dumb and instant (P3). |
| `file_intake(intake_id, actions jsonb) → filed_refs` | The filer's atomic apply: a batch of typed sub-actions (`create_person`, `add_handle`, `create_task`, `create_expectation`, `log_entry`, `add_link`, `set_directive`, `resolve_expectation`) validated and executed in ONE transaction; intake row stamped `filed` + `filed_refs`. Partial failure rolls back whole batch. Unknown sub-action → reject. |
| `create_person(name, summary, handles, links, sensitivity) → id` | Raises `claudio.handle_conflict` if any handle already owned (forces match-don't-create). |
| `add_handle(person_id, source, handle, verified)` | |
| `merge_people(keep_id, drop_id)` | Panel/core only; re-points handles + links; archives drop row. Agents use `propose`. |
| `create_task(description, due, person_id, primary_role_id, source_ref, links, sensitivity) → id` | |
| `complete_task(id)` / `drop_task(id, reason)` | |
| `create_expectation(description, person_id, due, follow_up, follow_up_at, primary_role_id, source_ref, links, sensitivity) → id` | |
| `resolve_expectation(id, status, resolved_by)` | `met`/`missed`/`dropped`; missed + `follow_up='auto_task'` ⇒ creates the follow-up task in the same tx. |
| `log_entry(ts, ts_end, kind, summary, detail, refs, primary_role_id, links, sensitivity) → id` | |
| `amend_log(id, patch jsonb)` | Snapshots prior version to audit. |
| `merge_atoms(canonical_id, duplicate_ids[])` | Sets `canonical_of`, accumulates refs+links. Agents at confidence ≥0.9 same-time-same-participants; else propose. |
| `add_link(from, to, kind, origin, confidence, description) → id` | `origin='asserted'` requires panel/core. Inferred over existing asserted = no-op. |
| `remove_link(id)` | Agents: inferred only. |
| `set_directive(statement, scope_type, scope_id, expires_at) → id` | Agent calls allowed only from entry-point context (user dictation); otherwise propose. |
| `retire_role(role_id) → proposal_id` | Never direct: always emits a cascade-preview proposal (components to suspend, adapters to close, open tasks to re-home). Apply on approval. |
| `post_message(queue, kind, payload, requires_approval) → id` | |
| `claim_message(id)` / `read_message(id)` / `resolve_message(id, status, result)` | Claim uses `FOR UPDATE SKIP LOCKED`. |
| `propose(summary, action jsonb, evidence jsonb) → message_id` | Sugar: `post_message('user','proposal',…,true)`. `action.requires_core` marks proposals only a core session may apply. |
| `approve_message(id)` / `reject_message(id, reason)` | **panel/core roles only** (trigger-enforced). |
| `register_component(id, kind, circle, definition_path, trigger, config) → id` | Agent role: `circle='outer'` only (CHECK inside). Inner registration is a core-session act. |
| `start_run(component_id) → run_id` / `finish_run(run_id, outcome, tokens, cost, summary, error)` | Worker wrapper calls these; a run without `finish_run` after 2× expected duration ⇒ watchdog alert. |
| `purge(table_name, row_id, reason)` | **core only.** Hard-deletes row + its links + document refs; logs the purge fact to audit. |

## Read functions / views

| Surface | Notes |
|---|---|
| `get_context(anchor_type, anchor_id, opts) → jsonb` | **The** function. v0 is pure SQL (deterministic, fast, no LLM); the assembler agent later *wraps* it for synthesis-quality packets. Packet shape below. |
| `search_people(q)` | Name + handle + alias search. |
| `what_happened(from_ts, to_ts, filters) → atoms` | Canonical atoms only (merged duplicates excluded). |
| `due_tasks(scope)` / `pending_expectations(scope)` | Scope = role / person / all. |
| `queue_status(actor)` | My mailbox + things I'm waiting on + stale handoffs. |
| Views | `v_stale_expectations`, `v_unfiled_intake`, `v_run_misses` (watchdog source), `v_open_proposals`, `v_orphan_documents`, `v_component_health` (last run, outcome, cost trend). |

All reads pass through RLS — a worker's packet physically cannot contain rows above its clearance.

## The context packet

```jsonc
{
  "anchor":      { "type": "role", "id": "prod", "summary": "...", "doc": "wiki/roles/prod.md" },
  "taste":       { "directives": [...in scope...], "goals": [...linked, active...] },
  "obligations": { "tasks_due": [...], "expectations_pending": [...], "time_sensitive": [...] },
  "state":       { "recent_atoms": [...last N, canonical...], "rollups": ["wiki/roles/prod.md", ...] },
  "capabilities":{ "workflows": [...scoped_to anchor...], "tools": [...] },
  "people":      [...members, by recency...],          // when anchor is a role
  "budget":      { "requested": 4000, "spent_estimate": 2810 }
}
```

Rules: every item carries `id` + `source_ref` (citable, drillable). Items ordered by recency × due-ness. `opts.budget_tokens` truncates sections by fixed priority: taste → obligations → state → people → capabilities (taste is never truncated — P5). Rollup *paths* are returned, not contents; the consumer reads files it wants (keeps the packet small and the choice with the consumer).

## MCP front door

One thin MCP server (`claudio-mcp`, inner circle) exposing exactly the L1 surface as tools — no extra logic, no caching, no state. Tool descriptions are generated from the Postgres `COMMENT ON` for each function (decay test: docs cannot drift from reality). Connects as the per-consumer worker role (clearance applies). Local stdio for on-mini harnesses; never network-exposed in v0.

## Rate limits

Inside every L1 write: bump `rate_counters(actor, minute_window)`; raise `claudio.rate_limited` beyond per-role ceilings (default 60 writes/min, 600 reads/min via view wrapper; per-component override in `config`). Bounds hijacked-worker blast radius deterministically (`04-security.md`).
