# Stage 07 — Discovery E2E report

**Declaration: GREEN**

Final runner (authoritative; not fixer self-reports):

```
 Test Files  3 passed (3)
      Tests  52 passed (52)
   Start at  12:48:47
   Duration  25.48s (transform 480ms, setup 203ms, collect 2.43s, tests 59.22s, environment 0ms, prepare 770ms)
```

- Passing: **52**
- Skipped: **0** (Register 5 #7 S07-051/052 implemented via isolate cache seam; zero unexpected skips)
- Failing: **0**

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-07-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`

## 1. Chunk map

| File | ID range | Writer |
|---|---|---|
| `ai-platform/test/e2e/stage-07-routing-identity.test.ts` | S07-001 … S07-018 | Writer 1 |
| `ai-platform/test/e2e/stage-07-entitlement-filters.test.ts` | S07-019 … S07-037 | Writer 2 |
| `ai-platform/test/e2e/stage-07-etag-cache.test.ts` | S07-038 … S07-052 | Writer 3 |

## 2. Writer outcomes

### 2.1 Writer 1 — `stage-07-routing-identity.test.ts`

Implemented (real `it`): S07-001 … S07-018 (18).

Skipped: **none**.

S07-018 uses real rotate (second key) then `revoke-key` of the original kid (cannot revoke last active key), then `clearConfigCache()`, then GET with the revoked-kid AAT.

### 2.2 Writer 2 — `stage-07-entitlement-filters.test.ts`

Implemented (real `it`): S07-019 … S07-037 (19).

Skipped: **none**.

`[SEED]` only on S07-021 (corrupt `public_key`) and S07-030 (malformed `allowed_capabilities`). Catalog D1 UPDATEs without `[SEED]` (valid_until, pending installation, revoked grant, delete pending entitlement sentinel) use `seedSql` / D1 UPDATE with comments — no matching HTTP.

### 2.3 Writer 3 — `stage-07-etag-cache.test.ts`

Implemented (real `it`): S07-038 … S07-052 (15).

Skipped: **none**. S07-039 sunset overlay pairing is not a separate ID; no control-plane sunset route, so that pairing is not exercised (comment only).

S07-040 uses real `POST /control/kill-switches/arm` (Register 5 #27 is stale). S07-051/052 not skipped: isolate TTL + `clearConfigCache()`. S07-052 entitles via raw `controlFetch` because `entitleInstallation` clears the cache.

## 3. Iteration count

**2 runner→fixer iterations** (3 runner passes).

| Pass | Result | Fixers |
|---|---|---|
| Runner 1 | 51 passed, 0 skipped, **1 failed** (S07-051) | 1 fixer (`stage-07-etag-cache.test.ts`) — `seedSql` → `env.DB.prepare` |
| Runner 2 | 51 passed, 0 skipped, **1 failed** (S07-051; file-only green, parallel suite still missed 100 ms TTL) | 1 fixer — `isolateConfigCache.setTtlMs(30_000)` around the experiment, restore in `finally` |
| Runner 3 | **52 passed, 0 skipped, 0 failed** | none — green |

## 4. Final counts (Runner 3)

| | Count |
|---|---|
| Passing | 52 |
| Skipped | 0 |
| Failing | 0 |
| Test files | 3 passed |

Skipped IDs: none.

## 5. Catalog-vs-code conflicts

Recorded in `ai-platform/test/e2e/reports/stage-07-conflicts.md`. Tests follow code.

### 5.1 S07-051 — injectable 30 s ConfigCache vs pool TTL 100

Catalog: `handleDiscoveryRequest` with `new ConfigCache(30000)`; D1 revoke without cache clear still lists; `cache.clear()` then empty.

Code / harness: injectable cache is not on the frozen barrel; pool `CONFIG_CACHE_TTL_MS` is `"100"` (TTL `"0"` unsafe). Clinic GETs hit `isolateConfigCache`. Test uses barrel `isolateConfigCache.setTtlMs(30_000)` before the warm GET, then restores TTL 100 in `finally`. Assertions unchanged (listed → still listed → empty after `clearConfigCache()`).

`config-cache/index.ts:72-78` (`setTtlMs`); `:153` (`isolateConfigCache`); `vitest.e2e.config.ts` TTL `"100"`.

### 5.2 S07-029 / S07-037 — empty `grants: []` is 400

Catalog wants no grant rows / `grants: []`. Code rejects empty grants (`400 invalid_payload`, Stage 4). S07-029 keeps a dummy installation grant (`allowed_capabilities: []` skips grant evaluation). S07-037 uses an unpublished `clinic.patient_triage` installation grant so both `clinic.visit_summary` grant lookups miss.

### 5.3 S07-040 — kill-switch HTTP exists

Catalog `[SEED]` INSERT (Register 5 #27: no HTTP API). Code has `POST /control/kill-switches/arm`. Test uses the real arm route. Discover never loads `kill_switches`; capability stays listed.

### 5.4 Default entitle grants vs B0

Harness `DEFAULT_ENTITLE_PAYLOAD` writes installation **and** plan grants. Catalog B0 is installation-only. Tests override to installation-only except S07-034 (both) and S07-036 (plan only), so S07-033/S07-051 revoke actually empties the list.

### 5.5 Phase 0 alignments still in force

- AAT claim is `role`, not `roles` (S07-041 mints `role: "receptionist"`).
- `CONFIG_CACHE_TTL_MS="0"` is unsafe; harness `"100"`.
- Control 401 is `{ "error": "unauthorized" }` (not used on this clinic GET path).
- Entitle is one-shot (`409 not_pending`).
- Stage 6 minting is deferred; tests mint via harness `mintAat` after real enroll. No Supabase IDs.

## 6. Harness gaps (commented in tests; harness not extended)

| ID | Gap |
|---|---|
| S07-003…S07-006 | Cannot assert `discovery_auth_rejected` log reasons; isolate console not captured (Register 5 #5). HTTP taxonomy asserted instead. |
| S07-027 | No HTTP to delete the enroll pending-entitlement sentinel; catalog journey uses D1 DELETE. |
| S07-024 | Enroll writes `status = 'active'`; no HTTP “stop before activation”; D1 UPDATE to `pending`. |
| S07-019 / S07-033 / S07-034 | No HTTP for `valid_until` / grant `revoked_at`; D1 UPDATE. |
| S07-042…S07-049 | `getCapabilities` omits `Cache-Control` / `Content-Type` and treats 304 as `body: null`. Tests use `clinicFetch` + `readHttpResult`. |
| S07-051/052 | `handleDiscoveryRequest` injectable cache not on barrel. S07-051 uses `isolateConfigCache.setTtlMs(30_000)`. S07-052 uses raw `controlFetch` entitle because `entitleInstallation` always `clear()`s. |

## 7. Remaining failures

None.

## 8. Out-of-scope / deferred

**Supabase contract scenarios: none in Stage 07.** All 52 catalog IDs are Worker `GET /v1/capabilities`. Stage 6 minting is deferred; AATs are minted with harness `mintAat` after real enroll. Register 5 #7 (S07-051/052) is automatable and was implemented, not skipped.

## 9. Files touched (tests + reports only)

- `ai-platform/test/e2e/stage-07-routing-identity.test.ts` (Writer 1)
- `ai-platform/test/e2e/stage-07-entitlement-filters.test.ts` (Writer 2)
- `ai-platform/test/e2e/stage-07-etag-cache.test.ts` (Writer 3, then Fixers 1–2)
- `ai-platform/test/e2e/reports/stage-07-failures.md` (runners)
- `ai-platform/test/e2e/reports/stage-07-conflicts.md` (fixers)
- `ai-platform/test/e2e/reports/stage-07.md` (this report)

Harness, production `ai-platform/src/`, and `backend/supabase/migrations/` were not modified.
