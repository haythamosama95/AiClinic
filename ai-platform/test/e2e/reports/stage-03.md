# Stage 03 — Installation enrollment E2E report

**Declaration: GREEN**

Final runner (authoritative; not fixer self-reports):

```
 Test Files  4 passed (4)
      Tests  83 passed (83)
   Start at  11:46:42
   Duration  7.95s (transform 536ms, setup 267ms, collect 3.34s, tests 15.38s, environment 0ms, prepare 911ms)
```

- Passing: **83**
- Skipped: **0** (Register 5 #2 S03-083 implemented via `dispatchControlRequest` with `{ DB }` only; zero unexpected skips)
- Failing: **0**

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-03-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`

## 1. Chunk map

| File | ID range | Writer |
|---|---|---|
| `ai-platform/test/e2e/stage-03-auth-routing.test.ts` | S03-001 … S03-020 | Writer 1 |
| `ai-platform/test/e2e/stage-03-enroll-validation.test.ts` | S03-021 … S03-040 | Writer 2 |
| `ai-platform/test/e2e/stage-03-lifecycle-rotate.test.ts` | S03-041 … S03-060 | Writer 3 |
| `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts` | S03-061 … S03-083 | Writer 4 |

## 2. Writer outcomes

### 2.1 Writer 1 — `stage-03-auth-routing.test.ts`

Implemented (real `it`): S03-001 … S03-020 (20).

Skipped: **none**.

Register 5 #9 (timing-safe compare) is not an ID skip; observable 401 bodies are asserted.

### 2.2 Writer 2 — `stage-03-enroll-validation.test.ts`

Implemented (real `it`): S03-021 … S03-040 (20).

Skipped: **none**. Register 5 #20 (importKey catch) is a note, not an ID skip.

### 2.3 Writer 3 — `stage-03-lifecycle-rotate.test.ts`

Implemented (real `it`): S03-041 … S03-060 (20).

Skipped: **none**.

### 2.4 Writer 4 — `stage-03-revoke-delete-purge.test.ts`

Implemented (real `it`): S03-061 … S03-083 (23).

Skipped: **none**. S03-083 is a real `it` via barrel `dispatchControlRequest` + `{ DB: env.DB }` (no `R2`). `dispatchControl` / `controlBindingsFromEnv` were not used because they backfill pool R2.

## 3. Iteration count

**1 runner→fixer iteration** (2 runner passes).

| Pass | Result | Fixers |
|---|---|---|
| Runner 1 | 72 passed, 0 skipped, **11 failed** (S03-036, S03-037, S03-038, S03-039, S03-040, S03-047, S03-059, S03-066, S03-070, S03-078, S03-079) | 3 fixers (one per failing file) |
| Runner 2 | **83 passed, 0 skipped, 0 failed** | none — green |

## 4. Final counts (Runner 2)

| | Count |
|---|---|
| Passing | 83 |
| Skipped | 0 |
| Failing | 0 |
| Test files | 4 passed |

Skipped IDs: none.

## 5. Catalog-vs-code conflicts

Recorded in `ai-platform/test/e2e/reports/stage-03-conflicts.md`. Tests follow code.

### 5.1 Enroll success `platform_base_url` (S03-037…S03-040)

Catalog: `{"platform_base_url":"http://localhost:8787"}`.
Code: `handleEnroll` returns `{ platform_base_url: new URL(request.url).origin }` (`lifecycle.ts`). Pool origin is harness `GATEWAY_ORIGIN` (`https://ai-gateway.test`). HTTP 200 and D1 side effects match catalog.

### 5.2 Catalog I2 public key `XI2` is 30 bytes (S03-036, S03-047, S03-059, S03-066, S03-070, S03-078, S03-079)

Catalog `XI2` = `dGhJkLzXcVbNm2QeRtYuIoPaSd8f7a9b0c1d2e3f4` base64url-decodes to 30 bytes.
Code: `isEd25519PublicKeyByteLength` requires 32 → HTTP 400 `invalid_payload` (`platform-vocabulary.ts`, `lifecycle.ts` enroll length check).
Tests use `generateTestKeypair()` (32-byte key) so uppercase-UUID enroll and later I2 lifecycle/purge isolation can run. S03-036 still asserts verbatim uppercase D1 storage.

### 5.3 Revoke-key kid compare is case-sensitive (S03-070, S03-078)

Catalog revoke body uses lowercase `KI2` after S03-036 stored uppercase `key_id`.
Code: `WHERE key_id = ? AND installation_id = ?` with no case folding; SQLite TEXT compare is case-sensitive → 404 `key_not_found`.
Tests send the stored uppercase kid so revoke-on-suspended and delete-from-suspended are exercised.

### 5.4 Purge vs `grace_admission_queue` FK (S03-079)

Catalog: HTTP 200 `{}`; two `purge_installation` audits; D1 footprint including `installation` deleted; grace row survives.
Code: `purgeByInstallationId` deletes R2 then a D1 batch that never touches `grace_admission_queue`. That table FKs to `installation` (`20260821120000_grace_admission_queue.sql`). `DELETE FROM installation` fails; `runPurge` maps to HTTP 500 `{"error":"storage_error"}`. Intent audit is written first; completion audit is skipped; D1 batch rolls back; R2 objects are already gone; I2 untouched.
Test follows code (500 `storage_error`, one intent audit, grace kept, R2 gone).

### 5.5 Phase 0 conflicts still in force

- Operator bearer is harness `OPERATOR_BEARER` (`test-operator-bearer-token`), not catalog `op-token-9f8e7d6c5b4a`. Tests use `controlFetch` auth variants.
- Control 401 is `{"error":"unauthorized"}` (not taxonomy).
- AAT claim is `role`, not `roles` (not exercised in this stage).
- `CONFIG_CACHE_TTL_MS="0"` is unsafe; harness `"100"`.

## 6. Harness gaps (commented in tests; harness not extended)

| ID | Gap |
|---|---|
| S03-037 | Frozen API has `r2Exists(key)` / `getR2Json(key)` but no list-all. Test uses barrel `env.R2.list` (same as Stage 00). |
| S03-079 | Catalog `[SEED]` covers rollup / counter / grant / grace. Request, attempt, usage_event, and R2 envelopes are Stage 8–13 by-products; they were also seeded with a HARNESS-GAP comment so purge deletes can be observed. `env.R2.put` is pool binding use, not a harness extension. |
| S03-083 | Frozen `dispatchControl` / `controlBindingsFromEnv` backfill pool R2 (`overrides.R2 ?? env.R2`). Test calls `dispatchControlRequest` with `{ DB }` only — the documented partial-bindings seam. |

Register 5 items noted but not skipped (automatable seams used):

- #2 `missing_r2_binding` — S03-083 implemented.
- #9 timing-safe compare — functional 401 coverage only (S03-001…S03-016).
- #19 `storage_error` from `runControlBatch` — not an ID in this chapter; UNIQUE paths covered by S03-040 / S03-057.
- #20 `requireValidPublicKey` import-failure — not an ID skip.
- #21 `invalid_route` — unreachable via HTTP; not an ID skip.

## 7. Remaining failures

None.

## 8. Out-of-scope / deferred

**Supabase contract scenarios: none in Stage 03.** All 83 catalog IDs are platform-worker control-plane. Register 5 #2 was implemented rather than skipped. None deferred.

## 9. Files touched (tests + reports only)

- `ai-platform/test/e2e/stage-03-auth-routing.test.ts` (Writer 1)
- `ai-platform/test/e2e/stage-03-enroll-validation.test.ts` (Writer 2, then Fixer 1)
- `ai-platform/test/e2e/stage-03-lifecycle-rotate.test.ts` (Writer 3, then Fixer 2)
- `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts` (Writer 4, then Fixer 3)
- `ai-platform/test/e2e/reports/stage-03-failures.md` (runners)
- `ai-platform/test/e2e/reports/stage-03-conflicts.md` (fixers)
- `ai-platform/test/e2e/reports/stage-03.md` (this report)

Harness, production `ai-platform/src/`, `backend/supabase/migrations/`, Stage 00/01/02 tests, and exemplars were not modified.
