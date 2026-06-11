# 06 — Surfaces

Edges of the system. One contract: **messiness dies at the mouth** — adapters own 100% of translation; inward they speak only L1. This is core product function #1 (ingest everything) and the outbound half of function #3.

## Adapter contract

Every adapter is a component (`kind='adapter'`) implementing:

- **`sync()`** (pipe, cron): pull tier-0 deltas → `capture()` (or direct `log_entry` for unambiguous structured sources — ended gcal events). Idempotent by construction: `intake (adapter, locator)` and `log` locator uniqueness make re-runs no-ops; `flock` prevents overlap.
- **Window closing**: chat-like adapters close atom windows (thread-day by default) and emit one `capture` per closed window. The filer writes the atom. (No separate summarizer workflow — one owner for atomization.)
- **Role mapping** (`config.role_map`): the inheritance default — prod-slack ⇒ `prod`; school email ⇒ `student`; iMessage ⇒ candidate set. The window is a *dependent type narrowing the candidate set* before the filer judges.
- **Source semantics** (`config.semantics`): per-source trust/meaning. gcal: `commitment_strength: tentative` — Sam plans in gcal; ended events log with `meta.tentative=true` unless corroborated by another source or confirmed. Chat: `atom_window: thread-day`.
- **Source-side metrics**: deterministic per-message stats during sync (unanswered counts, reply lag by thread/role) upserted into `metrics`. Granular analytics; no per-message atoms. Powers dashboards and the alignment gardener.
- **Sensitivity default** for captures, capped at 1 (the filer's clearance); restricted-class captures route to the panel.

v0 adapters: **iMessage** (the edge, below), **gcal**. Then: gmail, slack, transcripts, notion, old dashboard (input stream first, output surface later), substack, local note folders, location.

## The edge (iMessage, primary entry + only sender)

One long-running deterministic pipe in Sam's GUI session (TCC: Full Disk Access, Automation). No LLM in this context, ever.

**Inbound (capture-first):**
1. Every new message → `capture()` immediately — durable before anything else (P3/P6: an API outage can delay a reply, never lose a text).
2. Sender verification: handle on the command allowlist **and** `service='iMessage'` (SMS is spoofable ⇒ data, never commands).
3. Verified-Sam messages → post to the orchestrator's queue with the `intake_id` (the dictation artifact). The Sam↔claudio thread is exempt from thread-day atomization.
4. Everyone else's messages → normal intake for the filer.

**Outbound:** the only send path. Reads the user queue: conversational replies (fast poll), proactive pushes (budget ≤ 5/day, directive-tunable; reminders/alerts/time-sensitive questions exempt — never suppressed). Resolves a message only after the send API succeeds; retries with backoff; heartbeats to the external dead-man after each successful cycle. Destinations are constants in core-owned code.

**Orchestrator** (w1, queue-triggered ~10s): stock harness via `claude -p --resume <session(thread,day)>`, handed the packet + message. Tools: L1 MCP (agent + user sets, dictation-gated) + read-only connectors. No send tools, no open network. Replies and proposals go out through the edge. High-risk actions → proposal + panel link, never executed from chat.

## Panel (the permanent surface)

The one non-disposable UI; the approval gate's home. v0 scope — plain, fast, boring:

- **Approvals**: open proposals, server-derived privilege class, evidence, `quoted` rendered as foreign text. Approve applies synchronously; standing-approval classes shown with a revoke control. The panel **server** (not the UI) polls open proposals on a short interval and auto-approves those whose derived class matches an active `approval_class` directive — that is the standing-approval actor.
- **Registry**: components, status, last run, cost trend; enable/disable (`set_component_status`).
- **People**: list/edit/merge (edits set `verified_fields`).
- **Intake**: held items + the filer's questions; answer applies via `resolve_held_intake`.
- **Runs & queues**: feed, failures, stale handoffs, watchdog state.
- **Wiki**: rendered browse.

Stack: minimal Next.js, runs as `claudio-p`, binds 127.0.0.1 with a bearer token (kept in Sam's keychain, entered once per browser session) + Host-header check — **localhost is not authentication**; a hijacked worker must not be able to curl an approval. Tailscale later only if remote need is proven. Every panel write goes through L1.

## Custom dashboards (disposable surfaces)

Provisioned via the pipeline (propose → approve → built → **deployed by core**, workers never write code paths) → registered with its own DB role: `SELECT` on named views plus `propose`/`post_message` and nothing else. Tiles read `metrics` + views (expectations leaderboard, ignored-messages trend, urgent-replies queue); any write action is a proposal. Regenerable from the catalog; deleting one costs nothing.
