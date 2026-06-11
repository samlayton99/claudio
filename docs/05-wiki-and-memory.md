# Wiki & Memory

Two prose stores, one per plane.

- **Life wiki** (`wiki/`) — narrative knowledge of the life: person pages, role pages, ongoing situations, projects, trips. Read by the user and by agents.
- **System memory** (`memory/`) — the gardeners' continual learning: filing lessons, source quirks, what worked. Deliberately small. Pruning rule: a recurring lesson gets **promoted** into a directive or a code fix, never hoarded as prose.

## The boundary rule (DB vs wiki)

> The DB stores what agents **query**; the wiki stores what agents **read**.

Filter, count, traverse mechanically → row. Read to understand → page. The DB is the scaffold; entities carry high-level summaries and dense pointers into the wiki, where specific knowledge lives.

Enforced mechanically in both directions: DB summary columns are `CHECK`-length-bounded (~500 chars — compaction enforced by the type system); wiki pages are soft-capped (~1,500 words — oversize triggers a gardener proposal to split into linked subpages).

## Typed prose: page kinds

A closed set of kinds, each a contract — required frontmatter, required sections, allowed link targets, expected size: `person`, `role`, `topic`, `event`, `index` (MOC), `digest`. Adding a kind is a proposal, like promoting schema. Templates make pages predictable to write and to read.

## Cleanliness rules (enforced, not hoped)

1. **Anchoring.** Every page anchors to a DB entity or a parent page. Entity pages are unique by constraint (`documents` unique on kind + entity_ref) — a duplicate person page cannot exist. No orphans by construction.
2. **File writes go through L1.** Pages are created/renamed/moved only via functions that enforce naming, frontmatter, `documents` registration — and rewrite inbound links on rename, atomically. Single-write-path, extended to files.
3. **Dedup at creation.** Topic pages are the duplicate risk: creation searches titles + aliases first; a near-match becomes a proposal, not a new page. Same pattern as person dedup.
4. **Flat folders, link hierarchy.** Directories by kind only (`wiki/people/`, `wiki/topics/`, ...). Hierarchy lives in index (MOC) pages and links — items belong to multiple hierarchies; folders-as-taxonomy is how wikis rot. Categories and filters come from frontmatter kind/tags, queryable via `documents`.
5. **One fact, one home.** Facts that exist as rows (dates, statuses) are not restated in prose except as narrative. Lint heuristics flag; the wiki gardener rewrites.
6. **Lint is a pipe.** A deterministic validator (frontmatter valid, links resolve, kinds honored, sizes in range, registered) runs on schedule; failures queue for the wiki gardener. No LLM for checking.
7. **Staleness is computed.** `documents.freshness` vs new log atoms on the linked entity; drift queues a refresh.

## Traversal & the assembler

Traversal conventions: `[[wikilinks]]` between pages (the wiki is self-navigable without the DB — decay test applied to prose); index pages per role; backlink sections; `document_links` mirrors the wikilink graph into SQL so graph queries (backlinks, orphans, hubs) are cheap.

The **assembler** is the second keystone agent — the filer writes, the assembler reads. Context gathering is a defined procedure, not wandering:

1. Resolve the anchor (role/person/goal/workflow) → rows + canonical pages.
2. Budgeted graph expansion over DB links + `document_links`, in SQL — reading only summaries and frontmatter at the frontier.
3. LLM judges relevance only at the frontier, only on summaries; full pages open only for top-scoring nodes.
4. Synthesize the context packet with citations (refs) so consumers can drill.

Token budget is a first-class parameter of `get_context`. Like the filer, the assembler is built against an eval corpus (morning-brief assembly, meeting prep, "what's going on with X").

pgvector / semantic search / graph algorithms: promote-on-need, not foundation.

## Open

Frontmatter spec on hold — review prior art (Obsidian conventions, agent-memory systems) before freezing.
