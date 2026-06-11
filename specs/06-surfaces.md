# 06 — Surfaces

Edges of the system. One contract: **messiness dies at the mouth** — adapters own 100% of translation; inward they speak only L1.

## Adapter contract

Every adapter is a component (`kind='adapter'`) implementing:

- **`sync()`** (pipes, cron): pull tier-0 deltas → `capture()` rows (or direct `log_entry` for unambiguous structured sources like ended gcal events). Idempotent: re-running never duplicates (dedup on source locator).
- **Role mapping** (`config.role_map`): the inheritance default — prod-slack ⇒ `prod`; school email ⇒ `student`; iMessage ⇒ multiple candidates. Sam's framing is law: the window acts as a *dependent type narrowing the candidate set* before the filer judges.
- **Source semantics** (`config.semantics`): per-source trust/meaning knobs. Examples: gcal `commitment_strength: tentative` (Sam uses gcal as a draft/planner — ended events log with `meta.tentative=true` unless corroborated by another source or confirmed); chat `atom_window: thread-day`.
- **Source-side metrics** (`config.metrics`): deterministic per-message stats computed during sync — unanswered counts, response lag by thread/role — written to `runs.meta` / a metrics view. Powers dashboards (ignored-messages tiles, expectation leaderboards) without per-message atoms.
- **Sensitivity default** for captured rows.

v0 adapters: **iMessage** (chat.db reader — exists as MCP; wrapped), **gcal**. Phase 2+: gmail, slack, transcripts (recording pin), notion, old dashboard (its Supabase becomes an input stream; later an output surface), substack, local folders (Sam's notes-watcher example), location (his maps example).

## Entry point (iMessage, primary)

The one fast-poll long-running pipe.

1. New message → sender handle vs **command allowlist** (Sam's verified handles, core-owned constant).
2. Allowlisted → command path: invoke orchestrator = `claude -p --resume <session(thread, day)>` with the message + `get_context` packet; reply via notifier. Session continuity: one session per thread per day (resume), so conversation holds context without unbounded growth.
3. Not allowlisted → `capture()` as data. **Never commands.** (Texts from others are intake, not instructions.)
4. High-risk commands (anything `requires_core`, purges, approvals) → never executed from chat; orchestrator replies with a panel link + pending proposal. Optional passphrase gate later.

The orchestrator slot runs a stock harness (P4); its tool surface: L1 MCP + read-only connector tools. **No send tools** — its outbound is `propose` / notifier-mediated reply to Sam only.

## Panel (the permanent surface)

The one non-disposable UI. v0 scope — plain, fast, boring:

- **Approvals**: open proposals with evidence; `quoted` content rendered visibly as foreign text (taint). Approve/reject. This is the hardware interrupt — it must stay legible.
- **Registry**: components, status, last run, cost trend; enable/disable.
- **People**: list/edit/merge (asserted edits set `verified_fields`).
- **Runs & queues**: feed, failures, stale handoffs.
- **Intake**: held items with the filer's question.
- **Wiki**: rendered browse of `wiki/` with backlinks.

Stack: minimal Next.js (Sam's stack), localhost-only, connects as `claudio_panel`. No public exposure; Tailscale later if remote need is proven. Every panel write goes through L1 like everyone else.

## Custom dashboards (disposable surfaces)

Provisioned via the pipeline (propose → approve → coding agent builds in `custom/` → registered): each gets its own DB role (SELECT on named views only), renders read-only tiles (expectations leaderboard, ignored-messages trend, urgent-replies queue — Sam's examples), and any write action posts L1 calls/proposals. Regenerable from the catalog; deleting one costs nothing.
