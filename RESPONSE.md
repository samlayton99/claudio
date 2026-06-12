# RESPONSE
*Refresh every time, this is not a log. Items not yet addressed carry over to the next response if still applicable*

Session report for Sam. Rewritten each session; git history keeps prior reports. Explains the most significant moves, what you most need to know, what to do, and points to the details. Open decisions live in `docs/questions-queue.md`, not here.

## Session 2026-06-12 (day, part 2): your four responses integrated

### 1. Spam filters → window `filters`

Windows now carry `filters`: deterministic pre-capture drop rules — things never recorded at all, inherent to each window's config as you said. Two type-level guardrails: no model ever decides not-to-record (deterministic patterns only), and every drop increments a per-window counter metric so over-filtering stays visible (not-recording is irreversible). Distinct from `discard`, which records raw but extracts no atom. → `specs/06-surfaces.md` §Windows, `specs/01-schema.md` intake note. Ships empty; your term adds patterns as spam appears (queue 13).

### 2. Corpus labels, explained properly

Rewritten in plain language — queue item 1. Short version: each fixture is a raw input from your life plus the *proposed correct answer* (the exact calls the filer should make, what it must never do, allowed wiggle). Confirming = reading them and saying "yes, that's what I'd want" or correcting. They're the ground truth the filer is graded against before it touches real data. The 15-minute high-leverage pass: `evals/filer/corpus-walkthrough.json` + every `must_not`.

### 3. Storage

Resolved as you said: keep everything forever, worry later. Removed from standing defaults; noted under Resolved.

### 4. The type/term split — now P11, with an audit

This is the significant move of the session. Your words → what changed → where:

- **"the life-harness is the type, my life is the term... clearly divided"** → **P11 Type over term** added to the constitution, with the standing question at every decision: *what are we assuming about how the user lives or uses this? Any assumption belongs in the term.* Vocabulary entries for Type/Term/Regime. → `specs/00-constitution.md`.
- **"do an audit log... what is term, what is type"** → `docs/type-term-audit.md`: full classification of everything built. Headline finding: the harness is already cleanly type almost everywhere (schema/functions/specs carry you only in *examples*) — with one real leak: `0008` seeds `edge-imessage` and `window-gcal` (with your planner-regime semantics baked in) as if they were type. Tolerated at v0, moves to a `term/` seed at the packaging milestone (queue 11).
- **"someone else likely uses their gcal as raw truth. I use it as a planner... this should be configurable"** → ruled exactly so: per-source meaning (`semantics`) is term config under a type mechanism. The type assumes only that a window declares what its data means — never what a calendar is. → `specs/06-surfaces.md`.
- **"robust... mutable, dependent on time"** (gcal regime change in 8 months) → **regimes**: term values that interpret data are dated lists; any capture is interpreted under the regime in force at its `received_at`, so history reads under historical regimes. No accessor code until the first real regime change — grow by promotion (queue 12). → `specs/00` vocab, `specs/06`, audit doc.
- **"makes it shippable and packagable"** → packaging path in the audit: the new-user story is *clone the type → elicitation (their contract + roles) → register windows (their meaning, their filters)* — onboarding IS term-authoring. Physical `term/` split lands post-P2 gate, not mid-loop.
- **"you may be tempted in the future to conflate"** → pitfall 9 in `CONTEXT.md`: every future session names which side of the line each change is on.

No code changed this session (spec/doc layer only), so the suites stand as last verified: red-team 51/51, contract 76/76.

### What you need to do (carried over)

Still the gate items, now clearer: **(1) confirm corpus labels** (explained above — your next 15 minutes), **(2) run the elicitation** (which also sets the role weights/sensitivity you deferred — they're term seeds, set there, not before), **(4) name the backup destination** (default: restic → Backblaze B2; matters slightly more now that backups carry keep-forever tier-0).

### Pointers

The audit (read this one): `docs/type-term-audit.md`. Constitution: `specs/00` (P11, vocab, decision map). Windows: `specs/06` (filters, regime-dated semantics). Queue: `docs/questions-queue.md` (items 1–4 yours; 10–13 new defaults). Reasoning trail: `CONTEXT.md` (pitfall 9).
