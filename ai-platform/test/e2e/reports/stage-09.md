# Stage 09 — The Guard E2E report

**Declaration: GREEN**

Final runner (authoritative; not fixer self-reports):

```
 Test Files  4 passed (4)
      Tests  80 passed | 5 skipped (85)
   Start at  14:17:59
   Duration  26.29s (transform 533ms, setup 260ms, collect 3.30s, tests 88.60s, environment 1ms, prepare 985ms)
```

- Passing: **80**
- Skipped: **5** (Register 5 #28: S09-075, S09-076, S09-077, S09-079; Register 5 #29: S09-082; zero unexpected skips)
- Failing: **0**

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-09-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`

## 1. Chunk map

| File | ID range | Writer |
|---|---|---|
| `ai-platform/test/e2e/stage-09-adapter-identity.test.ts` | S09-001 … S09-022 | Writer 1 |
| `ai-platform/test/e2e/stage-09-entitlement-ratelimit.test.ts` | S09-023 … S09-043 | Writer 2 |
| `ai-platform/test/e2e/stage-09-capability-context-preflight.test.ts` | S09-044 … S09-065 | Writer 3 |
| `ai-platform/test/e2e/stage-09-admission-journal-compose.test.ts` | S09-066 … S09-085 | Writer 4 |

All 85 catalog IDs (S09-001…S09-085) were assigned. No Supabase-contract IDs in this stage.

## 2. Writer outcomes

### 2.1 Writer 1 — `stage-09-adapter-identity.test.ts`

Implemented (real `it`): S09-001 … S09-022 (22).

Skipped: **none**.

### 2.2 Writer 2 — `stage-09-entitlement-ratelimit.test.ts`

Implemented (real `it`): S09-023 … S09-043 (21).

Skipped: **none**. Register 5 seams implemented rather than skipped:

- Kill-switches S09-036…039 use `POST /control/kill-switches/arm` (code route; not D1 `[SEED]`)
- #31 S09-040…043 — `createRateLimiterDouble` plus live `RATE_LIMITER_*`.limit host-object patch (same family as S08-044)

S09-032…034 entitle **without** the default plan-scope grant so plan fallback cannot admit. S09-035 is plan-only and expects HTTP 200 SSE `accepted`.

### 2.3 Writer 3 — `stage-09-capability-context-preflight.test.ts`

Implemented (real `it`): S09-044 … S09-065 (22).

Skipped: **none**. Register 5 #30 S09-050 implemented via `loadManifest` / `createCapabilityRegistry` / `setCapabilityRegistry({ replace: true })`, restored in `finally`.

### 2.4 Writer 4 — `stage-09-admission-journal-compose.test.ts`

Implemented (real `it`): S09-066…S09-074, S09-078, S09-080…S09-085 (15).

Skipped (`it.skip`, Register 5): S09-075, S09-076, S09-077, S09-079 (#28 frozen `env.DO`); S09-082 (#29 frozen `env.DB`). Documented seams exist on the barrel (`wrapDurableObjectNamespace`, `wrapD1`, `installEnvOverrides`) but do not reach `worker.fetch` / `SELF.fetch`.

Register 5 seams implemented rather than skipped:

- #28 S09-078 — live DO `request_quota: 0` path is the same 429 `quota_exhausted` observable as grace ledger exhaustion
- S09-073 — Quota DO `gatewayObjectJson` admission ×16 (no credit) then 17th `POST /v1/requests` (see conflicts)
- S09-083 — missing prompt artifact via `setCapabilityRegistry` with a broken `businessRuleFragmentRefs` pin (barrel has no `__setArtifactContentForTest`)

## 3. Iteration count

**3 runner→fixer iterations** (4 runner passes).

| Pass | Result | Fixers |
|---|---|---|
| Runner 1 | 73 passed, 0 skipped, **12 failed** | 3 files (`adapter-identity`, `entitlement-ratelimit`, `admission-journal-compose`) |
| Runner 2 | 78 passed, 5 skipped, **2 failed** (S09-022, S09-073) | 2 files |
| Runner 3 | 79 passed, 5 skipped, **1 failed** (S09-073) | 1 file (`admission-journal-compose`) |
| Runner 4 | **80 passed, 5 skipped, 0 failed** | none — green |

## 4. Final counts (Runner 4)

| | Count |
|---|---|
| Passing | 80 |
| Skipped | 5 |
| Failing | 0 |
| Test files | 4 passed |
| Catalog IDs in this stage | 85 |
| Assigned to writers | 85 (S09-001…085) |
| Deferred (not tests, not skips) | 0 |

Skipped IDs (expected Register 5): S09-075, S09-076, S09-077, S09-079, S09-082.

## 5. Catalog-vs-code conflicts

Recorded in `ai-platform/test/e2e/reports/stage-09-conflicts.md`. Tests follow code.

### 5.1 S09-022 — last-character signature flip is not always a different Ed25519 blob

Catalog: flip the final JWS character (`${AAT%?}x`) → `crypto.subtle.verify` false → 401.

Code: Ed25519 signatures are 64 bytes / 86 base64url chars with unused trailing bits. A↔B (or some last-char-only mutations) can decode to the same 64 bytes. Variant (a) also flips an earlier signature character so decoded bytes change. Variant (b) (foreign keypair, enrolled `kid`) is unchanged.

### 5.2 S09-027 — restore via entitle is idempotent on live grants

Catalog: after `[SEED] DELETE FROM entitlement`, restore with Stage 4 entitle.

Code: live installation-scope grants are skipped like plan-scope duplicates. Teardown re-inserts a pending entitlement row, then `entitleInstallation` returns HTTP 200 without a second live grant. POST assertions stay HTTP 500 `internal_error`.

### 5.3 S09-068 — failed idempotent replay uses stored terminal code

Catalog: replay `failed` event body is canned `internal_error`.

Code: `replayIdempotentTerminal` uses `prior.terminalErrorCode` when it is a taxonomy code. Empty-chain setup stores `provider_unavailable`; replay asserts that code.

### 5.4 S09-073 — concurrency setup via Quota DO admission RPC

Catalog: sixteen full-path POSTs held in-flight (FakeAdapter hang).

Code: `inFlight >= 16` is the gate. The barrel has no FakeAdapter hang; overlapping `clinicFetch` still credits. Prior `inFlight` is filled with 16 documented `gatewayObjectJson` `kind: "admission"` calls (no credit) on the same `idFromName` object. The 17th `POST /v1/requests` still asserts HTTP 429 `quota_exhausted` + `period_reset`.

### 5.5 Stage 08 alignments still in force

- Invoke SSE accept is HTTP **200**, not 202.
- Unique AAT `jti` per POST (reused jti → 401 replay).
- Entitlement stage 3 runs before registry stage 5 (unknown capability without a grant is 403, not 404). S09-044 entitles the unknown id first so stage 5 is reached.
- `quota_exhausted` carries `period_reset` from entitle `period_end` (DEFAULT `2027-01-01T00:00:00.000Z`).
- AAT claim is `role`, not `roles`.
- Kill-switch arm is `POST /control/kill-switches/arm`.

## 6. Harness gaps (commented in tests; harness not extended)

| ID | Gap |
|---|---|
| S09-040…043 | `installEnvOverrides` swapping `RATE_LIMITER_*` does not reach `limit()` on `SELF.fetch`. Tests patch `.limit` on the live host objects (S08-044 family). |
| S09-063 / S09-064 | `promptScaffoldByteLength` is not on the barrel. S09-063 uses a short H0 intent; S09-064 pads toward the catalog byte boundary. |
| S09-075, S09-076, S09-077, S09-079 | Register 5 #28: in-pool `env.DO` frozen; `wrapDurableObjectNamespace` / `installEnvOverrides` do not reach `SELF.fetch`. `it.skip`. |
| S09-082 | Register 5 #29: in-pool `env.DB` frozen; `wrapD1` / `prepare` patch does not reach `SELF.fetch`. `it.skip`. |
| S09-073 | No FakeAdapter hang on the barrel. Setup uses `gatewayObjectRpc` admission ×16 (conflict 5.4). |
| S09-083 | `__setArtifactContentForTest` is not on the barrel. Test uses `setCapabilityRegistry` with a broken fragment pin instead. |
| S09-084 | Composed `CanonicalRequest` neutralization is asserted from the R2 envelope when present. |

## 7. Remaining failures

None.

## 8. Out-of-scope / deferred

**None.** Stage 09 has no Supabase contract IDs (hard rule 7). All 85 catalog IDs are either a real `it` or a Register 5 `it.skip`.

## 9. Files touched (tests + reports only)

- `ai-platform/test/e2e/stage-09-adapter-identity.test.ts` (Writer 1, then Fixers)
- `ai-platform/test/e2e/stage-09-entitlement-ratelimit.test.ts` (Writer 2, then Fixer)
- `ai-platform/test/e2e/stage-09-capability-context-preflight.test.ts` (Writer 3)
- `ai-platform/test/e2e/stage-09-admission-journal-compose.test.ts` (Writer 4, then Fixers)
- `ai-platform/test/e2e/reports/stage-09-failures.md` (runners)
- `ai-platform/test/e2e/reports/stage-09-conflicts.md` (fixers)
- `ai-platform/test/e2e/reports/stage-09.md` (this report)

Harness, production `ai-platform/src/`, `backend/supabase/migrations/`, and other stages were not modified.
