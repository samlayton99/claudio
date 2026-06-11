# Questions Queue

Open items for Sam. Defaults are chosen and specced — answering changes the spec; silence keeps the default.

1. **Wiki frontmatter spec** — kept minimal and unfrozen per your hold (`05-wiki.md`). Revisit after prior-art review (Obsidian, agent-memory conventions).
2. **Wiki file sensitivity gap** — files are readable by all workers (one OS user). v0 rule: nothing above sensitivity 1 in files; restricted stays DB-only. Upgrade path: per-clearance OS groups. Comfortable? (`04-security.md`)
3. **Worker billing** — default: launchd + `claude -p`, cheap models, cost ceilings (metered credits). Alternative if metering hurts: migrate hot workers to Cowork scheduled tasks (subscription bucket). Decide with real cost data at P2 exit; billing facts volatile — re-verify then.
4. **gcal-as-draft semantics** — default: ended gcal events log with `meta.tentative=true` unless corroborated (another source) or confirmed (you). Matches "gcal is my draft planner." Tune?
5. **Chat atom granularity** — default: one atom per thread per day. Adapter-configurable. Feels right?
6. **Orchestrator continuity** — one session per iMessage thread per day (resume within day, fresh next day). Enough memory for how you converse?
7. **Notification budget** — default 5 proactive pushes/day (reliability alerts + reminders exempt, never suppressed). Tune?
8. **Backup destination** — default: restic → Backblaze B2 (encrypted) + git remote (private GitHub) for repo/wiki. OK?
9. **Old-dashboard adapter timing** — slotted P6. Pull earlier if you're still using it daily?
10. **Relationship vocab seed** — `knows, family, introduced_by, colleague` to start; person↔person edges conservative (asserted or explicit-intro ≥0.9). Add kinds now or let promotion handle it?
11. **Panel stack** — minimal Next.js chosen (your stack). Fine?
