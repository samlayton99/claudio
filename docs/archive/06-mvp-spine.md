# MVP Spine

Sequenced so each step pays immediately. Start small; everything else attaches to a spine that is already paying.

0. **Eval corpus first.** 20–30 real intake examples (notes, texts, transcript snippets) hand-labeled with expected typed outputs. Pressure-tests the type system before any DDL — if a real example doesn't file cleanly into the types, the types are wrong.
1. **Schema v0** + L1 functions + audit triggers + the two Postgres roles. The trust line exists from day one, while it's cheap.
2. **Two pipes:** iMessage adapter (existing MCP reads chat.db) + gcal adapter. launchd, run logging, watchdog.
3. **The filer**, built against the corpus.
4. **First loop:** capture-by-text + morning brief. Daily value begins here.
5. **Todo manager + expectation scanner.**
6. **Panel v1:** plain and fast — approvals, registries, people editor, run log.

Then, in whatever order need dictates: per-window summaries, meeting setter, old-dashboard adapter, wiki gardener, X-feed workflow, tool scout, gmail adapter.
