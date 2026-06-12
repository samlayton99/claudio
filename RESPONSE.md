# RESPONSE
*Refresh every time, this is not a log. Items not yet addressed carry over to the next response if still applicable*

Session report for Sam. Rewritten each session; git history keeps prior reports. Explains the most significant moves, what you most need to know, what to do, and points to the details. Open decisions live in `docs/questions-queue.md`, not here.

## Session 2026-06-12 (day, part 3): notable typechecked, P12, backup decided

### Your question: how is notable captured?

Your instinct found a real gap. The state before today: `notable` was already binary and privilege-gated (boolean column; only the daily pass and you can set it — the filer can only flag `meta.notable_candidate`, and the red-team suite proves agents get rejected). But the *reason* was a comment-level convention stuffed in `meta` jsonb — prose, never validated. Exactly the thing you smelled.

Now closed, top to bottom:

- **`atoms.notable_reason`** is a real column, CHECK-paired with the boolean (`notable=true` ⇔ reason present — the database makes half-states unrepresentable).
- The reason must be an **active kind in a closed `notable_reason` vocabulary** — trigger-validated like every other kind. "Felt important" is unwritable; the model selects from a list it didn't write.
- **Starter list of 8** (seeded, yours to veto — queue 4b): `milestone`, `first_contact`, `purpose_advance`, `rare_event` (frequency claims must survive a COUNT, never model recall), `relationship_beat`, `decision`, `emotional_peak`, `user_asserted` (always wins).
- **7 new contract tests**: no reason → rejected; junk reason → rejected; valid → stored; unset → reason auto-clears; agents still blocked. **Suites: red-team 51/51, contract 83/83.**
- Found and fixed a pre-existing bug while testing: the guard blocked `w_brief` (the daily pass itself!) from setting notable — it could never have worked. My new tests caught it; this is your "every function needs test cases" rule paying out on day one.

### Generalized, as you suggested: P12 "Judgments are selections"

Now constitutional (`specs/00`): **any LLM judgment the scaffold acts on is a binary or closed-vocabulary selection, typechecked at write time — never free prose.** Nuance goes in prose fields that drive nothing. If a judgment can't be enumerated, it isn't automated — it becomes a question to you, and recurring answers grow the vocabulary by promotion. Much of the system already obeyed this (atom/link kinds, server-classified proposal classes, sensitivity); notable was the leak. Remaining free-text judgment fields (discard reason, hold reasons) get vocabs as their surfaces are built — queue 14.

### Backup: decided (you delegated)

Two layers. **Local**: restic repo at `~/.claudio/backup` from day one — zero setup, covers you immediately; moves to the external drive when you buy one. **Offsite**: restic → Backblaze B2, client-side encrypted (B2 only ever sees ciphertext; your data at life scale costs cents per month). The one 5-minute step only you can do — create the B2 account + bucket + key — happens at deploy, guided. Nothing is blocking on this anymore.

### Housekeeping

Your corpus rename left t03's raw text still saying Emma/Josh while the fixtures bound Ally/Kate — aligned the raw to your names. Walkthrough noted as approved; the other corpus files (`corpus-core`, `corpus-coverage`, `corpus-sam`) still carry `labels_status: proposed` whenever you want the same pass on them.

### Elicitation: you're clear to start

Nothing pending on my side. Say **"run the elicitation"** in a core session — the mirror's prompt is `core/agents/mirror/prompt.md`; it fills the purpose contract + role weights (including the disciple sensitivity default you deferred) and ends with your signature.

### Pointers

P12 + decision map: `specs/00`. Schema: `specs/01` §atoms, `core/l1/migrations/0002/0003/0005/0008`. Tests: `evals/contract/run.sh` (notable section). Queue: 4 (backup, decided), 4b (the 8 reasons — skim), 14 (P12 sweep). Reasoning: `CONTEXT.md`.
