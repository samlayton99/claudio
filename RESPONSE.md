# RESPONSE
*Refresh every time, this is not a log. Items not yet addressed carry over to the next response if still applicable*

Session report for Sam. Rewritten each session; git history keeps prior reports. Explains the most significant moves, what you most need to know, what to do, and points to the details. Open decisions live in `docs/questions-queue.md`, not here.

## Session 2026-06-12 (evening, part 2): fork softened, panel customizable, Occam findings

### Your two corrections, applied

- **"Installed by default (recommended), fork if you wish"** — softened everywhere (`specs/00` P11, `07 §Distribution`, `CONTEXT.md`, audit doc). The distribution section is now explicitly framed as *an option preserved cheaply, not a commitment* — nothing in it is load-bearing for a single-user install; it exists so heading there later is easy. The fork test survives as the design bar (install+term-build should beat forking on effort), not as a prohibition.
- **Panel: core is type, chrome is term** (`specs/06 §Panel`) — the panel must always exist with core functionality intact (approvals, registry, intake, parameters, and above all the what-will-execute commit paths). On top: embeddable AND customizable — re-skin, rearrange, extend with term pages/tiles, or wrap entirely inside your FPD-style dashboard. One deliberate limit, which is itself an Occam call: customization happens in term surfaces, **no plugin framework in the type**, and the server-rendered approval views are never overridable — however deep the custom chrome goes, what-you-approve remains what-executes.

### The simplification check (you asked for Occam's razor findings — here they are, biggest first)

**1. The spec is outrunning the build — freeze new law until P2 ships.** The binding constraint is the daily loop by ~06-26. Of this week's additions, the raw store and P12 are load-bearing for P2; regimes, distribution, probing protocol are not — they're good law written early. The risk isn't that they're wrong; it's the pattern: we are one week into a two-week clock and spec mass is still growing. Recommendation: every new directive until P2 gets one question first — *does the daily loop need it?* — and if not, it goes to the queue as a one-liner, not into the specs as law. (This includes things I write.)

**2. `tasks` + `expectations` are one table wearing two names.** They share description, person, due, status, role, sensitivity, links, provenance; expectations add only `follow_up`/`resolved_by`. Your own type-system brainstorm had this right originally: one **obligations** table with `direction: by_me | to_me`. Merging cuts a table, ~4 L1 functions, and view branches; the scanner reads one surface; agents walk one concept. Cost: a day of L1+test churn *now* — and it's now or never, because every phase after P2 builds on these two names. This is the single biggest structural simplification available. My lean: do it.

**3. `filters` vs `semantics.discard_patterns` — two mechanisms for "this is noise."** Both are deterministic per-window pattern lists; the only difference is stage (pre-capture drop vs post-capture discard). Unify: one `noise_patterns` list per window, each pattern tagged `drop` (never recorded — your privacy case) or `discard` (recorded, no atom; the default). One concept instead of two, and the drop-counter guardrail covers both. My lean: do it (spec-only change; filters aren't built yet).

**4. Regimes: we violated our own grow-by-promotion rule.** The spec mandates `semantics` be a dated list *from day one* — list-shaped config for a regime change that may never come, which is exactly pitfall-5 speculative structure. Simplify: `semantics` stays scalar; the audit log already records every config change, so history is never lost; promote to the dated-list shape at the *first real* regime change (the trigger and target shape are pre-agreed, so the promotion is mechanical). My lean: do it.

**5. Checked and deliberately kept** (so you know the pass was real): staged OS tiers (security arrives with its load — already the simplified form); intent binding (closed the deepest red-team finding); the 8 notable reasons (small, and `milestone`-reason vs `milestone`-kind overlap is legitimate — a kind=meeting atom can be reason=milestone); eleven wiki chapters (research-validated MOC anchors, zero runtime cost); metrics/embeddings/probe-budget deferrals (all have explicit triggers); two backup layers (the local one is one directory); the seeded-but-disabled component roster (it's the registry being honest about what will exist).

Items 2–4 are yours to call — you said you'll start the simplification next; I've changed nothing on them. If you bless 2, it should happen before any P2 code references the two names.

### Carried over

- **Elicitation: clear to start** — unaffected by any of this. Say "run the elicitation" in a core session.
- Corpus: `corpus-core/coverage/sam` still `proposed`. Queue 4b: skim the 8 notable reasons.
- Queue 11: distribution stays tentative by design; public-vs-private undecided, zero cost to defer.

### Pointers

Fork softening: `specs/00` P11, `specs/07 §Distribution`. Panel: `specs/06 §Panel`. The Occam items above reference: `specs/01` (tasks/expectations DDL), `specs/06 §Windows` (filters, semantics), `specs/00` vocab (Regime). Queue: `docs/questions-queue.md`.
