# J1 Report — filer graded against the confirmed corpus (2026-07-03)

Harness: `evals/filer/grade.py`. Per fixture: fresh db -> shared+db fixtures -> capture (received_at backdated to context_date) -> real filer (`claude -p`, calls counted) -> row delta -> deterministic gates (terminal intake state; zero-LLM where the label demands it) -> LLM judge vs expected/must_not/tolerances. 26 fixtures run (23 filer-lane + 3 template-lane); 4 skipped (orchestrator/aging lanes, not built yet). Results: `evals/filer/j1-results.json`; logs: runs 1-7 under the job tmp dir.

## Scores

| run | pass | restraint | security | extraction | change |
|---|---|---|---|---|---|
| 1 | 16/26 | 71% | 80% | 50% | baseline |
| 4 | 23/26 | 100% | 80% | 85% | schema+laws+templates |
| 5 | 25/26 | **100%** | **100%** | **92%** | **all bars met** (targets 100/100/>=90) |
| 6 | 23/26 | 100% | 80% | 85% | no changes — pure model variance |
| 7 | in flight | | | | link-leak fix + 2 laws; log: `~/.claude/jobs/6fbde586/tmp/j1-run7.log` |

Run 2 was destroyed by the session rate limit (not counted). Honest read: the bars were met on run 5, but 100% restraint/security is NOT yet stable run-over-run — the residual failures (f02 due-date nuance, f07 closure) are stochastic judgment, not systematic gaps. Re-grade after any prompt change; expect +/-2 fixtures per run.

## What J1 fixed (each run killed a failure class)

**Prompt** (`core/agents/filer/prompt.md`): exact arg schemas with REQUIRED keys (the model was inventing key names — batches quarantined); sensitivity is 0|1 integer, NEVER 2 (an s2 write by a c1 worker RLS-fails and loses the row); hold is for genuine ambiguity, a self-introducing named sender is NEW; hold questions name the candidates; closure law + worked example (resolve_obligation when the awaited thing arrives); never span an atom across a future event (calendar stays authoritative); contingent user actions are still tasks; due dates are the user's own — someone else's ETA is the expectation's due, never the task's.

**Plumbing** (`core/agents/filer/main.py`): closed vocabularies (atom/link kinds) injected into context; known-sender header now carries the person uuid; people roster (50, recency-ordered) in context; batch validated BEFORE dispatch with a pointed one-retry (required keys, sensitivity ints, uuid-or-$ref ids — kills the whole quarantine class); split batches number their tier-0 refs (locator#2...) so multi-atom days stop colliding on `atoms_source_locator`; LLM timeout 300s env-tunable; quarantined batches are logged verbatim.

**Deterministic lanes** (no LLM pass, per the corpus's own bars): `semantics.discard_patterns` (stdlib OTP regex on the edge window) discards without a model; zero-signal thread-days file one templated atom (any question/commitment/time/link/money pattern or unknown sender routes to the model instead); structured windows name a converter in config — `gcal-event`, `day-log` — malformed payloads fall back to the model. All stub-tested dead-model in `filer/test.sh` (27 tests).

## The find that mattered

**Sensitivity leak in L1** (f05): links created through `record_atom` were born at sensitivity 0 even when the atom was 1 — the pastoral EDGE (who was in the room) was readable at c0. Fixed in `0005` (links inherit the atom's floor), pinned by contract test `link-inherits-atom-floor`. A real red-team-class bug found by grading, not by review.

## Caveats

- The judge is `claude -p` with a rubric; spot-checked against the db on every failure I acted on — explanations were accurate each time. Deterministic gates (intake terminal, zero-LLM labels) never rely on it.
- Quarantine is fail-closed: a bad batch holds the row for panel review; nothing is silently lost, but nothing is filed either.
- Template-lane roles fall to the window's default role; per-chat/entry role maps are term config (`entry_roles`, `default_role`).
- Cost: ~50 model calls per full run (filer + judge per fixture), ~20-25 min.
