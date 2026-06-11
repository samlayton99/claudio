# 05 — Wiki

`wiki/` is the **portrait**: the canonical written image of the life — who matters most, priorities, goals and progress, history, who has been there and who has wronged, projects, failures, successes, learning, people to meet. Root self page anchors it (seeded from `About_Me.md`); role/person/goal/topic pages carry the weight; grown gradually from atoms. Maintaining it clean and healthy is core product function #2 — and it is what makes the context packets good (function #3): rollups are the hot path of context.

There is no separate `memory/` store: gardener lessons promote to directives (taste), component config, or docs — never a private prose pile (decay test).

## Boundary rule

> The DB stores what agents **query**; the wiki stores what agents **read**.

Enforced both directions: DB summaries `CHECK ≤ 500` chars; pages soft-capped ~1,500 words (oversize ⇒ split proposal). A page full of statuses/dates, or a DB text column with paragraphs, is a violation lint flags.

## Wikipedia discipline

- **Citations**: factual claims carry dated refs to atoms/tier-0 (`[[log:uuid]]`). Citing is pointing, never restating.
- **History**: git is the page history; every edit commits as the acting worker.
- **Judgment attribution**: characterizations of people/feelings are user-authored or user-approved, sourced to the user's own statements. Agents propose with evidence; never assert the moral ledger. (P5, P7)
- **Verification**: the verifier re-derives claims from cited sources in fresh context (never the author); unsourced/contradicted ⇒ proposal. Manual-trigger in v0; promoted to cron if real drift appears.

## Page kinds (typed prose)

| kind | anchor | required sections |
|---|---|---|
| `person` | people.id | Summary · Relationship & context · Highlights (cited) · Links |
| `role` | roles.id | Summary · Why it matters (goals) · Current state · Pointers |
| `topic` | parent page or role | Summary · Narrative (cited) · Links |
| `event` | log.id (umbrella atoms) | What happened · Who · Outcomes (cited) |
| `index` | role or root | curated MOC — the hierarchy |
| `digest` | component (`entity_id='<component>/<period>'`) | generated rollups |

Frontmatter v0 (minimal, deliberately unfrozen — questions-queue): `title, kind, entity, tags, updated, sensitivity (≤1)`.

## Write path (honest version)

L1's `register_page`/`move_page` own the `documents` rows; the file half is **`wiki-tool`** — a core-owned CLI (registered component, the only *sanctioned* file writer) that performs the file op + the L1 call as one step, including atomic inbound-link rewrite on rename. Workers (w1 only) could technically write `wiki/` directly — **lint is the enforcement**: unregistered, malformed, or convention-violating files are flagged to the wiki gardener and the panel. Sanctioned path + deterministic detection, not false claims of impossibility.

## Cleanliness rules

1. **Anchored**: every page anchors to a DB entity or parent page; entity pages unique by the `documents` constraint. No orphans, no duplicate person pages.
2. **Dedup at creation**: title + alias search (`person_handles` `source='alias'`) first; near-match ⇒ proposal, not a page.
3. **Flat folders, link hierarchy**: directories by kind only; hierarchy lives in `index` pages (items belong to multiple hierarchies; folder taxonomies rot).
4. **One fact, one home** (lint heuristic + gardener rewrite).
5. **Lint is a pipe** (w0, daily): frontmatter valid, `[[wikilinks]]` resolve, kinds/sections honored, sizes in range, registered in `documents`, no sensitivity-2 patterns, backlink sections current, orphan scan. **Lint parses files directly — there is no `document_links` mirror table** (the files are authoritative; promote a table only when a real SQL graph query shows up).
6. **Freshness computed**: `documents.freshness` vs new atoms on the anchor; drift queues refresh.

## Wiki gardener procedure (w1, daily)

1. New canonical atoms since cursor, grouped by anchor.
2. Touched anchors: update Highlights/Current with cited additions; create entity pages only past the threshold (people with ≥3 atoms or user-flagged — P7: not every contact deserves a page).
3. Published artifacts (`kind='artifact'`): place under the right role/topic, link both ways, relate to goals (`advances` proposals where plausible).
4. Maintain `index` pages + backlink sections; hand violations to lint's report.
5. Judgment claims → proposals, never page text.
