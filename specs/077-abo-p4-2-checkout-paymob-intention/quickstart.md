# Checkout creation, Paymob intention, coverage view and cross-worker harness

**Unit**: P4.2 · **Harnesses**: H-XW, H-PAY, import-boundary · **Verification**: T029 green

## 1. What was implemented

Clinic administrators open Paymob Unified Checkout sessions from the billing host, with live or cached platform coverage on the response, append-only checkout facts in D1, and a minute cron that refreshes `coverage_view` from the platform feed (FR-001 through FR-009).

- **Checkout API** (`abo/src/clinic-api/checkouts.ts`) — `POST /v1/checkouts` validates sellable offers, billing contact, and current terms; idempotent `client_request_id`; hourly create rate limit; `GET /v1/checkouts/{id}` and `GET /v1/checkouts?open=1` are tenant-scoped.
- **Provider port and Paymob** — `abo/src/provider/port.ts`, `registry.ts`, `paymob/adapter.ts`, and `paymob/client.ts` (sole provider HTTP). Domain code uses the registry and port only.
- **Coverage snapshot** (`abo/src/coverage/view.ts`) — minute cron reads `PLATFORM.readCoverageEvents` and updates `coverage_view` and `feed_cursor` when `(binding_epoch, clinic_seq)` advances.
- **Worker dispatch** (`abo/src/worker.ts`) — billing routes and cron hook; `wrangler.toml` binds Paymob env vars and `PLATFORM` (`VendorEntrypoint`).
- **Harness** — H-PAY and platform-throw stubs, cross-worker vitest configs, platform build script, import-boundary check, and CI jobs `abo-cross-worker` and `abo-import-boundary`.

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `abo/migrations/0002_checkout.sql` | FR-001, FR-005, FR-008 |
| `abo/src/provider/port.ts` | FR-005 |
| `abo/src/provider/registry.ts` | FR-001, FR-005 |
| `abo/src/provider/paymob/client.ts` | FR-001, FR-009 |
| `abo/src/provider/paymob/adapter.ts` | FR-001, FR-005, FR-009 |
| `abo/src/clinic-api/checkouts.ts` | FR-001–FR-007 |
| `abo/src/coverage/view.ts` | FR-003, FR-008 |
| `abo/src/worker.ts` | FR-001, FR-002, FR-007, FR-008 |
| `abo/wrangler.toml` | FR-001, FR-002 |
| `abo/package.json` | FR-009 |
| `abo/scripts/build-platform-for-hxw.mjs` | FR-002, FR-009 |
| `abo/scripts/check-import-boundary.mjs` | FR-009 |
| `abo/vitest.cross-worker.config.ts` | FR-002, FR-009 |
| `abo/vitest.platform-throw.config.ts` | FR-003, FR-009 |
| `abo/test/stubs/paymob/worker.ts` | FR-001, FR-005, FR-009 |
| `abo/test/stubs/platform-throw/worker.ts` | FR-003 |
| `abo/test/system/cross-worker-harness.ts` | FR-002, FR-009 |
| `abo/test/system/checkout.cross-worker.test.ts` | FR-001, FR-002, FR-004–FR-007 |
| `abo/test/system/checkout-throw.cross-worker.test.ts` | FR-003 |
| `abo/test/system/coverage-view.cross-worker.test.ts` | FR-008 |
| `abo/test/import-boundary/boundary.test.mjs` | FR-009 |
| `abo/test/fixtures/import-boundary/bad/src/` | FR-009 |
| `.github/workflows/ci.yml` | FR-009 |
| `specs/077-abo-p4-2-checkout-paymob-intention/quickstart.md` | FR-001–FR-009 |

## 3. Harness commands for this unit's tests only

```bash
cd abo && npm run test:cross-worker
cd abo && npm run test:import-boundary
```

## 4. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P4.2-01 | `worker.ts` → `checkouts.ts` → `registry.ts` → `adapter.ts` → `client.ts` → H-PAY |
| E2E-P4.2-02 | That chain, plus `PLATFORM.getCoverage` |
| E2E-P4.2-03 | `checkouts.ts` reads `coverage_view` after the throw or `transient` result |
| E2E-P4.2-04 | `worker.ts` → `checkouts.ts` → `registry.ts` → `adapter.ts` → `client.ts` → H-PAY |
| E2E-P4.2-05 | `worker.ts` → `checkouts.ts` → `registry.ts` → `adapter.ts` → `client.ts` → H-PAY |
| E2E-P4.2-06 | `worker.ts` → `checkouts.ts` → `registry.ts` → `adapter.ts` → `client.ts` → H-PAY |
| E2E-P4.2-07 | `worker.ts` → `checkouts.ts` read paths |
| E2E-P4.2-08 | `worker.ts` `scheduled` → `coverage/view.ts` → `PLATFORM.readCoverageEvents` |
| E2E-P4.2-09 | `check-import-boundary.mjs` on the fixture tree |
