# RESPONSE

Session report for Sam. Rewritten each session; git history keeps prior reports. Explains the most significant moves, what you most need to know, what to do, and points to the details. Open decisions live in `docs/questions-queue.md`, not here.

## Session 2026-06-12 (day): raw storage directive integrated + push fixed

### The push

Your commit was fine — the GitHub repo was empty, so `origin/main` didn't exist. Pushed and set upstream; plain `git push` works now.

### The significant move: the historical record is owned in-house

Your words → what changed → where:

- **"there needs to be an inhouse raw storage"** → `intake` is now THE tier-0 record, not disposable staging. Rows are never deleted ('discarded' = no atom extracted, raw remains); large payloads in `archive/` via `raw_ref`. → `specs/01-schema.md` (intake), `core/l1/migrations/0002_tables.sql`.
- **"tags noting how raw it is... AI summary or truly raw? P8"** → `rawness` column: `verbatim | derived`. Derived = summarized upstream by an AI/agent window — P8 counts it one summary deep; context, never ground truth. When a source offers both (your iMessage MCP: summaries + raw polling), the verbatim feed is the record. → schema + `capture()` (new arg, validated), `specs/06-surfaces.md`.
- **"passive windows vs probing windows"** → window `mode` in config and constitution vocabulary. Passive = stream copy on cron. Probing = inquiry-based (MCP server or external agent wearing the window hat), cadence-triggered or orchestrator-triggered. → `specs/06-surfaces.md` §Windows, `specs/00-constitution.md` §Vocabulary.
- **"orchestrator owns these triggers... probe around, make judgement calls"** → orchestrator owns ad-hoc probe triggers; probes when the record is discrepant/incomplete; every probe is a logged run; results land through `capture()` like everything else. → `specs/06-surfaces.md`.
- **"primary source is the historical record"** → P4 amended: pointers-over-mirrors now applies only to *live external state* (gcal futures, mailbox state); history is owned in-house because external refs rot. `fetch_ref` resolves in-house first, external tool as fallback. → `specs/00-constitution.md` P4, `specs/02-l1-api.md`.
- **"atoms are the accounting and directory system... raw should also be scannable itself"** → stated in §Atoms; `intake_by_day` index added; grep over `archive/` named as the second door. → `specs/01-schema.md`.

Code matched to spec in place (no deploy exists yet, so no 0009 migration): **fresh rebuild green — red-team 51/51, contract 76/76**, plus a manual smoke test of the new arg (valid `derived` stored; junk value rejected). `SCHEMA.md` regenerated. `CONTEXT.md` pitfall 7 updated so future agents don't re-narrow this.

### Your pasted threads (status)

You pasted four open threads from the early brainstorm into this file; where they stand now:

1. **"Do we trust the pointers, or archive high-value raws?"** — Resolved today, in your direction: ALL raws in-house; pointers are a courtesy, not a dependency.
2. **Calendar/email un-mirrored** — Refined, not reversed: live state (future events, mailbox) stays at source; the moment something happens it's in-house. "What's on Thursday" remains a live connector call. Flag if that still bothers you.
3. **Goals rows-plus-docs** — Superseded by the purpose plane (`specs/00` §Vocabulary, `01` §purpose): goals/values/attributes + priorities document, `advances` edges. Old dashboard metrics machinery stays dead until missed.
4. **Day-one tracking for focus/avoidance** — Covered structurally: atoms record honest time use (TV included); the mirror's lived-vs-proclaimed judgment is the procrastination check. No new table needed.

### What you need to do (unchanged gate items + two new defaults)

The four blocking items are still `docs/questions-queue.md` 1–4: **corpus labels, the elicitation session, role weights/disciple sensitivity, backup destination.** New standing defaults to veto if wrong (queue 10–11): raw retention = keep everything forever (revisit at ~5 GB or first purge request); probe spend unmetered v0 (logged, capped only if the P5 spend report flags it).

### Pointers

Spec deltas: `specs/00` (P4, vocab), `01` (intake, atoms), `02` (fetch_ref), `06` (windows). Code: `core/l1/migrations/0002/0005/0008`. Open items: `docs/questions-queue.md`. Reasoning trail: `CONTEXT.md`.
