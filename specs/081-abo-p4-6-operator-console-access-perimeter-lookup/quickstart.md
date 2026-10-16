# Operator console: Access perimeter, lookup, views and class-H ABO actions

**Unit**: P4.6 · **Harness**: H-XW · **Verification**: T014 green

## 1. What was implemented

The ops console on the ops host validates the Access JWT, looks up one clinic, serves the clinic page and global views, retries parked grant work, and cancels an open checkout. Class-H actions record append-only `operator_action` in ABO D1 and `control_audit` on the platform (FR-001 through FR-008).

- **Ops console module** (`abo/src/ops/index.ts`) — `verifyAccessJwt` on `Cf-Access-Jwt-Assertion`; lookup by `AIC-…`, `org_id`, billing email, `CK-`, `PAY-`, or `GR-`; clinic page with `inspectCoverage` relay; global views for parked work, findings, grants, payout imports, and key/credential registries; retry parked grant work; cancel open checkout.
- **Platform method** (`ai-platform/src/vendor/entrypoint.ts`) — class-H `recordOperatorAction` frozen on `VendorEntrypoint`; uses `verifyHpAccess` and `writeEntrypointAudit`.
- **Schema** (`abo/migrations/0006_operator_action.sql`) — append-only `operator_action` with `action_id`, `actor_email`, `access_jti`, `action`, `subject`, `params_sha256`, `assertion_sha256`, and `result`.
- **Worker dispatch** (`abo/src/worker.ts`) — `/ops/*` delegated after `checkContractVersion(request, "aboConsole")`; stale or missing version returns HTTP 400 `contract_version_unsupported` with `reload: true` before authentication and before any write.
- **Access JWT fixture** (`abo/test/system/hxw-access-fixture.ts`) — `mintHxwVendorAccessJwt` sets `jti` and accepts an optional `iss` override.
- **Vitest include** (`abo/vitest.cross-worker.config.ts`) — adds `test/system/ops.cross-worker.test.ts` to H-XW.
- **Harness** — seven E2E scenarios in `abo/test/system/ops.cross-worker.test.ts` (H-XW platform worker). The harness observes every scenario; no manual steps.

### 1.1 Files this unit adds or modifies

| File | FR |
| --- | --- |
| `abo/migrations/0006_operator_action.sql` | FR-007 |
| `abo/src/ops/index.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `abo/src/worker.ts` | FR-001, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `ai-platform/src/vendor/entrypoint.ts` | FR-001, FR-007 |
| `abo/test/system/hxw-access-fixture.ts` | FR-007 |
| `abo/vitest.cross-worker.config.ts` | FR-001 |
| `abo/test/system/ops.cross-worker.test.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `specs/081-abo-p4-6-operator-console-access-perimeter-lookup/quickstart.md` | FR-001–FR-008 |

## 2. Harness command for this unit's tests only

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/ops.cross-worker.test.ts
```

## 3. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P4.6-01 | `opsFetch` → `worker.ts` `handleOps` → `ops/index.ts` `verifyAccessJwt`; `platformCall` → `VendorEntrypoint.recordOperatorAction` → `verifyHpAccess` |
| E2E-P4.6-02 | `opsFetch` → `ops/index.ts` lookup and clinic page → `PLATFORM.inspectCoverage`; same session → parked, findings, `PLATFORM.listGrants`, payout imports, `PLATFORM.listIssuerKeys` / `listServiceKeys` / `listOperatorCredentials` |
| E2E-P4.6-03 | `opsFetch` → `ops/index.ts` lookup |
| E2E-P4.6-04 | `opsFetch` → `GET /ops/parked` → `POST` retry → `operator_action` → `PLATFORM.recordOperatorAction` → `work/grant.ts` `runDueGrantWork` |
| E2E-P4.6-05 | `opsFetch` → cancel → `operator_action` → `PLATFORM.recordOperatorAction`; later `worker.ts` `scheduled` → `work/sweep.ts` → `work/runner.ts` `paid_late` |
| E2E-P4.6-06 | `opsFetch` → `worker.ts` version gate (`reload: true`); `ops/index.ts` is not called |
| E2E-P4.6-07 | `opsFetch` → `ops/index.ts` → `PLATFORM.inspectCoverage`; `platformCall("inspectCoverage")` with no JWT |
