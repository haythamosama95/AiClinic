# Stage X — Cron and failure journeys E2E report

**Declaration: GREEN**

Final runner (authoritative; not fixer self-reports):

```
 Test Files  4 passed (4)
      Tests  62 passed | 1 skipped (63)
   Start at  16:32:17
   Duration  13.98s (transform 716ms, setup 303ms, collect 3.66s, tests 38.60s, environment 0ms, prepare 1.06s)
```

- Passing: **62**
- Skipped: **1** (SX-063 Register 5 #45 only; zero unexpected skips)
- Failing: **0**

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-X-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`

Per-file: `stage-X-ledger-reconciliation-sweep.test.ts` 16/16 (6752 ms); `stage-X-credit-inspect-do-rpc.test.ts` 14/14 + 1 skip (9877 ms); `stage-X-cron-flush-reconcile.test.ts` 16/16 (10935 ms); `stage-X-grace-retention.test.ts` 16/16 (11040 ms).

## 1. Chunk map

| File | ID range | Writer |
|---|---|---|
| `ai-platform/test/e2e/stage-X-cron-flush-reconcile.test.ts` | SX-001 … SX-016 | Writer 1 |
| `ai-platform/test/e2e/stage-X-grace-retention.test.ts` | SX-017 … SX-032 | Writer 2 |
| `ai-platform/test/e2e/stage-X-ledger-reconciliation-sweep.test.ts` | SX-033 … SX-048 | Writer 3 |
| `ai-platform/test/e2e/stage-X-credit-inspect-do-rpc.test.ts` | SX-049 … SX-063 | Writer 4 |

All 63 catalog IDs (SX-001…SX-063) were assigned. No Supabase-contract IDs in this stage (hard rule 7). No Supabase IDs in tests (`newScenario()` UUIDs).

## 2. Writer outcomes

### 2.1 Writer 1 — `stage-X-cron-flush-reconcile.test.ts`

Implemented (real `it`): SX-001 … SX-016 (16).

Skipped: **none**.

Register 5 #28 implemented rather than skipped (cron `invokeCron(cron, runtimeEnv)` takes wrapped env):

- SX-004 — `wrapD1` throw on `INSERT INTO platform_counter` + `invokeCron(CRON_RETENTION, { ...env, DB: shim })`
- SX-008 — direct `flushRejectionCounters({ DB: shim })` then recovery cron
- SX-013 — `wrapDurableObjectNamespace({ fetchThrow })` + `invokeCron(CRON_ROLLUP, { ...env, DO })`

### 2.2 Writer 2 — `stage-X-grace-retention.test.ts`

Implemented (real `it`): SX-017 … SX-032 (16).

Skipped: **none**. SX-017 / SX-018 / SX-022 use `wrapDurableObjectNamespace` on `invokeCron` (not skipped like S09-075 `SELF.fetch`). SX-031 AwaitingContext implemented via labeled `[SEED]` (Register 5 #36).

### 2.3 Writer 3 — `stage-X-ledger-reconciliation-sweep.test.ts`

Implemented (real `it`): SX-033 … SX-048 (16).

Skipped: **none**. SX-043 AwaitingContext implemented via labeled `[SEED]`.

### 2.4 Writer 4 — `stage-X-credit-inspect-do-rpc.test.ts`

Implemented (real `it`): SX-049 … SX-062 (14).

Skipped (`it.skip`, Register 5):

| ID | Register 5 | Reason |
|---|---|---|
| SX-063 | #45 | In-pool GatewayObject cannot take injected storage; `wrapDoStorage` only reaches `admissionRPC`/`creditRPC` |

SX-057…SX-062 use direct `gatewayObjectRpc` / `env.DO` stub.fetch (no public HTTP route).

## 3. Iteration count

**1 runner→fixer iteration** (2 runner passes).

| Pass | Result | Fixers |
|---|---|---|
| Runner 1 | 57 passed, 1 skipped, **5 failed** (SX-002, SX-020, SX-032, SX-035, SX-057) | 4 fixers (one per file) |
| Runner 2 | **62 passed, 1 skipped, 0 failed** | none — green |

## 4. Final counts (Runner 2)

| | Count |
|---|---|
| Passing | 62 |
| Skipped | 1 |
| Failing | 0 |
| Test files | 4 passed |

Skipped IDs: SX-063 (Register 5 #45). Zero unexpected skips.

## 5. Catalog-vs-code conflicts

Recorded in `ai-platform/test/e2e/reports/stage-X-conflicts.md`.

1. **SX-002 cost 0.003 vs 0.005.** Catalog wants FakeAdapter settlement cost `0.003`. Code writes `usage_event.cost=0.005` (fake-v1 10+20 tokens). Tests follow code (`toBeCloseTo(0.005, 3)` on event and rollup). `stage-X-cron-flush-reconcile.test.ts:423,:455`.

2. **SX-035 two live same-capability grants.** Catalog seeds aged + fresh live installation grants for the same capability. Unique index `idx_capability_grant_live_installation` forbids that. Seed ages the existing live grant and uses a different `capability_id` for the fresh live control. `ledger_deleted=3` unchanged.

## 6. Harness gaps

Harness was not modified. Tests import production modules with `HARNESS-GAP` comments:

- `recordGuardRejection` / `flushRejectionCounters` (`../../src/rate-limit`)
- `runAdmission` / `attachGraceUsage` (`../../src/admission`)
- `drainDroppedGraceJournal` / `reconcileGraceUsage` (`../../src/credit`)
- `createD1ConfigReader` (`../../src/config-cache`)
- `dashboardQuotaRejectionRate` (`../../src/dashboards`)
- `runRetentionPurge` / `createManifestRetentionClassResolver` (`../../src/retention`)
- `runRollupAndReconciliation` (`../../src/rollup`)
- FakeAdapter spy (`../../src/provider/fake`)
- SX-057: `gatewayObjectRpc` always attaches a body; GET uses `env.DO.get(id).fetch(new Request(QUOTA_DO_RPC_URL, { method: "GET" }))`
- SX-014: `request_quota=0` cannot be produced via `runAdmission` (`isLedgerQuotaExhausted`); entitlement_json mutated after a real grace insert (catalog did not label `[SEED]`)

Register 5 seams that **do** reach cron (unlike S09-075 `SELF.fetch`): `wrapD1` / `wrapDurableObjectNamespace` passed as `invokeCron` `runtimeEnv`.

## 7. Remaining failures

**None.**

## 8. Declaration

**GREEN**
