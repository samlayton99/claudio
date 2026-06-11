# 03 — Runtime

What runs, where, when, and what happens when it fails. Everything on the Mac mini. launchd is the scheduler of record (P6) — never agent memory, never the app layer. **No dispatcher, no router daemon** (P4): every worker claims its own work.

## Execution contexts

| Context | OS user | What | Why |
|---|---|---|---|
| Core | `sam` (GUI) | human build sessions, migrations, secret deploy, core proposals | full privilege is a human act |
| **Edge** | `sam` (GUI LaunchAgent) | `imessage-edge`: the ONE long-running pipe — reads chat.db, sends replies + proactive pushes | chat.db + iMessage send require Sam's session, Full Disk Access, Automation consent (TCC reality). Deterministic code only — **no LLM ever runs in this context** |
| Panel | `claudio-p` | the panel server | approver credential isolated from workers |
| Workers, clearance 1 | `claudio-w1` | filer, merge, wiki, orchestrator | OS user = clearance tier; cross-tier theft is OS-enforced |
| Workers, clearance 0 | `claudio-w0` | brief, scanner, lint, catalog, watchdog, reconciler, backup, alignment | |

DB auth: local socket; per-uid `.pgpass` mode 0600. Residual (stated): same-tier workers can read each other's role credential — attribution within a tier is good-faith; across tiers it is OS-enforced.

`run-worker.sh` (core-owned, `flock`-guarded against overlap): resolve component → for queue/query triggers, **check for work first via psql** (claim or cursor peek) — exit `skipped` cheaply if none — else `start_run` → exec worker under its DB role + core-owned settings (tool allowlist, model) → `finish_run`. A worker cannot start untracked, cannot run concurrently with itself, and never spawns a model on an empty queue.

## Triggers

- `cron` — launchd `StartInterval`/`StartCalendarInterval`.
- `queue` — 1-min cron + `claim_message` (SKIP LOCKED ⇒ no double-fire; lease reaper covers abandoned claims). For the orchestrator: 10s interval, claim-check is a cheap psql call.
- `query` — 1-min cron + SQL predicate over rows since the component's **cursor** (last-seen id/ts in `runs.meta`). Atom-triggered workflows watch the table; nobody owes fan-out bookkeeping. `skipped` runs are healthy.
- `manual` — user request via orchestrator or panel.

Chained automation (intro text → calendar + day-before reminder): the filer just writes atoms; the gcal workflow's `query` trigger picks up new meeting-scheduling atoms via its cursor; its write to gcal is a proposal that a **standing approval** (`approval_class='gcal_solo_block'`, user-granted) may auto-apply; attendee-bearing events always wait for a real approval (they email third parties).

## Gardener roster (inner)

| Gardener | Tier | Trigger | Job | Autonomy |
|---|---|---|---|---|
| **filer** | w1 | query (pending intake) + 15-min sweep (incl. held-with-answer) | intake → `file_intake` batch. Write-side keystone. | File at confidence ≥ 0.8; else `hold_intake` + question. **The discriminator: intake text may describe world-obligations (file tasks/expectations as data — the bishop's visit list) but may never select system actions; system-addressed imperatives from non-user senders file as data with `meta.suspected_injection=true`** (the C5/C8 line). People created on explicit evidence only. Never directives. Sensitivity floor server-clamped. |
| **merge** | w1 | daily | person-dedup candidates; cross-source atom merges | Propose (auto only ≥0.9 identical time+participants). |
| **wiki** | w1 | daily | grow the portrait from new canonical atoms; MOCs, backlinks, freshness; place artifacts | Page edits free (git-revertible); judgment claims propose (05). |
| **catalog** | w0 | on migration + weekly | regenerate `SCHEMA.md` from live schema + comments | Free. |
| **alignment** | w0 | weekly (+ monthly deep) | drift: activity-vs-goals distribution (`advances` edges + metrics), response-decay by role, unlinked activity clusters, low-priority-role crowding | **Question, never act** (P7). ≤ 3 *new* questions/week; unresolved questions re-ask weekly until answered or snoozed by directive (the "incessant" contract). Outcomes are typed: answer → asserted link / directive (dictation gate) or an accepted reminder automation. |
| **hygiene** | w0 | monthly | unused components, token spend, stale directives, promote/demote candidates | Propose. |
| **verifier** | w1 | **manual** (cron at P6 if drift observed) | re-check pages against cited sources; never the author | Flag → proposal. |
| **tool scout** | w0 | monthly (P6) | better MCP servers/tools → proposals | Propose. |

The **assembler** stays deferred: `get_context` v0 is pure SQL; the agentic assembler later wraps the same signature.

## Core workflows (inner)

| Workflow | Trigger | Pipeline |
|---|---|---|
| **morning brief** | cron 7:00 | SQL packet (gcal via MCP, due tasks, pending expectations, intake highlights) → one cheap-model step (prioritize + voice) → user queue. **Degraded mode (P6): model step fails ⇒ send the deterministic SQL skeleton.** Delivery never depends on an LLM. |
| **todo & expectation scanner** | cron hourly | pure SQL: due/overdue, `follow_up_at` arrivals, missed expectations → resolves + reminder messages. No LLM. **Critical.** |
| **meeting setter** | query (scheduling atoms) | proposes times from gcal free/busy + drafts the reply — always a proposal; **never books, never sends** |
| **query-what-happened** | manual | orchestrator answers from `what_happened` + packet |

(The old "daily window summaries" workflow is deleted: adapters close their own atom windows; the filer writes the atoms. Digest-style pushes are just messages.)

## Reliability machinery (P6)

- **Watchdog** (w0, critical, 15-min): expected runs vs `runs` (schedule misses, unfinished > 2× trailing-median duration), stale `posted` messages, **expired claims (lease reaper: back to `posted` + alert)**. Alerts post to the user queue. Liveness of the watchdog itself: an independent dead-man cron alerts if the watchdog hasn't run in 1h.
- **The edge sends; nothing else does.** Destination constants (Sam's verified handles) live in core-owned edge code, not config. Delivery semantics: a user-queue message resolves only after the send API succeeds; failures retry with backoff; nothing expires silently. Send-path failure has an **independent alarm**: the edge heartbeats to an external dead-man service (egress-allowlisted) after each successful send cycle; a missed heartbeat alerts out-of-band (and the panel shows a banner). Notification budget: ≤ 5 proactive pushes/day, directive-tunable — **never applies to reminders, alerts, or time-sensitive filer questions** (P6 > P3; a suppressed held-intake question about tomorrow's deadline is a silently dropped reminder).
- **Failure policy** (reads `reliability`): standard components — retry once, alert, auto-disable after 3 consecutive failures (never silent). **Critical components (scanner, watchdog, edge) are never auto-disabled** — retry with backoff forever, alert every failure.
- **Reconciler** (w0, pipe): converges launchd plists to the `components` registry. That is its whole job — approved proposals are applied synchronously by the panel at approve time, not by a privileged background executor.
- Build failures of provisioned components escalate to the user; hand-wiring is the documented fallback.

## Queues in practice

`messages` is the only coordination fabric: workflow→workflow handoffs, gardener questions, proposals, user pushes. Diagnostics are the table: `queue_status()`, panel feed, watchdog staleness rules. Queues coordinate **handoffs, never control flow** — a workflow's internal steps are its own pipeline (P4 guardrail).
