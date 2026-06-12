# 04 — Security

Deterministic stops at every boundary; probabilistic layers operate only inside them. Threat model: workers WILL be hijacked — intake is adversary-writable by construction — and the test adversary is a **superintelligent malicious agent** trying to read the life, act as the user, or poison the pipeline. Design target: full compromise of any worker yields only bad *content* through audited, reversible, clearance-bounded syscalls.

## Identity & privilege map

| Actor | OS user | DB role | Clearance | Function sets (`02`) |
|---|---|---|---|---|
| Sam (build) | `sam` (GUI) | `claudio_core` | 2 | all |
| Reconciler | `sam` (LaunchAgent) | `w_reconciler` | 0 | agent subset (registry reads, runs) |
| Edge | `sam` (LaunchAgent; TCC: FDA + Automation) | `w_edge` | 1 | `capture`, `post_message`, `read_message`, `resolve_message`. Deterministic only; no LLM |
| Panel | `claudio-p` | `claudio_panel` | 2 | panel + user + agent |
| Clearance-1 workers | `claudio-w1` | `w_filer`, `w_merge`, `w_wiki`, `w_verifier`, `w_lint`, `w_orchestrator`, `w_mirror` | 1 | agent (+ user for orchestrator/mirror, dictation-gated + intent-bound; `merge_atoms` for `w_merge`). The mirror stays the most isolated agent — **no connectors, no send, model API via fixed endpoint** — because its writes are the apex contract; it no longer needs a higher *read* tier since the purpose plane is sensitivity 0 (mission alignment, the user's call; clearance 2 is reserved for future finance/medical) |
| Clearance-0 workers | `claudio-w0` | `w_brief`, `w_scanner`, `w_watchdog` (+`reap_expired_claims`), `w_catalog`, `w_hygiene`, `w_approver` (P5), … | 0 | agent |
| Base / test | — / `claudio-w0` | `claudio_agent` (NOLOGIN) / `w_test` | — / per run | agent |

OS user = trust tier (same-uid credential theft is macOS reality; cross-tier is kernel-enforced). Clearance truth: `role_clearances` via `l1.clearance()` keyed on `session_user`. `FORCE ROW LEVEL SECURITY`; invoker views; sensitivity floors and `verified_fields` enforced inside L1; search_path pinned; `session_user` everywhere (`current_user` in SECURITY DEFINER is the owner — a guard reading it is a no-op); TEMP/CREATE revoked from PUBLIC.

**Staged hardening** (ux-rings: Ring 0 must not kill the project): P1 ships two OS users (`sam` + one worker uid; all components inner-circle, data ≤ c1, mirror runs as core sessions); the full tier split (`claudio-p`, `w1/w0`) + pf + Tailscale land at **P3**, when approvals, third-party data volume, and the panel make them load-bearing. The red-team suite tests whichever stage is deployed; the staging schedule is itself core-ring config.

**Availability is a security property** (the deepest chain ends at the keyboard): FileVault prevents unattended boot — UPS is required hardware; `fdesetup authrestart` for planned reboots; the away-case runbook (dead-man fires mid-trip) is written, not wished away. Trade accepted explicitly: disk encryption > unattended power-loss recovery.

## The boundary rules

1. **No write outside L1** (grants). **No external write inside claudio at all** — sends/posts belong to owning agents, post-approval, via handoff.
2. **No read above clearance** — RLS down to `messages` payloads. (The purpose plane is deliberately sensitivity 0 — every agent is mission-aligned by reading the contract; clearance 2 guards future finance/medical. Purpose *writes* remain the most-gated operation in the system.)
3. **Text never escalates privilege — and channel proof is not intent proof.** Inner-circle crossings = panel/core role, reachable only by human act. Taste-class writes require the **intent binding** (`02`): verbatim-in-raw or edge read-back-confirm — the LLM that drafted a taste write is never in its commit path; the orchestrator stages taste, never writes it. Taste-class is non-bundlable and non-standing-approvable; the fn→class map + arg-predicates are core-ring. SMS and unknown senders are data. (A master passphrase — hash-verified by code, **never by an agent** — is a P6 slot; no operation class currently needs it beyond panel + dictation + intent binding.)
4. **One sender** (the edge), destinations hardwired. Approval acts on claudio-owned surfaces only; approved external work hands off to the owning agent's own channel.
5. **Privilege classes derived, never declared.** Server classifies `actions[].fn`; panel renders the derived class; standing approvals never cover core-class or third-party-visible actions beyond their named class.
6. **Lethal trifecta forbidden** per worker: filer (untrusted + c1, no network); orchestrator (untrusted + c1, **no taste-write grants**, no send tools, network = model API + read-only connectors); mirror (writes the apex contract ⇒ most isolated: no connectors, model API via a fixed-endpoint wrapper with size caps). **No allowlisted tool for any worker ≥ c1 may accept a caller-controlled URL/host/query** — read connectors are fixed-endpoint with server-fixed parameters (a GET query string is an exfil channel; pf allowlists hosts, not queries). Enforced by allowlists + grants + pf, not prompts.
7. **Capability is issued, never declared** (the handshake law, `06`): external agents have no write access to hide because they have none until claudio's grant creates it. Write-capable registrations are visually distinct at approval; the user gate sits at issuance. Tools are **pinned** (version/hash locally; endpoint+manifest fingerprint remotely); any change re-triggers handshake review; new components' outputs are probationary (`03` injection fence). Sandbox trials are stated honestly: they catch naive-malicious tools, not patient ones — probation and pinning carry the rest.
8. **Taint visibility** (`quoted` + `suspected_injection` render foreign everywhere — the injection fence, `03`), **rate ceilings** (audit-counted), **anomaly alerts** (watchdog), and **taste-write provenance review**: every directive/purpose/`verified_fields` write surfaces with its dictation source in a monthly panel review (the mirror's observational report carries it) — slow, in-policy poisoning is caught by reviewing the taste ledger itself, since no access-control alarm will ever fire on it.

## Filesystem, process, network

- `core/` + `custom/` read-only to all worker uids (code deploys via core; workers never write code paths). Workers write only `wiki/` (w1) and `archive/` (large tier-0 payloads, per-tier subdirs).
- launchd plists root/sam-owned, reconciler-generated; per-worker tool allowlists core-owned. No self-modification.
- Tripwire (hourly): git drift over `core/`+`custom/` from P1; permission audit + worker-uid persistence scan (LaunchAgents, crontabs, login items) from **P3** — before the tier split there are no worker uids to scan.
- Kill switch `claudio-stop`: bootout + pkill every worker uid + panel banner; drilled quarterly. Red-team-red posts a critical alert; panel/core performs containment.
- pf: default-deny per worker uid, allowlist (model API, approved connector hosts, dead-man, backup target). Stated honestly as a coarse backstop — allowlisted SaaS is multi-tenant; the operative stop is per-worker tool allowlists; upgrade path is a core-owned forward proxy.
- Secrets: per-uid `.pgpass` 0600; core secrets in the `sam` login keychain; nothing secret in env or plists. FileVault; encrypted backups; retention bounds purge (90-day parameter).

## Privacy

Third parties never consented: minimize (pointers over mirrors), sensitivity defaults by role context, RLS keeps pastoral/confidential rows out of low-clearance packets structurally. Wiki files carry sensitivity ≤ 1 (restricted content exists only in DB rows; `wiki/` mounted to w1 only; lint scans for leak patterns). `purge()` core-only, fact-audited; wiki scrub = page edit + `git filter-repo`; model boundary = no-training/retention API terms (re-verify annually); restricted (clearance-2) rows reach a model only in user-invoked core sessions.

## The malicious-superintelligence review (standing red-team lens)

Beyond the weekly negative-space suite, every new component answers five questions at review: (1) what could it read above its need? (2) what could it cause to be *sent*? (3) what persistent state could it poison (directives, purpose, wiki, standing approvals are the crown jewels — all are user-set-gated or verifier-checked)? (4) what does it do with instruction-shaped content? (5) how would we notice? A dedicated adversarial audit (fresh-context agent, full spec access, "find the weasel path") runs at each phase gate — first findings folded in at `07` P1.

## Standing verification

**Red-team suite** (weekly + every migration; merge gate): as `w_test` per tier — direct INSERT fails; DDL fails; `approve_message` not executable; clearance self-raise has no effect; sensitivity-2 invisible at c1 through every view; `pg_temp` shadowing inert; `file_intake` rejects `set_directive`; floors and `verified_fields` immutable to agents; purpose tables unwritable by any `w_*` except via user-set gate; `core/`/`custom/`/own-plist unwritable; non-allowlisted egress fails. Every new grant ships with its negative test. Kill-switch and restore drills quarterly.
