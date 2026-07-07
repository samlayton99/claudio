# RESPONSE
*Refresh every time, this is not a log. Items not yet addressed carry over to the next response if still applicable.*

Session report for Sam. Rewritten each session; git history keeps prior reports. Explains the most significant moves, what you most need to know, and points to the details. Open decisions live in `docs/questions-queue.md`, not here.

**Template (binding — every report ends with these four sections):**
1. **Your plate** — what Sam needs to do, in priority order, with time estimates where known.
2. **My plate** — what Claude does next, in order.
3. **Dependencies / async / blockers** — what runs in parallel, what joins where, what is blocked on whom (reviews count as blockers).
4. **Why I stopped** — sanity check / clean stopping point vs. a genuine blocker, named.

---

## Checkpoint 2026-07-07: robustness pass — the repo is now safe to hand to any agent

Per your instruction: a full audit (three independent reviews: doc drift, code complexity, deploy bugs) plus fixes, so future agents — and the mac mini deploy — can't be misled or do damage. Ten suites still green (274 tests). Everything is in the working tree, **uncommitted** pending your look.

### The guards that now exist (each was a real hole)

- **Live cluster is fenced.** `live.sh reset` would have dropped the live db with zero confirmation, and `live.sh test` would have run fixture suites into it. Both now refuse (`reset` needs `CLAUDIO_LIVE_CONFIRM=DROP-LIVE`); `dev.sh reset|test` also refuse if live env leaked in. `live.sh autostart` now refuses before `init` (was: launchd crash-loop) and `live.sh stop` boots out the KeepAlive agent (was: postgres silently restarting after "stopped").
- **Reconcile can't misdeploy.** Bare `./reconcile.sh` used to be the real run, defaulting to the dev cluster and `echo` send — workers permanently wired to dev, outbound messages dropped, looking green. Now: `--dry-run|--apply` only, target banner printed, `--apply` against dev refuses. **The J3 command is `./core/deploy/live.sh reconcile --apply`.** Also: unparseable cron now errors instead of silently running every 15 min; sed values escaped; rendered plists linted before load; unchanged plists not reloaded (no more killing in-flight workers on every reconcile); run-worker's lock now survives SIGTERM.
- **The kill switch now actually contains.** `claudio-stop` missed `com.claudio-backup` (label outside its pattern) — a compromised box would keep exporting the full db nightly. Now booted out; the backup and restore-test entrypoints also honor the STOPPED marker.
- **First backup on the mini can't fail silently.** `run-live.sh` now bootstraps: generates `~/.claudio/restic.pass` (0600) if absent, `restic init`s the repo, and leaves `~/.claudio/backup-FAILED` on any failure (watchdog food). Before: every 02:30 run died in `backup.err` forever, zero snapshots.
- **Credits can't be burned by accident.** `grade.py` now refuses without `--spend` and prints your standing rule (~50 calls, only after prompt.md changes, prefer `--only`).
- **Tests no longer dirty git.** SCHEMA.md regeneration is byte-deterministic (timestamps normalized, unaligned rows) and refuses to run from a non-dev cluster — regenerating from live would have committed real life rows into git.

### Orientation for the next agent

Root `CLAUDE.md` added (auto-loaded; orientation order, the two clusters, credits rule, session conventions). `CONTEXT.md` de-rotted: the resolved gates (labels, weights) no longer read as open; the live cluster and the new J3 command are narrated; hardcoded test counts replaced by "run `./evals/run-all.sh`". Convention stragglers annotated (brief has inline prompts by design; mirror not yet built; run-worker's `w_<id>` role fallback documented). Stale-doc sweep (your call, same day): `docs/` now holds only the live pair — `questions-queue.md` + `j1-report.md`; the seven finished rationale docs (claude/sam-examples, honesty-audit, research x2, ux-rings, type-term-audit) moved to `docs/archive/` with every cross-reference in specs/CONTEXT/evals updated — nothing deleted, since they are signed-label provenance and spec-cited evidence. `elicitation-notes.md` stays with the mirror: it is working memory for future purpose-version sessions.

### For future Claude (compaction pointers)

- Orientation: `CLAUDE.md` -> `CONTEXT.md` -> `specs/00-07` -> `docs/questions-queue.md` -> this file. Run everything free: `./evals/run-all.sh`.
- Deferred by judgment (small, non-blocking): unifying the five hand-rolled test epilogues onto lib.sh `summary` (run-all now dumps full output on failure, which covers the diagnostic need); per-suite clean-db assertions; a `CLAUDIO_PGHOST` env var for symmetry.

## 1. Your plate

1. **Mac mini bring-up** (~30 min before the J3 session proper): install Homebrew + `postgresql@17` + `restic` + the claude CLI; clone the repo; **copy `archive/` from this machine — it is gitignored, tier-0 payloads do not travel with git**; then `./core/deploy/dev.sh init && ./core/deploy/dev.sh start && ./evals/run-all.sh` must print ALL SUITES GREEN before anything live.
2. **J3 on the mini** (~30 min together): `./core/deploy/live.sh init|start` (+ `createdb`, `migrate`, seed), `setup-os-users.sh p1`, per-uid `.pgpass`, Full Disk Access + signed-in iMessage for the edge, real handles into edge config, then `./core/deploy/live.sh reconcile --apply`, `./core/deploy/live.sh autostart`. First backup self-bootstraps `~/.claudio/restic.pass` — **copy that file off the machine; no password, no restore**. B2 account when you're ready (queue item 4).
3. **Review + commit this pass** — the whole robustness pass is uncommitted in the working tree for your skim (or tell Claude to commit it).

## 2. My plate

1. **Build the watchdog** (`core/pipes/watchdog/`) — unchanged from last checkpoint: free, deterministic, the last `critical` roster gap; now also has `backup-FAILED` to sweep.
2. J3 support when you schedule it.
3. Post-J3: scoring tuning + brief frame treatment, driven by real packets.

## 3. Dependencies / async / blockers

- **J3 needs you present** (system-state rule) — still the only true blocker, now with the mini bring-up in front of it.
- The uncommitted tree is a soft blocker on any parallel session — commit (item 3, yours) before other work lands.
- Watchdog build is independent and free.

## 4. Why I stopped

**Clean checkpoint, named.** The requested robustness pass is done and verified: every review finding either fixed or explicitly deferred with the reason above; all guards exercised by hand (each refuses with a pointed message); ten suites green after every edit; SCHEMA.md determinism proven by back-to-back resets. Committing is yours to trigger since it bundles your uncommitted J3 prep from before this session.
