# Quickstart — P3.10 control-plane port and vendor entrypoint removal

## 1. What was implemented

- **Class-H control on `VendorEntrypoint`** — routing policy publish/canary/promote/rollback, kill-switch arm/disarm, capability deprecate/retire, cohort activate/promote, token-contract begin-rotation/retire, and support lookup call the kept modules under `src/control/*` and `src/support/index.ts` via the vendor entrypoint instead of HTTP `/control/*`.
- **`/control/*` removed** — `worker.ts` no longer dispatches operator HTTP control routes; former paths return 404.
- **Bearer and `OPERATOR_ID` removed** — vitest worker bindings no longer supply `OPERATOR_BEARER_TOKEN` or `OPERATOR_ID`; operator auth is Access JWT on vendor calls.
- **Transitional tables dropped** — migrations remove invoicing/plan/entitlement-era tables; readers and tests use `coverClinic`, published `plan_version`, and `coverage_mirror` instead of dropped `entitlement` / `plan` SQL.
- **Crons without `0 5 1 * *`** — monthly period-close cron removed; retention (`0 3 * * *`) and rollup/reconciliation (`0 4 * * *`) remain.
- **Harness off `operatorFetch`** — system and e2e harnesses route control actions through `vendorCall` / `test/e2e/harness/control.ts` rather than bearer-backed HTTP to `/control/*`.

`publishPlanVersion`, `retirePlanVersion`, `inspectCoverage`, `suspend`, `resume`, and `deleteInstallation` remain on `VendorEntrypoint`. `GET /v1/feed/coverage`, `GET /v1/coverage`, and `feedConsumerHealth` are unchanged.

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `specs/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal/quickstart.md` | FR-001 through FR-012 |
| `ai-platform/src/vendor/entrypoint.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006 |
| `ai-platform/src/control/routing-policy.ts` | FR-001, FR-002 |
| `ai-platform/src/control/kill-switch.ts` | FR-001, FR-003 |
| `ai-platform/src/control/audit.ts` | FR-003 |
| `ai-platform/src/control/capability-lifecycle.ts` | FR-001, FR-004 |
| `ai-platform/src/control/token-contract.ts` | FR-001, FR-005 |
| `ai-platform/src/control/cohort.ts` | FR-001 |
| `ai-platform/src/support/index.ts` | FR-006 |
| `ai-platform/src/control/types.ts` | FR-008 |
| `ai-platform/src/worker.ts` | FR-007, FR-008, FR-011 |
| `ai-platform/src/period-close/index.ts` (delete) | FR-007 |
| `ai-platform/src/control/index.ts` (delete) | FR-007 |
| `ai-platform/src/control/auth.ts` (delete) | FR-007, FR-008 |
| `ai-platform/src/control/http.ts` (delete) | FR-007 |
| `ai-platform/src/control/entitle.ts` (delete) | FR-007 |
| `ai-platform/src/control/credit-price.ts` (delete) | FR-007 |
| `ai-platform/src/control/lifecycle.ts` (delete) | FR-008 |
| `ai-platform/src/control/plan.ts` (delete) | FR-008 |
| `ai-platform/src/control/quota-inspect.ts` (delete) | FR-008 |
| `ai-platform/src/control/support-purge.ts` (delete) | FR-008 |
| `ai-platform/migrations/20261006170000_drop_invoicing.sql` | FR-009 |
| `ai-platform/migrations/20261006170100_drop_plan_entitlement.sql` | FR-009 |
| `ai-platform/src/config-cache/index.ts` | FR-009 |
| `ai-platform/src/admission/index.ts` | FR-009 |
| `ai-platform/wrangler.toml` | FR-010, FR-011 |
| `ai-platform/test/system/control-plane-port.system.test.ts` | FR-001 through FR-008, FR-010, FR-011 |
| `ai-platform/test/system/harness.ts` | FR-001, FR-012 |
| `ai-platform/test/e2e/harness/control.ts` | FR-012 |
| `ai-platform/test/e2e/harness/env.ts` | FR-012 |
| `ai-platform/test/vendor-entrypoint.test.ts` | FR-012 |
| `ai-platform/test/control.test.ts` (delete) | FR-012 |
| `ai-platform/vitest.workers.config.ts` | FR-012 |
| `ai-platform/vitest.e2e.config.ts` | FR-012 |
| `ai-platform/test/period-close.test.ts` (delete) | FR-012 |
| `ai-platform/test/price-list-activation.test.ts` (delete) | FR-012 |
| `ai-platform/test/entitle-grant.test.ts` (delete) | FR-012 |
| `ai-platform/test/e2e/stage-03-enroll-validation.test.ts` (delete) | FR-012 |
| `ai-platform/test/e2e/stage-03-lifecycle-rotate.test.ts` (delete) | FR-012 |
| `ai-platform/test/e2e/stage-04-entitle-auth-period.test.ts` (delete) | FR-012 |
| `ai-platform/test/e2e/stage-04-entitle-quota-grants-validation.test.ts` (delete) | FR-012 |

Rewritten workers-pool and e2e catalogue files (T027 mapping) are listed in `plan.md` Test Layout; they are not duplicated here.

## 3. Harness commands (this unit only)

Unit file (E2E-P3.10-01 through E2E-P3.10-07):

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/control-plane-port.system.test.ts
```

E2E-P3.10-08 — rewritten catalogues (after the unit file is green):

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts test/system
cd ai-platform && npx vitest run --config vitest.e2e.config.ts test/e2e
```

Do not use repository-root `npm test` or other packages for this unit (rule S8).

## 4. Entry point → module chain (E2E ids)

| ID | Chain |
| --- | --- |
| E2E-P3.10-01 | `SELF.fetch` on `worker.ts` `fetch` for each former `isControlRoute` path → 404. Worker module loads with `OPERATOR_BEARER_TOKEN` absent from the vitest bindings. |
| E2E-P3.10-02 | `vendorCall("publishRoutingPolicy")` → `vendorCall("canaryRoutingPolicy")` → `vendorCall("promoteRoutingPolicy")` on `VendorEntrypoint` → `src/control/routing-policy.ts` → `POST /v1/requests` follows the promoted policy. |
| E2E-P3.10-03 | `vendorCall("armKillSwitch")` → `src/control/kill-switch.ts` → `writeEntrypointAudit` → `raiseAl19FromOutbox` → `POST /v1/requests` returns `capability_disabled`. |
| E2E-P3.10-04 | `vendorCall("deprecateCapability")` or `vendorCall("retireCapability")` → `src/control/capability-lifecycle.ts` → `GET /v1/capabilities`. |
| E2E-P3.10-05 | `vendorCall("beginTokenContractRotation")` → `src/control/token-contract.ts` → `token_contract` ver `2` current. |
| E2E-P3.10-06 | `vendorCall("supportLookup")` → `src/support/index.ts`, once by subscription ref and once by reference. |
| E2E-P3.10-07 | `ai-platform/wrangler.toml` `[triggers].crons` → `runScheduled("0 3 * * *")` → `runRetentionPurge`; `runScheduled("0 4 * * *")` → `runRollupAndReconciliation` keyed by `term_id`. |
| E2E-P3.10-08 | Rewritten `test/system/` and `test/e2e/` catalogues, `test/e2e/harness/control.ts`, `test/e2e/harness/env.ts`, `vitest.workers.config.ts`, `vitest.e2e.config.ts`. |
