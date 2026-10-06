# Quickstart — P3.11 platform rebuild procedures and write budget

## 1. What was implemented

- **`rebuildClinicDo` on `VendorEntrypoint`** — class-H method rebuilds one clinic's DO from the last `coverage_event` snapshot plus later `grant_ledger` / `grant_void`, hold, release, suspension, and transfer events and `usage_event` rows into DO `term` and `hot` (FR-001, E2E-P3.11-01).
- **Mirror compare and platform alert** — when the rebuilt DO diverges from `coverage_mirror`, an insert into `platform_alert` records the mismatch (FR-002, E2E-P3.11-02).
- **`rebuildGrantLedger` on `VendorEntrypoint`** — separate class-H method lists R2 `grant-ledger/` objects and `INSERT OR IGNORE`s into `grant_ledger` and `grant_void` (FR-003, E2E-P3.11-03).
- **`refreshCoverageSnapshot` on `VendorEntrypoint`** — separate class-H method enqueues one snapshot `coverage_event` on the DO outbox; existing ship updates D1 `coverage_event` and `coverage_mirror` (FR-004, E2E-P3.11-04).
- **Write-budget measurement on `POST /v1/requests`** — admission and settlement in `src/quota-do/index.ts` record per-request DO row writes (FR-005, FR-006).

`ai-platform/src/worker.ts` stays on the existing `POST /v1/requests` entry.

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `specs/075-abo-p3-11-platform-rebuild-procedures-write-budget/research.md` | FR-006 |
| `specs/075-abo-p3-11-platform-rebuild-procedures-write-budget/quickstart.md` | FR-001 through FR-006 |
| `ai-platform/src/vendor/entrypoint.ts` | FR-001, FR-002, FR-003, FR-004 |
| `ai-platform/src/quota-do/coverage.ts` | FR-001, FR-002, FR-003, FR-004 |
| `ai-platform/src/alert/index.ts` | FR-002 |
| `ai-platform/src/quota-do/index.ts` | FR-006 |
| `ai-platform/src/worker.ts` | FR-006 |
| `ai-platform/test/system/harness.ts` | FR-001, FR-003, FR-004 |
| `ai-platform/test/system/platform-rebuild.system.test.ts` | FR-001, FR-002, FR-003, FR-004 |

`packages/vendor-contracts/**` stays. No migration file. `ai-platform/package.json` script `test:load` stays pointed at `test/load/load-and-cost.test.ts`.

## 3. Harness commands (this unit only)

System rebuild and snapshot tests (E2E-P3.11-01 through E2E-P3.11-04):

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/platform-rebuild.system.test.ts
```

Do not use `npm test`, `npm run test:load`, or other packages for this unit (rule S8).

## 4. Entry point → module chain (E2E ids)

| ID | Chain |
| --- | --- |
| E2E-P3.11-01 | `vendorCall("rebuildClinicDo")` → `VendorEntrypoint.rebuildClinicDo` → `src/quota-do/coverage.ts` load of the last `coverage_event`, later `grant_ledger` / `grant_void` / hold events, and `usage_event` → DO `term` and `hot`. |
| E2E-P3.11-02 | `vendorCall("rebuildClinicDo")` → the same rebuild → compare with `coverage_mirror` → `src/alert/index.ts` insert into `platform_alert`. |
| E2E-P3.11-03 | `vendorCall("rebuildGrantLedger")` → `src/quota-do/coverage.ts` list of R2 `grant-ledger/` → `INSERT OR IGNORE` into `grant_ledger` and `grant_void`. |
| E2E-P3.11-04 | `vendorCall("refreshCoverageSnapshot")` → DO outbox `coverage_event` → existing ship into D1 `coverage_event` and `coverage_mirror`. |
