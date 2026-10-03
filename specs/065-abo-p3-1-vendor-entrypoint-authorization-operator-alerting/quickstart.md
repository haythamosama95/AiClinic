# Vendor entrypoint, operator credentials, and platform alerting

**Unit**: P3.1 · **Harness**: H-AP · **Verification**: T033 green

## 1. What was implemented

The AI Platform worker exports `VendorEntrypoint` as a named `WorkerEntrypoint` and implements operator credential lifecycle plus platform alerting (FR-001 through FR-025).

- **`VendorEntrypoint`** (`ai-platform/src/vendor/entrypoint.ts`, re-exported from `ai-platform/src/worker.ts`) — class M / HP RPC surface with version negotiation before authentication.
- **Three methods** — `registerOperatorCredential` (bootstrap when the registry is empty, otherwise HP with assertion), `revokeOperatorCredential` (HP), and `listOperatorCredentials` (M).
- **D1 tables** — `operator_credential`, `assertion_used`, and `platform_alert`; `control_audit` gains nullable `actor` and `assertion_sha256` (migration `20261003120000_operator_credential_and_platform_alert.sql`, snapshot in `schema.snap.sql`).
- **`*/5` cron branch** — `scheduled()` retries unsent `platform_alert` rows, pings `HEARTBEAT_URL`, and on job failure logs one JSON line and inserts `platform_alert` with code `scheduled_job_failed`.
- **H-AP helpers** — `vendorCall`, Access team fixture, email capture, `setTestClock`, injectable `sendPlatformEmail` failure, and heartbeat `fetch` capture in `ai-platform/test/system/harness.ts`; `TEST_CLOCK` and `VENDOR` self-binding in `vitest.workers.config.ts`.

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/research.md` | FR-001, FR-004, FR-011 |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/data-model.md` | FR-009, FR-010, FR-012, FR-019 |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/class-table.md` | FR-001, FR-004, FR-005 |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/refusal-codes.md` | FR-002, FR-016, FR-017 |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/credential-lifecycle.md` | FR-003, FR-006, FR-007, FR-008, FR-011, FR-013, FR-018 |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/alert-body.md` | FR-019, FR-022, FR-025 |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/platform-alert.md` | FR-019, FR-020, FR-021, FR-023 |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/quickstart.md` | FR-001–FR-025 |
| `ai-platform/migrations/20261003120000_operator_credential_and_platform_alert.sql` | FR-009, FR-010, FR-012, FR-019 |
| `ai-platform/schema.snap.sql` | FR-009, FR-010, FR-012, FR-019 |
| `ai-platform/src/clock.ts` | FR-014 |
| `ai-platform/src/vendor/entrypoint.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-011, FR-013, FR-015, FR-016, FR-017, FR-018 |
| `ai-platform/src/alert/index.ts` | FR-019, FR-020, FR-021, FR-022, FR-023 |
| `ai-platform/src/alert/email.ts` | FR-019, FR-020, FR-025 |
| `ai-platform/src/control/audit.ts` | FR-012 |
| `ai-platform/src/worker.ts` | FR-001, FR-021, FR-023 |
| `ai-platform/wrangler.toml` | FR-001, FR-021, FR-023, FR-024 |
| `ai-platform/vitest.workers.config.ts` | FR-014, FR-025 |
| `ai-platform/test/system/harness.ts` | FR-014, FR-025 |
| `ai-platform/test/system/vendor-entrypoint.system.test.ts` | FR-001–FR-025 |
| `ai-platform/test/worker-entry.test.ts` | S2 |

Full-suite regression is verification task T033, not this file.

## 3. Harness command for this unit's tests only

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/vendor-entrypoint.system.test.ts
```

Every scenario is asserted by H-AP; this file records harness commands only.

## 4. How to inspect the change

- **Entrypoint implementation:** `ai-platform/src/vendor/entrypoint.ts` — `VendorEntrypoint`, class table, Access JWT, assertions, credential lifecycle, and list output.
- **Wrangler export:** `ai-platform/src/worker.ts` — `export { VendorEntrypoint } from "./vendor/entrypoint"` and the `*/5` `scheduled` branch.
- **Deploy config:** `ai-platform/wrangler.toml` — `*/5 * * * *` cron, `[observability]`, `SEND_EMAIL`, vars (`ACCESS_TEAM_DOMAIN`, `HEARTBEAT_URL`, `ALERT_EMAIL_TO`, …); production and staging have no `TEST_CLOCK`.
- **Harness output:** run the command in §3 and confirm E2E-P3.1-01 through E2E-P3.1-10 pass.

## 5. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P3.1-01 | `vendorCall` → `env.VENDOR.registerOperatorCredential` → `src/vendor/entrypoint.ts` bootstrap insert → `src/alert/index.ts` AL-13 → `src/alert/email.ts` `SEND_EMAIL.send` |
| E2E-P3.1-02 | `setTestClock` → `src/clock.ts` → `vendorCall` `revokeOperatorCredential` → signer credential read in `src/vendor/entrypoint.ts`. The test also reads `wrangler.toml` and asserts the production and staging envs have no `TEST_CLOCK` |
| E2E-P3.1-03 | `vendorCall` `revokeOperatorCredential` → `verifyAccessJwt` → `verifyAssertion` → `assertion_used` insert → `src/control/audit.ts` |
| E2E-P3.1-04 | `vendorCall` `revokeOperatorCredential` → `src/clock.ts` freshness and Access email comparison in `src/vendor/entrypoint.ts` |
| E2E-P3.1-05 | `vendorCall` `revokeOperatorCredential` with a bad Access JWT → `verifyAccessJwt` → `rejected` `unauthenticated` before any D1 write |
| E2E-P3.1-06 | `vendorCall` on each of the three methods → `negotiate` in `src/vendor/entrypoint.ts` before `verifyAccessJwt` |
| E2E-P3.1-07 | `vendorCall` `revokeOperatorCredential` (signer A, target B) → revoke update → `src/alert/email.ts` → a later `vendorCall` whose signer is B |
| E2E-P3.1-08 | `src/alert/email.ts` throws → `platform_alert` stays `unsent` → `runScheduled("*/5 * * * *")` → `src/worker.ts` `scheduled` → `src/alert/index.ts` retry → `src/alert/email.ts` |
| E2E-P3.1-09 | `runScheduled("*/5 * * * *")` → `src/worker.ts` → heartbeat `fetch` captured in the harness; a thrown heartbeat `fetch` → JSON `console.log` → `platform_alert` insert |
| E2E-P3.1-10 | `vendorCall` `listOperatorCredentials` → promote-due read → active-key JSON in `detail` |
