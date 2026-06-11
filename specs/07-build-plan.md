# 07 — Build Plan

Phases gate on acceptance criteria, not vibes. Each phase pays for itself before the next starts (P3: immediate benefit).

## Eval suites (built first, run forever)

- **Filer evals** (unit): canonical corpus from `docs/claude-examples.md` (15) + the filer-level slices of `docs/sam-examples.md`, normalized to fixtures: `{id, adapter, sender, raw, db_fixture, expected: [l1 calls], tolerances}`. Harness: seed scratch DB → run filer headless → diff actual vs expected L1 calls. Pass bar: 100% on restraint/security cases (no-extract, no-guess, injection, sensitivity), ≥90% on extraction accuracy.
- **Scenario evals** (integration, per-phase): Sam's 10 workflow examples become end-to-end fixtures, activated as their machinery lands (mapping below).
- **Red-team suite**: `04-security.md`. Green is a merge gate from Phase 1 on.

## Phases

**P0 — Corpus + ground truth (no code)**
Normalize both example sets; label expected outputs together; resolve type-system frictions found. *Gate: 25+ labeled fixtures; no example that can't be expressed in L1 calls.*

**P1 — The contract**
Schema migrations (01), L1 functions (02), audit triggers, RLS + roles (`claudio_core/panel/agent`, `w_test`), rate limits, red-team suite, nightly backup + restore-test pipe, kill switch. *Gate: red-team green; restore drill passes; `get_context('role','prod')` returns a correct packet on seed data.*

**P2 — First loop (daily value begins)**
iMessage adapter (sync + entry point + allowlist), gcal adapter, filer (passes eval bar), notifier, watchdog, morning brief (with degraded mode), todo & expectation scanner. Seed roles/goals/directives + root wiki page from About_Me. *Gate: 7 consecutive days: brief delivered 7/7 (≥1 via degraded path test), capture-by-text files correctly, watchdog catches one induced miss, zero silent failures.*

**P3 — Trust the writes**
Merge gardener, held-intake flow, panel v0 (approvals, registry, people, runs, intake), applier, proposals end-to-end. *Gate: person dedup works on real collisions ("two Mikes"); a proposal approved in panel applies; an injected test email files as data (live, not just eval).*

**P4 — The portrait**
Wiki gardener + lint + `register_page` functions + verifier; seed person/role pages; weekly review digest. *Gate: 2 weeks of gardener growth with zero lint failures and no judgment-claim violations; Sam corrects a page and the correction sticks (verified_fields equivalent for prose).*

**P5 — Workflows & the system that builds itself**
Workflow trigger machinery (event handoffs), meeting setter, daily window summaries, provisioning pipeline (propose → build in `custom/` → register), first custom automation end-to-end (Sam's intro-to-gcal chain), alignment gardener (conservative settings). *Gate: one chained automation runs from a real text; one provisioned outer component built, approved, observable; alignment gardener asks ≤3 good questions in its first two weeks.*

**P6 — Widen**
gmail/slack/transcript/notion adapters, old-dashboard adapter, custom dashboards, meeting scanner (with web-search enrichment), tool scout, hygiene reviews, Cowork-migration of hot workers if cost data says so.

## Scenario → phase traceability (Sam's examples)

| Sam # | Scenario | Lands |
|---|---|---|
| 1 | intro text → person+atom+gcal+expectation chain | P5 |
| 2 | airline email + spouse texts → atom merge | P3 (merge) + P6 (gmail) |
| 3 | quit job → retire_role cascade | P3 (proposals) — `retire_role` in P1 |
| 4 | topology-notes drift question | P5 (alignment) + P6 (folder adapter) |
| 5 | left-on-read decay detection | P5 (alignment; metrics from P2 adapter) |
| 6 | substack → wiki placement | P4 + P6 (adapter) |
| 7 | low-priority-role crowding, incessant alignment | P5 |
| 8 | dashboard activity logs → atoms with inheritance | P6 (old-dashboard adapter) |
| 9 | custom dashboard tiles | P6 |
| 10 | meeting scanner → enrich → propose connection | P6 |

## Standing rules of the build

- Inner circle ships only via core sessions with migrations + tests; outer circle only via the provisioning pipeline.
- Every component lands with: registry row, runs wiring, watchdog expectation, negative tests for any new privilege.
- Anything cut from scope gets written to `docs/questions-queue.md`, never silently dropped.
