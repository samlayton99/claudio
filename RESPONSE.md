# RESPONSE
*Refresh every time, this is not a log. Items not yet addressed carry over to the next response if still applicable*

Session report for Sam. Rewritten each session; git history keeps prior reports. Explains the most significant moves, what you most need to know, what to do, and points to the details. Open decisions live in `docs/questions-queue.md`, not here.

## Session 2026-06-12 (evening): the type is installed, never forked

### Your directive, integrated

The distribution model is now law (`specs/00` P11 extension, `specs/07 §Distribution`, `specs/04` install guarantee). Three artifacts:

| Artifact | Who writes it |
|---|---|
| **Type release** — installed at a pinned version, core-owned, read-only to every uid *including your own login session* | nobody locally |
| **Term workspace** — your repo: windows, dashboards, custom agents, seeds, wiki | you and your agents, freely |
| **Dev checkout** — a normal clone | maintainers; changes go upstream as PRs |

Your requirements, mapped:

- **"users aren't editing the core files"** → the install guarantee: the type lands core-owned and read-only. Not a convention — file ownership. Even the dumbest dashboard-building agent gets a permission error, not a footgun.
- **"I MUST ENSURE that I NEVER change or touch the core system"** → the same guarantee protects you from yourself: your interactive sessions can't write an install either. Maintaining the type = editing a dev checkout and shipping a release; building your life = the term workspace. Two different directories, two different permissions, impossible to confuse.
- **"propagate easily... I'd like the option"** → `claudio update`: fetch tagged release → run new migrations (append-only from first release) → regenerate catalog → restart workers. The term never lives in type paths, so updates structurally can't touch it. The model is identical whether the repo stays private or goes public — the option costs nothing to keep open (queue 11).
- **"a very strong test... more onerous to fork than to use"** → **the fork test** is now the packaging acceptance test, and its enforcement loop: every "I had to fork to do X" is filed as a type defect. This is just P11's standing question with teeth — if a legitimate customization needs a type edit, the type is wrong.
- **Your dashboard use case** → specced in `specs/06`: dashboards are term components that may wear **two hats** — surface (data out) and window (data in: the daily-log box writes `capture()`), each hat getting its own narrow grant via the handshake. And **panel views are embeddable**: your FPD-style dashboard mounts the type's approval/registry/intake views inside its own chrome — the term decides the look, the type keeps the commit paths. You wire it all up with your own Claude Code sessions against L1, and none of it can touch core.

### One interim rule that starts now

Until the physical split (post-P2 packaging milestone), this repo is the dev checkout with your term co-resident. **Term-building sessions — the custom dashboard especially — run in their own repos against L1, never inside this checkout.** That's the line until file permissions enforce it.

### Carried over

- **Elicitation: still clear to start** — say "run the elicitation" in a core session. Nothing this directive changes blocks it; the purpose contract is term, exactly where it belongs.
- Corpus: walkthrough approved (your rename applied); `corpus-core/coverage/sam` still `proposed` when you want the same pass.
- Queue 4b: skim the 8 notable reasons. Queue 11: the only open sub-decision is public-vs-private type repo, no rush.

### Pointers

Distribution: `specs/07 §Distribution` (the three artifacts, update path, fork test). Law: `specs/00` P11. Enforcement: `specs/04` install guarantee. Dashboard dual-hat + embeddable panel: `specs/06`. Audit updated: `docs/type-term-audit.md`. Queue: 11.
