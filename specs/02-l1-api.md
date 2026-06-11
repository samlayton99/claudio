# 02 — L1 API

**The context is the API.** L1 is the syscall layer: `SECURITY DEFINER` Postgres functions in schema `l1`, every one pinned `SET search_path = pg_catalog, l1`. Consumers hold `EXECUTE` on their function set plus `SELECT` on `security_invoker` views — zero direct table writes, reads always under their own RLS clearance. Every function: validate args → enforce write-rate ceiling (trailing-minute audit count) → clamp sensitivity floor → write → audit (`session_user`) → return ids. Errors raise structured `claudio.*` states; no prose parsing.

## Function sets (privilege groups — the grants matrix)

| Set | Granted to | Functions |
|---|---|---|
| **agent** | `claudio_agent` (NOLOGIN base; every `w_*` role inherits) | `capture`, `file_intake`, `hold_intake`, `discard_intake`, `create_person`, `add_handle`, `update_person` (rejects `verified_fields`), `create_task`, `complete_task`, `drop_task`, `amend_task`, `create_expectation`, `resolve_expectation`, `log_entry`, `amend_log`, `add_link` (inferred), `remove_link` (inferred), `register_page`, `move_page`, `upsert_metric`, `post_message`, `claim_message`, `read_message`, `resolve_message`, `propose`, `start_run`, `finish_run`, all reads |
| **user** (dictation-gated) | orchestrator + panel | `set_directive`, `retire_directive`, `add_link`/`remove_link` (asserted), `upsert_goal`, `upsert_role`, `update_person` (may touch `verified_fields`), `retire_role`, `resolve_held_intake` |
| **panel** | `claudio_panel`, `claudio_core` (panel also holds the agent + user sets — approve-time apply runs under its own grants) | `approve_message`, `reject_message`, `apply_actions`, `merge_people`, `merge_atoms`, `set_component_status` |
| **core** | `claudio_core` only | `register_component` (both circles — registration is always a core-deploy act), `purge`, migrations/DDL, `role_clearances` writes |
| narrow extras | single roles | `merge_atoms` additionally to `w_merge` (auto-merge bar ≥0.9 + identical time/participants enforced server-side); `reap_expired_claims` to `w_watchdog` only (exempt from queue scoping, lease-age-guarded) |

The **dictation gate**: user-set functions take `dictation_intake_id`; the function verifies the intake row's sender is a verified user handle, `service='iMessage'`, received ≤ 10 min ago. The panel satisfies the gate by role instead. Text from anyone else can never become law (P5).

## The batch shape

One canonical encoding everywhere: `[{"fn": "<L1 name>", "args": {...}}, ...]`, with `{"$ref": i}` referring to the id returned by sub-action *i* (e.g. a `log_entry` citing the `create_person` above it). Used by `file_intake`, `propose(actions)`, `apply_actions`. Sub-actions execute the **same functions with the same guards** as standalone calls — the batch adds atomicity, never privilege. Caps: ≤ 20 sub-actions, ≤ 100 rows per batch (component-overridable downward).

## Write functions (selected semantics)

| Function | Notes |
|---|---|
| `capture(adapter, raw, sender, locator, raw_ref) → intake_id` | Dumb, instant, durable (P3). Dedup on `(adapter, locator)`. |
| `file_intake(intake_id, actions) → filed_refs` | Opens with `UPDATE intake SET status='filed' WHERE id=$1 AND status='pending'`; zero rows ⇒ abort (concurrent filer loses cleanly). Batch executes atomically; partial failure rolls back everything including the status flip. **`set_directive` is not a legal sub-action** — directives only pass the dictation gate. |
| `hold_intake(intake_id, question_message_id)` / `discard_intake(intake_id, reason)` | Same conditional-transition guard. `resolve_held_intake(intake_id, answer)` records the user's answer **and flips `held` → `pending`**, so the row re-enters the filer's next sweep with the answer attached. |
| `create_person(...)` | Raises `claudio.handle_conflict` if any handle is owned (match, don't create). |
| `merge_people(keep, drop)` | Panel-set. Locks both rows in id order; on `(source,handle)` collision the keep side wins and the duplicate row is dropped; rejects self-merge, archived `keep`, or re-merging a prior target. |
| `merge_atoms(canonical, duplicates[])` | Target must be canonical (`canonical_of IS NULL`); duplicates must not be merge targets; no self/cycles. Agents may call only at the auto-merge bar (≥0.9, identical time+participants); else propose. |
| `log_entry(ts, ts_end, kind, summary, detail, refs, primary_role_id, links, sensitivity, meta) → id` | `meta` exposed (gcal `tentative`, `suspected_injection`, …). Same for `create_task` / `create_expectation`. |
| `amend_log(id, patch)` | Prior version snapshotted to audit; agents cannot lower sensitivity or edit rows above their clearance. |
| `resolve_expectation(id, status, resolved_by)` | `missed` + `follow_up='auto_task'` creates the follow-up task in the same tx. |
| `update_person(id, patch, dictation_intake_id?)` | Agent calls reject any field listed in `verified_fields`; user-set calls may touch them and extend the list. |
| `retire_role(role_id) → proposal_id` | Always a cascade-preview proposal (suspend scoped components, close adapters, re-home open tasks) carried as a batch-shape `actions` array; applied by `apply_actions` on approval. |
| `register_page(path, kind, title, entity_type, entity_id)` / `move_page(old, new)` | The `documents` registration half of wiki writes; the file half is the core-owned `wiki-tool` (05). `move_page` rewrites inbound wikilinks atomically (tool-mediated). |
| `propose(summary, actions, evidence, quoted) → message_id` | `privilege_class` and `requires_approval` are **derived server-side** from `actions[].fn` against a fixed classification — the proposer's opinion of its own danger is ignored. Sensitivity floor = max of cited rows. |
| `approve_message(id)` | Panel-set. Applies the proposal's L1 `actions` **synchronously in the same transaction** under the panel role — no second trust domain, immediate feedback. **External (non-L1) halves** — e.g. the gcal write itself — are not applied here: approval posts a `handoff` back to the proposing workflow's queue, whose own pipeline step performs the connector write under its own tools. Standing approvals: if the derived `privilege_class` matches an active `approval_class` directive, the panel server auto-approves (deterministic, revocable, P5 — mechanism in `06`). Core-class actions never auto-approve and only a core session may apply them. |
| `set_component_status(id, status)` | Panel-set. The registry is the source of truth; the reconciler pipe converges launchd plists to it. |
| `purge(table, row_id, reason)` | Core-only. Hard-deletes row + edges + document anchors; the purge *fact* is audited; backups age out ≤ 90 days. |

## Read surface

| Surface | Notes |
|---|---|
| `get_context(anchor_type, anchor_id, opts) → jsonb` | Anchors: `role · person · goal · component`. v0 is pure SQL (deterministic, no LLM); the agentic assembler later wraps the same signature. |
| `search_people(q)` | Names + handles + aliases (`source='alias'`). |
| `what_happened(from, to, filters)` | Canonical atoms only. |
| `due_tasks(scope)` / `pending_expectations(scope)` | `blocks` links surface here: a task blocked by a pending expectation is annotated, not hidden. |
| `queue_status(actor)` | Own queue only; `user` queue readable by edge + panel. |
| Views (all `security_invoker`) | `v_unfiled_intake` (includes held-with-resolved-question), `v_open_proposals`, `v_run_misses`, `v_component_health`, `v_stale_expectations`, `v_source_metrics`. |

## The context packet

```jsonc
{
  "anchor":      { "type": "role", "id": "prod", "summary": "...", "page": "wiki/roles/prod.md" },
  "taste":       { "directives": [...in scope...], "goals": [...via advances links...] },
  "obligations": { "tasks_due": [...], "expectations_pending": [...], "time_sensitive": [...] },
  "state":       { "recent_atoms": [...canonical...], "rollups": ["wiki/roles/prod.md", ...] },
  "capabilities":{ "workflows": [...scoped_to anchor...], "tools": [...] },
  "people":      [...members by recency...],
  "budget":      { "requested": 4000, "spent_estimate": 2810 }
}
```

Every item carries `id` + `source_ref` (citable, drillable). Truncation priority under `opts.budget_tokens`: capabilities → people → state → obligations; **taste is never truncated** (P5). Component anchors pull workflow-scoped directives — the morning brief reads its own law. Rollup *paths* returned, not contents.

## MCP front door

`claudio-mcp` (inner): exposes exactly the caller's L1 function set as tools, descriptions generated from `COMMENT ON` (docs cannot drift — decay test). Connects as the consumer's worker role over the local socket; clearance and grants apply identically. No extra logic, no cache, no network exposure.
