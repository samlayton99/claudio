# 06 — Surfaces

Edges of the system. One contract: **messiness dies at the mouth** — adapters own 100% of translation; inward they speak only L1.

## Windows (first-class: data in, role-assigned)

Every window is a component (`kind='window'`) implementing:

- **`sync()`** (pipe, cron): tier-0 deltas → `capture()` (or direct `record_atom` for unambiguous structured sources). Idempotent by constraint (locator uniqueness), flock-guarded.
- **Window closing**: chat-like windows close atom windows (thread-day default) and emit one capture per closed window; the filer writes the atom.
- **`role_map`**: the inheritance default (`01` §Inheritance) — the window is a dependent type narrowing the candidate set. Every window may map to `general`.
- **`semantics`**: per-source trust/meaning (gcal `commitment_strength: tentative` — planner-as-draft; ended events log `meta.tentative` unless corroborated/confirmed).
- **Source-side `metrics`**: deterministic per-message stats (unanswered counts, reply lag by thread/role) — granular analytics, no atom explosion; feeds dashboards and alignment.
- **Sensitivity default**, capped at 1.

v0: iMessage (the edge), gcal. Then: gmail, slack, transcripts, notion, old dashboard (input stream first, output surface later), substack, local note folders, location, claude-code-activity. **The scout proposes new windows from usage signals** — the more windows, the better the system, so window suggestions are a standing hygiene output (user approves; handshake applies).

## The edge (the required ground-zero channel)

One **required**, claudio-owned, deterministic pipe with ground-zero permissions, owned by no external vendor — the user's direct line. The concrete channel is configurable (iMessage v0; email/Telegram/chat variants later); the *slot* is mandatory and the dictation gate binds to whichever verified channel fills it. Outsourcing this to an external assistant (Poke-class) is explicitly rejected: the entry point is simultaneously the untrusted-intake boundary and the proof-of-user — third parties can consume claudio context, never be the mouth.

**Inbound (capture-first):** every message → `capture()` durably *before anything else* → sender verification (allowlisted handle + verified service; SMS = data, never commands) → verified-user messages post to the orchestrator queue with the `intake_id` (the dictation artifact); everyone else's → filer intake.

**Outbound:** the only sender. Conversational replies (fast poll) + proactive pushes (budget parameter; reminders/alerts/time-sensitive questions exempt). Resolves only on send-API success; retries; external dead-man heartbeat. **Progress indicators**: long orchestrator runs surface "working on it" states so latency never reads as silence (internal latency is fine; perceived deadness is not).

**Orchestrator** (w1, queue ~10s): a configurable stock harness handed the packet + message. Tools: L1 MCP (agent + user sets, dictation-gated) + read-only connectors. No send tools. High-risk actions → proposal + panel link. Chat holds clearance equal to the panel; panel wins conflicts.

## Panel (the permanent surface — ultimate authority)

The human window into the system; inputs here are the highest-authority taste. **Every panel write is tagged user-asserted and overrides anything** — a wiki edit from the panel is a permanent artifact (immutable span); a person edit sets `verified_fields`; a parameter change is law. v1 is core functionality (plain, fast, searchable); design iterates later via Claude Design (DesignSync).

- **Approvals**: open proposals, derived privilege class, evidence, `quoted` as visibly-foreign text; standing-approval classes with revoke controls; the panel server polls and auto-approves matching classes.
- **Chat**: a full chat interface to the orchestrator — ask questions, run custom research over atoms/wiki/runs, drive the system. Same dictation authority as the verified channel.
- **Registry / audit page**: every agent, automation, workflow, window — what the system defines their role as, their scopes, their usage in practice (`v_component_health`), cost trends; enable/disable.
- **People / Intake / Runs & queues / Parameters** (outer ring editable; core ring visible, core-session editable).
- **Wiki**: rendered browse with loud freshness + one-tap "this is wrong" per page (`05`).

Stack: minimal Next.js, `claudio-p`, 127.0.0.1 + bearer token + Host check (localhost is not auth). Tailscale later if proven needed.

## Handshake (onboarding external agents — the decay test for outsiders)

A protocol, not a resident agent: (1) the newcomer reads the public catalog slice (SCHEMA.md, component registry, chapter index); (2) declares what it wants — purpose, requested scopes (read clearance, function sets, tools), triggers/windows it would attach to; (3) claudio generates the registration proposal: scope summary, **write-capable flagged loudly**, overlap report against existing components (redundancy tags where it overlaps something — MECE by default, tagged redundancy where reliability wants it); (4) the user approves; (5) capability is **issued** — role created, grants applied, registry row written, observable from its first run. Until step 5 the agent can touch nothing; there is nothing to probe and nothing it could hide. Sandboxed trial runs (no-network, scratch DB) available as an approval condition for anything write-capable.

## Custom dashboards (disposable surfaces)

Provisioned via the pipeline; own DB role (`SELECT` on named views + `propose`/`post_message` only). Tiles read `metrics` + views; **a dashboard may own derived metrics** — tracking a metric that doesn't exist yet is just `upsert_metric` rows under its component id (granted narrowly). Any write action is a proposal. Regenerable; deleting one costs nothing.
