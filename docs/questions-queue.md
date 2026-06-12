# Questions Queue

Live opens only. (Resolved questions: see `CONTEXT.md` and `docs/archive/`.) Defaults stand unless Sam objects.

## Needs Sam (P0/P1 gate items)

1. **Corpus labels** — 30 filer fixtures + 10 scenarios + 3 method evals are normalized with PROPOSED labels (`evals/`). Confirm or correct, then flip `labels_status` to confirmed. Highest-leverage review: `corpus-walkthrough.json` (Thiel/meme/split) and every `must_not`.
2. **The elicitation session** — the one P0 item only you can do. Say "run the elicitation" in a core session (the mirror's prompt is `core/agents/mirror/prompt.md`); it fills `core/l1/seeds/purpose-contract.md` + `roles.json` weights and ends with your signature.
3. **Role weights + disciple sensitivity** — `core/l1/seeds/roles.json` has null weights (yours to set during elicitation) and proposes `default_sensitivity: 1` on disciple (pastoral content). Confirm.
4. **Backup destination** — default restic -> Backblaze B2 (encrypted) + private git remote; confirm or name another. Scripts are ready (`core/pipes/backup/`); nothing runs until the destination + password file exist.

## Standing defaults (no action until their trigger)

5. **Scoring tuning** — two-lane exponents seeded v0 in `parameters.scoring`; tuned against the first week of real packets (P2).
6. **Wiki frontmatter freeze** — current keys are v0; freeze after a month of real pages.
7. **Filer judgment quality** — the corpus must prove `notable` reasons + atom-splitting; P0 labeling decides if the bars are right.
8. **Embeddings promotion** — trigger defined (logged search misses; they already audit); no action until it fires.
9. **Resident orchestrator occupant** — slot supports `resident`; pick the occupant (Hermes-class) at P3+.
10. **Raw retention** — default: keep ALL intake rows forever, including discarded spam/OTP (text is cheap; the record is the point — your 2026-06-12 directive). Revisit triggers: `archive/` exceeds ~5 GB, or the first privacy purge request. Backup destination (item 4) now carries tier-0, so its sizing matters slightly more.
11. **Probe budget** — orchestrator-triggered probes of probing windows are unmetered in v0 (logged as runs, visible in `v_component_health`). A cadence/cost cap gets a parameter only if probe spend shows up in the P5 spend report.

## Disclosures (done while you slept; objections reversible)

- **Homebrew install**: `postgresql@17` (binaries only — no service registered). Dev cluster lives at `~/.claudio/pg`, socket-only on port 5433, outside iCloud. `./core/deploy/dev.sh start|stop|reset|test`.
- **The P2-in-two-weeks clock started**: first DDL committed 2026-06-12 (the honesty-gate condition). P2 = the daily loop (edge, filer, brief, scanner) by ~2026-06-26 or shrink.
- **OS users NOT created, crons/launchd NOT loaded, no backups configured** — system-state changes wait for you (scripts exist: `setup-os-users.sh p1`, `reconcile.sh --dry-run`).
