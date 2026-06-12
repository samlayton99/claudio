# 06 — Surfaces

Edges of the system. One contract: **messiness dies at the mouth** — adapters own 100% of translation; inward they speak only L1.

## Windows (first-class: data in, role-assigned)

Every window is a component (`kind='window'`) implementing:

- **`sync()`** (pipe, cron): tier-0 deltas → `capture()` (or direct `record_atom` for unambiguous structured sources). Idempotent by constraint (locator uniqueness), flock-guarded.
- **Window closing**: chat-like windows close atom windows (thread-day default) and emit one capture per closed window; the filer writes the atom.
- **`role_map`**: the inheritance default (`01` §Inheritance) — the window is a dependent type narrowing the candidate set. Every window may map to `general`.
- **`semantics`**: per-source trust/meaning (gcal `commitment_strength: tentative` — planner-as-draft; ended events log `meta.tentative` unless corroborated/confirmed). v0 gcal rides a **read-only ICS URL** (zero OAuth ceremony — ux-rings Ring-0 cut); the OAuth connector arrives only when write-back does.
- **`replayable: true|false`**: declared per window; replayable sources re-scan to the last captured locator after any outage.
- **Source-side `metrics`** (P5, with the metrics table): deterministic per-message stats (unanswered counts, reply lag by thread/role) — granular analytics, no atom explosion; feeds dashboards and the mirror. Intake/atoms are durable, so P5 backfills history by query.
- **Sensitivity default**, capped at 1.

v0: iMessage (the edge), gcal. Then: gmail, slack, transcripts, notion, old dashboard (input stream first, output surface later), substack, local note folders, location, claude-code-activity. **Hygiene proposes new windows (and tools) from usage signals** — the more windows, the better the system; the user approves, the handshake law applies.

## The edge (the required ground-zero channel)

One **required**, claudio-owned, deterministic pipe with ground-zero permissions, owned by no external vendor — the user's direct line. The concrete channel is configurable (iMessage v0; email/Telegram/chat variants later); the *slot* is mandatory and the dictation gate binds to whichever verified channel fills it. Outsourcing this to an external assistant (Poke-class) is explicitly rejected: the entry point is simultaneously the untrusted-intake boundary and the proof-of-user — third parties can consume claudio context, never be the mouth.

**Inbound (capture-first):** every message → `capture()` durably *before anything else* → sender verification (allowlisted handle + verified service; SMS = data, never commands) → verified-user messages post to the orchestrator queue with the `intake_id` (the dictation artifact); everyone else's → filer intake.

**Outbound:** the only sender. Conversational replies (fast poll) + proactive pushes (a budget arrives at P5 with proactive workflows; reminders/alerts/time-sensitive questions are always exempt). Resolves only on send-API success; retries; external dead-man heartbeat; on-disk spool when the DB is unreachable. **Progress indicators**: long orchestrator runs surface "working on it" states so latency never reads as silence.

**Two deterministic user-action flows live here** (no LLM in either commit path): the **taste-confirm flow** — staged taste writes render verbatim ("Set directive: '…' — reply YES"), a fresh confirming message commits via `confirm_taste_write` — and **phone approvals** for low-risk proposal classes, rendering the server-generated what-will-execute text, reply-to-approve bound to the message id. Together with hold-questions riding the brief, the phone covers the entire daily decision surface; the panel is for depth, never a daily requirement (ux-rings cascade A).

**Orchestrator** (w1, queue ~10s): a configurable stock harness handed the packet + message. Tools: L1 MCP (agent set; taste is *staged* via the confirm flow — no direct taste-write grants, red-team finding 1) + read-only fixed-endpoint connectors. No send tools. High-risk actions → proposal + panel link. Chat holds clearance equal to the panel; panel wins conflicts.

## Panel (the permanent surface — ultimate authority)

The human window into the system; inputs here are the highest-authority taste. **Every panel write is tagged user-asserted and overrides anything** — a wiki edit from the panel is a permanent artifact (immutable span); a person edit sets `verified_fields`; a parameter change is law. v1 is core functionality (plain, fast, searchable); design iterates later via Claude Design (DesignSync).

Phased scope (over-engineering pass: seven surfaces in a v1 is how panels miss their phase). **P3 ships what the P3 gate exercises**: Approvals + Registry/audit + Intake + Parameters. **P4 adds** Wiki browse. People/Runs detail views grow as needed. Chat is cut — the edge is chat; core sessions are the research surface; a panel chat returns only if phone chat proves too thin in practice.

- **Approvals**: the server-rendered **what-will-execute view** (`02`: per-action classes, `$ref`s resolved to `{id,name}`, in-batch creations with field values, confusable-name flags) — the agent summary is decoration; `quoted`/evidence as visibly-foreign text; standing-approval classes with revoke controls (P5, applied by `w_approver` — the panel is pure surface).
- **Registry / audit page**: every agent, automation, workflow, window — what the system defines their role as, their scopes, their usage in practice (`v_component_health`), cost; enable/disable.
- **People / Intake / Runs & queues / Parameters** (outer ring editable; core ring visible, core-session editable).
- **Wiki** (P4): rendered browse with loud freshness + one-tap "this is wrong" per page (`05`).

Stack: minimal Next.js, `claudio-p`, 127.0.0.1 + bearer token + Host check (localhost is not auth). **Tailscale ships at P3** — approvals become load-bearing there, and a desk-bound approval surface starves the proposal economy.

## Handshake (onboarding external agents — the decay test for outsiders)

The law, binding now: **capability is issued, never declared** — a newcomer reads the public catalog slice, declares requested scopes, and can touch nothing until the user approves and claudio creates its role; write-capable registrations are flagged loudly; registration is always a core act. The protocol's full ceremony (overlap reports, trial conditions) is designed at **P6**, when the first real external agent shows what review actually needs — pinning and probation (`04` rule 7) carry the security load meanwhile.

## Custom dashboards (disposable surfaces)

(P6.) Provisioned via the pipeline; own DB role (`SELECT` on named views + `propose`/`post_message` only). Tiles read `metrics` + views; **a dashboard may own derived metrics** — tracking a metric that doesn't exist yet is just `upsert_metric` rows under its component id (granted narrowly). Any write action is a proposal. Regenerable; deleting one costs nothing.
