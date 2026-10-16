# Notification intake, inquiry, work pipeline and payment confirmation

**Unit**: P4.3 · **Harnesses**: H-ABO, H-PAY · **Verification**: T026 green

## 1. What was implemented

Paymob callbacks on the billing host are HMAC-checked, stored as evidence, and confirmed by inquiry into one payment, checkout events, and a `grant` work row when the disposition is `grant` (FR-001 through FR-012).

- **Notify intake** (`abo/src/notify/intake.ts`) — `POST /notify/paymob` (body cap, per-IP rate limit, HMAC, dedupe, evidence in R2, `confirm` work enqueue); `GET /notify/paymob` and `GET /return/paymob` schedule inquiry without `waitUntil`.
- **Work runner** (`abo/src/work/runner.ts`) — lease, backoff, Paymob inquiry, confirm batch (payment, checkout events, `grant` row), classifications and dispositions.
- **Provider** — `parseNotification` and `inquire` on `abo/src/provider/port.ts`, `abo/src/provider/paymob/adapter.ts`, and inquiry HTTP in `abo/src/provider/paymob/client.ts`.
- **Alerts** (`abo/src/alert/index.ts`) — `raiseAlert` for AL-01, AL-02, AL-05, and AL-09.
- **Worker dispatch** (`abo/src/worker.ts`) — billing notify/return routes before `/v1/` gates; `waitUntil` on processed POST callbacks; minute cron runs due `confirm` rows.
- **Schema** (`abo/migrations/0003_notify_work.sql`) — `notification`, `inquiry_result`, `payment`, `work`, `paymob_txn`, `paymob_state_seen`, `notify_rate`.
- **Harness** — H-PAY inquiry routes and script, Paymob fixtures, intake fault helpers, `PAYMOB_STUB` binding, and twelve E2E scenarios in `notify.system.test.ts`.

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `abo/migrations/0003_notify_work.sql` | FR-001, FR-002, FR-004, FR-005, FR-006, FR-007, FR-008, FR-010 |
| `abo/src/provider/port.ts` | FR-001, FR-005, FR-012, FR-013 |
| `abo/src/provider/paymob/client.ts` | FR-005, FR-008, FR-013 |
| `abo/src/provider/paymob/adapter.ts` | FR-001, FR-003, FR-004, FR-005, FR-006, FR-012, FR-013 |
| `abo/src/notify/intake.ts` | FR-001, FR-002, FR-003, FR-009, FR-011, FR-012 |
| `abo/src/work/runner.ts` | FR-001, FR-004, FR-005, FR-006, FR-007, FR-008, FR-010 |
| `abo/src/alert/index.ts` | FR-003, FR-005, FR-007, FR-008 |
| `abo/src/worker.ts` | FR-001, FR-008, FR-011, FR-012 |
| `abo/wrangler.toml` | FR-001, FR-013 |
| `abo/test/stubs/paymob/worker.ts` | FR-013 |
| `abo/test/fixtures/paymob/success.json` | FR-003, FR-004, FR-013 |
| `abo/test/fixtures/paymob/decline.json` | FR-003, FR-004, FR-013 |
| `abo/test/fixtures/paymob/refund-parent.json` | FR-003, FR-004, FR-013 |
| `abo/test/fixtures/paymob/refund-child.json` | FR-003, FR-004, FR-013 |
| `abo/test/fixtures/paymob/bad-hmac.json` | FR-003, FR-004, FR-013 |
| `abo/test/system/harness.ts` | FR-009, FR-010, FR-013 |
| `abo/test/system/notify.system.test.ts` | FR-001–FR-012 |
| `abo/vitest.workers.config.ts` | FR-013 |
| `specs/078-abo-p4-3-notification-intake-inquiry-work-pipeline/quickstart.md` | FR-001–FR-012 |

## 3. Harness command for this unit's tests only

```bash
cd abo && npx vitest run --config vitest.workers.config.ts test/system/notify.system.test.ts
```

## 4. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P4.3-01 | `worker.ts` → `notify/intake.ts` → `adapter.ts` `parseNotification` → R2 and D1 → `waitUntil` → `work/runner.ts` → `adapter.ts` `inquire` → `client.ts` → H-PAY |
| E2E-P4.3-02 | `worker.ts` → `notify/intake.ts` → `adapter.ts` `parseNotification` → R2 and D1 → `waitUntil` → `work/runner.ts` → `adapter.ts` `inquire` → `client.ts` → H-PAY |
| E2E-P4.3-03 | `worker.ts` → `notify/intake.ts` → `adapter.ts` → R2 `hmac-invalid/` → `alert/index.ts` |
| E2E-P4.3-04 | `worker.ts` → `notify/intake.ts` → `adapter.ts` `parseNotification` → R2 and D1 → `waitUntil` → `work/runner.ts` → `adapter.ts` `inquire` → `client.ts` → H-PAY |
| E2E-P4.3-05 | the 01 chain, with the scripted inquiry result |
| E2E-P4.3-06 | the 01 chain, with the scripted inquiry result |
| E2E-P4.3-07 | the 01 chain, with the scripted inquiry result |
| E2E-P4.3-08 | `worker.ts` `scheduled` and `waitUntil` → `work/runner.ts` |
| E2E-P4.3-09 | `worker.ts` → `notify/intake.ts` with the harness wrappers |
| E2E-P4.3-10 | `worker.ts` `scheduled` and `waitUntil` → `work/runner.ts` |
| E2E-P4.3-11 | `worker.ts` → `notify/intake.ts` (no `waitUntil`) |
| E2E-P4.3-12 | `worker.ts` → `notify/intake.ts` (no `waitUntil`) |
