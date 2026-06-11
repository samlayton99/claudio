# Questions Queue

Open items for Sam. Defaults are chosen and specced — answering changes the spec; silence keeps the default.

## New since spec v2 (review-driven changes you should sanity-check)

1. **OS users as clearance tiers.** Reviews found the single-service-user design collapses the privilege lattice (same-uid credential theft) and that chat.db/iMessage-send legally require your GUI session (TCC). v2: `sam` (core + the deterministic iMessage edge), `claudio-p` (panel), `claudio-w1`/`claudio-w0` (worker tiers). Slightly more setup, kernel-enforced boundaries. OK?
2. **External dead-man service.** P6 needs an alarm independent of the alarm channel: the edge heartbeats to a hosted dead-man (e.g. Healthchecks.io) after each successful send cycle; a miss alerts out-of-band. One small cloud dependency in a local-first system — accept?
3. **Standing approvals.** User-granted directives (`scope_type='approval_class'`) let the panel auto-apply named, server-classified proposal classes — proposed seed: `gcal_solo_block` (your intro→calendar chain runs silently; attendee-bearing events still propose). Grant it?
4. **Dictation privileges via chat.** Verified-iMessage texts from you can set directives, assert links, edit goals (the dictation gate). SMS and all other senders never can. Comfortable with chat-as-law at that scope, or should some of it stay panel-only?
5. **Orchestrator reply latency.** No router daemon (P4) means queue-triggered workers: ~10–20s text-reply latency in v0. Acceptable, or revisit?

## Carried defaults

6. **Wiki frontmatter spec** — minimal + unfrozen pending prior-art review (`05`).
7. **Wiki file sensitivity gap** — files ≤ sensitivity 1, restricted stays DB-only; `wiki/` mounted to w1 only. Upgrade path: per-clearance subtrees. (`04`)
8. **Worker billing** — launchd + `claude -p`, cheap models, cost ceilings; revisit with real cost data at P2 exit (billing facts volatile).
9. **gcal-as-draft** — ended events log `meta.tentative=true` unless corroborated/confirmed. Tune?
10. **Chat atom granularity** — thread-day default, adapter-configurable.
11. **Notification budget** — 5 proactive/day; reminders, alerts, time-sensitive questions exempt.
12. **Backups** — restic → Backblaze B2 (encrypted) + private git remote; 90-day retention (purge completes within window).
13. **Old-dashboard adapter timing** — P6; pull earlier if you still use it daily.
14. **Relationship vocab seed** — `knows, family, introduced_by, colleague`; conservative creation per your note.
15. **Panel stack** — minimal Next.js, localhost + bearer token (localhost alone is not auth).
