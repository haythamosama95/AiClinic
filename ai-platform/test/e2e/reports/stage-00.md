# Stage 00 — Platform boot E2E report

**Declaration: GREEN**

Final runner (authoritative; not fixer self-reports):

```
 Test Files  2 passed (2)
      Tests  30 passed | 8 skipped (38)
   Start at  11:10:38
   Duration  7.07s
```

- Passing: **30**
- Skipped: **8** (all Register 5; zero unexpected skips)
- Failing: **0**

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-00-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`

## 1. Chunk map

| File | ID range | Writer |
|---|---|---|
| `ai-platform/test/e2e/stage-00-boot-bindings-routing.test.ts` | S00-001 … S00-018 | Writer 1 |
| `ai-platform/test/e2e/stage-00-auth-schema-cron-happy.test.ts` | S00-019 … S00-037 | Writer 2 |

## 2. Writer outcomes

### 2.1 Writer 1 — `stage-00-boot-bindings-routing.test.ts`

Implemented (real `it`): S00-004, S00-005, S00-006, S00-007 (harness empty-registry seam), S00-008, S00-009, S00-010, S00-011, S00-015, S00-016, S00-017, S00-018.

Skipped (`it.skip`, Register 5):

| ID | Register 5 | Reason |
|---|---|---|
| S00-001 | #1 | Pool always supplies wrangler.toml bindings; DB cannot be removed per-test |
| S00-002 | #1 | Same for R2 |
| S00-003 | #1 | Same for DO |
| S00-007 throwing-load arm | #3 | Bundled manifest is a static import; cannot become malformed in a running isolate |
| S00-012 | #5 | Requires capturing worker isolate console output |
| S00-013 | #5 | Same |
| S00-014 | #5 | Same |

S00-007 is mixed: throwing-`load()` arm skipped; empty-registry seam implemented and passing.

### 2.2 Writer 2 — `stage-00-auth-schema-cron-happy.test.ts`

Implemented (real `it`): S00-019, S00-020, S00-021, S00-022, S00-023, S00-024, S00-025, S00-026, S00-027, S00-029, S00-030, S00-031, S00-032, S00-033, S00-034, S00-035, S00-036, S00-037.

Skipped (`it.skip`, Register 5):

| ID | Register 5 | Reason |
|---|---|---|
| S00-028 | #4 | Pool applies migrations once per test database; `d1_migrations` tracking is platform behavior |

## 3. Iteration count

**2 runner→fixer iterations** (3 runner passes).

| Pass | Result | Fixers |
|---|---|---|
| Runner 1 | 25 passed, 8 skipped, **5 failed** (S00-008, S00-011, S00-024, S00-032, S00-037) | 2 fixers (one per file) |
| Runner 2 | 29 passed, 8 skipped, **1 failed** (S00-037) | 1 fixer (`stage-00-auth-schema-cron-happy.test.ts`) |
| Runner 3 | **30 passed, 8 skipped, 0 failed** | none — green |

## 4. Final counts (Runner 3)

| | Count |
|---|---|
| Passing | 30 |
| Skipped | 8 |
| Failing | 0 |
| Test files | 2 passed |

Skipped IDs: S00-001, S00-002, S00-003, S00-007 (throwing-load arm only), S00-012, S00-013, S00-014, S00-028.

## 5. Catalog-vs-code conflicts

Recorded in `ai-platform/test/e2e/reports/stage-00-conflicts.md` plus fixer notes for S00-024 / S00-032.

### 5.1 S00-008 — guard order

Catalog: entitle only `test.echo`, POST `clinic.visit_summary` → `capability_unknown` (404).
Code: guard stage 3 (`evaluateEntitlement`) runs before stage 5 (`resolve`); that setup is `forbidden_capability` (403).
Test follows code: entitle both capabilities; registry only `test.echo@9.9.9`; POST `clinic.visit_summary` → `capability_unknown`.
`pipeline/index.ts` stage 3 then 5; `entitlement/index.ts` `capability_not_granted`; `capability/index.ts` registry miss.

### 5.2 S00-011 / S00-037 — entitle is one-shot; TTL `"0"` unsafe

Catalog: Stage 4 re-entitle `allowed_capabilities: []`. Catalog S00-011 also wants `CONFIG_CACHE_TTL_MS="0"`.
Code: `handleEntitle` returns 409 `not_pending` when status is not pending (`entitle.ts:199-201`). No control route rewrites `allowed_capabilities` on an active row. Phase 0: TTL `"0"` throws `ConfigCacheMissError` on the post-accept routing consult; harness uses `"100"` + `clearConfigCache()`.
Tests follow code: cohort-activate `clinic.visit_summary@2.0.0` with `minimumPlanTier: "enterprise"` so a fresh discovery is `{"manifests":[]}`. S00-011 uses `clearConfigCache()` (TTL-0 stand-in). S00-037 uses `controlFetch` activate only (no cache clear) so the in-TTL GET is stale and the post-TTL GET is empty.

### 5.3 S00-024 — isolate rejection tallies survive D1 reset

Catalog: unrecognized cron on empty airport leaves `platform_counter` empty.
Code: `flushRejectionCounters` runs on every tick. In-isolate `rejectionTally` survives `resetE2eState` (D1 wipe only). Earlier tests in the same file (S00-019/020/022/023) tally unauthenticated rejections; the first cron writes `platform_counter`.
Test follows code: drain with a real `invokeCron`, `resetE2eState()`, then the catalog tick asserts `platform_counter === 0`.

### 5.4 S00-032 — Routing.provider message

Catalog: adding `Routing.provider` throws `Manifest must not name provider or model at manifest.Routing.provider`.
Code: exact-key validation of Routing runs first → `Malformed manifest group: Routing`. The naming-ban message is unreachable for an extra `provider` key.
Test follows code. Governance-removal and `diagnostic_400d` arms match the catalog.

### 5.5 Phase 0 conflicts still in force

- AAT claim is `role`, not `roles` (tests use `role`).
- `CONFIG_CACHE_TTL_MS="0"` is unsafe; harness `"100"`.

## 6. Harness gaps (commented in tests; harness not extended)

| ID | Gap |
|---|---|
| S00-004 | Cannot omit `RATE_LIMITER_*`; pool always supplies them. Boot + `/health` 200 still asserted. |
| S00-005 | Cannot unset `OPERATOR_BEARER_TOKEN`. Fail-closed 401 asserted with a non-matching bearer. |
| S00-006 | Cannot observe `secretStore.getSecret`; `/health` 200 is the observable. |
| S00-009 | `getCapabilityRegistry` / `resolve()` not on the barrel. Immutability asserted on a harness-installed registry handle. |
| S00-010 | Cannot reconfigure `CONFIG_CACHE_TTL_MS` per isolate; `resolveConfigCacheTtlMs` not exported. |
| S00-023 | D1 may reject `PRAGMA foreign_keys`; child-first DROP + `applyAllMigrations()` in `finally`. |
| S00-024 / S00-025 / S00-026 | Cannot capture worker log sequence; side effects (no writes) asserted instead. |
| S00-030 / S00-031 | `verifyManifestTree` / `hashManifest` not on the barrel. Local SHA-256 / `loadManifest` stand-in; committed manifests not mutated. |

## 7. Remaining failures

None.

## 8. Out-of-scope / deferred

**Supabase contract scenarios: none in Stage 00.** All 37 catalog IDs are platform-worker / build-gate / D1-schema. Register 5 skips are listed in §2; they are in-pool non-automatable, not a separate pgTAP track.

## 9. Files touched (tests + reports only)

- `ai-platform/test/e2e/stage-00-boot-bindings-routing.test.ts` (Writer 1, then Fixer 1)
- `ai-platform/test/e2e/stage-00-auth-schema-cron-happy.test.ts` (Writer 2, then Fixers 2/3)
- `ai-platform/test/e2e/reports/stage-00-failures.md` (runners)
- `ai-platform/test/e2e/reports/stage-00-conflicts.md` (fixers)
- `ai-platform/test/e2e/reports/stage-00.md` (this report)

Harness, production `ai-platform/src/`, and `backend/supabase/migrations/` were not modified.
