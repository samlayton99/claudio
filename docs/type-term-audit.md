# Type/Term Audit

Sam's directive (2026-06-12): **the life-harness is the type; a life is the term.** Claudio ships as a general product; Sam's life is the reference term — the test case that makes it good, never the spec. The classification rule: *if a design decision rests on an assumption about how the user lives or uses a tool, it belongs in the term (config, seeds, regimes), not the type (schema, functions, specs).* Occam's razor on user assumptions: the fewer the type makes, the more decisions answer themselves.

## The audit

### Type (ships to any user)

| Artifact | Verdict |
|---|---|
| `specs/00–07` normative statements | Type. Protocols, planes, tiers, L1 contract, security model, wiki machinery, build gates. |
| `core/l1/migrations/` schema + validation + RLS + functions | Type. No term data in DDL or function logic. Sam appears only in `COMMENT ON` *examples* — acceptable and good (concrete beats abstract), provided the normative text stays term-free. |
| Vocab seeds (atom kinds, link kinds, message kinds) | Type defaults; promote/demote machinery lets any term extend. |
| `parameters` keys + shipped defaults | Type. Tuned *values* become term. |
| Component roster: required slots (filer, brief, scanner, watchdog, orchestrator, mirror, catalog, the edge *slot*) | Type. Every instance needs these organs. |
| `core/pipes/`, `core/deploy/`, panel, eval harness, `evals/contract/` | Type. Contract tests verify the harness, not a life. |
| The `general` role | Type — the spec-mandated catch-all. |
| Wiki chapters (the eleven) | Type default taxonomy; a term may rename/extend at the frontmatter freeze. |
| Regime mechanism, filters mechanism, rawness, clearances | Type mechanisms; their *values* are term. |

### Term (Sam's instance)

| Artifact | Verdict |
|---|---|
| `core/l1/seeds/roles.json` (disciple, prod, husband-father, student; weights; disciple sensitivity) | Term seed. |
| `core/l1/seeds/purpose-contract.md` (post-elicitation) | Term — the apex of the term, in fact. |
| `evals/filer/corpus-*.json` (Thiel day, meme day, Jamie, Brother Hansen) | Term test data exercising type functions. Ship the harness + an anonymized starter corpus; Sam's corpus stays his. |
| Window instances + config: which windows exist, `role_map`, `semantics` regimes, `filters`, edge channel choice (iMessage), allowlisted handles | Term. **Found leak:** `0008` seeds `edge-imessage` + `window-gcal` (with Sam's `commitment_strength: tentative`) as if type — tolerated at v0, moves to a term seed at the packaging milestone (queue). |
| Directives, role_clearances rows, tuned parameter values, all DB life-plane data, `wiki/` content | Term. |
| `docs/sam-examples.md`, CONTEXT.md "Who Sam is" | Term documentation. |
| Sam's deploy choices (Mac mini, launchd, backup destination) | Term deployment; type stays POSIX-portable (00 §Portability). |

### Gray calls, ruled

- **gcal semantics** — the debate that triggered this. Sam uses gcal as a *planner* (tentative; drift against it is mirror signal); another user's gcal is *truth*. Both are valid terms. Ruling: `commitment_strength` (and all per-source trust/meaning) is term config under the type's `semantics` mechanism. The type assumes only: a window declares what its data *means*; it never assumes what a calendar *is*.
- **Mirror prompt** — the mirror slot, elicitation protocol, and intent-binding are type; the elicited content is term. The prompt file must keep those separable.
- **Spec examples** — illustrative term inside type docs: keep (P8 favors concrete examples), but each normative sentence must survive s/Sam/any-user/.
- **The brief's 7am cron, two-week P2 clock, role names in fixtures** — term values riding type mechanisms; all configurable.

## Regimes: terms are mutable in time

The type must be robust to **different terms** (independence) and to **the same term changing** (mutability). A term value that interprets data is therefore *dated*, not scalar: `semantics` becomes a list of regimes `[{"effective_from": ts, ...values}]`. Interpretation of any capture uses the regime in force at `intake.received_at` — if gcal flips from planner to truth in 8 months, new captures read under the new regime and historical questions answer under the old one. No accessor is built until the first real regime change (grow by promotion; queue item). Role retirement (`status`) and link supersedence already follow this pattern; regimes extend it to window meaning.

## Packaging path (how this ships)

Sam's distribution directive (2026-06-12 evening): **installed, never forked.** Users don't clone-and-run-with-it; they install a versioned type they cannot edit and author their term beside it. Maintainers (Sam +, if ever public) edit type upstream; releases propagate to installs without touching any term. Full model: `specs/07 §Distribution`, `specs/00 P11`, `specs/04` install guarantee.

1. **Now (directive)** — P11 + this audit; every future decision states its side of the line. New-user story, stated as the target: *install the type → run the elicitation (produces the purpose contract + roles) → register windows (role_map, semantics, filters per their life) → done.* Onboarding IS term-authoring; there is no other setup.
2. **P2 (while building the daily loop)** — keep the line visible in code review; no restructure mid-loop. Term-building sessions (the custom dashboard) run in their own repos against L1, never inside this checkout.
3. **Packaging milestone (post-P2 gate)** — the physical split: type repo (specs/, core/, contract tests, installer, updater) vs Sam's private term repo (seeds, window instances, Sam corpus, dashboards, deploy choices); installed type core-owned read-only to everyone including Sam's login session; `0008` roster trimmed to required slots; migrations go append-only; anonymized starter corpus authored from the type's needs, not Sam's data. Acceptance test = the fork test: using-and-term-building must be strictly easier than forking, even for a senior dev.

## The standing question for every future decision

> What are we assuming about how the user uses this? If the answer is anything but "nothing," the assumption goes in the term.
