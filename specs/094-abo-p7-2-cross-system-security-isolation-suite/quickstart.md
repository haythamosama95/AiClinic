# Quickstart — P7.2 cross-system security and isolation suite

**Unit**: P7.2 · **Branch**: `ai/094-abo-p7-2-cross-system-security-isolation-suite` · **Verification**: T014 (nine E2E ids)

## 1. What was implemented

- **H-FS stack boot** — `p7-2-stack.mjs` boots local Supabase, the platform worker, the harness worker, the Paymob stub, and the ABO worker (with `--test-scheduled`). It captures platform `send_email` text and reads ABO D1 via `wrangler d1 execute` (FR-001–FR-009).
- **Harness vendor-call route** — `register-issuer.ts` gains `POST /vendor-call` for the eight `VendorEntrypoint` methods (`grant`, `suspend`, `resume`, `armKillSwitch`, `setCeilingPolicy`, `beginTransfer`, `releaseHeld`, `voidGrant`). `POST /register-issuer-key` stays in place (FR-005, FR-006, FR-007).
- **Dart session capture driver** — Package `abo_p7_2_session_capture` and `session_jwt_capture.dart` construct `DiscoveryClient`, `PlatformHttpsSubmitPort`, `UsageSummaryClient`, and `AboClient` with a recording `http.Client` and print `{url, authorization}` for each outbound call (FR-009).
- **Nine failing E2E tests** — Three test files cover untrusted clinic/payment callers (FR-001–FR-004), VendorEntrypoint paid grant and class H/HP (FR-005–FR-007), and credential isolation (FR-008, FR-009). Each test title starts with its E2E id. No product files were changed; this unit adds harness and test scaffolding only.

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `e2e/fullstack/src/register-issuer.ts` | FR-005, FR-006, FR-007 |
| `e2e/fullstack/test/p7-2-stack.mjs` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009 |
| `e2e/fullstack/test/p7-2-untrusted-callers.test.mjs` | FR-001, FR-002, FR-003, FR-004 |
| `e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs` | FR-005, FR-006, FR-007 |
| `e2e/fullstack/test/p7-2-credential-isolation.test.mjs` | FR-008, FR-009 |
| `e2e/fullstack/dart/pubspec.yaml` | FR-009 |
| `e2e/fullstack/dart/bin/session_jwt_capture.dart` | FR-009 |
| `specs/094-abo-p7-2-cross-system-security-isolation-suite/quickstart.md` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009 |

## 3. Harness command (this unit only)

From `e2e/fullstack/`:

```bash
node --import tsx --test test/p7-2-untrusted-callers.test.mjs test/p7-2-vendor-entrypoint.test.mjs test/p7-2-credential-isolation.test.mjs
```

**T015 result:** the harness command was not executed because the H-FS stack was not running and this workflow does not start wrangler. Do not boot wrangler. Do not run `npm test` in `e2e/fullstack`.

## 4. Entry point → module chain (E2E ids)

| ID | Chain |
| --- | --- |
| E2E-P7.2-01 | `p7-2-untrusted-callers.test.mjs` → `p7-2-stack.mjs` → ABO `fetch` → `POST /notify/paymob` and `GET /return/paymob` on `BILLING_HOST` |
| E2E-P7.2-02 | `p7-2-untrusted-callers.test.mjs` → `p7-2-stack.mjs` → PostgREST `public.issue_billing_token` and staff RPCs including `get_ai_status`; platform `GET /v1/coverage` |
| E2E-P7.2-03 | `p7-2-untrusted-callers.test.mjs` → `p7-2-stack.mjs` → ABO `handleBillingV1` paths `/v1/offers`, `/v1/subscription`, `/v1/payments`, `/v1/billing-contact`, `/v1/checkouts`, `/v1/checkouts/{id}`; PostgREST RPCs the administrator session can execute; platform `GET /v1/capabilities`, `POST /v1/requests`, `GET /v1/coverage`, `GET /v1/feed/coverage` |
| E2E-P7.2-04 | `p7-2-untrusted-callers.test.mjs` → `p7-2-stack.mjs` → ABO `POST /notify/paymob`, then the ABO inquiry of that callback against the H-FS Paymob stub |
| E2E-P7.2-05 | `p7-2-vendor-entrypoint.test.mjs` → `p7-2-stack.mjs` → harness `POST /vendor-call` → `VendorEntrypoint.grant` and the class HP methods. Platform `SEND_EMAIL` for AL-11 and AL-17. ABO `scheduled` cron `0 6 * * *` → `runReconciliation` |
| E2E-P7.2-06 | `p7-2-vendor-entrypoint.test.mjs` → `p7-2-stack.mjs` → class H: harness `POST /vendor-call` → `suspend`, `resume`, `armKillSwitch`; ABO `POST /ops/checkouts/{id}/cancel` and `POST /ops/parked/{id}/retry` with `Cf-Access-Jwt-Assertion`. Class HP: `grant` (complimentary), `setCeilingPolicy`, `beginTransfer`, `releaseHeld`, `voidGrant` |
| E2E-P7.2-07 | `p7-2-credential-isolation.test.mjs` → `p7-2-stack.mjs` → `abo/wrangler.toml` and `ai-platform/wrangler.toml`; PostgREST on local Supabase |
| E2E-P7.2-08 | `p7-2-credential-isolation.test.mjs` → `p7-2-stack.mjs` → `dart run bin/session_jwt_capture.dart` → `DiscoveryClient`, `PlatformHttpsSubmitPort`, `UsageSummaryClient`, `AboClient` |
| E2E-P7.2-09 | `p7-2-vendor-entrypoint.test.mjs` → `p7-2-stack.mjs` → harness `POST /vendor-call` → class HP methods `grant`, `setCeilingPolicy`, `beginTransfer`, `releaseHeld`, `voidGrant` |
