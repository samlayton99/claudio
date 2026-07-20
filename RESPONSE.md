# RESPONSE
*Refresh every time, this is not a log. Items not yet addressed carry over to the next response if still applicable.*

Session report for Sam. Rewritten each session; git history keeps prior reports. Explains the most significant moves, what you most need to know, and points to the details. Open decisions live in `docs/questions-queue.md`, not here.

**Template (binding — every report ends with these four sections):**
1. **Your plate** — what Sam needs to do, in priority order, with time estimates where known.
2. **My plate** — what Claude does next, in order.
3. **Dependencies / async / blockers** — what runs in parallel, what joins where, what is blocked on whom (reviews count as blockers).
4. **Why I stopped** — sanity check / clean stopping point vs. a genuine blocker, named.

---

## Checkpoint 2026-07-19: mac mini is green; the watchdog is built. P2 code is complete — everything left is the J3 session with you.

First session on the mini. Bring-up from the last report's checklist is done except one item only you can do (copy `archive/`). The last critical-roster gap — the watchdog — is built and tested. Eleven suites, 290 tests, ALL SUITES GREEN on this machine.

### Bring-up (done by Claude, disclosed in the queue)

Installed `postgresql@17` + `restic` (binaries only, no services), initialized the dev cluster, ran the full suite. One test failed on first run: the brief fixture recorded its notable atom at `now() - 20 hours`, which lands on *today* when the suite runs after 8pm — your old machine always ran it earlier. Root-caused, fixture pinned to yesterday-noon (`current_date - interval '12 hours'`), same family as the date-rotted contract fixture from J1. Product code untouched.

### The watchdog (`core/pipes/watchdog/`, 16 tests)

Pure SQL + filesystem, no LLM (P6), runs as `w_watchdog`. The four checks from `03 §Reliability` plus the backup sweep: schedule misses (`v_run_misses`), stuck runs (> 2x trailing 7-day median, floored at 30 min), stale posted messages per queue, expired-claim reaping, and the `~/.claudio/backup-FAILED` marker. One alert per incident — every alert carries a `watchdog_key`; a key never fires twice, a new incident gets a new key (recovery-then-new-silence is proven in tests). Alerts are s0 user-queue notifications the edge already delivers. After each sweep it writes `~/.claudio/watchdog-heartbeat` and pings `CLAUDIO_WATCHDOG_DEADMAN_URL` if set (same convention as the edge — the alarm about the watchdog must not depend on the watchdog).

Real bug found while wiring it: no seeded trigger declared `max_silence_min`, so `v_run_misses`' 120-min default would have false-flagged the daily brief every morning and the idle filer/orchestrator (query/queue components write no run row when idle) after 2h. Honest per-cadence values now seeded in 0008 — table in the queue disclosure.

## 1. Your plate

1. **Copy `archive/` from the old machine** (~5 min) — gitignored tier-0 payloads; the clone here has an empty `archive/`. The last bring-up remainder.
2. **Skim the queue** (~5 min): the 2026-07-19 disclosures (especially the seeded `max_silence_min` values) and new item 15 (dead-man URLs).
3. **J3 on the mini** (~30-40 min together, schedule it): `./core/deploy/live.sh init|start|createdb|migrate` + seed, `setup-os-users.sh p1`, per-uid `.pgpass`, Full Disk Access + signed-in iMessage for the edge, real handles into edge config, `./core/deploy/live.sh reconcile --apply`, `./core/deploy/live.sh autostart`. Then: **copy `~/.claudio/restic.pass` off the machine** (first backup self-bootstraps it; no password, no restore), B2 account (queue 4), healthchecks.io account for the two dead-man URLs (queue 15). Also 30 seconds: `! echo "reply ok" | claude -p` to confirm the CLI is logged in for the filer/brief harness — the permission classifier blocked me from probing it.

## 2. My plate

1. J3 support when you schedule it (walk the checklist with you, verify each hop live).
2. Post-J3: the 7-day P2 gate (`specs/07`) — brief 7/7 with one forced-degraded, induced miss/send-failure drills, queue properties under induced crash; then scoring tuning + brief disciple-frame treatment from real packets.
3. Deferred by judgment, standing: test-epilogue unification, per-suite clean-db assertions, `CLAUDIO_PGHOST` symmetry.

## 3. Dependencies / async / blockers

- **J3 needs you present** — the only true blocker, and it now blocks everything on my plate.
- The permission classifier here blocks live-cluster commands and `claude -p` spawns even pre-data — so J3 prep I could have staged (empty live cluster init/migrate) folded into the J3 session itself. Consistent with the system-state rule; nothing lost but ~5 min.
- This session's work is committed; the tree is clean for parallel sessions.

## 4. Why I stopped

**Clean checkpoint, named.** P2's operative roster (filer, scanner, watchdog, brief + edge/windows) is now fully built and green on the machine that will run it live. Everything remaining before go-live requires you physically present (OS users, TCC grants, iMessage, live seed, external accounts) or blocked-by-design (live cluster, model spend). Verified before stopping: eleven suites green after every edit, watchdog suite green twice (including after the dead-man addition), SCHEMA.md regenerated deterministically by the migration hook.
