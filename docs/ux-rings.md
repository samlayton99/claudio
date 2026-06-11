# UX Rings — the sins list

Audit of spec v3 against P3: every required user action, ringed by necessity. Consequence = what happens when skipped (assume it will be). Referenced by `00` P3 and `07`.

## Ring 0 — setup (one-time; ~12–18 h of user action across P0–P2, excluding build labor — the meta-trap in `docs/honesty-audit.md` owns that)

| Action | Time | If skipped |
|---|---|---|
| Mac mini base: macOS, FileVault, updates, power/login posture | 1–2 h | no system |
| Create 4 OS users (`claudio-p`, `-w2`, `-w1`, `-w0`) + per-uid `.pgpass` + dir perms (`04`) | 1–2 h | no tiering; security model void |
| Postgres + DB + ~18 roles + migrations (core sessions, P1) | 1–2 h supervised | no system |
| TCC grants for edge: System Settings > Privacy > Full Disk Access (chat.db read) + Automation (Messages send) — GUI-only, re-prompted after some macOS updates | 15 min | edge mute: no capture, no sends |
| launchd bootstrap (reconciler + first plists) | 30 min | nothing runs |
| pf anchors per worker uid (root) | 1–2 h | egress backstop absent |
| Keychain secrets, Anthropic API key + billing | 30 min | no LLM steps |
| B2 account + restic init + first restore test (P1 gate) | 1 h | no backups |
| Dead-man heartbeat service signup + wiring | 20 min | edge death is silent |
| Master passphrase (argon2) | 10 min | high-risk ops ungated |
| Panel bearer token; first browse (localhost-only) | 15 min | no approvals at all |
| gcal OAuth: GCP project, consent screen, scopes, token | 30–45 min | no calendar window |
| Mirror elicitation session #1 → purpose contract v1, signed (P0 gate) | 2–3 h | build blocked at P0 |
| About_Me + seed roles/directives + help label 25+ fixtures (P0 gate) | 2–4 h | no eval bar; filer untrusted |

## Ring 1 — bare minimum recurring (any use at all)

| Action | Time | Freq | If skipped |
|---|---|---|---|
| Text claudio (capture) | ~0 | ad lib | no input; system idles (briefs still arrive) |
| Read morning brief | 1–2 min | daily | passive; no system harm |
| Act on reminders/alerts (critical alerts every failure, exempt from budget) | 5–60 min | ~monthly steady; storms on breakage | broken window persists; alert stream continues |
| Re-OAuth dead tokens (Google testing-mode refresh tokens die in 7 days; revoked on password change) | 10–20 min | per expiry | window dead; gap until re-auth (gcal/gmail replayable; some sources not) |
| Physically log in after reboot/power loss (FileVault + GUI LaunchAgent edge = no auto-recovery) | 5 min | per outage | total mute until login; dead-man fires |
| macOS update recovery (TCC re-grants, launchd quirks) | 1–4 h | 1–2×/yr | edge/windows die post-update |

## Ring 2 — meaningful use

| Action | Time | Freq | If skipped |
|---|---|---|---|
| Proposal review on the panel — desk-bound; "panel link" texted to a phone points at localhost | 10–20 min | weekly | auto-expire (good) → merges never apply → duplicate people/atoms accrete |
| Answer held-intake questions | 2–5 min | daily-ish | holds park forever (no expiry/budget specced) → novel items never filed |
| Alignment questions (≤3/wk; re-ask weekly until answered/snoozed) | 1–2 min ea | weekly | re-ask → habitual snooze → alignment dead |
| One-tap "this is wrong" while reading wiki | ~0 | opportunistic | drift compounds; verifier catches fabrication, not wrongness |
| Grant standing approvals (one per class) | 2 min ea | once per class | every automation instance needs manual approve forever |
| Directives / taste texts (dictation gate) | ~0 | ad lib | system guesses taste; P7 holds more |

## Ring 3 — full functionality

| Action | Time | Freq | If skipped |
|---|---|---|---|
| Each new window: OAuth/API ceremony + approval (gmail, slack, notion, …) | 15–45 min ea | per window | fewer windows; scout proposals pile |
| Mirror observational session | 15–30 min | monthly | promote/cut stalls; automations drift from life |
| Elicitation refresh | 1–2 h | quarterly-ish | contract stales; alignment checks a dead doc |
| Kill-switch + restore drills (`04`) | 30–60 min ea | quarterly | backups unproven exactly when needed |
| Hygiene/spend review | 10 min | monthly | cost drift (flag guardrail mitigates) |
| Parameter tuning ("iterated in practice") | ad hoc | ad hoc | defaults must carry forever |
| Handshake approvals; dashboards; annual API-terms re-verify | 10–15 min ea | rare | fewer capabilities; terms drift |

## ADHD filter — what WILL be skipped, and the cascades

Will be skipped, with certainty: quarterly drills, annual terms check, parameter tuning, hygiene review, elicitation refresh, desk-bound panel sessions, held-intake answers after week one, alignment answers after week three.

- **Cascade A (the killer): approvals are desk-bound.** User lives on the phone; `approve_message` is panel/core-only (`01`, `02`), panel is localhost (`06`, Tailscale "later"). Proposals expire unactioned → merge debt → packets show split/duplicate state → briefs read wrong → user stops reading → the human error-correction loop (`05`: "people only correct what they read") dies → wiki and mirror model a stale person.
- **Cascade B: holds park forever.** Filer holds exactly the novel/ambiguous items; unanswered = unfiled. The most interesting events are systematically the missing ones. No expiry, budget, or fallback specced.
- **Cascade C: alert storms during neglect.** Critical components alert every failure, exempt from notification budget (`03`); no coalescing specced. A dead token + 3 absent weeks = a wall of alerts → notification fatigue → real reminders ignored → P6's purpose defeated.
- **Cascade D: standing approvals never granted** → every automation is a manual approve → claudio degrades into a noisy todo app — the exact thing it swore not to be.
- **Cascade E: elicitation gates P0.** The highest-friction introspective task blocks the first DDL. Stall here feeds the meta-trap.

Already mitigated (credit where due): capture durable before judgment; proposals budgeted/ranked/auto-expiring; brief degraded mode; questions capped + snoozable; scanner/reminders LLM-free and never auto-disabled; watchdog + dead-man make failure visible; demotion keeps reading load sublinear; point-of-reading correction; parameters editable without redeploy; the kill criterion itself.

Unmitigated cliffs: phone-unreachable approvals; held-intake immortality; alert-storm exemption; FileVault-vs-GUI-edge after power loss; quarterly human ceremonies; OAuth expiry ceremonies; P0 elicitation gate; no defined "return from neglect" experience.

## Design changes, prioritized

| # | Change | Shrinks | Amends |
|---|---|---|---|
| 1 | **Phone-native approvals.** Extend the dictation gate to `approve_message` for non-core, non-write-capable derived classes ("approve 3" on the verified channel — the edge IS a claudio-owned surface, so `00`'s approval rule holds); ship Tailscale + panel at P3, not "later if proven needed" | Ring 2 → 1 | `02`, `04`, `06` |
| 2 | **Neglect mode (test THIS, not drills).** Silence sensor (no verified-user message N days) → coalesce alerts to one daily digest, auto-snooze alignment, pause non-critical pushes; on first message back, one "while you were gone" rollup with one-tap bulk actions. Add an induced 3-week-neglect eval as a phase gate | Ring 1 survives zero effort | `03`, `06`, `07` |
| 3 | **Collapse Ring 0.** Start with 2 OS users (`sam` + one worker uid); split tiers + pf at P3 when panel/sensitivity-2 data actually exist; mirror elicitation runs as a core session (user is present by definition — no `claudio-w2` until P5); gcal v0 via read-only ICS URL (zero OAuth), OAuth as upgrade; defer master password + panel token to P3 | Ring 0 ≈ halves; protects P2-in-two-weeks | `03`, `04`, `06`, `07` |
| 4 | **Held-intake lifecycle.** Budget + age-out: unanswered holds auto-file after N days as kind `unknown`, flagged low-confidence (visible, marked, correctable) instead of parking; hold-questions ride the morning brief as a batch with one-tap answers — one touchpoint, not pings | Ring 2 → ~0 | `01`, `02`, `03` |
| 5 | **Standing-approval bootstrap.** After 2–3 manual approvals of the same derived class, the system proposes the standing approval itself (one tap to grant, revocable) | Ring 2 → 1 | `02`, `06` |
| 6 | **Automate the ceremonies.** Restore-test = monthly cron restoring to scratch DB + checksum + alert on fail; kill-switch test rides the migration red-team suite; annual terms check = hygiene task emitting a proposal. Humans do not drill | Ring 3 ceremony → 0 | `04` |
| 7 | **OAuth durability rule.** Prefer non-expiring credential modes (ICS, app passwords, device-code); require GCP app published to production; every auth-death alert carries a one-tap re-auth link | Ring 1 | `06` |
| 8 | **Power-loss posture.** Decide FileVault-vs-auto-login explicitly; dead-man alert text includes the exact recovery steps | Ring 1 debugging | `04` |
| 9 | **De-gate elicitation.** P0 accepts a seed contract distilled from About_Me + a 30-min session; deep elicitation moves to P2+, once the system pays daily | Ring 0 | `07` |

UX cost exceeding ring-0/1 value, flag for the over-engineering trim at gates: 4-uid tiering before sensitivity-2 data exists, pf before P3, master password before the panel, quarterly human drills, annual terms re-verification as a user act.
