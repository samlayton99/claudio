# 02 — L1 API

**The context is the API.** L1 is the syscall layer: `SECURITY DEFINER` Postgres functions in schema `l1`, search_path-pinned. Consumers hold `EXECUTE` on their function set plus `SELECT` on `security_invoker` views — zero direct table writes. Every function: validate (args + jsonb schemas) → rate ceiling → sensitivity clamp → write → audit (`session_user`) → return. Structured `claudio.*` error states.

**Internal vs external writes — the trust boundary in one sentence:** L1 writes touch only the scaffold (internal); **external writes** (email sends, calendar posts, anything leaving for the world) are never claudio's — they belong to the owning agent/workflow, fire only after approval, via handoff (`03`). Claudio is the brain and the approval surface; external agents are the hands.

## Function sets (the grants matrix)

| Set | Granted to | Functions |
|---|---|---|
| **agent** | `claudio_agent` (NOLOGIN base; all `w_*` inherit) | `capture`, `file_intake`, `hold_intake`, `discard_intake`, `create_person`, `add_handle`, `update_person` (rejects `verified_fields`), `create_task`, `complete_task`, `drop_task`, `amend_task`, `create_expectation`, `resolve_expectation`, `record_atom`, `amend_atom`, `add_link` (inferred), `invalidate_link` (inferred), `register_page`, `move_page`, `upsert_metric`, `post_message`, `claim_message`, `read_message`, `resolve_message`, `propose`, `start_run`, `finish_run`, all reads |
| **user** (dictation-gated) | orchestrator, mirror, panel | `set_directive`, `retire_directive`, `add_link`/`invalidate_link` (asserted), `upsert_purpose`, `new_purpose_version`, `upsert_role`, `update_person` (may touch `verified_fields`), `retire_role`, `resolve_held_intake` |
| **panel** | `claudio_panel`, `claudio_core` (panel also holds agent + user sets) | `approve_message`, `reject_message`, `apply_actions`, `merge_people`, `merge_atoms`, `set_component_status` |
| **core** | `claudio_core` only | `register_component` (both circles; registration is a core-deploy act), `purge`, migrations/DDL, `role_clearances` + core `parameters` writes |
| narrow extras | single roles | `merge_atoms` → `w_merge` (auto-bar enforced server-side); `reap_expired_claims` → `w_watchdog` |

**Dictation gate**: user-set functions take `dictation_intake_id`; the function verifies the sender is a verified user handle on the verified channel, received ≤ 10 min ago (parameter). Panel satisfies by role; the mirror satisfies during an elicitation session the user is actively in. Text from anyone else can never become law. Chat and panel hold equal clearance; **panel wins conflicts** — its writes are tagged user-asserted and are the ultimate taste.

**Naming rule** (P1/decay): function and table names ARE the vocabulary — `record_atom` not `log_entry`, `atoms` not `log`. Every `COMMENT ON FUNCTION` carries 2–3 example invocations including an edge case; `SCHEMA.md` carries sample rows. Names favor descriptive over short.

## The batch shape

`[{"fn": "<L1 name>", "args": {...}}, ...]` with `{"$ref": i}` for intra-batch ids. Used by `file_intake`, `propose(actions)`, `apply_actions`. Sub-actions run the same functions with the same guards — atomicity, never privilege. Caps from `parameters` (default ≤20 sub-actions, ≤100 rows).

## Write functions (selected semantics)

| Function | Notes |
|---|---|
| `capture(adapter, raw, sender, locator, raw_ref)` | Dumb, instant, durable. Dedup on `(adapter, locator)`. |
| `file_intake(intake_id, actions)` | Conditional open (`status='pending'` → `filed`); atomic batch; rollback restores pending. **Quote-at-write**: load-bearing facts (commitments, dates, amounts, names) go into `atoms.quotes` verbatim (P8). `set_directive` is not a legal sub-action. |
| `hold_intake(id, question_message_id)` / `discard_intake(id, reason)` | Conditional transitions. `resolve_held_intake(id, answer)` records the answer and flips `held` → `pending`. |
| `record_atom(ts, ts_end, kind, summary, detail, quotes, refs, primary_role_id, links, sensitivity, meta)` | The atom writer (was `log_entry`). |
| `amend_atom(id, patch)` | Prior version snapshotted to audit; agents cannot lower sensitivity. |
| `create_person(...)` | `claudio.handle_conflict` if any handle is owned — match, don't create. |
| `merge_people(keep, drop)` | Panel-set. Locks in id order; handle collisions resolve to keep; rejects self/archived/re-merge. |
| `merge_atoms(canonical, dups[])` | Target canonical; dups not targets; no cycles. Agent path only at the auto-bar (parameter). |
| `invalidate_link(id, superseded_by?)` | Supersedence, not deletion: sets `invalidated_at`; history stays queryable (research-traversal §3.6). Asserted links: user-set only. |
| `upsert_purpose(...)` / `new_purpose_version(body)` | **User-set only.** The contract changes through the user, period. |
| `retire_role(role_id) → proposal_id` | Cascade-preview proposal (suspend scoped components, close windows, re-home open tasks). **Never touches wiki pages or atoms** — active-roles is a filter, not an eraser. |
| `register_page(path, kind, title, chapter, entity, read_moment)` / `move_page(old, new)` | Page creation demands its chapter and its read-moment (anti-accretion, `05`); move rewrites inbound links atomically (wiki-tool). |
| `propose(summary, actions, evidence, quoted)` | `privilege_class` + `requires_approval` derived server-side from `actions[].fn`; proposer's opinion ignored. Sensitivity = max of cited rows. |
| `approve_message(id)` | Panel-set; applies L1 actions synchronously in-transaction. External halves: approval posts a `handoff` to the proposing workflow's queue — the owning agent performs the external write through its own tools. Standing approvals auto-approve matching derived classes (panel server polls; revocable). Core-class never auto-approves. |
| `set_component_status(id, status)` | Panel-set; registry is truth; reconciler converges plists. |
| `purge(table, row_id, reason)` | Core-only; fact audited; backups age out ≤ retention. |

**The re-ground rule (P8, enforced in workflow contracts):** before any irreversible or external action, the acting workflow re-reads tier-0 via `refs` — never acts from a summary alone.

## Read surface

Ergonomics (research-validated): every read takes `response_format: concise|detailed` (concise ≈ ⅓ tokens) + pagination with token-cap defaults from `parameters`; **no bare UUIDs in any response** — always `{id, name}` pairs; every item renders its event timestamp and age inline (temporal reasoning is memory systems' measured weak spot).

| Surface | Notes |
|---|---|
| `get_context(anchor_type, anchor_id, opts)` | Anchors: `role · person · purpose · component`. Pure SQL v0 (no LLM at query time — production-validated). Two-phase protocol: packet first, then agentic drill-down (views, wiki grep/read, `refs`) — packet link expansion caps at 1 hop; agents iterate for hop 2+ ("start wide, then narrow"). |
| `search_people(q)` | Names + handles + aliases. Misses logged (the embeddings promotion trigger). |
| `what_happened(from, to, filters)` | Canonical atoms only; misses logged. |
| `due_tasks(scope)` / `pending_expectations(scope)` | `blocks` annotations included. |
| `queue_status(actor)` | Own queue; `user` queue: edge + panel. |
| Views (`security_invoker`) | `v_unfiled_intake`, `v_open_proposals`, `v_run_misses`, `v_component_health` (incl. role mapping + usage — the audit page's source), `v_stale_expectations`, `v_source_metrics`, `v_purpose_alignment`. |

## The context packet

```jsonc
{
  "anchor":      { "type": "role", "id": "prod", "name": "PROD", "summary": "...", "page": "wiki/professional/prod.md" },
  "taste":       { "directives": [...], "purpose": [...via advances: goals/values in scope...] },
  "obligations": { "tasks_due": [...], "expectations_pending": [...], "time_sensitive": [...] },
  "state":       { "recent_atoms": [...], "pulse": "wiki/digests/2026-06-11.md", "rollups": [paths] },
  "capabilities":{ "workflows": [...], "tools": [...] },
  "people":      [...],
  "budget":      { "requested": 3000, "spent_estimate": 2410 }
}
```

- Every item: `{id, name}`, event timestamp + age inline, `source_ref`.
- **Scoring is a weighted sum, not a product**: `score = w_r·exp_decay(recency) + w_d·dueness + w_i·importance` (weights in `parameters`) — a product zeroes old-but-critical items (Generative Agents).
- Default budget ~3k tokens (measured optimum band 2–4k; context rot beyond). Truncation order: capabilities → people → state → obligations; **taste never truncates**. Rollup paths, not contents (progressive disclosure).
- `opts.verbosity: skeleton|standard|verbose`; clearance already enforces need-to-know.

## MCP front door

`claudio-mcp` (inner): exposes exactly the caller's function set; tool descriptions generated from `COMMENT ON` (with the example calls — docs cannot drift). Connects as the consumer's role over the local socket. No extra logic, no cache, no network exposure.
