# Phase 15 coverage audit (iteration 2)

Audit of catalog scenario IDs vs Worker E2E tests after gap-fixer edits to existing test files. Production source, harness, and test files were not modified. The suite was not run.

**Method.** Catalog IDs from `## Scenario SNN-XXX` headings in the 14 stage chapters; cross-checked against `| ID | SNN-XXX |` table rows (exact match) and every `SNN-XXX` mention in README.md + registers.md + the 14 chapters (818 unique; zero extras). `docs/testing/catalog/remediation-plan.md` was not a source. Test IDs from `it` / `test` / `it.skip` titles under `ai-platform/test/e2e/**/*.test.ts` (40 files). No `it.skipIf`, `test.skip`, `test.skipIf`, or `describe.skip` calls exist. Two `.test(` hits in Stage 10/11 files are `RegExp.prototype.test`, not vitest `test()`.

---

## 1. Catalog inventory

Footer of `docs/testing/catalog/registers.md` (and README) claims S00=37, S01=31, S02=27, S03=83, S04=104, S05=85, S06=47, S07=52, S08=69, S09=85, S10=34, S11=29, S12=72, SX=63 (total 818). **Verified: exact match.** Every chapter is consecutive from `-001` through its max with no holes.

| Prefix | Chapter | File | Range | Count | Footer |
|---|---|---|---|---|---|
| S00 | Stage 00 — Platform boot | `stage-00-platform-boot.md` | S00-001 … S00-037 | 37 | 37 |
| S01 | Stage 01 — Token contract | `stage-01-token-contract.md` | S01-001 … S01-031 | 31 | 31 |
| S02 | Stage 02 — Clinic keypair | `stage-02-clinic-keypair.md` | S02-001 … S02-027 | 27 | 27 |
| S03 | Stage 03 — Installation enrollment | `stage-03-installation-enrollment.md` | S03-001 … S03-083 | 83 | 83 |
| S04 | Stage 04 — Entitlement and grants | `stage-04-entitlement-capability-grants.md` | S04-001 … S04-104 | 104 | 104 |
| S05 | Stage 05 — Routing policy | `stage-05-routing-policy.md` | S05-001 … S05-085 | 85 | 85 |
| S06 | Stage 06 — Minting an AAT | `stage-06-minting-an-aat.md` | S06-001 … S06-047 | 47 | 47 |
| S07 | Stage 07 — Discovery | `stage-07-discovery.md` | S07-001 … S07-052 | 52 | 52 |
| S08 | Stage 08 — Request ingress | `stage-08-request-ingress.md` | S08-001 … S08-069 | 69 | 69 |
| S09 | Stage 09 — The Guard | `stage-09-the-guard.md` | S09-001 … S09-085 | 85 | 85 |
| S10 | Stage 10 — Accept / route / invoke / stream | `stage-10-accept-route-invoke-stream.md` | S10-001 … S10-034 | 34 | 34 |
| S11 | Stage 11 — Terminal settlement | `stage-11-terminal-settlement.md` | S11-001 … S11-029 | 29 | 29 |
| S12 | Stage 12 — Lookup and support | `stage-12-lookup-and-support.md` | S12-001 … S12-072 | 72 | 72 |
| SX | Stage X — Cron and failure journeys | `stage-X-cron-and-failure-journeys.md` | SX-001 … SX-063 | 63 | 63 |
| **Total** | | | | **818** | **818** |

README.md contains no scenario IDs (counts only). registers.md mentions a subset of the same 818 IDs (no IDs outside the chapter headings). Heading IDs, `| ID |` table rows, and all `SNN-XXX` mentions across README + registers + the 14 chapters are the same 818-set.

---

## 2. Test inventory

40 files matching `ai-platform/test/e2e/**/*.test.ts`. Unique IDs with a real `it`/`test`: **707**. Unique IDs with `it.skip`: **21** (20 skip-only + 1 mixed). Union: **727**. `it` calls tagged with a catalog ID: 707. `it.skip` calls: 21. P00 exemplar `it` calls: 3 (see §6).

### 2.1 Per-file summary

| File | Implemented IDs | Skipped IDs | Untagged |
|---|---|---|---|
| `phase-00-exemplars.test.ts` | 0 | 0 | 3 |
| `stage-00-boot-bindings-routing.test.ts` | 12 | 7 (incl. mixed S00-007) | 0 |
| `stage-00-auth-schema-cron-happy.test.ts` | 18 | 1 | 0 |
| `stage-01-auth-validation.test.ts` | 16 | 0 | 0 |
| `stage-01-rotation-retire.test.ts` | 15 | 0 | 0 |
| `stage-03-auth-routing.test.ts` | 20 | 0 | 0 |
| `stage-03-enroll-validation.test.ts` | 20 | 0 | 0 |
| `stage-03-lifecycle-rotate.test.ts` | 20 | 0 | 0 |
| `stage-03-revoke-delete-purge.test.ts` | 23 | 0 | 0 |
| `stage-04-entitle-auth-period.test.ts` | 20 | 0 | 0 |
| `stage-04-entitle-quota-grants-validation.test.ts` | 20 | 0 | 0 |
| `stage-04-entitle-happy-cohort-activate.test.ts` | 25 | 0 | 0 |
| `stage-04-cohort-promote-deprecate.test.ts` | 20 | 0 | 0 |
| `stage-04-deprecate-retire-auth.test.ts` | 19 | 0 | 0 |
| `stage-05-publish.test.ts` | 20 | 0 | 0 |
| `stage-05-canary-promote.test.ts` | 21 | 0 | 0 |
| `stage-05-rollback-serving.test.ts` | 19 | 2 | 0 |
| `stage-05-filters-kill-switch.test.ts` | 21 | 2 | 0 |
| `stage-07-routing-identity.test.ts` | 18 | 0 | 0 |
| `stage-07-entitlement-filters.test.ts` | 19 | 0 | 0 |
| `stage-07-etag-cache.test.ts` | 15 | 0 | 0 |
| `stage-08-size-json-headers.test.ts` | 17 | 3 | 0 |
| `stage-08-trace-auth.test.ts` | 20 | 0 | 0 |
| `stage-08-guard-sse-adapter.test.ts` | 20 | 0 | 0 |
| `stage-09-adapter-identity.test.ts` | 22 | 0 | 0 |
| `stage-09-entitlement-ratelimit.test.ts` | 21 | 0 | 0 |
| `stage-09-capability-context-preflight.test.ts` | 22 | 0 | 0 |
| `stage-09-admission-journal-compose.test.ts` | 15 | 5 | 0 |
| `stage-10-route-retry-idempotency.test.ts` | 17 | 0 | 0 |
| `stage-10-prose-guard-stream.test.ts` | 17 | 0 | 0 |
| `stage-11-completed-failed-cancelled.test.ts` | 11 | 0 | 0 |
| `stage-11-replay-envelope-grace.test.ts` | 10 | 0 | 0 |
| `stage-12-get-lookup.test.ts` | 18 | 0 | 0 |
| `stage-12-get-auth.test.ts` | 22 | 0 | 0 |
| `stage-12-support-lookup.test.ts` | 15 | 0 | 0 |
| `stage-12-quota-inspect-dashboard.test.ts` | 17 | 0 | 0 |
| `stage-X-cron-flush-reconcile.test.ts` | 16 | 0 | 0 |
| `stage-X-grace-retention.test.ts` | 16 | 0 | 0 |
| `stage-X-ledger-reconciliation-sweep.test.ts` | 16 | 0 | 0 |
| `stage-X-credit-inspect-do-rpc.test.ts` | 14 | 1 | 0 |
| **Unique IDs (not sum of rows)** | **707** | **21 unique / 20 skip-only** | **3** |

No Stage 2 or Stage 6 Worker test files exist (hard rule 7).

### 2.2 Per-file ID lists

**`phase-00-exemplars.test.ts`** — implemented: none. skipped: none. untagged: P00-001, P00-002, P00-003 (see §6).

**`stage-00-boot-bindings-routing.test.ts`**
- Implemented: S00-004, S00-005, S00-006, S00-007, S00-008, S00-009, S00-010, S00-011, S00-015, S00-016, S00-017, S00-018
- Skipped: S00-001, S00-002, S00-003, S00-007 (throwing-load arm only), S00-012, S00-013, S00-014

**`stage-00-auth-schema-cron-happy.test.ts`**
- Implemented: S00-019 … S00-027, S00-029 … S00-037
- Skipped: S00-028

**`stage-01-auth-validation.test.ts`** — S01-001 … S01-016 (all implemented).

**`stage-01-rotation-retire.test.ts`** — S01-017 … S01-031 (all implemented).

**`stage-03-auth-routing.test.ts`** — S03-001 … S03-020.

**`stage-03-enroll-validation.test.ts`** — S03-021 … S03-040.

**`stage-03-lifecycle-rotate.test.ts`** — S03-041 … S03-060.

**`stage-03-revoke-delete-purge.test.ts`** — S03-061 … S03-083.

**`stage-04-entitle-auth-period.test.ts`** — S04-001 … S04-020.

**`stage-04-entitle-quota-grants-validation.test.ts`** — S04-021 … S04-040.

**`stage-04-entitle-happy-cohort-activate.test.ts`** — S04-041 … S04-065.

**`stage-04-cohort-promote-deprecate.test.ts`** — S04-066 … S04-085.

**`stage-04-deprecate-retire-auth.test.ts`** — S04-086 … S04-104.

**`stage-05-publish.test.ts`** — S05-001 … S05-020.

**`stage-05-canary-promote.test.ts`** — S05-021 … S05-041.

**`stage-05-rollback-serving.test.ts`**
- Implemented: S05-042 … S05-059, S05-062
- Skipped: S05-060, S05-061

**`stage-05-filters-kill-switch.test.ts`**
- Implemented: S05-063 … S05-077, S05-079 … S05-081, S05-083 … S05-085
- Skipped: S05-078, S05-082

**`stage-07-routing-identity.test.ts`** — S07-001 … S07-018.

**`stage-07-entitlement-filters.test.ts`** — S07-019 … S07-037.

**`stage-07-etag-cache.test.ts`** — S07-038 … S07-052.

**`stage-08-size-json-headers.test.ts`**
- Implemented: S08-001, S08-002, S08-004, S08-006 … S08-008, S08-010 … S08-020
- Skipped: S08-003, S08-005, S08-009

**`stage-08-trace-auth.test.ts`** — S08-021 … S08-040.

**`stage-08-guard-sse-adapter.test.ts`** — S08-041 … S08-060.

**`stage-09-adapter-identity.test.ts`** — S09-001 … S09-022.

**`stage-09-entitlement-ratelimit.test.ts`** — S09-023 … S09-043.

**`stage-09-capability-context-preflight.test.ts`** — S09-044 … S09-065.

**`stage-09-admission-journal-compose.test.ts`**
- Implemented: S09-066 … S09-074, S09-078, S09-080, S09-081, S09-083 … S09-085
- Skipped: S09-075, S09-076, S09-077, S09-079, S09-082

**`stage-10-route-retry-idempotency.test.ts`** — S10-001 … S10-017.

**`stage-10-prose-guard-stream.test.ts`** — S10-018 … S10-034.

**`stage-11-completed-failed-cancelled.test.ts`** — S11-001 … S11-011.

**`stage-11-replay-envelope-grace.test.ts`** — S11-012 … S11-021.

**`stage-12-get-lookup.test.ts`** — S12-001 … S12-018.

**`stage-12-get-auth.test.ts`** — S12-019 … S12-040.

**`stage-12-support-lookup.test.ts`** — S12-041 … S12-055.

**`stage-12-quota-inspect-dashboard.test.ts`** — S12-056 … S12-072.

**`stage-X-cron-flush-reconcile.test.ts`** — SX-001 … SX-016.

**`stage-X-grace-retention.test.ts`** — SX-017 … SX-032.

**`stage-X-ledger-reconciliation-sweep.test.ts`** — SX-033 … SX-048.

**`stage-X-credit-inspect-do-rpc.test.ts`**
- Implemented: SX-049 … SX-062
- Skipped: SX-063

No catalog ID appears as a real `it` in more than one file.

### 2.3 Coverage vs catalog by prefix

| Prefix | Catalog | Deferred | Automatable | Real `it` | Skip-only | Mixed | Union | Gaps |
|---|---|---|---|---|---|---|---|---|
| S00 | 37 | 0 | 37 | 30 | 7 | 1 (S00-007) | 37 | 0 |
| S01 | 31 | 0 | 31 | 31 | 0 | 0 | 31 | 0 |
| S02 | 27 | 27 | 0 | 0 | 0 | 0 | 0 | 0 |
| S03 | 83 | 0 | 83 | 83 | 0 | 0 | 83 | 0 |
| S04 | 104 | 0 | 104 | 104 | 0 | 0 | 104 | 0 |
| S05 | 85 | 0 | 85 | 81 | 4 | 0 | 85 | 0 |
| S06 | 47 | 47 | 0 | 0 | 0 | 0 | 0 | 0 |
| S07 | 52 | 0 | 52 | 52 | 0 | 0 | 52 | 0 |
| S08 | 69 | 9 | 60 | 57 | 3 | 0 | 60 | 0 |
| S09 | 85 | 0 | 85 | 80 | 5 | 0 | 85 | 0 |
| S10 | 34 | 0 | 34 | 34 | 0 | 0 | 34 | 0 |
| S11 | 29 | 8 | 21 | 21 | 0 | 0 | 21 | 0 |
| S12 | 72 | 0 | 72 | 72 | 0 | 0 | 72 | 0 |
| SX | 63 | 0 | 63 | 62 | 1 | 0 | 63 | 0 |
| **Total** | **818** | **91** | **727** | **707** | **20** | **1** | **727** | **0** |

### 2.4 Register 5 IDs implemented (not skipped) — not gaps

These IDs are named in Register 5 rows 1–45 (scenario, why, or proposed-seam cells) and still have a real `it` (seam, [SEED], or in-pool path). Allowed.

S00-007 (empty-registry seam; throwing-load arm skipped), S00-032, S01-013, S01-017, S01-025, S01-026, S01-029, S03-083, S04-091, S05-016, S05-020, S05-059, S05-069, S05-070, S07-051, S07-052, S08-004, S08-006, S08-007, S08-044, S08-049, S08-056, S08-057, S08-058, S08-060, S09-040, S09-041, S09-042, S09-050, S10-009, S10-033, S10-034, S11-018, S11-019, S11-021, S12-009, S12-039, S12-040, S12-060, SX-004, SX-008, SX-013, SX-017, SX-018, SX-022, SX-025, SX-031, SX-043.

---

## 3. Deferred-to-pgTAP (hard rule 7)

These are **not Worker coverage gaps** and are **not** counted as Register 5 skips unless they also appear as `it.skip` in the E2E suite. None of them appear in any E2E `it` / `it.skip`.

| Range | Count | Catalog chapter | Why deferred |
|---|---|---|---|
| S02-001 … S02-027 | 27 | `stage-02-clinic-keypair.md` | Entire Stage 2 is Supabase/pgTAP (clinic keypair enrollment). |
| S06-001 … S06-047 | 47 | `stage-06-minting-an-aat.md` | Entire Stage 6 is Supabase/pgTAP (AAT minting). |
| S08-061 … S08-069 | 9 | `stage-08-request-ingress.md` | Context-provider RPC against PostgreSQL (Register 5 #41); not the workers pool. |
| S11-022 … S11-029 | 8 | `stage-11-terminal-settlement.md` | PostgREST / SQL-side settlement contract (pgTAP). |
| **Total** | **91** | | |

27 + 47 + 9 + 8 = **91**. Automatable expected = 818 − 91 = **727**.

---

## 4. Gaps (automatable IDs with no test and no skip)

**ZERO GAPS.**

Every automatable catalog ID (727) appears as a real `it` and/or `it.skip`. Gap-fixer edits did not leave residual holes and did not introduce new uncovered IDs.

---

## 5. Skips without Register 5 citation

**ZERO.**

21 `it.skip` calls (20 skip-only IDs + mixed S00-007 arm). Each cites Register 5 by row number and/or by quoting the register Why/behavior text.

| ID | File | Skip title | Register 5 |
|---|---|---|---|
| S00-001 | `stage-00-boot-bindings-routing.test.ts` | S00-001 — The pool always supplies the bindings declared in the test wrangler.toml; a binding cannot be removed per-test | #1 (Why-column verbatim) |
| S00-002 | `stage-00-boot-bindings-routing.test.ts` | S00-002 — (same Why text as S00-001) | #1 |
| S00-003 | `stage-00-boot-bindings-routing.test.ts` | S00-003 — (same Why text as S00-001) | #1 |
| S00-007 | `stage-00-boot-bindings-routing.test.ts` | S00-007 throwing-load arm — The manifest is a static JSON import baked at build time; cannot become malformed in a running isolate | #3 (Why-column verbatim; mixed — see §8) |
| S00-012 | `stage-00-boot-bindings-routing.test.ts` | S00-012 — Requires capturing the worker isolate's console output, which the pool may not expose per-isolate | #5 (Why-column verbatim) |
| S00-013 | `stage-00-boot-bindings-routing.test.ts` | S00-013 — (same Why text as S00-012) | #5 |
| S00-014 | `stage-00-boot-bindings-routing.test.ts` | S00-014 — (same Why text as S00-012) | #5 |
| S00-028 | `stage-00-auth-schema-cron-happy.test.ts` | S00-028 — The pool applies migrations once per test database; d1_migrations tracking is platform behavior, not worker code | #4 (Why-column near-verbatim) |
| S05-060 | `stage-05-rollback-serving.test.ts` | S05-060 — Register 5 #26: createD1ConfigReader/selectCandidateChain are not exported by the frozen harness barrel; … | #26 (row number) |
| S05-061 | `stage-05-rollback-serving.test.ts` | S05-061 — Register 5 #26: selectCandidateChain is not exported … | #26 |
| S05-078 | `stage-05-filters-kill-switch.test.ts` | S05-078 — Inputs the bundled manifest set cannot produce (… Register 5 #26 router-seam; …) | #26 |
| S05-082 | `stage-05-filters-kill-switch.test.ts` | S05-082 — Inputs the bundled manifest set cannot produce (… Register 5 #26 router-seam; …) | #26 |
| S08-003 | `stage-08-size-json-headers.test.ts` | S08-003 — Content-Length one byte over 1 MiB (Register 5 #37: …) | #37 |
| S08-005 | `stage-08-size-json-headers.test.ts` | S08-005 — Under-declared Content-Length smuggle (Register 5 #37: …) | #37 |
| S08-009 | `stage-08-size-json-headers.test.ts` | S08-009 — Non-numeric Content-Length (Register 5 #37: …) | #37 |
| S09-075 | `stage-09-admission-journal-compose.test.ts` | S09-075 — DO outage admits under grace … (Register 5 #28: in-pool env.DO frozen; …) | #28 |
| S09-076 | `stage-09-admission-journal-compose.test.ts` | S09-076 — grace replay of pending row … (Register 5 #28: …) | #28 |
| S09-077 | `stage-09-admission-journal-compose.test.ts` | S09-077 — sixth concurrent grace is rate_limited … (Register 5 #28: …) | #28 |
| S09-079 | `stage-09-admission-journal-compose.test.ts` | S09-079 — DO HTTP 400 bad_request is internal_error not grace (Register 5 #28: …) | #28 |
| S09-082 | `stage-09-admission-journal-compose.test.ts` | S09-082 — journal INSERT failure … (Register 5 #29: in-pool env.DB frozen; …) | #29 |
| SX-063 | `stage-X-credit-inspect-do-rpc.test.ts` | SX-063 — Register 5 #45: in-pool GatewayObject cannot take injected storage; … | #45 |

Stage 0 skips cite the register Why text and do not contain the string `Register 5`; that still satisfies the citation rule (row number **and/or** register scenario/behavior text). S09-075/076/077 cite row #28 (DO-outage family) even though those three IDs are not named in the Register 5 scenario cell; the row citation is sufficient.

Skip-only IDs (20): S00-001, S00-002, S00-003, S00-012, S00-013, S00-014, S00-028, S05-060, S05-061, S05-078, S05-082, S08-003, S08-005, S08-009, S09-075, S09-076, S09-077, S09-079, S09-082, SX-063.

---

## 6. Untagged tests

Three tests in `ai-platform/test/e2e/phase-00-exemplars.test.ts` use Phase 0 harness IDs (`P00-*`), not catalog `SNN-XXX` IDs:

| Kind | Title | File |
|---|---|---|
| `it` | P00-001 — control-plane 401 unauthorized | `phase-00-exemplars.test.ts` |
| `it` | P00-002 — guard rejection full taxonomy body | `phase-00-exemplars.test.ts` |
| `it` | P00-003 — happy-path SSE accepted | `phase-00-exemplars.test.ts` |

These are harness smoke exemplars, not catalog scenarios. They do not create catalog gaps. They are still untagged relative to the catalog ID rule.

No other untagged `it` / `test` / skip titles exist.

---

## 7. Extra IDs in tests not in catalog

**ZERO.**

Every `SNN-XXX` in an `it` / `it.skip` title is one of the 818 catalog headings. No test-only IDs. Deferred-to-pgTAP IDs do not appear in tests.

---

## 8. Mixed IDs (skip + real it)

**S00-007** — OK.

| Arm | File | Title |
|---|---|---|
| Real `it` | `stage-00-boot-bindings-routing.test.ts` | S00-007 — Bundled manifest failing validation aborts isolate boot (harness empty-registry seam) |
| `it.skip` | `stage-00-boot-bindings-routing.test.ts` | S00-007 throwing-load arm — The manifest is a static JSON import baked at build time; cannot become malformed in a running isolate |

The ID is implemented via the registry seam; the throwing-`load()` arm is Register 5 #3. Counted under implemented (707), not under skip-only.

No other mixed IDs.

---

## 9. Verdict

**COVERAGE COMPLETE**

All 727 automatable catalog IDs have a Worker E2E `it` or `it.skip`. Hard-rule-7 ranges are excluded from Worker gaps. Every skip cites Register 5. No extra catalog IDs. Iteration 2 (post gap-fixer) matches the same coverage identity as iteration 1.

| Metric | Count |
|---|---|
| Catalog total | 818 |
| Deferred-to-pgTAP | 91 |
| Automatable expected | 727 |
| Implemented (real `it`, unique IDs) | 707 |
| Skipped (Register 5, skip-only unique IDs) | 20 |
| Mixed (skip + real `it`) | 1 (S00-007; included in 707) |
| Gaps | 0 |
| Untagged | 3 (`P00-001` … `P00-003` in `phase-00-exemplars.test.ts`; not catalog IDs) |
| Extra IDs in tests not in catalog | 0 |
| Skips without Register 5 citation | 0 |

Identity check: 707 implemented + 20 skip-only = 727 automatable.
