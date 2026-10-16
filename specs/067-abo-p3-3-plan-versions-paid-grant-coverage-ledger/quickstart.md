# Plan versions, paid-grant intake and the per-clinic coverage ledger

**Unit**: P3.3 · **Harness**: H-AP · **Verification**: T030 green

## 1. What was implemented

P3.3 adds paid-grant intake on the existing AI Platform worker (FR-001 through FR-016).

- **Paid `grant`** — class M on `VendorEntrypoint`; ABO signature verification, plan-bound checks, binding resolution, platform-signed receipt, idempotent replay, and conflict on envelope hash mismatch.
- **Plan-version and service-key methods** — `publishPlanVersion` and `retirePlanVersion` (class HP); `registerServiceKey`, `revokeServiceKey`, and `listServiceKeys` (HP/M). Service-key register and revoke raise AL-13.
- **Per-clinic DO tables** — `hot`, `term`, `grant`, and `outbox` in the quota Durable Object; DO RPC negotiates `contract_version` before any read or write.
- **Alarm ship** — `GatewayObject.alarm` drains the outbox to D1 (`coverage_event`, `grant_ledger`, `coverage_mirror`, alerts), R2 `grant-ledger/`, and related tables.
- **Calendar** — `src/coverage/calendar.ts` for UTC month clamping, day multiples, and optional staging `DURATION_SCALE`.
- **Coverage reads** — `getCoverage`, `listGrants`, and `readCoverageEvents` on the vendor entrypoint; grant apply enqueues AL-11 and, when velocity limits apply, AL-17.

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/data-model.md` | FR-001, FR-002, FR-004, FR-006, FR-011, FR-012, FR-014 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/grant-paid.md` | FR-005, FR-007, FR-008, FR-009, FR-010 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/get-coverage.md` | FR-014 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/list-grants.md` | FR-016 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/read-coverage-events.md` | FR-016 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/service-key-methods.md` | FR-004 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/plan-version-methods.md` | FR-006, FR-015 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/do-schema.md` | FR-001, FR-002, FR-003 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/coverage-event.md` | FR-011, FR-012, FR-013 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/receipt-production.md` | FR-005 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/quickstart.md` | FR-001 through FR-016 |
| `ai-platform/migrations/20261003140000_plan_version_paid_grant_coverage.sql` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/schema.snap.sql` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/src/coverage/calendar.ts` | FR-010 |
| `ai-platform/src/quota-do/index.ts` | FR-001, FR-002, FR-008, FR-010, FR-011 |
| `ai-platform/src/worker.ts` | FR-003, FR-011, FR-013 |
| `ai-platform/src/vendor/entrypoint.ts` | FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-014, FR-015, FR-016 |
| `ai-platform/src/alert/index.ts` | FR-004, FR-013 |
| `ai-platform/src/admission/index.ts` | FR-003 |
| `ai-platform/src/credit/index.ts` | FR-003 |
| `ai-platform/src/pipeline/index.ts` | FR-003 |
| `ai-platform/src/usage-summary/index.ts` | FR-003 |
| `ai-platform/src/control/quota-inspect.ts` | FR-003 |
| `ai-platform/wrangler.toml` | FR-005, FR-010 |
| `ai-platform/vitest.workers.config.ts` | FR-005 |
| `ai-platform/vitest.e2e.config.ts` | FR-005 |
| `ai-platform/test/system/harness.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/e2e/harness/d1.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/e2e/harness/gateway-object.ts` | FR-003 |
| `ai-platform/test/migrations.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/system/paid-grant-coverage.system.test.ts` | FR-001 through FR-016 |
| `ai-platform/test/worker-request-orchestrator.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/token-contract-control.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/usage-summary.test.ts` | FR-003, FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/retention.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/plan-catalogue.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/identity.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/entitle-grant.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/config-readers.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/discovery-http.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/control.test.ts` | FR-004, FR-006, FR-011, FR-012 |

The test files in the last block apply `20261003130000_issuer_key_tenant_binding.sql` themselves. Each also applies `20261003140000_plan_version_paid_grant_coverage.sql` after it. `usage-summary.test.ts` also sends `contract_version` on its direct DO `fetch`. `src/identity/index.ts`, `src/config-cache/index.ts`, `src/vendor/contract-version.ts`, and `packages/vendor-contracts/**` stay as they are. The quota JSON blob helpers stay.

## 3. Harness command for this unit's tests only

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/paid-grant-coverage.system.test.ts
```

Every scenario is asserted by H-AP; this file records harness commands only.

## 4. How to inspect the change

- **Vendor RPC:** `ai-platform/src/vendor/entrypoint.ts` — plan-version, service-key, `grant`, `getCoverage`, `listGrants`, and `readCoverageEvents`.
- **DO grant and coverage:** `ai-platform/src/quota-do/index.ts` — `apply_grant`, `read_coverage`, outbox rows, and alarm shipping.
- **Worker DO gateway:** `GatewayObject.fetch` and `GatewayObject.alarm` in `ai-platform/src/worker.ts` — contract negotiation, RPC dispatch, and alarm handler.
- **Term dates:** `ai-platform/src/coverage/calendar.ts` — month clamping, day duration, and `DURATION_SCALE`.
- **Grant alerts:** `ai-platform/src/alert/index.ts` — AL-11 per grant and AL-17 velocity.
- **Deploy config:** `PLATFORM_SIGNING_KEY` and `DURATION_SCALE` (staging only) in `ai-platform/wrangler.toml`.
- **Harness output:** run the command in §3 and confirm E2E-P3.3-01 through E2E-P3.3-12 pass.

## 5. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P3.3-01 | `vendorCall` `publishPlanVersion` then `registerServiceKey` then `grant` → `src/vendor/entrypoint.ts` → binding insert → `GatewayObject.fetch` `apply_grant` → `src/coverage/calendar.ts` → `signCompactJws` |
| E2E-P3.3-02 | `vendorCall` `grant` twice → `runDurableObjectAlarm` → `GatewayObject.alarm` → `grant_ledger` |
| E2E-P3.3-03 | `vendorCall` `grant` with a changed allowance → DO `conflict` |
| E2E-P3.3-04 | `vendorCall` `grant` twice → `vendorCall` `getCoverage` → DO `read_coverage` |
| E2E-P3.3-05 | `vendorCall` `grant` with an unknown `kid`; `vendorCall` `revokeServiceKey` then `grant` |
| E2E-P3.3-06 | `vendorCall` `grant` for each named refusal |
| E2E-P3.3-07 | `vendorCall` `grant` → `runDurableObjectAlarm` → D1 and R2 → `vendorCall` `readCoverageEvents` |
| E2E-P3.3-08 | `vendorCall` `grant` → `runDurableObjectAlarm` → `src/alert/index.ts` AL-11; a fourth paid grant → AL-17 |
| E2E-P3.3-09 | `setTestClock` → `vendorCall` `grant` → `src/coverage/calendar.ts`; the 30-minute case sets `env.DURATION_SCALE` for that call only |
| E2E-P3.3-10 | `vendorCall` `retirePlanVersion` → `vendorCall` `grant` → existing `term.plan_snapshot` |
| E2E-P3.3-11 | `env.DO.get(env.DO.idFromName(...)).fetch` POST with `contract_version` 1 → `negotiate(CHANNEL_VERSIONS.platformDo)` → echoed `contract_version` |
| E2E-P3.3-12 | The same `fetch` with `contract_version` missing or 2 → `rejected` `contract_version_unsupported` before any DO write |
