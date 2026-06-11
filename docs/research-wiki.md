# Research: Why Personal Wikis Succeed or Fail

Deep-research survey (2026-06-11; GitHub numbers fetched live via API) of PKM tools, community practice, failure modes, and LLM-maintained-wiki prior art, to pressure-test claudio's wiki design (`specs/05-wiki.md`). Bracketed numbers cite sources listed at the end.

## 1. Winners and losers

| Tool | Status 2026-06 | Evidence |
|---|---|---|
| Obsidian | Winner. Est. 5-10M users (CEO; no telemetry), ~9-person team, no VC, 2,000+ plugins | [1][2][3] |
| Notion | 100M users (2024) — mass-market cloud workspace, but the thing PKM users migrate *away from* when data ownership matters | [4] |
| TiddlyWiki | Quiet winner: 22 years continuous (2004→), 8.6k stars, v5.4.0 shipped 2026-04 | [5] |
| Logseq | Cautionary: 43k stars but frozen — markdown→database rewrite begun ~2022 still beta; officially split into two versions 2026-05; users bleeding to Obsidian | [6][7][8] |
| org-roam | Alive but stagnant: 6k stars, sole-maintainer burnout, open "maintenance status?" issue | [9] |
| Roam | Fall: $200M seed valuation 2020 → "The Fall of Roam" by 2022 ("a garbage dump full of crufty links... we hardly ever revisit"), hollowed community, ~10 staff | [10][11][12] |
| Dendron | Dead by announcement 2023 (founder burnout + "not able to find product market fit"). **Correction to premise: repo is NOT archived** (`archived:false`, 7.4k stars) — it entered maintenance mode | [13][14] |
| Foam / Zettlr / Quartz | Niche plateaus: 17k / 13k / 12k stars; Foam+Dendron capped by requiring VS Code; Quartz healthiest as a garden *publisher* | [15] |
| gollum / DokuWiki | Lost personal use to markdown vaults: "the sole user of a wiki... made little sense to keep a service running when one could just have some Markdown files locally" | [16] |
| Evernote | Killed by owner: staff gutted 2023, ~2x price hike, 50-note free tier | [17] |

**Design principles that actually mattered:**
- **Data outlives the app.** Every survivor is plain files (markdown, org plaintext, one HTML file); every casualty was cloud/proprietary (Roam, Evernote) or needed a developer container (Dendron/Foam→VS Code, gollum→server) [2][5][13][16].
- **2026 twist:** the top stated Roam→Obsidian migration reason is now *AI tools need direct file access*: "Data locked in the cloud — AI tools couldn't access it" [18]. An agent-written markdown wiki sits exactly on this trend.
- **Don't fight the file substrate.** Logseq's block model required IDs/state markdown couldn't carry, forcing a 3.5-year DB rewrite that froze the product [7][8]. Keep pages plain prose + wikilinks + frontmatter, nothing cleverer.
- **Stars track hype, not longevity.** Logseq 43k stars stalled; TiddlyWiki 8.6k stars thriving for 22 years. The file format, not the app, is the contract [5][6].

## 2. Convergent community wisdom (structure, granularity, linking, maintenance)

- **Flat folders won.** The recurring failure of PARA/Johnny-Decimal/deep trees is the single-location constraint: "a file can only be in one folder... moving files from folder to folder" is pure maintenance [19][20]. Obsidian's CEO keeps a near-flat vault; 3-year retrospectives say max 2-3 levels [20][21]. Claudio's flat-folders-by-kind + index pages is exactly the convergent practice.
- **Structure emerges at the "mental squeeze point," never up front** [22]. MOCs are "nondestructive, non-restrictive" heterarchical overlays — multiple maps over the same note [22]. Up-front taxonomy is the most-warned-against meta-work: "digital hoarding disguised as productivity" [21].
- **Granularity:** Matuschak's evergreen canon — atomic, concept-oriented, densely linked, "prefer associative ontologies to hierarchical taxonomies" [23]. But the 2025 correction from zettelkasten.de: atomicity is an *outcome*, not an input gate; enforcing it at capture "nudges us to underdeveloped notes" [24]. Biography-feel chapter pages are concept-oriented; that beats atomic-note confetti for a portrait.
- **Titles are APIs:** complete-phrase, claim-bearing titles ("Educational objectives often subvert themselves") force clear pages and stable link targets [23].
- **Linking:** link profusely at write time, including to pages that don't exist yet [19]. But the *global graph is decoration* — community verdict is it's unusable past a few hundred notes; actual retrieval is search + local backlinks [25]. Don't invest in graph features; invest in retrieval.
- **Metadata:** properties became first-class in Obsidian 1.4 (2023) [26]; Dataview's top-tier adoption (~millions of downloads) proves frontmatter-querying is mainstream [27]. Convention that survived: few, reusable, composable keys; tags as status/type signals, not topic taxonomy (topics are pages) [19]. Claudio's 6-key frontmatter fits; resist key growth.
- **Daily notes won because capture is zero-decision** [19]; weekly/monthly rollups are the GTD review ported to PKM (Periodic Notes plugin) [28] — but for humans "the Weekly Review is the hardest habit to achieve and the main reason why people no longer stay organized" [29]. The pattern is right and the human execution is the broken part — ideal to delegate to agents.
- **Negative finding:** no measured statistics exist on orphan rates or "% of notes never read again"; circulating numbers (e.g., "wiki accuracy decays to 12%") trace to no study. Don't cite them; assume anecdote [25][30].

## 3. Failure modes, ranked by likelihood for an agent-written / human-read wiki

Prior art first: **nobody has shipped a beloved agent-maintained personal wiki yet.** Obsidian's AI ecosystem is retrieval-first (Smart Connections, ~1M installs, read-only [31]; Copilot edits only on user trigger [32]; Obsidian keeps AI out of core [33]). The closest precedents are agent memory systems (Mem0 58k stars, Letta 23k [34]; A-MEM is literally an agentic Zettelkasten that rewrites old notes as new ones arrive [35]) and auto-generated wikis (Cognition's DeepWiki [36]) — and both document the same degradations:

1. **Unbounded accretion** — near-certain. Writing costs agents nothing, so the collector's fallacy ("'to know about something' isn't the same as 'knowing something'" [37]) runs at machine speed. The human end state is Westenberg deleting 10,000 notes: "my second brain became a mausoleum... old selves... piled on top of each other" [30]. The scarce resource is the owner's reading appetite, not storage.
2. **Staleness + contradiction accumulation** — certain without scheduled consolidation. Claude Code's markdown memory "after 20 sessions... cluttered with contradictory entries, stale debugging notes referencing deleted files, and relative timestamps like 'yesterday'" [38]; both Anthropic and OpenAI converged on background consolidation passes (prune, merge dupes, absolutize dates) as the fix [38][39]. And staleness is invisible: "nothing visually distinguishes a page reviewed last week from one... never touched since" [40].
3. **Lossy re-summarization drift** — high if summaries feed summaries. Iterative compression "silently discards low-frequency details"; documented semantic intensification ("mild spicy" → "very spicy") [41]. Mitigation in the literature: append-only ground truth + views re-derivable from it [41][42].
4. **Mis-anchored or fabricated citations** — high. The #1 defect Wikipedia's AI Cleanup catalogs: fully fake sources, real-but-off-topic citations, an AI hoax article that survived 11 months; escalated to speedy-deletion criterion G15 (July 2025) for unreviewed LLM text [43]. DeepWiki's analog: confident wrong docs because the model "fixates on large files or outdated configurations" [36].
5. **Duplication / near-duplicate pages** — high; merging dupes is a core step of every memory-consolidation fix [38][39]. Claudio's dedup-at-creation addresses the front door; consolidation must catch the rest.
6. **AI-slop voice → owner stops reading** — medium-high, and fatal: in this design the human is the error-correction loop, and people only correct what they read [40]. Wikipedia's tells: puffery, stock phrases ("testament," "underscores the importance") [43]; lifelogging summarizers drift "generic" [36].
7. **Poisoned writes propagate** — medium frequency, high severity: one wrong stored fact has "a one-to-many effect across later conversations" and gains authority each rewrite [39][41].
8. **Over-structuring** — medium: agents told to "organize" will deepen hierarchies and spawn MOCs; folder taxonomies and premature structure are how human vaults rot [19][20][22].
9. **Orphans / link rot** — low-medium: claudio's anchoring constraint + lint covers the classic case; redefine orphan as "unreachable from a chapter page."
10. **Human review fatigue** — low-medium: proposal queues are claudio's weekly review; the review habit is the first thing humans drop [29], so queue volume needs a budget too.

## 4. Recommendations for claudio (current design is mostly validated; these adjust it)

1. **Keep: flat folders, plain markdown, wikilinks, minimal frontmatter, git history.** This is the surviving substrate [2][5][19] and rides the 2026 AI-needs-files trend [18]. Logseq's lesson: never add syntax or state the files can't natively carry [7].
2. **Make the owner's ~10 biography chapters the fixed top level** (people, personal life, significant events, professional life, purpose, progress, interests, lessons learned, pitfalls, how-to-work-with-me). These are MOCs — stable heterarchical overlays [22] — and concept-oriented portrait beats DB mirroring [23]. Rule: every page reachable from a chapter in ≤2 hops; below chapters, structure only at squeeze points, never pre-built [22].
3. **Budget pages against reading appetite, not data volume.** The "interesting in 6 months" bar is the anti-collector's-fallacy test [37][30] — enforce it: at creation the gardener must name the chapter that links it and the future moment it gets read; add a demotion cron (pages uncited by digests/unread for N months merge into their parent). Page count should grow sublinearly with atoms; entity-page thresholds (≥3 atoms) are right, extend the same gate to topics/events. Explicitly drop 1:1 DB mirroring — DeepWiki failed by mirroring structure instead of answering reader questions [36].
4. **Periodic digests are the killer feature — generate each one fresh from atoms, never from prior digests.** Weekly/monthly/biannual state-of-life pages match the proven Periodic Notes pattern [28], and agents fix its known failure (humans skip reviews [29]). Re-derive from the append-only log to dodge summarization drift [41][42]; absolute dates only — relative timestamps are a documented decay vector [38].
5. **Double down on citation discipline with writer/verifier separation.** Fabricated and mis-anchored references are the single most documented AI-wiki defect [43][36]. Lint must check cited atom IDs *exist*; the verifier (never the author) must sample that atoms *support* the claim — claudio's spec already says this; evidence says it's load-bearing, promote verification to cron early.
6. **Make human corrections immutable spans.** Memory systems show corrections get silently re-summarized away and errors re-assert [39][41]. Mark user-authored text (e.g., cited to `[[user:...]]`) as content gardeners may move but never reword; on correction, walk the citation graph to find and flag dependent claims (poisoning is one-to-many [41]).
7. **Add an anti-slop style gate to lint.** Use Wikipedia's "signs of AI writing" patterns (puffery, stock phrases) as lint heuristics [43]; keep the ≤1,500-word cap; require the first ~3 sentences of every page to stand alone — the lede is what the owner actually reads.
8. **Render freshness and provenance loudly; put the correction affordance at the point of reading.** Stale and fresh pages look identical [40], and opportunistic correction-while-reading is the only review habit that survives in practice [29][40]. Show `updated`, drift badge vs. anchor atoms, and one-tap "this is wrong" on every page.
9. **Skip graph features; invest in search and chapter navigation.** Backlink sections and profuse links are cheap for agents and useful locally, but global graphs are decoration [25]; retrieval-by-search is how surviving vaults are actually used [25][30].
10. **Cap the proposal queue.** The human's only duties are reading and adjudicating; if proposals pile up like a GTD weekly review, they'll be abandoned like one [29]. Budget proposals per week, rank by impact, auto-expire stale ones.

## Sources

1. kepano (Obsidian CEO), user estimate — https://mastodon.social/@kepano/114871343744754732 (2025)
2. Steph Ango, "File over app" — https://stephango.com/file-over-app (2023; quote verified)
3. Obsidian manifesto/team — https://obsidian.md/about
4. Notion 100M users — https://www.notion.com/blog/100-million-of-you (2024)
5. TiddlyWiki — https://api.github.com/repos/TiddlyWiki/TiddlyWiki5 (fetched 2026-06-11); https://talk.tiddlywiki.org/t/tiddlywiki-is-almost-20-years-old/8068
6. Logseq repo — https://api.github.com/repos/logseq/logseq (43,342 stars; fetched 2026-06-11)
7. Logseq DB-version rationale — https://github.com/logseq/docs/blob/master/db-version.md
8. Logseq two-version split — https://discuss.logseq.com/t/whats-new-with-logseq-db-may-16th-2026/35020 (2026-05-16)
9. org-roam — https://api.github.com/repos/org-roam/org-roam; https://github.com/org-roam/org-roam/issues/2375
10. Roam $200M seed — https://pitchbook.com/newsletter/roam-raises-seed-round-at-200m-valuation (2020)
11. Dan Shipper, "The Fall of Roam" — https://every.to/superorganizers/the-fall-of-roam (2022; quotes verified)
12. Roam community decline — https://www.outlinersoftware.com/topics/viewt/10622 (2024); https://www.cbinsights.com/company/roam-research/people
13. Dendron shutdown announcement — https://github.com/dendronhq/dendron/discussions/3890 (2023)
14. Dendron repo (not archived) — https://api.github.com/repos/dendronhq/dendron (verified 2026-06-11)
15. Foam / Zettlr / Quartz — https://api.github.com/repos/foambubble/foam; /Zettlr/Zettlr; /jackyzha0/quartz (fetched 2026-06-11)
16. DokuWiki→Obsidian migrations — https://blog.ivansmirnov.name/moving-from-dokuwiki-to-obsidian/; https://kaeruct.github.io/posts/2024/08/18/migrating-from-dokuwiki-to-obsidian/
17. Evernote under Bending Spoons — https://techcrunch.com/2023/02/27/bending-spoons-lays-off-129-evernote-staffers/; https://techcrunch.com/2023/11/27/evernote-pushes-users-to-upgrade-with-test-of-a-free-plan-limited-to-only-50-notes/
18. Roam→Obsidian for AI file access — https://yu-wenhao.com/en/blog/roam-research-to-obsidian/ (2026-01)
19. Steph Ango's vault conventions — https://stephango.com/vault
20. "The PARA method and the hard facts of life" — https://forum.obsidian.md/t/the-para-method-and-the-hard-facts-of-life/22279 (2021)
21. 3-year vault retrospective — https://www.makeuseof.com/i-wish-i-knew-these-before-creating-my-obsidian-vault/ (2025)
22. Nick Milo, MOCs — https://notes.linkingyourthinking.com/Cards/MOCs+Overview
23. Matuschak, evergreen notes + titles — https://notes.andymatuschak.org/Evergreen_notes; https://notes.andymatuschak.org/Prefer_note_titles_with_complete_phrases_to_sharpen_claims
24. Sascha Fast, atomicity as outcome — https://zettelkasten.de/posts/principle-of-atomicity-difference-between-principle-and-implementation/ (2025)
25. Graph-as-decoration + search-beats-structure — r/ObsidianMD consensus via https://codeculture.store/blogs/developer-culture/obsidian-graph-view-useful (low-confidence aggregator) + HN testimony in [30]
26. Obsidian Properties (v1.4.5) — https://obsidian.md/changelog/2023-08-31-desktop-v1.4.5/
27. Dataview adoption — https://www.obsidianstats.com/plugins/dataview (exact count tracker-dependent)
28. Periodic Notes plugin — https://github.com/liamcain/obsidian-periodic-notes
29. Weekly review failure — https://facilethings.com/blog/en/weekly-review-feature
30. Westenberg, "I Deleted My Second Brain" — https://medium.com/westenberg/i-deleted-my-second-brain-b7a65bce3717 (2025); HN discussion https://news.ycombinator.com/item?id=44402470
31. Smart Connections (retrieval-only) — https://github.com/brianpetro/obsidian-smart-connections (~1M downloads)
32. Obsidian Copilot — https://github.com/logancyang/obsidian-copilot (7.2k stars)
33. Obsidian's AI stance — https://stephango.com/obsidian
34. Mem0 paper + repos — https://arxiv.org/abs/2504.19413 (verified); https://api.github.com/repos/mem0ai/mem0; https://api.github.com/repos/letta-ai/letta
35. A-MEM (agentic Zettelkasten) — https://arxiv.org/abs/2502.12110 (verified)
36. DeepWiki accuracy failures — https://finance.biggo.com/news/202508270142_DeepWiki_Accuracy_Concerns (2025-08); Limitless summary quality https://thoughts.jock.pl/p/voice-ai-hardware-limitless-pendant-real-world-review-automation-experiments
37. Collector's fallacy — https://zettelkasten.de/posts/collectors-fallacy/ (2014)
38. Claude Code memory decay + consolidation — https://blog.laozhang.ai/en/posts/claude-code-memory; https://milvus.io/blog/claude-code-memory-memsearch.md; https://claudefa.st/blog/guide/mechanics/auto-dream (unofficial docs)
39. ChatGPT memory poisoning + background re-synthesis — https://www.techbuzz.ai/articles/chatgpt-s-memory-feature-silently-poisons-answers-with-bad-data; https://every.to/also-true-for-humans/why-i-turned-off-chatgpt-s-memory
40. Wiki staleness invisible / Confluence rot — https://community.atlassian.com/forums/App-Central-articles/Your-Confluence-wiki-is-confidently-giving-people-wrong/ba-p/3192612 (vendor); https://dev.to/pabloportugues/confluence-is-where-information-goes-to-die-25n
41. Memory drift literature — SSGM https://arxiv.org/abs/2603.11768 (verified); MemMachine https://arxiv.org/abs/2604.04853 (verified)
42. Append-only + re-derivable views — https://arxiv.org/pdf/2603.05344 (coding-agent memory lessons, 2026)
43. Wikipedia WikiProject AI Cleanup + G15 — https://en.wikipedia.org/wiki/Wikipedia:WikiProject_AI_Cleanup (verified 2026-06-11)
