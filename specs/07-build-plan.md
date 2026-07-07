# 07 — Build Plan

Build order law: **structure first, types and contracts second, functionality and wiring third.** Phases gate on acceptance criteria; each phase pays for itself before the next starts.

## Repo structure (built at P0)

```
claudio/
├── CONTEXT.md              # prose context for any future agent (with specs/, fully self-sufficient)
├── specs/                  # THE LAW (00-07)
├── core/                   # inner circle — read-only to all workers, ships via core sessions
│   ├── agents/<id>/        # ONE FOLDER PER INNER AGENT (P10): prompt.md + context.md
│   │                       #   (context.md declares the deterministic pulls: "reading yesterday's
│   │                       #    atoms: {what_happened(...)}" — assembled by run-worker.sh)
│   ├── l1/                 # migrations, functions, triggers, RLS, seeds
│   ├── pipes/              # deterministic scripts: edge, windows, watchdog, lint, backup, red-team
│   ├── panel/              # the permanent surface
│   ├── deploy/             # launchd templates, reconciler, OS-user setup, pf anchors, kill switch
│   └── params/             # core-ring parameter seeds (fn→class map, arg-predicates)
├── custom/                 # outer circle — starts EMPTY; agent-authored, user-approved, core-deployed
│   └── agents/<id>/        # one folder per outer agent/automation, same shape as core/agents/
├── wiki/                   # the biography (eleven chapter dirs incl. cadences/, digests under it)
├── archive/                # tier-0 payloads claudio itself retains
├── evals/                  # filer corpus, scenario fixtures, packet evals, harness
└── docs/                   # working notes; docs/archive/ = the historical brainstorm (not law)
```

## Distribution (P11: the type ships; planned now, built at the packaging milestone)

Status: an **option preserved cheaply, not a commitment** — Sam hasn't decided whether the type is ever maintained for others. Nothing in this section is load-bearing for a single-user install; it exists so heading there later is easy. Default path is install; forking is allowed.

Three artifacts:

| Artifact | Who writes it | Where |
|---|---|---|
| **Type release** | nobody locally — installed at a pinned tag, core-owned, read-only to ALL non-core uids including the user's login session | e.g. `~/claudio-system/` (installer-created) |
| **Term workspace** | the user and their agents, freely | the user's own repo: term components (windows, dashboards, custom agents), seeds, wiki, deploy choices |
| **Dev checkout** | maintainers only | a normal clone; type changes go upstream as PRs |

- **Update path** (cheap by construction, whether or not the project is ever public): `claudio update` = fetch tagged release → run new migrations → regenerate catalog → reconciler restarts workers. The term never lives in type paths, so updates cannot touch it.
- **Migrations are append-only from the first release.** (Pre-release, in-place editing + `dev.sh reset` is fine — that era ends at packaging.)
- **The fork test is the packaging acceptance test**: forking is permitted, but a senior dev must find using-and-term-building strictly easier than forking. Every "I had to fork to do X" is filed as a type defect.
- **This repo, today**, is the dev checkout with Sam's term co-resident; the milestone splits them (type repo + Sam's private term repo). Until then: term-building sessions (e.g. the custom dashboard) run in their own repos against L1 — never inside this checkout.

## Standing gates (from `docs/archive/honesty-audit.md`)

1. **P2 in two weeks** of first DDL, or shrink before continuing.
2. **Value at every stopping point** — every phase leaves the user better off if work stops forever.
3. **The governing trio**: the kill criterion (at P3 exit: maintenance minutes > minutes saved ⇒ stop or shrink) + the effort slider (one dial on system proactivity) + the mirror's usage monitoring. Budget ceiling exists but defaults to none.

## Standing rules of the build

- Inner circle ships only via core sessions with migrations + tests; outer only via the provisioning pipeline; workers never write code paths.
- Every component lands with: registry row, parameters, runs wiring, watchdog expectation, negative tests for new privilege, reconciler plist.
- **Independent audits run at every phase gate**: structural-completeness + over-engineering trim + the malicious-superintelligence review (`04`) + the dependency sweep (`03`). Scope cut at a gate is written to `docs/questions-queue.md`, never silently dropped.
- **Drills are automated, not assigned**: restore-test is a monthly cron with checksum + alert; kill-switch verification is scripted with a calendar nudge. Humans do not drill (ux-rings).
- Evals are not law: they grow and change with scope. Restraint/security cases stay at a 100% bar.
- Continuous naming check: anything an agent calls gets a descriptive name or it doesn't merge.
- **One folder per agent** (P10): everything that defines an agent — prompt, context-construction spec, config — lives in its own folder under `core/agents/` (inner) or `custom/agents/` (outer). Tweaking an agent is editing its folder; nothing scattered.

## Eval suites (built first, run forever)

- **Filer evals**: corpus from `docs/archive/claude-examples.md` + filer-level slices of `docs/archive/sam-examples.md`, normalized `{id, adapter, sender, raw, db_fixture, expected: [batch], tolerances}` (implicit thread-day atoms tolerated). Bar: 100% restraint/security (no-extract, no-guess, injection, sensitivity, world-obligation vs system-instruction), ≥90% extraction.
- **Scenario evals**: Sam's 10 workflow scenarios end-to-end, activated per traceability (autonomy encoded: S2 merge via proposal; S1 calendar via standing approval).
- **Packet evals** (new): context-assembly scenarios (brief assembly, meeting prep, "what's going on with X") scored for citation correctness + budget discipline.
- **Red-team suite**: merge gate from P1.

## Phases

**P0 — Structure + ground truth (no code)**
Repo layout (above), corpus normalized and labeled together, **the first elicitation session** (run manually as a core session; it doubles as the initiation protocol — the chat walks the user through what to fill out, can fill the files itself, and tours the panel when it exists) → purpose contract v1: goals, values/beliefs, attributes, the priorities document (front-load the irreplaceable — honesty audit). *Gate: 25+ labeled fixtures (incl. the Thiel/meme day, a two-episode thread, and the three assessment-question scenarios), every example expressible in L1 calls; purpose contract exists and Sam signs it.*

**P1 — Types & contracts**
Migrations (3 planes; `metrics` deferred to P5), L1 function sets + grants, jsonb schema validation, audit + RLS (forced, invoker) + `role_clearances` + `parameters` (seeded minimally), catalog as a migration-runner hook, **staged tiers: two OS users** (`04`), red-team suite, backup + monthly restore-test cron, kill switch. **Seed the contract**: purpose markdown → `purpose` rows. *Gate: red-team green for the deployed stage; restore cron passes; `get_context('role','prod')` correct on seed data incl. taste; contract tests green.*

**P2 — First loop (daily value)**
The edge (capture-first, sender verification, spool, dead-man, taste-confirm flow), gcal window (read-only ICS), filer (eval bar; critical; poison quarantine), orchestrator (stages taste, never writes it), watchdog, morning brief (degraded-mode tested; hold-questions ride it; writes the daily digest page), scanner. Seed roles/directives + **verified user handles** + chapter MOCs + root pages from About_Me. *Gate: 7 consecutive days — brief 7/7 (≥1 forced-degraded), capture-by-text files, a dictated directive commits via read-back-confirm, induced miss alerts ≤15 min, induced send failure alerts via dead-man, queue properties proven under induced crash (claim-time reaping, no double-fire), zero silent failures.*

**P3 — Trust the writes (+ staged hardening completes)**
Merge gardener, panel v0 (what-will-execute approvals, registry/audit page, intake, parameters — the P3-gate surfaces only; wiki browse lands P4, chat is the edge), phone approvals for low-risk classes, `retire_role` cascade, generated TS types (first consumer: the panel), **full OS tier split + pf + Tailscale**. All approvals are manual until P5 — panel + phone are cheap by design. *Gate: two-Mikes by text + approved merge; multi-action proposal applies atomically with the rendered view matching execution; live injected email files as data AND its span renders fenced downstream; an approval completed from the phone. Kill-criterion check #1.*

**P4 — The biography**
wiki-tool + page functions, wiki gardener (delta-only) with the **chained verifier step** (fresh context, never the author), lint (citations + anti-slop), weekly state-of-life digest, panel wiki browse (+ one-tap corrections). *Gate: 2 weeks growth — zero un-triaged lint failures, zero judgment-claim violations, citation sampling clean, a panel correction sticks as an immutable span, page count sublinear in atoms.*

**P5 — Workflows & alignment**
Query triggers + cursors (cycle guard), meeting setter, **`w_approver` + standing approvals (arg-predicates)**, the S1 intro→gcal chain under standing approval, provisioning pipeline end-to-end (first outer component), **the mirror's observational mode** (the alignment surface; + taste-write provenance review), metrics table + window source-side stats (backfilled by query), notification budget, hygiene (incl. demotion sweep + window/tool proposals), neglect mode. *Gate: S1 from a real text; a standing approval auto-applies a solo gcal block, rejects an attendee-bearing one, and is revocable; one outer component live; the mirror's first report asks ≥1 question Sam rates "good catch" and leads to one real promote/cut; **the induced 3-week-neglect eval passes — the system recovers with one rollup, no cleanup project**. Kill-criterion check #2.*

**P6 — Widen**
gmail/slack/transcript/notion/folder windows, old-dashboard window, custom dashboards, meeting scanner (outer), monthly/biannual state-of-life cadences (if the weekly is read), embeddings if the promotion trigger fires, Cowork migration if cost data demands, handshake protocol designed against its first real external agent.

## Scenario → phase traceability

| Sam # | Scenario | Lands |
|---|---|---|
| 1 | intro text → person/atom → gcal + day-before expectation | P5 |
| 2 | airline email + spouse texts → atom merge (proposal) | P3 + P6 (gmail) |
| 3 | quit job → retire_role cascade | P3 |
| 4 | topology-notes drift question (mirror observational) | P5 + P6 (folders) |
| 5 | left-on-read decay (mirror + metrics) | P5 |
| 6 | substack → wiki placement | P4 + P6 |
| 7 | role-purpose crowding ultimatum (re-ask rule) | P5 |
| 8 | dashboard logs → atoms with inheritance | P6 |
| 9 | custom dashboard tiles | P6 |
| 10 | meeting scanner → enrich → propose connection | P6 |

UX setup/maintenance burden per ring: `docs/archive/ux-rings.md` (the sins list — every required user action is a debt to shrink).
