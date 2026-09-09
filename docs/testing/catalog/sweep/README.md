# Catalog Verification — Master Work List (ai/master, 2026-09-06)

This directory + `../implementation-audit-findings.md` together form the complete,
consolidated findings set for "implement everything here and the catalog is verified
and the known bugs are fixed."

## 1. Sources

| File | Scope | Result |
|---|---|---|
| `../implementation-audit-findings.md` | Adjudication of every recorded `*-conflicts.md` entry + remediation-plan (C-01…C-24) sweep at HEAD | 5 confirmed Worker bugs, 2 minor Worker issues, 3 minor backend bugs, ~20 stale catalog texts |
| `stages-00-01-03.md` | Silent-workaround sweep, 151 scenarios | 0 code bugs; 1 CATALOG WRONG; 3 WEAK TEST |
| `stages-04-05.md` | Silent-workaround sweep, 189 scenarios | 0 code bugs; 6 WEAK TEST (1 medium: missing C-01 settlement side-effect assertions in S05-050/053/055/056/057) |
| `stages-07-08-09.md` | Silent-workaround sweep, 206 scenarios | 0 code bugs; 6 CATALOG WRONG; 11 WEAK TEST (incl. S09-066 dead replay assertion — HIGH); 2 MISSING COVERAGE |
| `stages-10-11-12.md` | Silent-workaround sweep, 135 scenarios | 0 code bugs; 7 WEAK TEST (incl. systematic missing Quota-DO credit assertions across ~22 stage-10 scenarios — MEDIUM) |
| `stage-X-and-coverage.md` | Stage X sweep (63) + independent coverage audit + harness audit | 1 TEST WRONG (SX-037); 5 unrecorded CATALOG WRONG; 7 WEAK TEST; 4 WEAK SKIPS; 13 harness deviations catalogued; coverage claims independently verified |
| `sql-track.md` | SQL-track sweep (S02, S06, S08-061…069, S11-022…029 = 91 IDs) | 1 TEST WRONG (S08-063); 1 CATALOG WRONG (S06-006); 4 WEAK TEST (incl. S06-019 fingerprint strengthening); 1 MISSING COVERAGE (S06-038) |

**Coverage (independently verified):** all 818 catalog IDs accounted for — 727 Worker
E2E tests, 91 pgTAP/SQL-track, 21 documented `it.skip`s, zero gaps, zero extras.

## 2. Consolidated work list

### 2.1 Code fixes (the only remaining code bugs)

| # | Bug | Severity | Detail |
|---|---|---|---|
| 1 | BUG-01 — purge FK failure + non-atomic partial purge | HIGH | audit §3 |
| 2 | BUG-03 — missing-handoff settlement drops attempt/credit/usage/envelope | HIGH | audit §3 |
| 3 | BUG-04 — raw-body 16 KiB mid-codepoint slice | MEDIUM | audit §3 |
| 4 | BUG-05 — truncation-exhausted drops buffered `text_delta` | MEDIUM | audit §3 |
| 5 | BUG-06 — `CONFIG_CACHE_TTL_MS=0` breaks same-request preload→consult | MEDIUM | audit §3 |
| 6 | BUG-07 — kid casing not normalized | LOW | audit §3 |
| 7 | BUG-08 — entitle installation-grant INSERT not idempotent | LOW | audit §3 |
| 8 | BUG-09/10/11 — backend: `created_by` upsert, missing REVOKE, revoke timestamp | LOW | audit §4 |

### 2.2 Test rewrites (tests that pin wrong behavior or must move with a fix)

| Scenario(s) | Why |
|---|---|
| S03-079, S10-034, S11-018, S10-028 | Pin BUG-01/03/04/05 (audit §5.1) — rewrite with the code fix |
| SX-037 | TEST WRONG: engineered FakeAdapter (`output: 0`) to pass the catalog's wrong cost arithmetic; also fakes the `2026-09` period via SQL. Rebuild on real settlements + correct priced values (sweep/stage-X-and-coverage.md) |
| S08-063 | TEST WRONG: unjustified `[SEED]` — `save_visit_documentation(visit, NULL, …)` produces the state for real (sweep/sql-track.md) |
| S09-066, S10-017 | Dead replay assertions — pass under both pre/post-C-04 behavior; drain the stream and assert NO fabricated terminal (audit BUG-02) |
| S05-050/053/055/056/057 | Add the C-01-mandated synthetic-attempt / `usage_event` / R2-envelope assertions (sweep/stages-04-05.md) |
| ~22 stage-10 scenarios | Add the catalog-mandated Quota-DO credit profile assertions (count, `partial`, `idempotencyState`, usage) (sweep/stages-10-11-12.md) |
| S06-019 | Strengthen "mint writes ONLY `ai_token_issuance`" with full-row `md5(r::text)` hashes (sweep/sql-track.md) |
| Remaining WEAK TESTs | S00-010, S00-030/031/033, S07-052, S09-058/059/060/063/064/074/078/083/084/085, S10-010, S11-012, S11-021, S12-050, S05-052/054-b, S06 B0 settings pinning, S06-024, S02-024 — see per-stage files |

### 2.3 Catalog text corrections (doc-only; tests already correct)

- Audit §5.2 (~20 rows: 202→200, 403-order, period_reset, replay code, 0.005 costs,
  XI2 fixture, S09-022 fixture, one-shot entitle, S03-080 409, AAT 600 s, 22023,
  usernames, S02-027, S11-027, S11-028/029, SX-035, S08-053 placement, S09-065 wording,
  S10-005/008).
- Sweep additions: S00-032 (error message), S07-040, S07-029/037, S09-045, S09-047,
  S09-066 text, S09-070/071/072, SX-053, SX-028, SX-056, SX-014 (missing `[SEED]`
  label), S06-006 (missing deactivate step).

### 2.4 Coverage to add

- S06-038 (soft-deleted key row behaves like unknown — verifier half).
- S07-039 (sunset pairing), S09-078 (grace-ledger exhaustion branch — currently
  substituted with the live-DO path).
- Implement the 4 weak skips S05-060/061/078/082 via Register 5 #26's documented
  direct-call seam (`selectCandidateChain` / `createD1ConfigReader` are exported;
  stage-X files already import non-barrel src modules as precedent).

### 2.5 Harness hardening (optional but recommended)

- `CONFIG_CACHE_TTL_MS=100` vs production 30 000 — real TTL windows never exercised;
  after BUG-06, adopt TTL 0 per remediation D-02 (sweep/stage-X-and-coverage.md).
- Silent compatibility-date fallback to 2025-09-06 — tests run on an older runtime
  than configured; pin or fail loudly.

## 3. What "100% verified" cannot include (by design)

Even after every item above lands, these remain outside automated verification — they
are Register 5 / remediation F-items, not oversights:

- Live provider traffic (DeepSeek/Gemini wire behavior) — Register 5 #33; belongs to
  `test/eval/live-smoke.test.ts` / manual verification.
- Multi-isolate cache divergence, timing-safe compare, real concurrency races,
  DO/D1 fault injection, platform cron triggering, wall-clock horizons — Register 5;
  17 of the 21 skips are these and are legitimate.
- Conversational / structured-output / repair paths — remediation F-01…F-08, deferred
  until such manifests ship.
- PostgREST HTTP-level shapes for the SQL track — Register 5 #12; SQL-level assertions
  are the agreed substitute.

## 4. Definition of done

1. All §2.1 code fixes landed, each in the same commit as its §2.2 test rewrite and
   its catalog text edit (remediation-plan §8's rule).
2. §2.3 catalog sweep applied (doc-only).
3. §2.4 coverage added; §2.5 harness items decided.
4. Full suite green: `npx vitest run --config vitest.e2e.config.ts` (ai-platform) and
   `bash backend/tests/catalog/run.sh` — with the rewritten tests asserting the
   *fixed* behavior, and the skip count back down from 21 to 17.
