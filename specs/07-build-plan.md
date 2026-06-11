# 07 — Build Plan

Build order law: **structure first, types and contracts second, functionality and wiring third.** Phases gate on acceptance criteria; each phase pays for itself before the next starts.

## Standing gates (from `docs/honesty-audit.md`)

1. **P2 in two weeks** of first DDL, or shrink before continuing.
2. **Value at every stopping point** — every phase leaves the user better off if work stops forever.
3. **The kill criterion** — at P3 exit: weekly maintenance minutes > weekly minutes saved ⇒ stop or shrink.

## Standing rules of the build

- Inner circle ships only via core sessions with migrations + tests; outer only via the provisioning pipeline; workers never write code paths.
- Every component lands with: registry row, parameters, runs wiring, watchdog expectation, negative tests for new privilege, reconciler plist.
- **Independent audits run at every phase gate**: structural-completeness + over-engineering trim + the malicious-superintelligence review (`04`). Scope cut at a gate is written to `docs/questions-queue.md`, never silently dropped.
- Evals are not law: they grow and change with scope. Restraint/security cases stay at a 100% bar.
- Continuous naming check: anything an agent calls gets a descriptive name or it doesn't merge.

## Eval suites (built first, run forever)

- **Filer evals**: corpus from `docs/claude-examples.md` + filer-level slices of `docs/sam-examples.md`, normalized `{id, adapter, sender, raw, db_fixture, expected: [batch], tolerances}` (implicit thread-day atoms tolerated). Bar: 100% restraint/security (no-extract, no-guess, injection, sensitivity, world-obligation vs system-instruction), ≥90% extraction.
- **Scenario evals**: Sam's 10 workflow scenarios end-to-end, activated per traceability (autonomy encoded: S2 merge via proposal; S1 calendar via standing approval).
- **Packet evals** (new): context-assembly scenarios (brief assembly, meeting prep, "what's going on with X") scored for citation correctness + budget discipline.
- **Red-team suite**: merge gate from P1.

## Phases

**P0 — Structure + ground truth (no code)**
Repo layout (`core/`, `custom/`, `wiki/` chapters, `archive/`), corpus normalized and labeled together, **the mirror's first elicitation session** → purpose contract v1 + priorities (front-load the irreplaceable — honesty audit). *Gate: 25+ labeled fixtures, every example expressible in L1 calls; purpose contract exists and Sam signs it.*

**P1 — Types & contracts**
Migrations (3 planes), L1 function sets + grants, jsonb schema validation, audit + RLS (forced, invoker) + `role_clearances` + `parameters`, OS tiers, red-team suite, backup + restore-test, kill switch. *Gate: red-team green across tiers; restore drill passes; `get_context('role','prod')` correct on seed data; generated types compile.*

**P2 — First loop (daily value)**
The edge (capture-first, sender verification, dead-man), gcal window, filer (eval bar), orchestrator (dictation gate), watchdog + reaper, morning brief (degraded-mode tested), scanner, pulse. Seed roles/directives + chapter MOCs + root pages from About_Me + purpose contract. *Gate: 7 consecutive days — brief 7/7 (≥1 forced-degraded), capture-by-text files, induced miss alerts ≤15 min, induced send failure alerts via dead-man, queue properties proven under induced crash (lease reaping, no double-fire), zero silent failures.*

**P3 — Trust the writes**
Merge gardener, panel v0 (approvals + derived classes + taint, chat, registry/audit page, people, intake, parameters, runs), standing approvals, `retire_role` cascade. *Gate: two-Mikes by text + panel-approved merge; multi-action proposal applies atomically; live injected email files as data; standing approval auto-applies a solo gcal block and is revocable. Kill-criterion check #1.*

**P4 — The biography**
wiki-tool + page functions, wiki gardener (delta-only), lint (citations + anti-slop), **verifier on weekly cron**, state-of-life digests, demotion sweep. *Gate: 2 weeks growth — zero un-triaged lint failures, zero judgment-claim violations, citation sampling clean, a panel correction sticks as an immutable span, page count sublinear in atoms.*

**P5 — Workflows & alignment**
Query triggers + cursors, meeting setter, the S1 intro→gcal chain under standing approval, provisioning pipeline end-to-end (first outer component), alignment gardener, **the mirror's observational mode**. *Gate: S1 from a real text; one outer component live; alignment asks ≥1 question Sam rates "good catch"; mirror's first usage report leads to one real promote/cut.*

**P6 — Widen**
gmail/slack/transcript/notion/folder windows, old-dashboard window, custom dashboards, meeting scanner (outer), scout (tools + windows), hygiene reviews, embeddings if the promotion trigger fires, Cowork migration if cost data demands, handshake's first real external agent.

## Scenario → phase traceability

| Sam # | Scenario | Lands |
|---|---|---|
| 1 | intro text → person/atom → gcal + day-before expectation | P5 |
| 2 | airline email + spouse texts → atom merge (proposal) | P3 + P6 (gmail) |
| 3 | quit job → retire_role cascade | P3 |
| 4 | topology-notes drift question | P5 + P6 (folders) |
| 5 | left-on-read decay | P5 (metrics from P2) |
| 6 | substack → wiki placement | P4 + P6 |
| 7 | role-purpose crowding ultimatum (re-ask rule) | P5 |
| 8 | dashboard logs → atoms with inheritance | P6 |
| 9 | custom dashboard tiles | P6 |
| 10 | meeting scanner → enrich → propose connection | P6 |

UX setup/maintenance burden per ring: `docs/ux-rings.md` (the sins list — every required user action is a debt to shrink).
