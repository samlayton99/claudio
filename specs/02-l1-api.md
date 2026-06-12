# 02 — L1 API

**The context is the API.** L1 is the syscall layer: `SECURITY DEFINER` Postgres functions in schema `l1`, search_path-pinned. Consumers hold `EXECUTE` on their function set plus `SELECT` on `security_invoker` views — zero direct table writes. Every function: validate (args + jsonb schemas) → rate ceiling → sensitivity clamp → write → audit (`session_user`) → return. Structured `claudio.*` error states.

**Internal vs external writes — the trust boundary in one sentence:** L1 writes touch only the scaffold (internal); **external writes** (email sends, calendar posts, anything leaving for the world) are never claudio's — they belong to the owning agent/workflow, fire only after approval, via handoff (`03`). Claudio is the brain and the approval surface; external agents are the hands.

## Function sets (the grants matrix)

| Set | Granted to | Functions |
|---|---|---|
| **agent** | `claudio_agent` (NOLOGIN base; all `w_*` inherit) | `capture`, `file_intake`, `hold_intake`, `discard_intake`, `create_person`, `add_handle`, `update_person` (rejects `verified_fields`), `create_task`, `complete_task`, `drop_task`, `amend_task`, `create_expectation`, `resolve_expectation`, `record_atom`, `amend_atom`, `add_link` (inferred), `invalidate_link` (inferred), `register_page`, `move_page`, `upsert_metric` (P5, with the metrics table), `post_message`, `claim_message`, `read_message`, `resolve_message`, `propose`, `start_run`, `finish_run`, all reads |
| **user** (dictation-gated + intent-bound) | mirror, panel (orchestrator: stages only, via confirm flow) | `set_directive`, `retire_directive`, `add_link`/`invalidate_link` (asserted), `upsert_purpose`, `new_purpose_version`, `upsert_role`, `update_person` (may touch `verified_fields`), `retire_role`, `resolve_held_intake` |
| **edge confirm** | `w_edge` only | `confirm_taste_write(pending_id, confirming_intake_id)` — commits a staged taste write after verifying the confirming message; deterministic code, no LLM in the commit path. Also: dictation-gated `approve_message` for **low-risk classes only** (never core, write-capable registrations, or taste) — the edge renders the server-generated what-will-execute text; reply approves. Phone-native approvals keep the proposal economy alive (ux-rings cascade A) |
| **panel** | `claudio_panel`, `claudio_core` (panel also holds agent + user sets) | `approve_message`, `reject_message`, `apply_actions`, `merge_people`, `merge_atoms`, `set_component_status` |
| **core** | `claudio_core` only | `register_component` (both circles; registration is a core-deploy act), `purge`, migrations/DDL, `role_clearances` + core `parameters` writes |
| narrow extras | single roles | `merge_atoms` → `w_merge` (auto-bar enforced server-side); `reap_expired_claims` → `w_watchdog` |

**Dictation gate — two bindings, both required for taste.** The gate proves *channel* (verified user handle, verified service, ≤ 10 min — a recency token) — but a channel proof is not an intent proof: a hijacked agent holding any fresh "ok thanks" must not be able to bless attacker text as law (red-team finding 1). So **taste-class writes** (`set_directive`, `upsert_purpose`, `new_purpose_version`, `update_person` touching `verified_fields`, asserted links) additionally require an **intent binding**, one of:
- **verbatim**: the load-bearing payload appears verbatim in the cited `intake.raw` (the user literally said it), or
- **read-back-confirm**: the edge (deterministic, no LLM) renders the *exact* proposed text back to the verified channel; a fresh confirming user message commits it via the edge's narrow `confirm_taste_write(pending_id, confirming_intake_id)` grant. The LLM that drafted the write is not in the commit path.

The panel satisfies both bindings by role (its writes are physically the user's). The mirror's session-active status satisfies channel only — **every purpose write read-backs with a diff against the prior version before commit**. Consequently the orchestrator holds **no direct taste-write grants**: it *stages* taste via the confirm flow. Chat and panel hold equal clearance; **panel wins conflicts** — panel writes are user-asserted, the ultimate taste.

**Taste-class isolation** (red-team findings 2, 7): taste/identity functions are **non-bundlable** (solo proposals only, never inside a batch) and **non-standing-approvable**; `merge_people` is identity-class — never standing-approvable. The fn→privilege-class map and all standing-approval arg-predicates live in the **core ring** of `parameters`, immutable to panel and proposals. `propose()` validates at propose time that every action lies within the **proposer's own** function set — an agent cannot stage above its privilege for the panel to execute.

**Naming rule** (P1/decay): function and table names ARE the vocabulary — `record_atom` not `log_entry`, `atoms` not `log`. Every `COMMENT ON FUNCTION` carries 2–3 example invocations including an edge case; `SCHEMA.md` carries sample rows. Names favor descriptive over short.

## The batch shape

`[{"fn": "<L1 name>", "args": {...}}, ...]` with `{"$ref": i}` for intra-batch ids. Used by `file_intake`, `propose(actions)`, `apply_actions`. Sub-actions run the same functions with the same guards — atomicity, never privilege. Caps from `parameters` (default ≤20 sub-actions, ≤100 rows).

## Write functions (selected semantics)

| Function | Notes |
|---|---|
| `capture(adapter, raw, sender, locator, raw_ref)` | Dumb, instant, durable. Dedup on `(adapter, locator)`. |
| `file_intake(intake_id, actions)` | Conditional open (`status='pending'` → `filed`); atomic batch; rollback restores pending. **Quote-at-write**: load-bearing facts (commitments, dates, amounts, names) go into `atoms.quotes` verbatim (P8). No taste-class sub-actions. **Poison-pill quarantine**: a row whose filing errors is individually quarantined (`held`/`discarded`, error recorded, run outcome `degraded`) — head-of-queue poison costs one row, never the filer. |
| `hold_intake(id, question_message_id)` / `discard_intake(id, reason)` | Conditional transitions. `resolve_held_intake(id, answer)` records the answer and flips `held` → `pending`. **Hold TTL** (parameter): unanswered holds age out by auto-filing as `kind='unknown'`, low-confidence, `meta.unresolved_hold=true` — visible and correctable, never parked forever; a later answer re-files via supersedence. Hold questions ride the morning brief as a one-tap batch. |
| `record_atom(ts, ts_end, kind, summary, detail, quotes, refs, primary_role_id, links, sensitivity, meta)` | The atom writer (was `log_entry`). |
| `amend_atom(id, patch)` | Prior version snapshotted to audit; agents cannot lower sensitivity. |
| `create_person(...)` | `claudio.handle_conflict` if any handle is owned — match, don't create. |
| `merge_people(keep, drop)` | Panel-set. Locks in id order; handle collisions resolve to keep; rejects self/archived/re-merge. |
| `merge_atoms(canonical, dups[])` | Target canonical; dups not targets; no cycles. Agent path only at the auto-bar (parameter). |
| `invalidate_link(id, superseded_by?)` | Supersedence, not deletion: sets `invalidated_at`; history stays queryable (research-traversal §3.6). Asserted links: user-set only. |
| `upsert_purpose(...)` / `new_purpose_version(body)` | **User-set only.** The contract changes through the user, period. (`new_purpose_version` writes the *priorities document* — versioned prose.) Reads are open to every agent: the system is mission-aligned by design (purpose plane is sensitivity 0). |
| `retire_role(role_id) → proposal_id` | Cascade-preview proposal (suspend scoped components, close windows, re-home open tasks). **Never touches wiki pages or atoms** — active-roles is a filter, not an eraser. |
| `register_page(path, kind, title, chapter, entity, read_moment)` / `move_page(old, new)` | Page creation demands its chapter and its read-moment (anti-accretion, `05`); move rewrites inbound links atomically (wiki-tool). |
| `propose(summary, actions, evidence, quoted)` | `privilege_class` derived server-side **per action**; propose-time check: every `fn` ∈ proposer's own set. Sensitivity = max of cited rows. **Regeneration dedup**: key `(from_actor, privilege_class, content_hash)` suppresses re-proposal while a matching pending/recently-expired proposal exists — user absence never produces a duplicate pile. |
| `approve_message(id)` | Panel-set (+ edge for low-risk classes). Approval binds to the **server-rendered "what will execute" view**, never the agent summary: every action with `$ref`s resolved to concrete `{id, name}`, in-batch creations shown with field values, names NFKC-normalized with confusable-script flags, privilege class per action. L1 actions apply synchronously in-transaction. External halves: approval posts a `handoff` (with `expires_at`, per-class parameter — a stale approval must not fire weeks later; expiry requires re-proposal) to the owning workflow's queue. **Standing approvals are a P5 feature** (built with `w_approver` when S1 creates approval volume; until then all approvals are manual — panel + phone, cheap by design). The laws bind now, before the machinery exists: a class gates on `fn` **plus a validated arg-predicate including external-handoff args** (`gcal_solo_block` ⇒ `attendees == [] and no_external_links`); fn-class alone never auto-approves; core- and taste-class never auto-approve; the map is core-ring. |
| `set_component_status(id, status)` | Panel-set; registry is truth; reconciler converges plists. |
| `purge(table, row_id, reason)` | Core-only; fact audited; backups age out ≤ retention. |

**The re-ground rule (P8, enforced in workflow contracts):** before any irreversible or external action, the acting workflow re-reads tier-0 via `refs` — never acts from a summary alone.

## Read surface

Ergonomics (research-validated, trimmed to what's evidenced): **no bare UUIDs in any response** — always `{id, name}` pairs; every item renders its event timestamp and age inline (temporal reasoning is memory systems' measured weak spot); token-cap defaults on every read. Responses ship concise-only — the two-phase protocol (packet → drill-down) *is* the detailed path; a `detailed` format and pagination get built when an agent measurably loops because concise lacks a field, not before.

| Surface | Notes |
|---|---|
| `get_context(anchor_type, anchor_id, opts)` | Anchors: `role · person · purpose · component`. Pure SQL v0 (no LLM at query time — production-validated). Two-phase protocol: packet first, then agentic drill-down (views, wiki grep/read, `refs`) — packet link expansion caps at 1 hop; agents iterate for hop 2+ ("start wide, then narrow"). |
| `fetch_ref(ref)` | **One-call pointer dereference** — hand it any `{source, locator, tool}` ref and get the tier-0 content back (routed via the named tool). Pulling things in must be dead simple: no thinking, no multi-step execution, one call. Atom records are the compact tier-1 rows; this is the standard way any agent reaches the raw beneath them. |
| `search_people(q)` | Names + handles + aliases. Misses logged (the embeddings promotion trigger). |
| `what_happened(from, to, filters)` | Canonical atoms only; misses logged. |
| `due_tasks(scope)` / `pending_expectations(scope)` | `blocks` annotations included. |
| `queue_status(actor)` | Own queue; `user` queue: edge + panel. `claim_message` reaps expired leases at claim time (race-safe via conditional transition); the watchdog reaper is the backstop, not the latency ceiling. |
| Views (`security_invoker`) | `v_unfiled_intake`, `v_open_proposals`, `v_run_misses`, `v_component_health` (incl. role mapping + usage — the audit page's source), `v_stale_expectations`, `v_source_metrics`, `v_purpose_alignment`. |

## The context packet

```jsonc
{
  "anchor":      { "type": "role", "id": "prod", "name": "PROD", "summary": "...", "page": "wiki/professional/prod.md" },
  "taste":       { "directives": [...], "purpose": [...via advances: goals/values in scope...] },
  "obligations": { "tasks_due": [...], "expectations_pending": [...], "time_sensitive": [...] },
  "state":       { "recent_atoms": [...], "daily_digest": "wiki/digests/2026-06-11.md", "rollups": [paths] },
  "capabilities":{ "workflows": [...], "tools": [...] },
  "people":      [...],
  "budget":      { "requested": 3000, "spent_estimate": 2410 }
}
```

- Every item: `{id, name}`, event timestamp + age inline, `source_ref`.
- **Scoring runs in two lanes** (the fix for the dueness bug Sam caught: an important task assigned long ago and due *now* must score at the top — a single product with a recency factor would drag it down).
  - **Obligations lane** (tasks, expectations, time-sensitive items): `score = (role_weight · importance)^β · urgency^γ` where `urgency` *rises* as the due moment approaches. Recency of creation is irrelevant to an obligation — only importance and imminence matter.
  - **Context lane** (atoms, background state): `score = (role_weight · importance)^β · recency_decay^α` — fresh and important context wins; old context fades unless important.
  - Both Cobb-Douglas with **floors** (a raw product zeroes old-but-critical items; floored, it's a weighted sum in log space — the intuitive utility form and the research safety property at once). Exponents are the tweakable elasticities, unspecced until real packets tune them. Importance is **structural** (`01 §Atoms`): notable + obligations + links + user assertions, multiplied by the user-set `roles.weight`. Volume is never an input.
- Default budget ~3k tokens (measured optimum band 2–4k; context rot beyond). Truncation order: capabilities → people → state → obligations; **taste never truncates**. Rollup paths, not contents (progressive disclosure). Budget is the one dial — there is no separate verbosity knob; drill-down covers depth.

## MCP front door

`claudio-mcp` (inner): exposes exactly the caller's function set; tool descriptions generated from `COMMENT ON` (with the example calls — docs cannot drift). Connects as the consumer's role over the local socket. No extra logic, no cache, no network exposure.
