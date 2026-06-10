# Open Questions

Active frontier of the design. Each has a current lean; none is settled.

1. **System-plane minimalism.** Line drawn at registries + run logs; no orchestration engine (no in-DB job queue, retries, dependency graphs — the harness owns execution). Does session management need more than this?
2. **Role as the partition key.** Claim: role-scoped context assembly is the central relevance/token-efficiency mechanism. Is role the right slice, or is context sometimes project-shaped? (Roles are filters, never walls — people cross roles constantly.)
3. **The approval channel.** Proposals need exactly one home that actually gets looked at: iMessage thread, browser queue, or both. This choice determines whether the hygiene loop lives or dies.
4. **Autonomy dial, initial settings.** File inbox: free. Merge people: propose. Migrate schema: propose. Send communications: propose, always. Where else?
5. **Old dashboard fate.** Mine for patterns vs port the objectives/pushes/reflection loop vs run in parallel. Lean: mine, don't migrate; rebuild the reflection habit later as a skill if missed.
6. **First loop.** Lean: iMessage capture + morning brief — exercises the full spine (pipe, inbox, gardener, assistant, both message directions) and attacks the capture problem. Alternative: email triage (more pain relief, less spine).
7. **Backups.** Local-first means backup is our job. pg_dump to git/cloud nightly? Needs a decision before real data accumulates.
8. **Wiki structure.** Flat pages + links vs directories per role/person. Gardener-maintained either way. Defer until pages exist.
9. **Computer-use enforcement (future).** Locking content on computer/phone once computer use matures. Capability deferred; the consent pattern (proposals + autonomy levels) is designed now so enforcement slots in later.
10. **Poke and other closed assistants.** Per principle 4: feed if possible (MCP, handed context), coexist if closed. Never rebuild.
11. **Context interface design.** The central L1 question now: what context tools does the MCP front door expose first, and at what granularity? Pull (`get_context(role)`) vs pre-assembled briefs vs raw query passthrough; how much shaping happens in SQL views vs in the consuming agent.
