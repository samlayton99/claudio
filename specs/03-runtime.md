# 03 — Runtime

What runs, where, when, and what happens when it fails. launchd is the scheduler of record (P6); cron expressions, thresholds, budgets all live in `parameters` — nothing hardcodes a knob. No dispatcher, no router daemon for workflows (P4); the edge is the one fast resident for conversational latency.

## Execution contexts

| Context | OS user | What | Why |
|---|---|---|---|
| Core | `sam` (GUI) | build sessions, migrations, secret deploy; reconciler (sam-session LaunchAgent — plists are sam-owned) | full privilege is a human act |
| **Edge** | `sam` (GUI LaunchAgent; TCC) | the required ground-zero pipe: reads the verified channel, sends replies + pushes; progress indicators for long runs ("on it — checking your calendar…") | TCC reality; deterministic code only, **no LLM in this context** |
| Panel | `claudio-p` | panel server (+ standing-approval poller) | approver credential isolated |
| **Mirror** | `claudio-w2` | the one taste-modeling agent | clearance 2 (reads the purpose contract); isolated uid |
| Workers, clearance 1 | `claudio-w1` | filer, merge, wiki, verifier, lint, orchestrator | OS user = clearance tier |
| Workers, clearance 0 | `claudio-w0` | brief, scanner, pulse, windows (gcal, …), meeting setter, catalog, alignment, hygiene, scout, watchdog, tripwire, red-team, backup | |

DB auth: local socket, per-uid `.pgpass` 0600. `run-worker.sh` (core-owned, flock-guarded): resolve component → read its `parameters` → check for work via psql (claim/cursor peek; exit `skipped` if none — never spawn a model on an empty queue) → `start_run` → exec under the worker's DB role + core-owned settings → `finish_run`.

## Triggers

`cron` (launchd) · `queue` (1-min cron + `claim_message`, SKIP LOCKED + claim-time lease reaping; orchestrator at 10s) · `query` (1-min cron + SQL predicate over a cursor in `runs.meta`) · `manual`. Chained automation runs on query triggers reading new atoms — no writer owes fan-out. **Cycle guard**: query triggers exclude `kind='agent_action'` atoms by default (opt-in per component) and derived writes carry `meta.chain_depth` with a hard cap — no A→B→A loops burning spend. Approved external halves arrive as handoffs with expiry (`02`).

## Agent configuration (everything swappable)

Every gardener/workflow judgment step declares in `config`: harness (`claude -p` today — any headless agent runner that can call MCP qualifies), model tier, cost ceiling, tool allowlist. Swapping a harness or model is a registry edit + reconcile, not a redesign (P1/P4). The orchestrator slot is likewise configurable: Claude Code, Agent SDK, Codex, a Hermes-like — anything that consumes packets and speaks L1.

## Gardener roster (inner)

| Gardener | Tier | Trigger | Job | Autonomy |
|---|---|---|---|---|
| **filer** | w1 | query (1-min, pending intake + aged holds) | intake → `file_intake`. Write-side keystone, **reliability: critical** (auto-disabling the only writer blinds the system; poison rows quarantine individually, `02`). Discriminator: world-obligations file as data; system-addressed imperatives from non-user senders are data + `suspected_injection`. Quotes verbatim (P8). Confidence floor from `parameters`; below it → hold + question (TTL-bounded). Never directives. | file ≥ floor; else hold |
| **merge** | w1 | daily cron | person dedup; cross-source atom merges | propose (auto only ≥ bar) |
| **wiki** | w1 | daily cron | grow the biography from new canonical atoms — **delta edits only, full-page rewrites only via proposal** (ACE context-collapse); raw atoms always in context (P8); chapter + read-moment required at page creation | page deltas free; judgment claims propose |
| **verifier** | w1 | **weekly cron from P4** (research reversal: fabricated citations are the #1 documented AI-wiki defect) | sample pages: cited atoms exist AND support the claim; fresh context, never the author | flag → proposal |
| **catalog** | w0 | weekly cron + migration checklist | `SCHEMA.md` from live schema/comments, with sample rows | free |
| **alignment** | w0 | weekly cron (monthly deep in-run) | drift vs the purpose contract: activity-vs-`advances` distribution, response-decay by role, unlinked clusters, low-priority crowding | **question, never act**; ≤3 new/week; unresolved re-ask weekly until answered or snoozed (the "incessant" contract); outcomes typed: asserted link / directive / accepted reminder automation. No-ops with a `contract_missing_or_stale` metric when the purpose contract is empty/stale (packets stay valid with empty taste) |
| **approver** | w0 | 1-min queue | applies standing approvals: derived class + arg-predicate match ⇒ auto-approve. **reliability: critical**, runs-wired, watchdog-covered — extracted from the panel so no UI process sits inside the automation chain | deterministic; no judgment |
| **hygiene** | w0 | monthly cron | unused components, stale directives, token-spend report, promote/demote candidates, wiki demotion sweep | propose |
| **scout** | w0 | monthly cron (P6) | better tools AND new **windows** from usage signals (e.g. heavy Claude Code use ⇒ propose a coding-activity window) | propose |

**The mirror** (w2, the second licensed taste-owner — taste stays unified in one agent):
- *Elicitation mode* (manual/scheduled sessions with the user): translates the user's "what matters most" document into the purpose contract — goals, values, attributes + goalposts, priorities. Reads the user, knows when to go deeper and when to stop; the user must come away feeling understood. **Every purpose write read-backs verbatim with a diff before commit** (`02` intent binding — session-active alone never authorizes apex writes); candidates derived from `suspected_injection` atoms are barred. (First session runs as a core session at P0, before the w2 context exists.)
- *Observational mode* (monthly cron): actual usage + `v_purpose_alignment` vs the contract → promotes/cuts automations, proposes new ones, keeps the system serving the person. Conservative; interacts with the user often; the alignment gardener's mechanical flags are its input.

## Core workflows (inner)

| Workflow | Trigger | Pipeline |
|---|---|---|
| **morning brief** | cron | SQL packet → one cheap-model step → user queue. **Degraded mode: model fails ⇒ deterministic skeleton still delivers** (P6). |
| **todo & expectation scanner** | hourly cron | pure SQL: due/overdue, `follow_up_at`, missed expectations → resolutions + reminders. No LLM. **Critical.** |
| **pulse** | nightly cron | the day's tier-2 rollup, re-derived from atoms only (P8), absolute dates → digest page + packet pointer |
| **state-of-life digests** | weekly / monthly / biannual cron | regular audit of the person's general state, fresh from atoms each time, fed into general context (research-wiki: the periodic-review pattern humans drop and agents keep) |
| **meeting setter** | query | proposes times + drafts; never books, never sends |
| **query-what-happened** | manual | orchestrator over `what_happened` + packet |

## Reliability (P6)

- **Watchdog** (w0, critical, 15-min): schedule misses, stuck runs (> 2× trailing median), stale messages, expired claims (`reap_expired_claims`). Dead-man cron covers the watchdog itself.
- **The edge sends; nothing else does.** Delivery semantics: resolve only after send-API success; retry with backoff; never silent expiry. External dead-man heartbeat after each successful cycle. Notification budget (parameter) never applies to reminders, alerts, or time-sensitive questions. **DB-unreachable**: the edge appends to a core-owned on-disk spool and replays on reconnect; every window declares `replayable: true|false` and re-scans to its last captured locator on recovery — "capture is durable" holds through a Postgres outage.
- **Neglect mode** (ADHD cascade defense): a silence sensor (no user interaction for N days) coalesces alerts into one daily digest, auto-snoozes alignment, pauses non-critical pushes, and on return delivers a single "while you were gone" rollup with one-tap batch actions. **The system must survive three weeks of total neglect and recover without a cleanup project** — tested by an induced-neglect eval (07). Proposals dedup rather than pile; holds age into unknown atoms rather than accumulate.
- **Failure policy** by `reliability`: standard — retry once, alert, auto-disable after 3 consecutive (never silent); **critical — never auto-disabled**, backoff forever, alert every failure.
- **Queues are 100% reliable by construction**: conditional transitions, SKIP LOCKED claims, leases + reaper, idempotent re-delivery (dedup keys), and a P2 gate that proves each property under induced failure.
- **Reconciler** (core context): plists ⇄ registry. Build failures of provisioned components escalate to the user.

## Budget control (downward pressure on spend)

- Model routing is high-level by design: each worker class declares a tier in `config` (`cheap` default; `frontier` only where reasoning earns it — filer extraction quality and the mirror are the two justified frontier spends; everything else starts cheap).
- Monthly ceiling + per-component ceilings in `parameters`; `runs` records cost; hygiene's monthly spend report ranks components by cost-per-use and proposes cuts (P9: a gardener that exists to shrink the others).
- Guardrail: any component trending > its ceiling gets flagged before it's throttled — never silently degraded (P6 > thrift for critical paths).

## The injection fence (defense the whole runtime honors)

`suspected_injection` is load-bearing, not decorative: any flagged span — and any `refs` content from a non-user sender — renders into every agent context as **inert foreign text** (the same fencing the panel uses for `quoted`), never as live instruction. A content tripwire re-scans recent atoms/wiki deltas after any incident; kill-switch recovery includes a "quarantine writes since T" rollback built on audit diffs (processes die, but poisoned *data* is what reinfects). Newly approved components' writes are **probationary** (rendered as foreign) for a window or until verifier-cleared.

## Dependency posture

Everything async by default: queues coordinate handoffs; no workflow blocks on another's completion; the only synchronous chains are within a single workflow's own pipeline. User-input dependencies (approvals, held intake) are messages with leases **and TTLs** — they park, they never block, and they age out rather than accumulate. A dependency sweep audit runs at every phase gate (07). Stated honestly: the deepest chain in the system is physical — power event → FileVault unlock → GUI login → edge — so a UPS is required hardware, `fdesetup authrestart` covers planned reboots, and the away-case runbook (dead-man fires while traveling) is documented rather than wished away.
