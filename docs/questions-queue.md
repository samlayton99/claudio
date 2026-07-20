# Questions Queue

Live opens only. (Resolved questions: see `CONTEXT.md` and `docs/archive/`.) Defaults stand unless Sam objects.

## Needs Sam (P0/P1 gate items)

2. **RESOLVED (2026-07-03, your hand): role weights set** — disciple 10, husband-father 5, research 2.5, ward-exec-sec 2, prod 2, general 1, student 0.5 — seeded and pinned by test. Still open, smaller: how the brief should treat disciple-as-frame (weight 10 as apex/frame, not a 10x-loud section) — decide when the first real briefs land.
4. **Backup destination — DECIDED (you delegated 2026-06-12).** Two layers: (a) local restic repo at `~/.claudio/backup` from day one (moves to the external drive when bought); (b) offsite restic -> Backblaze B2, client-side encrypted (B2 never sees plaintext; ~cents/month at life-data scale). The one step only you can do, at deploy, ~5 min guided: create the B2 account + bucket + app key. Until then layer (a) covers you.

15. **External dead-man URLs (J3, ~5 min).** The edge and the watchdog each ping an optional heartbeat URL after a successful cycle (`CLAUDIO_DEADMAN_URL`, `CLAUDIO_WATCHDOG_DEADMAN_URL`) — the alarm that says "the box died" must live off the box. One free healthchecks.io account (or similar) with two checks covers both. Until then: local `~/.claudio/watchdog-heartbeat` + `backup-FAILED` markers exist, but nothing external alarms.

## Standing defaults (no action until their trigger)

5. **Scoring tuning** — two-lane exponents seeded v0 in `parameters.scoring`; tuned against the first week of real packets (P2).
6. **Wiki frontmatter freeze** — current keys are v0; freeze after a month of real pages.
7. **Filer judgment quality** — the corpus must prove `notable` reasons + atom-splitting; P0 labeling decides if the bars are right.
8. **Embeddings promotion** — trigger defined (logged search misses; they already audit); no action until it fires.
9. **Resident orchestrator occupant** — slot supports `resident`; pick the occupant (Hermes-class) at P3+.
10. **Probe budget** — orchestrator-triggered probes of probing windows are unmetered in v0 (logged as runs, visible in `v_component_health`). A cadence/cost cap gets a parameter only if probe spend shows up in the P5 spend report.
11. **Type/term packaging milestone** — now the full distribution model (`specs/07 §Distribution`): type repo (which ships the stdlib: default adapters/workflows/vocabs) + Sam's private term repo; installed type core-owned read-only to everyone (your login session included); `claudio update` propagates releases; migrations append-only from first release; fork test as acceptance. Lands post-P2 gate, not mid-loop. Until then: the line is enforced in review, and term-building sessions (your dashboard) run in their own repos against L1 — never inside this checkout. Open sub-decision, no rush: whether the type repo ever goes public (the model is identical either way; you keep the option).
12. **Regimes** — `semantics` is SCALAR (Occam #4, approved 2026-06-12); the audit log carries config history; promotes to a dated regime list at the first real regime change.
13. **Window filter defaults** — `filters` (pre-capture, never-recorded) ships empty by default; your term adds patterns as spam shows up. Type guardrails fixed: deterministic only + drop-counter metric.
14. **P12 sweep** — remaining free-text judgment fields get closed vocabs as their surfaces are built: `discard_intake` reason, hold reasons (P2, with the filer), wiki demotion reasons (P5). The mechanism exists; apply on touch.

## Standing rule until P2 ships (Occam #1, approved 2026-06-12)

New directives get one question first — *does the daily loop need it?* If not: a queue one-liner, never spec law. Applies to Claude's ideas too.

## Resolved by Sam (2026-07-03) — blanket approval ("I approve everything")

- **Corpus labels CONFIRMED** — all 43 fixtures approved verbatim; `labels_status` flipped to `confirmed (Sam, 2026-07-03)` across `evals/`. The corpus is ground truth for J1. P0 gate closed.
- **Three-row veto skim (was 2b)** — no veto; `love-of-math-and-building`, `outcomes-not-status`, `workout-daily` stand as approved/seeded.
- **Notable-reason vocabulary (was 4b)** — all 8 reasons stand.
- **Brief clearance (was 15)** — `w_brief` stays at c0: sensitivity-1 obligations never appear in the brief's ledger (the scanner at c1 still reminds about them). Revisit only if a real ward task goes unseen in practice.
- **"All nine" wording in the signed priorities prose** — approved as-is; left untouched.

## Resolved by Sam (2026-06-13)

- **Elicitation done; purpose contract v1 SIGNED and seeded** (2026-07-03): 22 rows + priorities v1 + 7 roles live in the db via `core/l1/seeds/seed.sh` (idempotent, refuses unsigned, skips DRAFT, reports drift). Deferred to a future version, not a re-sign: directives (none yet — highest-leverage remaining input for the brief), year-horizon goals, prune/merge calls.

## Resolved by Sam (2026-06-12)

- **Raw retention: keep everything forever.** 512 GB local; external drive when needed; revisit only when storage actually bites.
- **Spam pre-filtering exists** — as window `filters`, term config (`specs/06`).
- **Type/term split is law** — P11 (`specs/00`), audit in `docs/archive/type-term-audit.md`.
- **Obligations merge done** (Occam #2): one `obligations` table, kind task|expectation; `create_task`/`create_expectation` survive as verbs; lifecycle = `amend_obligation` + `resolve_obligation`. Suites 51 + 84 green.
- **Two-stage noise filtering kept** (Occam #3 rejected by Sam): `filters` (pre-capture) and `discard_patterns` (post-capture) stay distinct.

## Disclosures 2026-07-19 (mac mini session; objections reversible)

- **Mini bring-up done by Claude**: Homebrew `postgresql@17` + `restic` installed (binaries only, no services); dev cluster initialized at `~/.claudio/pg`; ALL SUITES GREEN (eleven suites, 290 tests). Still yours: copy `archive/` from the old machine (gitignored, not in the clone).
- **Watchdog built** (`core/pipes/watchdog/`, 16 tests): the last P2 critical-roster gap. Pure SQL, one alert per incident via `watchdog_key` dedup.
- **Seeded `max_silence_min` per component trigger** (0008, reversible): without it, `v_run_misses`' 120-min default would false-flag the daily brief every morning and idle query/queue components (filer, orchestrator — they write no run row when idle) after 2h. Values: edge 10m, watchdog 60m, gcal 60m, scanner 3h, brief/imessage ~26h, filer/orchestrator 3 days.
- **Live-cluster pre-staging attempted, blocked by the permission classifier** — consistent with the Sam-present rule; `live.sh init` stays on your J3 list. Same for a one-call `claude -p` login probe.

## Disclosures (done while you slept; objections reversible)

- **Homebrew install**: `postgresql@17` (binaries only — no service registered). Dev cluster lives at `~/.claudio/pg`, socket-only on port 5433, outside iCloud. `./core/deploy/dev.sh start|stop|reset|test`.
- **The P2-in-two-weeks clock started**: first DDL committed 2026-06-12 (the honesty-gate condition). P2 = the daily loop (edge, filer, brief, scanner) by ~2026-06-26 or shrink.
- **OS users NOT created, crons/launchd NOT loaded, no backups configured** — system-state changes wait for you (scripts exist: `setup-os-users.sh p1`, `reconcile.sh --dry-run`).
- **Edge stdlib trigger changed resident -> 60s interval** (2026-07-03, reversible): the v0 edge is a oneshot sweep+drain, and the reconciler only schedules cron/queue/query — as `resident` it would never have been loaded. The spec's fast-resident mode stays the P3 upgrade path. Same pass: components' `config.db_role` now maps component id -> db role (edge-imessage and window-imessage run as `w_edge`), and daily/hourly crons render real `StartCalendarInterval` blocks instead of a 900s poll. All rehearsed by `core/deploy/test-reconcile.sh` (dry-run only).
