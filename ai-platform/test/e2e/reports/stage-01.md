# Stage 01 — Token contract E2E report

**Declaration: GREEN**

Final runner (authoritative; not fixer self-reports):

```
 Test Files  2 passed (2)
      Tests  31 passed (31)
   Start at  11:24:04
   Duration  7.84s
```

- Passing: **31**
- Skipped: **0** (Register 5 #7 and #8 seams implemented; zero unexpected skips)
- Failing: **0**

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-01-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`

## 1. Chunk map

| File | ID range | Writer |
|---|---|---|
| `ai-platform/test/e2e/stage-01-auth-validation.test.ts` | S01-001 … S01-016 | Writer 1 |
| `ai-platform/test/e2e/stage-01-rotation-retire.test.ts` | S01-017 … S01-031 | Writer 2 |

## 2. Writer outcomes

### 2.1 Writer 1 — `stage-01-auth-validation.test.ts`

Implemented (real `it`): S01-001, S01-002, S01-003, S01-004, S01-005, S01-006, S01-007, S01-008, S01-009, S01-010, S01-011, S01-012, S01-013, S01-014, S01-015, S01-016.

Skipped: **none**.

S01-013 is a real `it` asserting catalog C-05 HTTP 400 `{"error":"invalid_ver"}` (Register 5 #8 seam: do not skip; do not pin a TypeError body unless code throws).

### 2.2 Writer 2 — `stage-01-rotation-retire.test.ts`

Implemented (real `it`): S01-017, S01-018, S01-019, S01-020, S01-021, S01-022, S01-023, S01-024, S01-025, S01-026, S01-027, S01-028, S01-029, S01-030, S01-031.

Skipped: **none**.

Register 5 #8 (S01-017) and #7 (S01-025 / S01-026 / S01-029) are implemented: 400 `invalid_ver` per the chapter, and `clearConfigCache()` after token-contract mutations (pool TTL stays `"100"`, not `"0"`).

## 3. Iteration count

**0 runner→fixer iterations** (1 runner pass).

| Pass | Result | Fixers |
|---|---|---|
| Runner 1 | **31 passed, 0 skipped, 0 failed** | none — green |

## 4. Final counts (Runner 1)

| | Count |
|---|---|
| Passing | 31 |
| Skipped | 0 |
| Failing | 0 |
| Test files | 2 passed |

Skipped IDs: none.

## 5. Catalog-vs-code conflicts

No fixer pass was required. Writers noticed (tests follow chapter / harness / code):

1. **Operator bearer.** Catalog examples use `op-secret-token-7f3c9a`. Harness / wrangler development binding is `test-operator-bearer-token` (`OPERATOR_BEARER`). Tests use the harness constant via `controlFetch` auth variants.

2. **S01-013 / S01-017 non-string `ver`.** Register 1B / Register 4 #10 / Register 5 #8 still say non-string `ver` throws uncaught TypeError. Stage 01 chapter (C-05) and current `requireNonEmptyString` (`token-contract.ts`) return HTTP 400 `{"error":"invalid_ver"}`. Tests follow the chapter and code. Register 5 #8 is not used as `it.skip`.

3. **`CONFIG_CACHE_TTL_MS="0"` is unsafe.** Catalog S01-025/026/029 and Register 5 #7 recommend TTL 0. Phase 0 / Stage 00: TTL `"0"` throws `ConfigCacheMissError` on post-accept routing consult. Tests use harness `"100"` plus `clearConfigCache()` after begin-rotation / retire. Follow code / harness.

4. **AAT claim is `role`, not `roles`.** Tests use `role` (Phase 0 conflict).

5. **S01-024 length label.** Chapter labels the Action `ver` as 118 chars; the quoted string is longer (writer used the quoted Action string). Tests passed with that string.

6. **S01-023 setup path.** Chapter allows either S01-020 then S01-027 then `" 3 "`, or fresh seed with `" 2 "`. Tests used the fresh-seed `" 2 "` alternative. Behavior under test is trim-before-insert.

7. **Catalog installation UUIDs are illustrative.** S01-004 / S01-025 / S01-026 / S01-029 use harness `newScenario()` / `provisionHappyPath()` IDs.

No `stage-01-conflicts.md` was created (no fixer pass).

## 6. Harness gaps

Writers reported **none**. Auth variants, truncated JSON via string `body`, AAT mint after real `enrollInstallation` / `provisionHappyPath`, D1 snapshots, and `clearConfigCache()` all fit the frozen API. Guard-rejection metrics for S01-026 / S01-029 were flushed with `invokeCron` and read from `platform_counter` (existing Stage 00 pattern). Harness was not extended.

## 7. Remaining failures

None.

## 8. Out-of-scope / deferred

**Supabase contract scenarios: none in Stage 01.** All 31 catalog IDs are platform-worker / D1 token-contract / identity probes against Stage 1 state. Register 5 #7 and #8 have automatable seams and were implemented rather than skipped.

## 9. Files touched (tests + reports only)

- `ai-platform/test/e2e/stage-01-auth-validation.test.ts` (Writer 1)
- `ai-platform/test/e2e/stage-01-rotation-retire.test.ts` (Writer 2)
- `ai-platform/test/e2e/reports/stage-01-failures.md` (Runner 1)
- `ai-platform/test/e2e/reports/stage-01.md` (this report)

Harness, production `ai-platform/src/`, `backend/supabase/migrations/`, Stage 00 tests, and exemplars were not modified.
