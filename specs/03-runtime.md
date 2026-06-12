# 03 — Runtime

What runs, where, when, and what happens when it fails. launchd is the scheduler of record (P6); cron expressions, thresholds, budgets all live in `parameters` — nothing hardcodes a knob. No dispatcher, no router daemon for workflows (P4); the edge is the one fast resident for conversational latency.

## Execution contexts

(Staging note — over-engineering pass: this table is the **P3+ end state**. The operative P1-P2 form is two OS users — `sam` + one worker uid, everything inner-circle, data ≤ c1, mirror elicitation as core sessions — per `04 §Staged hardening`.)

| Context | OS user | What | Why |
|---|---|---|---|
| Core | `sam` (GUI) | build sessions, migrations, secret deploy; reconciler (core-session script until P3, then a sam-session LaunchAgent) | full privilege is a human act |
| **Edge** | `sam` (GUI LaunchAgent; TCC) | the required ground-zero pipe: reads the verified channel, sends replies + pushes; progress indicators for long runs ("on it — checking your calendar…") | TCC reality; deterministic code only, **no LLM in this context** |
| Panel | `claudio-p` | panel server | approver credential isolated |
| **Mirror** | `claudio-w2` | the one taste-modeling agent | clearance 2 (reads the purpose contract); isolated uid |
| Workers, clearance 1 | `claudio-w1` | filer, merge, wiki (+ verifier step), lint, orchestrator | OS user = clearance tier; lint + verifier here because `wiki/` is w1-only |
| Workers, clearance 0 | `claudio-w0` | brief, scanner, windows (gcal, …), meeting setter, catalog, hygiene, approver (P5), watchdog, tripwire (P3+), red-team, backup | |

DB auth: local socket, per-uid `.pgpass` 0600. `run-worker.sh` (core-owned, flock-guarded): resolve component → read its `parameters` → check for work via psql (claim/cursor peek; exit `skipped` if none — never spawn a model on an empty queue) → `start_run` → exec under the worker's DB role + core-owned settings → `finish_run`.

## Triggers

`cron` (launchd) · `queue` (1-min cron + `claim_message`, SKIP LOCKED + claim-time lease reaping; orchestrator at 10s) · `query` (1-min cron + SQL predicate over a cursor in `runs.meta`) · `manual`. Chained automation runs on query triggers reading new atoms — no writer owes fan-out. **Cycle guard**: query triggers exclude `kind='agent_action'` atoms by default (opt-in per component) and derived writes carry `meta.chain_depth` with a hard cap — no A→B→A loops burning spend. Approved external halves arrive as handoffs with expiry (`02`).

## Agent configuration (everything swappable)

Every gardener/workflow judgment step declares in `config`: harness (`claude -p` today — any headless agent runner that can call MCP qualifies), model tier, tool allowlist. Swapping a harness or model is a registry edit + reconcile, not a redesign (P1/P4). The orchestrator slot is likewise configurable: Claude Code, Agent SDK, Codex, a Hermes-like — anything that consumes packets and speaks L1.

## Gardener roster (inner)

| Gardener | Tier | Trigger | Job | Autonomy |
|---|---|---|---|---|
The operative P2 roster is four components: **filer, scanner, watchdog, brief.** Later rows are one-liners whose full autonomy/cadence columns get written at their phase (over-engineering pass: spec organs at the fidelity of their phase, not before).

| Gardener | Tier | Phase | Trigger | Job | Autonomy |
|---|---|---|---|---|---|
| **filer** | w1 | P2 | query (1-min, pending intake + aged holds) | intake → `file_intake`. Write-side keystone, **reliability: critical** (poison rows quarantine individually, `02`). Discriminator: world-obligations file as data; system-addressed imperatives from non-user senders are data + `suspected_injection`. Quotes verbatim (P8). Confidence floor from `parameters`; below it → hold + question (TTL-bounded). Never directives. | file ≥ floor; else hold |
| **merge** | w1 | P3 | daily cron | person dedup; cross-source atom merges | propose (auto only ≥ bar) |
| **wiki** | w1 | P4 | daily cron | grow the biography from new canonical atoms — **delta edits only, full-page rewrites only via proposal**; raw atoms always in context (P8); chapter + read-moment required at creation. The **verifier step** runs chained on the same trigger in a fresh context that is never the author (citations exist AND support claims — the #1 documented AI-wiki defect); it splits into its own component only if scale demands a decoupled cadence | deltas free; judgment claims propose; verifier flags → proposals |
| **catalog** | w0 | P1 | **migration-runner hook** (schema changes only happen via migrations — don't poll for an event the system itself emits; P9 exemplar) | `SCHEMA.md` from live schema/comments, with sample rows | free |
| **hygiene** | w0 | P5 | monthly cron | unused components, stale directives, spend report, promote/demote candidates, wiki demotion sweep (P5+ — pages must age before they can demote), propose tools/windows from usage signals | propose |
| **approver** | w0 | P5 | 1-min queue | applies standing approvals: derived class + validated arg-predicate ⇒ auto-approve. **Critical**, runs-wired — no UI process in the automation chain. Built when S1 creates approval volume; until then approvals are manual (panel + phone, cheap by design) | deterministic |

(The alignment gardener was absorbed into the mirror's observational mode — two contract-watchers was the duplicate-organ pattern the over-engineering pass flagged. Scenario 7's "incessant" contract survives: unresolved mirror questions resurface in the next report and ride the brief.)

**The mirror** (w2, the second licensed taste-owner — taste stays unified in one agent):
- *Elicitation mode* (manual/scheduled sessions with the user): translates the user's "what matters most" document into the purpose contract — goals, values, attributes + goalposts, priorities. Reads the user, knows when to go deeper and when to stop; the user must come away feeling understood. **Every purpose write read-backs verbatim with a diff before commit** (`02` intent binding — session-active alone never authorizes apex writes); candidates derived from `suspected_injection` atoms are barred. (First session runs as a core session at P0, before the w2 context exists.)
- *Observational mode* (monthly cron, P5) — **the alignment surface**: actual usage + `v_purpose_alignment` + drift queries (activity-vs-`advances` distribution, response-decay by role, unlinked activity clusters, low-priority-role crowding) vs the contract → questions (never acts, P7; ≤3 new per report; unresolved re-ask next report and ride the brief — the "incessant" contract), promotes/cuts automations, carries the taste-write provenance review. An empty or stale contract is its first finding. One taste-owner, literally: there is no separate alignment gardener.

## Core workflows (inner)

| Workflow | Phase | Trigger | Pipeline |
|---|---|---|---|
| **morning brief / daily pass** | P2 | cron | SQL packet (incl. hold-questions batch) → one cheap-model step → user queue, **and writes the daily reflection page** (1:1 documents row + links — `05 §Summary ladder`); the same pass assigns/confirms `notable` with the whole prior day + wide context in window. One reflect-organ. **Degraded mode: model fails ⇒ deterministic skeleton still delivers** (P6). |
| **todo & expectation scanner** | P2 | hourly cron | pure SQL: due/overdue, `follow_up_at`, missed expectations → resolutions + reminders. No LLM. **Critical.** |
| **monthly summary** | P4 | monthly cron | long-form record: progress moves, role activity, expectation ledger, purpose drift — fresh from atoms (dailies as orientation only, never source). Biannual log (multi-page era record) follows at P5+. (`05 §Summary ladder`) |
| **meeting setter** | P5 | query | proposes times + drafts; never books, never sends |
| **query-what-happened** | P2 | manual | orchestrator over `what_happened` + packet |

## Reliability (P6)

- **Watchdog** (w0, critical, 15-min): schedule misses, stuck runs (> 2× trailing median), stale messages, expired claims (`reap_expired_claims`). Dead-man cron covers the watchdog itself.
- **The edge sends; nothing else does.** Delivery semantics: resolve only after send-API success; retry with backoff; never silent expiry. External dead-man heartbeat after each successful cycle. (A notification budget arrives at P5 with proactive workflows — until then the only pushes are the brief and exempt alerts/reminders, and there is nothing for a budget to govern; neglect-mode coalescing is the real storm defense.) **DB-unreachable**: the edge appends to a core-owned on-disk spool and replays on reconnect; every window declares `replayable: true|false` and re-scans to its last captured locator on recovery — "capture is durable" holds through a Postgres outage.
- **Neglect mode** (ADHD cascade defense): a silence sensor (no user interaction for N days) coalesces alerts into one daily digest, auto-snoozes alignment, pauses non-critical pushes, and on return delivers a single "while you were gone" rollup with one-tap batch actions. **The system must survive three weeks of total neglect and recover without a cleanup project** — tested by an induced-neglect eval (07). Proposals dedup rather than pile; holds age into unknown atoms rather than accumulate.
- **Failure policy** by `reliability`: standard — retry once, alert, auto-disable after 3 consecutive (never silent); **critical — never auto-disabled**, backoff forever, alert every failure.
- **Queues are 100% reliable by construction**: conditional transitions, SKIP LOCKED claims, leases + reaper, idempotent re-delivery (dedup keys), and a P2 gate that proves each property under induced failure.
- **Reconciler**: a core-session script at P1-P2 (you ran the migration; you run the reconcile); becomes a resident sam-LaunchAgent at P3 when the panel's `set_component_status` needs an automated crossing. Build failures of provisioned components escalate to the user.

## Budget control (downward pressure on spend)

- Model routing is high-level by design: each worker class declares a tier in `config` (`cheap` default; `frontier` only where reasoning earns it — filer extraction quality and the mirror are the two justified frontier spends).
- **One global monthly ceiling** in `parameters`; `runs` records cost; hygiene's spend report (P5) ranks components by cost-per-use and proposes cuts. Per-component ceilings and trend-flagging arrive only if a component's spend ever actually surprises (over-engineering pass: ~6 LLM-touching components owned by one person need one number, not a governance system).

## The injection fence (defense the whole runtime honors)

`suspected_injection` is load-bearing, not decorative: any flagged span — and any `refs` content from a non-user sender — renders into every agent context as **inert foreign text** (the same fencing the panel uses for `quoted`), never as live instruction. A content tripwire re-scans recent atoms/wiki deltas after any incident; kill-switch recovery includes a "quarantine writes since T" rollback built on audit diffs (processes die, but poisoned *data* is what reinfects). Newly approved components' writes are **probationary** (rendered as foreign) for a window or until verifier-cleared.

## Dependency posture

Everything async by default: queues coordinate handoffs; no workflow blocks on another's completion; the only synchronous chains are within a single workflow's own pipeline. User-input dependencies (approvals, held intake) are messages with leases **and TTLs** — they park, they never block, and they age out rather than accumulate. A dependency sweep audit runs at every phase gate (07). Stated honestly: the deepest chain in the system is physical — power event → FileVault unlock → GUI login → edge — so a UPS is required hardware, `fdesetup authrestart` covers planned reboots, and the away-case runbook (dead-man fires while traveling) is documented rather than wished away.
