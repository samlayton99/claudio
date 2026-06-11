# Wiki & Memory

Two prose stores, one per plane.

- **Life wiki** (`wiki/`) — narrative knowledge of the life: person pages, role pages, ongoing situations, projects, trips. Read by the user and by agents.
- **System memory** (`memory/`) — the gardeners' continual learning: filing lessons, source quirks, what worked. Deliberately small. Pruning rule: a recurring lesson gets **promoted** into a directive or a code fix, never hoarded as prose.

## The boundary rule (DB vs wiki)

> The DB stores what agents **query**; the wiki stores what agents **read**.

Filter, count, traverse mechanically → row. Read to understand → page. DB rows stay skinny (one-line summary + links + pointers) because the wiki absorbs depth — this is what prevents bloat on both sides. The DB is the scaffold; roles and entities carry high-level summaries and dense pointers into the wiki, where the specific knowledge of what's going on in life lives. A wiki page full of statuses and dates, or a DB text column with three paragraphs, means the rule was violated.

## Traversal

Conventions, not an engine (prior art deliberately copied from Obsidian: plain files, wikilinks, maps-of-content):

- Plain markdown with frontmatter: `title, kind, db_refs, tags, updated`.
- `[[wikilinks]]` between pages. The wiki is **self-navigable without the DB** — an agent handed only the folder can orient (decay test, applied to prose).
- Index pages (maps-of-content) per role; backlink sections on every page — both maintained by the wiki gardener, since agents are bad at remembering to link and great at batch-fixing links.
- `document_links` mirrors the wikilink graph into the DB, so graph queries (backlinks, orphans, hubs) are cheap SQL. Traversal works in both directions for the cost of one gardener job.

pgvector / semantic search / graph algorithms: promote-on-need, not foundation. Backlinks + hub pages cover ~90% of what graph machinery promises.

## Open

Review prior art (Obsidian conventions, agent-memory systems) before freezing the frontmatter spec.
