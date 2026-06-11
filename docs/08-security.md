# Security

Not a feature — the asset is a complete model of a human life plus credentials to act as that human. Design rule: every boundary gets a **deterministic stop** no model output can cross; probabilistic layers (prompts, judgment) operate only inside those walls. Extends the boundary enforcement in `04`.

## Trust boundaries

1. World → intake (adversary-writable text; the central assumption)
2. Agent context → L1 (the syscall boundary — `04`)
3. Outer circle → inner circle (code/config — `04`)
4. System → outbound world (impersonation risk)
5. System → third-party tools/MCP (supply chain, exfiltration)
6. Device → model provider (every LLM call ships context off-device)
7. Human → system (sender identity; who may command)
8. Worker → worker (least privilege per worker)
9. Physical device + backups at rest

## Deterministic stops

1. **No write outside L1** — Postgres grants + `SECURITY DEFINER` (`04`).
2. **Sensitivity tiers via Row-Level Security.** Every row labeled `normal / sensitive / restricted`; every worker role carries a clearance; RLS enforces label ≤ clearance in the database engine. Defaults by role context (church pastoral → sensitive; future finance/medical → restricted). This is the security tier reserved in `03`, designed.
3. **Outbound: agents draft, humans approve, a pipe sends.** No agent ever holds send credentials. Send-capable credentials live only in deterministic sender pipes whose sole input is the approved-proposals queue; `approved` is writable only via a human act on the panel. The pipe transmits exactly the approved bytes.
4. **Entry-point authentication.** Adapters check sender handle against the command allowlist (the user's registered handles) before routing: allowlisted → command path; everyone else → intake-as-data, never commands. High-risk commands require the passphrase regardless.
5. **Egress control by OS user.** macOS `pf` rules: the agent user gets a default-deny network allowlist (model API, approved connector hosts). A hijacked worker has nowhere to exfiltrate to.
6. **File perms, immutable launch configs, Keychain secrets, tripwire, red-team suite** (`04`).
7. **Kill switch.** One core command unloads every agent launchd job. Exists before the first worker runs.
8. **Rate limits inside L1 functions** — deterministic ceilings on reads/writes per worker per window; baseline-anomaly alerts via the watchdog.

## Prompt injection: defense in depth

- **Lethal-trifecta rule:** no single context window combines (a) untrusted input, (b) sensitive data access, and (c) an external channel. The filer reads the dirtiest input, so it lives narrowest: L1 writes, minimal clearance, no network tools. Consumers needing (a)+(b) — e.g. the orchestrator triaging email — never get (c): outbound goes through stop 3.
- **Deterministic control flow:** workflows are fixed pipelines where models fill slots; model output never chooses the next action (protocol 5 is a security protocol, not just a cost one).
- **Taint visibility:** provenance on every atom; proposals render untrusted content visibly as quoted foreign text in the panel, so instruction-shaped text in an email reads as what it is.

## Privacy & confidentiality

- **Third parties never consented.** The system stores other people's lives too (ward members' pastoral matters, founders' confidential plans, friends' texts). Stewardship: data minimization (pointers-not-mirrors), sensitivity defaults by role context, confidential material excluded from general context packets by RLS rather than by hope.
- **Real deletion exists.** "Retire, never delete" yields to privacy when the user says so: a core-privileged, user-only, audited `purge` — the fact of the purge is logged append-only; the content is genuinely gone, including from backups (hence retention windows on backups, not infinite history).
- **Model-provider boundary is a disclosure.** Provider with contractual no-training/retention; restricted-tier rows never enter model context without explicit per-use approval — enforced by clearance: the assembler runs at the requestor's clearance, not its own.

## Standing verification

The red-team suite (`04`) grows with every stop above: assert as the agent role that each deterministic stop actually stops. Boundary changes ship with their tests. The kill switch gets drilled, not just installed.
