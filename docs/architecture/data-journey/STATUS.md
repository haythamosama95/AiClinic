# STATUS

Next step: execute phase 1

| Group | Chapters | Money-critical | Trace | Chapters written | Verified | 2nd verifier | Fixes | Done |
|---|---|---|---|---|---|---|---|---|
| G00 | Prologue | - | - | - | - | - | - | - |
| G01 | 1–2 cast; clinic identity | - | - | - | - | - | - | - |
| G02 | 3–4 keypair/installation; first AI page | - | - | - | - | - | - | - |
| G03 | 5–7 billing token; handshake; offers | - | - | - | - | - | - | - |
| G04 | 8–9 billing contact; checkout creation | $ | - | - | - | - | - | - |
| G05 | 10–13 pay; polling; webhook; sweeps | $ | - | - | - | - | - | - |
| G06 | 14–16 work runner; grant; AP applies | $ | - | - | - | - | - | - |
| G07 | 17–18 coverage feed; subscription views | - | - | - | - | - | - | - |
| G08 | 19–21 AI token; discovery; context | - | - | - | - | - | - | - |
| G09 | 22 + guard: identity, entitlement, rate limit, capability | - | - | - | - | - | - | - |
| G10 | guard: context, cost, admission, journal, prompt | $ | - | - | - | - | - | - |
| G11 | 24–25 route/invoke; stream | - | - | - | - | - | - | - |
| G12 | 26–27 settlement; lookup | $ | - | - | - | - | - | - |
| G13 | 28–29 acceptance; degraded states | - | - | - | - | - | - | - |
| G14 | 30–31 term boundaries; renewal | - | - | - | - | - | - | - |
| G15 | 32–34 AP jobs; ABO scheduler; reconciliation | - | - | - | - | - | - | - |
| G16 | 35–36 refund; chargeback | $ | - | - | - | - | - | - |
| G17 | 37–38 key rotation; transfer | $ | - | - | - | - | - | - |
| G18 | 39–40 erasure; DR | $ | - | - | - | - | - | - |
| G19 | console gate; offers/plan-version/ceiling actions | - | - | - | - | - | - | - |
| G20 | complimentary, suspend, resume, delete, begin transfer | $ | - | - | - | - | - | - |
| G21 | release, chargeback, void, release-held, recover-stranded | $ | - | - | - | - | - | - |
| G22 | retry/cancel checkout, txn id, payout import, findings, op credentials, erase contact | - | - | - | - | - | - | - |
| G23 | AP control: capability, cohort, kill switch | - | - | - | - | - | - | - |
| G24 | AP control: routing, token contract, installation lifecycle | - | - | - | - | - | - | - |

## Log

- 2026-10-22 Phase 0 started: STATUS.md, traces/, tools/ created.
- 2026-10-22 Phase 0 done: 4 inventory files merged into INVENTORY.md (1978 items, all assigned; group assignment is keyword-based and coarse, G14 got none — tracers refine per group). Tools built (lint_terms, check_coverage, check_links, check_banned). GLOSSARY.md and 00-index.md created. Exit check: scripts run without crashing on the empty set; check_coverage reports every item as uncovered (expected, no chapters yet).
