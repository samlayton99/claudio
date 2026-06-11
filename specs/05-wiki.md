# 05 — Wiki

Two prose stores: `wiki/` (the **portrait** — the canonical written image of the life) and `memory/` (gardener continual-learning; small; recurring lessons promote to directives or code, never hoard).

## Boundary rule

> The DB stores what agents **query**; the wiki stores what agents **read**.

Enforced both directions: DB summaries `CHECK ≤ 500` chars; pages soft-capped ~1,500 words (oversize ⇒ split proposal). A page full of statuses/dates, or a DB text column with paragraphs, is a rule violation lint flags.

## The portrait

From the wiki it should be obvious: who matters most, priorities, goals and progress, history, who has been there and who has wronged, projects, failures, successes, learning, people to meet. Root self page anchors; role/person/goal/topic pages carry weight; grown gradually from atoms, seeded from `About_Me.md`.

Wikipedia discipline:
- **Citations**: factual claims carry dated refs to atoms/tier-0 (`[[log:uuid]]` short-form). Citing is pointing, never restating.
- **History**: git is the page-history; every edit commits as the acting worker (committer = worker name).
- **Judgment attribution**: characterizations of people/feelings are user-authored or user-approved, sourced to the user's own statements. Agents propose with evidence; never assert the moral ledger. (P5, P7)
- **Verification**: the verifier gardener re-derives claims from cited sources in fresh context (never the author); unsourced/contradicted ⇒ proposal.

## Page kinds (typed prose)

| kind | anchor | required sections |
|---|---|---|
| `person` | people.id | Summary · Relationship & context · Highlights (cited) · Links |
| `role` | roles.id | Summary · Why it matters (goals) · Current state · Pointers (people, projects, automations) |
| `topic` | parent page or role | Summary · Narrative (cited) · Links |
| `event` | log.id (umbrella atoms) | What happened · Who · Outcomes (cited) |
| `index` | role or root | curated MOC list — the hierarchy |
| `digest` | component | generated rollups (briefs, weekly reviews) |

Frontmatter v0 (minimal; deliberately unfrozen — questions-queue #1): `title, kind, entity, tags, updated, sensitivity(≤1)`.

## Cleanliness rules (enforced, not hoped)

1. **Anchored**: every page anchors to a DB entity or parent page; entity pages unique by `documents` constraint. No orphans by construction.
2. **L1 file writes**: create/rename/move only via `register_page`-class functions — naming, frontmatter, registration, atomic inbound-link rewrite on rename.
3. **Dedup at creation**: title+alias search first; near-match ⇒ proposal, not a page.
4. **Flat folders, link hierarchy**: directories by kind only; hierarchy lives in `index` pages (items belong to multiple hierarchies; folder taxonomies rot).
5. **One fact, one home** (lint heuristic + wiki gardener rewrite).
6. **Lint is a pipe**: frontmatter valid, links resolve, kinds honored, sizes in range, registered, no sensitivity-2 content patterns. Failures queue to the wiki gardener.
7. **Freshness computed**: `documents.freshness` vs new atoms on the anchor; drift queues refresh.
8. `document_links` mirrors `[[wikilinks]]` (maintained by the same L1 write path + lint check) — graph queries are SQL; the wiki stays self-navigable without the DB (decay test for prose).

## Wiki gardener procedure (daily)

1. New canonical atoms since last run, grouped by anchor (person/role/event).
2. For each touched anchor: update page Highlights/Current with cited additions; create missing entity pages (people with ≥3 atoms or user-flagged — P7: not every contact deserves a page).
3. Published artifacts (Sam's substack example): place under the right role/topic, link both ways, note relation to goals.
4. Maintain `index` pages + backlink sections; report to lint.

Judgment claims (anything characterizing a person beyond cited fact) go to proposals, not pages.
