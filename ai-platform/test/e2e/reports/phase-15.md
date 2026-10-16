# Phase 15 — Verification report

**Declaration: GREEN**

Coverage is complete (modulo deferred-to-pgTAP IDs). The full suite is green as declared by a clean full-suite runner pass (iteration 7), not by fixer self-reports.

Authoritative artifacts:

- Coverage: `ai-platform/test/e2e/reports/phase-15-coverage.md`
- Full suite: `ai-platform/test/e2e/reports/phase-15-failures.md`
- Conflicts: `ai-platform/test/e2e/reports/phase-15-conflicts.md`

## 1. Coverage summary

Auditor verdict (iteration 2 after first gap-fixer round; later fixers only edited existing tests, no IDs added or removed): **COVERAGE COMPLETE**.

| Metric | Count |
|---|---|
| Catalog total | 818 |
| Deferred-to-pgTAP (hard rule 7) | 91 |
| Automatable expected | 727 |
| Implemented (real `it`, unique IDs) | 707 |
| Skipped (Register 5, skip-only) | 20 |
| Mixed (skip + real `it`) | 1 (`S00-007`; counted in 707) |
| Gaps | **0** |
| Skips without Register 5 citation | **0** |
| Extra catalog IDs in tests | **0** |
| Untagged | 3 (`P00-001`…`P00-003` harness exemplars; not catalog IDs) |

Identity: 707 implemented + 20 skip-only = 727 automatable.

## 2. Full-suite counts

Authoritative runner: iteration 7 (`npx vitest run --config vitest.e2e.config.ts` from `ai-platform/`).

```
 Test Files  40 passed (40)
      Tests  710 passed | 21 skipped (731)
   Start at  17:34:36
   Duration  61.55s
```

| | Count |
|---|---|
| Passing | **710** |
| Skipped | **21** (20 skip-only IDs + mixed `S00-007` throwing-load arm) |
| Failing | **0** |
| Test files | 40 passed (40) |
| Total | 731 |

Exit code: **0**. Zero unexpected skips.

## 3. Gap-fixer iterations

| Pass | Result | Fixers |
|---|---|---|
| Auditor 1 + Runner 1 (parallel) | Coverage complete. Suite: 687 passed, 21 skipped, **23 failed** | — |
| Fixer round 1 | 13 files (settlement polling, cache TTL, snapshot races) | 13 children |
| Auditor 2 + Runner 2 (parallel) | Coverage complete. Suite: 706 passed, 21 skipped, **4 failed** (all `Config cache miss for active_routing_policy:routing/standard`) | — |
| Fixer round 2 | 3 files (`stage-05-filters-kill-switch`, `stage-05-rollback-serving`, `stage-11-completed-failed-cancelled`) | 3 children |
| Runner 3 | 703 passed, 21 skipped, **7 failed** (same cache-miss class, new IDs) | — |
| Fixer round 3 | 7 files — pin `isolateConfigCache` before **every** invoke in each file | 7 children |
| Runner 4 | 709 passed, 21 skipped, **1 failed** (`S10-019` attempt-snapshot race, not cache miss) | — |
| Fixer round 4 | 1 file (`stage-10-prose-guard-stream`) | 1 child |
| Runner 5 | 709 passed, 21 skipped, **1 failed** (`S12-007` cache miss on HangFake cancel) | — |
| Fixer round 5 | 1 file (`stage-12-get-lookup`) | 1 child |
| Runner 6 | 708 passed, 21 skipped, **2 failed** (`S10-002`, `S12-059` cache miss) | — |
| Fixer round 6 | 2 files (`stage-10-route-retry-idempotency`, `stage-12-quota-inspect-dashboard`) | 2 children |
| **Runner 7** | **710 passed, 21 skipped, 0 failed** | none — green |

Dominant full-suite flake: process-global `isolateConfigCache` (pool TTL 100 ms + parallel `clear()`) causing `ConfigCacheMissError` on `active_routing_policy:routing/standard` between preload and `selectCandidateChain`. Fixers followed code: pin TTL 30s and re-stamp the D1+R2 policy row immediately before POST. Secondary class: D1/`waitUntil` settlement lag after SSE terminal frames (poll, do not weaken).

## 4. Remaining gaps / failures

**None.**

- Coverage gaps: 0 (modulo deferred-to-pgTAP).
- Full-suite failures: 0.
- Unexpected skips: 0.

## 5. Deferred-to-pgTAP (hard rule 7)

Not Worker gaps. Not Register 5 skips. Out of scope for this suite:

| Range | Count | Track |
|---|---|---|
| `S02-001` … `S02-027` | 27 | Stage 2 clinic keypair (Supabase/pgTAP) |
| `S06-001` … `S06-047` | 47 | Stage 6 minting an AAT (Supabase/pgTAP) |
| `S08-061` … `S08-069` | 9 | Stage 8 context-provider RPCs |
| `S11-022` … `S11-029` | 8 | Stage 11 PostgREST/SQL contract |
| **Total** | **91** | |

## 6. Register 5 skip-only IDs (20)

S00-001, S00-002, S00-003, S00-012, S00-013, S00-014, S00-028, S05-060, S05-061, S05-078, S05-082, S08-003, S08-005, S08-009, S09-075, S09-076, S09-077, S09-079, S09-082, SX-063.

Mixed (OK): `S00-007` real `it` (empty-registry seam) + throwing-load `it.skip` (Register 5 #3).

## 7. Conflicts recorded

One catalog-vs-code conflict in `phase-15-conflicts.md`:

- **S09-065** — catalog claimed the first journal row is frozen after 401 jti-replay; code continues Stage 11 settlement of request 1 (`payload_pointer` and related columns). Test still asserts 401 `unauthenticated`, one `ai_request` row, and frozen identity fields.

Production source and harness were not modified. No commit.
