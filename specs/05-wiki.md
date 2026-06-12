# 05 — Wiki

`wiki/` is the **biography**: consolidated source material for understanding the life — not a mirror of the database. The DB is the 1:1 record (atoms); the wiki is what a person (or agent) reads to understand. The bar for a page: *would Sam, Sam-in-6-months, or someone in Sam's circle find this interesting or useful?* Default-no (P7); the content stays reachable through atoms regardless.

Substrate (research-validated): plain markdown, wikilinks, minimal frontmatter, git history, flat folders — every surviving PKM system is plain files, and "AI tools need direct file access" is now the top migration driver (research-wiki §1). Never add syntax or state the files can't natively carry.

## Chapters (the fixed top level)

Ten chapter MOCs — stable overlay maps, the one structure pattern that survives (research-wiki §2):

`people` · `personal-life` · `significant-events` · `professional` · `purpose` (beliefs over time; lived-vs-proclaimed discrepancies) · `progress` · `interests` · `lessons-learned` · `pitfalls` (problems I keep causing myself) · `how-to-work-with-sam` (agent-facing: the system learns the person)

**`how-to-work-with-sam` is taste-plane, not wiki-plane** (red-team finding 5: a page that steers agent behavior is a directive surface and must be governed like one): it is *rendered from* the directives table + user-asserted spans — gardeners never free-delta it, and behavioral guidance lives only behind the dictation gate. What gardeners may propose for it goes through proposals like any taste write.

Rules: **every page reachable from a chapter in ≤ 2 hops**; every page names its chapter at creation (`documents.chapter`); below chapters, structure emerges only at squeeze points — never pre-built taxonomy. Folders stay flat by kind; hierarchy lives in chapter/index pages.

## Page discipline (anti-accretion — the #1 documented AI-wiki failure)

- **The scarce resource is the owner's reading appetite, not storage.** Page creation requires: the chapter that links it AND `read_moment` — the future moment it gets read ("before PROD demo day", "when planning Q3"). Can't name one ⇒ no page.
- Entity thresholds: people get pages at ≥ 3 atoms or user flag; same gate for topics/events. **No pages for routine DB events** — an investor meeting is an atom + a line (with pointer) on the relevant page; a wedding or a death is a `significant_event` page.
- **Demotion sweep** (hygiene, P5+ — pages must age before they can demote; the P4 gate measures sublinearity, the sweep enforces it later): pages unread and uncited by digests for N months merge back into their parent; page count must grow sublinearly with atoms.
- Atoms can be cited by multiple pages; ≤ 1,500-word soft cap; the first three sentences of every page must stand alone (the lede is what actually gets read).

## Writing discipline (P8 made mechanical)

- **Raw atoms always in context**: any page update is prompted with the update reason, the previous version, and the full relevant atom list — never from another summary.
- **Delta edits only**: patch sections, append cited lines; full-page regeneration only via proposal (full rewrites cause documented "context collapse").
- **Digests re-derive from atoms every time** — the brief's daily digest page and the weekly state-of-life page never read prior digests. Absolute dates only.
- **Citations are load-bearing**: factual claims carry dated `[[atom:uuid]]` refs. Lint verifies cited atoms *exist*; the **verifier step** (chained on the wiki gardener's run in a fresh context that is never the author) samples that atoms *support* claims — fabricated/mis-anchored citations are the single most documented AI-wiki defect. It becomes a separately-scheduled component only if scale demands it.
- **Judgment attribution**: characterizations of people/feelings are user-authored or user-approved, cited to the user's own statements. Agents propose; never assert the moral ledger.
- **Human corrections are immutable spans**: user-asserted text (panel edits, dictated corrections — marked, e.g. cited to `[[user:date]]`) may be *moved* but never *reworded* by any gardener. On correction, walk the citation graph and flag dependent claims (poisoned facts propagate one-to-many).
- **Anti-slop gate in lint**: Wikipedia's "signs of AI writing" heuristics (puffery, stock phrases); voice drift is fatal because the human is the error-correction loop and people only correct what they read.

## Boundary rule (amended)

> The DB stores what agents **query**; the wiki stores what agents **read**.

DB rows stay skinny (≤500-char summaries) but must be *descriptive* — naming, comments, examples carry the scaffolding load; skinny ≠ cryptic. Pages absorb narrative depth. A page full of statuses, or a DB column with paragraphs, is a lint violation.

## Freshness & correction surface

`documents.freshness` vs new atoms on the anchor computes drift; the panel renders freshness loudly (stale and fresh pages must not look identical) with **one-tap "this is wrong" at the point of reading** — opportunistic correction-while-reading is the only review habit that survives. Corrections arrive as held questions or direct user-asserted edits.

## Write path

`register_page`/`move_page` (L1) own `documents`; the file half is `wiki-tool` (core-owned CLI, the sanctioned writer). Crash order is defined, not wished: **DB first, file second, lint reconciles drift** — filesystem and database cannot be jointly atomic, so the invariant is "a registered page may briefly lack its file, never the reverse." Lint (w1, daily) is the enforcement: frontmatter valid, links resolve, chapters honored, sizes in range, citations exist, no sensitivity-2 content, anti-slop, orphan scan (orphan = unreachable from a chapter in ≤2 hops). No `document_links` mirror; no graph features — search and chapter navigation are the real read paths.

Frontmatter v0 (few, composable keys — resist growth): `title, kind, chapter, entity, tags, updated, read_moment, sensitivity(≤1)`.

## Proposal economy

The proposal queue is the owner's weekly review, and the weekly review is the first habit humans drop: proposals **dedup** (no re-proposal piles) and **auto-expire** stale. That's the whole mechanism — a cap parameter gets added if observed volume ever exceeds what one phone session clears; impact-ranking requires an impact model nobody has (over-engineering pass).
