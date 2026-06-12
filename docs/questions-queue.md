# Questions Queue

Live opens only. (Resolved questions: see `CONTEXT.md` and `docs/archive/`.) Defaults stand unless Sam objects.

## Needs Sam (P0/P1 gate items)

1. **Corpus labels — plain version.** The eval corpus (`evals/filer/*.json`) is ~40 fixtures; each one is: a *raw input from your life* (a text, a Slack message, a thread-day) plus the **proposed correct answer** — `expected` (the exact L1 calls the filer should make: which atoms, tasks, people), `must_not` (what it must never do with this input), and `tolerances` (acceptable wiggle). The "label" is that proposed answer. **Confirming = reading each fixture and saying "yes, that's what I'd want claudio to do with this input" or correcting it.** They become the ground truth the filer is graded against before it touches your real data — wrong labels = a filer trained to your wrong taste. How: open the files, edit any `expected`/`must_not` you disagree with, flip `labels_status: proposed` → `confirmed`. Highest-leverage 15 minutes: `corpus-walkthrough.json` (Thiel/meme/split trio) and every `must_not`.
2. **The elicitation session** — the one P0 item only you can do. Say "run the elicitation" in a core session (the mirror's prompt is `core/agents/mirror/prompt.md`); it fills `core/l1/seeds/purpose-contract.md` + `roles.json` weights and ends with your signature.
3. **Role weights + disciple sensitivity** — per your note: these are **term** seeds (P11), set during the elicitation (item 2), not before. Standing default until then: `default_sensitivity: 1` on disciple (pastoral content).
4. **Backup destination — DECIDED (you delegated 2026-06-12).** Two layers: (a) local restic repo at `~/.claudio/backup` from day one (moves to the external drive when bought); (b) offsite restic -> Backblaze B2, client-side encrypted (B2 never sees plaintext; ~cents/month at life-data scale). The one step only you can do, at deploy, ~5 min guided: create the B2 account + bucket + app key. Until then layer (a) covers you.
4b. **Notable-reason starter vocabulary** — 8 reasons seeded (P12): milestone, first_contact, purpose_advance, rare_event, relationship_beat, decision, emotional_peak, user_asserted (`0008_seeds_grants.sql`). Type default; your term extends by promotion. Skim and veto any.

## Standing defaults (no action until their trigger)

5. **Scoring tuning** — two-lane exponents seeded v0 in `parameters.scoring`; tuned against the first week of real packets (P2).
6. **Wiki frontmatter freeze** — current keys are v0; freeze after a month of real pages.
7. **Filer judgment quality** — the corpus must prove `notable` reasons + atom-splitting; P0 labeling decides if the bars are right.
8. **Embeddings promotion** — trigger defined (logged search misses; they already audit); no action until it fires.
9. **Resident orchestrator occupant** — slot supports `resident`; pick the occupant (Hermes-class) at P3+.
10. **Probe budget** — orchestrator-triggered probes of probing windows are unmetered in v0 (logged as runs, visible in `v_component_health`). A cadence/cost cap gets a parameter only if probe spend shows up in the P5 spend report.
11. **Type/term packaging milestone** — now the full distribution model (`specs/07 §Distribution`): type repo + Sam's private term repo; installed type core-owned read-only to everyone (your login session included); `claudio update` propagates releases; migrations append-only from first release; fork test as acceptance. Lands post-P2 gate, not mid-loop. Until then: the line is enforced in review, and term-building sessions (your dashboard) run in their own repos against L1 — never inside this checkout. Open sub-decision, no rush: whether the type repo ever goes public (the model is identical either way; you keep the option).
12. **Regimes** — `semantics` is SCALAR (Occam #4, approved 2026-06-12); the audit log carries config history; promotes to a dated regime list at the first real regime change.
13. **Window filter defaults** — `filters` (pre-capture, never-recorded) ships empty by default; your term adds patterns as spam shows up. Type guardrails fixed: deterministic only + drop-counter metric.
14. **P12 sweep** — remaining free-text judgment fields get closed vocabs as their surfaces are built: `discard_intake` reason, hold reasons (P2, with the filer), wiki demotion reasons (P5). The mechanism exists; apply on touch.

## Standing rule until P2 ships (Occam #1, approved 2026-06-12)

New directives get one question first — *does the daily loop need it?* If not: a queue one-liner, never spec law. Applies to Claude's ideas too.

## Resolved by Sam (2026-06-12)

- **Raw retention: keep everything forever.** 512 GB local; external drive when needed; revisit only when storage actually bites.
- **Spam pre-filtering exists** — as window `filters`, term config (`specs/06`).
- **Type/term split is law** — P11 (`specs/00`), audit in `docs/type-term-audit.md`.
- **Obligations merge done** (Occam #2): one `obligations` table, kind task|expectation; `create_task`/`create_expectation` survive as verbs; lifecycle = `amend_obligation` + `resolve_obligation`. Suites 51 + 84 green.
- **Two-stage noise filtering kept** (Occam #3 rejected by Sam): `filters` (pre-capture) and `discard_patterns` (post-capture) stay distinct.

## Disclosures (done while you slept; objections reversible)

- **Homebrew install**: `postgresql@17` (binaries only — no service registered). Dev cluster lives at `~/.claudio/pg`, socket-only on port 5433, outside iCloud. `./core/deploy/dev.sh start|stop|reset|test`.
- **The P2-in-two-weeks clock started**: first DDL committed 2026-06-12 (the honesty-gate condition). P2 = the daily loop (edge, filer, brief, scanner) by ~2026-06-26 or shrink.
- **OS users NOT created, crons/launchd NOT loaded, no backups configured** — system-state changes wait for you (scripts exist: `setup-os-users.sh p1`, `reconcile.sh --dry-run`).
