# 03 — Runtime

What runs, where, when, and what happens when it fails. Everything runs on the Mac mini. launchd is the scheduler of record (P6) — never agent memory, never the app layer.

## Execution model

| Thing | Runs as | Trigger |
|---|---|---|
| Pipes (sync, watchdog, lint, notifier, applier, backup) | plain scripts (Python/TS), launchd | cron intervals |
| Gardeners & workflow judgment steps | `claude -p` headless, per-worker settings file (tool allowlist, model), wrapped by `run-worker.sh` | launchd cron or dispatcher |
| Orchestrator (conversational) | `claude -p --resume <thread-session>` invoked by entry adapter | inbound user message |
| Human core sessions (building claudio) | Claude Code / Cowork interactive | manual |
| Panel | local web app, launchd-kept-alive | always on |

`run-worker.sh` (inner, core-owned): resolves worker config from `components` → `start_run` → exec worker with its DB role + settings → `finish_run`. A worker cannot start untracked.

Long-running processes are exactly **two**: the entry-adapter poller (fast chat.db poll for conversational latency) and the panel. Everything else is cron. (Event dispatch v0 = 1-minute cron poll of `messages`; a LISTEN/NOTIFY dispatcher is a v1 upgrade only if 60s latency ever hurts.)

Billing note (volatile — re-verify): `claude -p` meters API credits. Workers default to cheap models (Haiku-class) with cost ceilings; if metering hurts, hot workers migrate to Cowork scheduled tasks (subscription bucket). Tracked in `runs.cost_usd`; hygiene reviews spend monthly.

## Component lifecycle

Defined in git (`core/` or `custom/`) → registered in `components` → scheduled by a generated launchd plist (core-owned; a worker cannot edit its own) → every execution writes a `runs` row → observable in panel. Disable = `status='disabled'` + plist unload (the applier pipe reconciles plists to the registry — registry is source of truth).

## Triggers

- `cron`: launchd interval.
- `event`: a `messages` row matching `trigger.filter` (e.g. `{"kind":"handoff","queue":"meeting-scanner"}`) — claimed via `claim_message` (SKIP LOCKED; double-fire impossible).
- `manual`: user request via entry point or panel.

Chained automation (Sam's example: scheduled-meeting atom → gcal event + day-before expectation) = the filer posts a `handoff` to the workflow's queue when it writes a matching atom. Workflows subscribe to typed writes **via messages**, never via database triggers calling out (no logic hiding in the DB beyond validation/audit).

## Gardener roster (inner circle)

| Gardener | Cadence | Job | Autonomy |
|---|---|---|---|
| **filer** | event (intake) + 15-min sweep | intake → `file_intake` batch. Write-side keystone. | Free: file at confidence ≥ 0.8. Else: `held` + question to user. Creates people only on explicit-evidence; never lowers sensitivity below adapter/role default. Untrusted text is data — never instructions (04). |
| **merge** | daily | person-dedup candidates (shared names, co-occurring handles); cross-source atom merges | Propose. Auto-merge atoms only ≥0.9 + identical time/participants. |
| **wiki** | daily | grow the portrait from new atoms; maintain MOCs, backlinks, freshness; place published artifacts | Free for page edits (git-versioned, revertible); propose for judgment claims (05-wiki). |
| **verifier** | weekly | re-check pages against cited sources; fresh context, never the author | Flag → proposal. |
| **catalog** | on migration + weekly | regenerate `SCHEMA.md` from live schema/comments; drift = alert | Free. |
| **alignment** | weekly (+ monthly deep) | drift detection: activity-vs-goals distribution; response-decay by role ("leaving research texts on read"); unlinked activity clusters ("the topology notes"); low-priority-role crowding | **Question, never act** (P7). Outcomes are typed: user answer becomes a new link/directive, or an accepted reminder automation. Max 3 questions/week. |
| **hygiene** | monthly | unused components, token spend review, stale directives, promote/demote candidates | Propose. |
| **tool scout** | monthly (phase 3+) | better MCP servers/tools → proposals | Propose. |

The **assembler** (read-side keystone) is deferred: `get_context` v0 is pure SQL. The agentic assembler arrives when synthesis quality demands it, *wrapping* the same function (consumers don't change).

## Core workflows (inner)

| Workflow | Trigger | Pipeline |
|---|---|---|
| **morning brief** | cron 7:00 | SQL packet (calendar via gcal MCP, due tasks, pending expectations, intake highlights) → judgment step (one cheap-model call: prioritize + voice) → notifier. **Degraded mode (P6): if the model step fails, send the deterministic SQL skeleton.** Delivery never depends on an LLM. |
| **todo & expectation scanner** | cron hourly | pure SQL: due/overdue tasks, `follow_up_at` arrivals, missed expectations → `resolve_expectation`/notifications per policy. No LLM. **Critical reliability tier.** |
| **daily window summaries** | cron per adapter config | per-source day digest → atom(s) + optional notification |
| **meeting setter** | event (handoff) | proposes times from gcal free/busy; drafts reply; **never books, never sends** — proposal to user |
| **query-what-happened** | manual | orchestrator answers from `what_happened` + packet |

## Reliability machinery (P6)

- **Watchdog** (pipe, critical): every 15 min compare `components.trigger` schedules vs `runs` → any miss or unfinished run ⇒ alert via notifier. The watchdog itself is monitored by a launchd KeepAlive + a dead-man cron that alerts if the watchdog hasn't run in 1h (who watches the watchman: launchd does).
- **Notifier** (pipe, critical): the **only send-capable component**. Reads `messages` where `queue='user'` and policy says push (alerts, time-sensitive proposals, briefs). Destination hardwired to Sam's verified handles — constant in core-owned code, not config. Notification budget: max N proactive pushes/day (default 5, directive-tunable) **except** reliability alerts and reminder-class messages, which are never suppressed (P6 > P3).
- **Applier** (pipe): executes approved proposals' `action` via L1 (agent-applicable ones); `requires_core` proposals wait for a human core session. Reconciles launchd plists to the registry.
- **Failure policy**: a failing component retries once, then `status` stays enabled but alert fires; 3 consecutive failures ⇒ auto-disable + alert (never silent, never infinite retry). Build failures of provisioned components escalate to the user — hand-wiring is the documented fallback.

## Queues in practice

`messages` is the only coordination fabric. Patterns: filer → workflow handoffs; gardener → user proposals/questions; watchdog → user alerts; workflow → workflow chains. Diagnostics: `queue_status()` + panel feed. Stale `posted` > 24h (non-user queues) ⇒ watchdog alert. Queues coordinate **handoffs, never control flow** — a workflow's internal steps are its own pipeline (P4 guardrail).
