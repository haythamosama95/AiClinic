# Grant pipeline to platform purchase

**Unit**: P4.4 · **Harnesses**: H-XW, H-PAY · **Verification**: T019 green

## 1. What was implemented

Paid checkout confirmation enqueues grant work; the grant step builds a signed envelope and calls `PLATFORM.grant`, then records outcomes, alerts, and clinic billing reads (FR-001 through FR-010).

- **Grant step** (`abo/src/work/grant.ts`) — `runDueGrantWork` and `refreshSigningKeyCheck`; paid envelopes carry an operation-object approval; retries respect transient/rejected/parked semantics; receipt verification against configured platform keys.
- **Schema** (`abo/migrations/0004_grant.sql`) — `grant_request`, `grant_outcome`, `reversal`, and `signing_key_gate`.
- **Notify kick** (`abo/src/notify/intake.ts`) — processed Paymob callback `waitUntil` runs confirm, then `runDueGrantWork`.
- **Checkout reads** (`abo/src/clinic-api/checkouts.ts`) — `shown_state` `Active` when payment is paid and grant outcome is `applied` or `already_applied`.
- **Billing reads** (`abo/src/clinic-api/billing-reads.ts`) — `GET /v1/subscription` and cursor-paged `GET /v1/payments`.
- **Alerts** (`abo/src/alert/index.ts`) — AL-04, AL-07, and AL-23.
- **Worker dispatch** (`abo/src/worker.ts`) — grant cron, signing-key refresh, billing routes, and `PLATFORM.grant` / `listServiceKeys` bindings.
- **Wrangler / vitest** — `ABO_GRANT_KEY`, `PLATFORM_PUBLIC_KEYS`, grant test include, and `PLATFORM_HTTP` fetch binding.
- **Paid approval validation** (`packages/vendor-contracts/src/grant-envelope.ts`) — `validateApproval` accepts the paid operation-object element for the minimum-of-one check; complimentary assertions keep WebAuthn checks.
- **Harness** — nine E2E scenarios in `abo/test/system/grant.cross-worker.test.ts` (H-XW platform worker + H-PAY Paymob stub).

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `abo/migrations/0004_grant.sql` | FR-005, FR-006, FR-009, FR-010 |
| `abo/src/work/grant.ts` | FR-001, FR-002, FR-003, FR-004, FR-006, FR-007, FR-010 |
| `abo/src/clinic-api/billing-reads.ts` | FR-005, FR-009 |
| `abo/src/clinic-api/checkouts.ts` | FR-001, FR-008 |
| `abo/src/notify/intake.ts` | FR-001, FR-008 |
| `abo/src/worker.ts` | FR-001, FR-002, FR-005, FR-006, FR-008, FR-009 |
| `abo/src/alert/index.ts` | FR-002, FR-003, FR-006 |
| `abo/wrangler.toml` | FR-001, FR-007 |
| `abo/vitest.cross-worker.config.ts` | FR-001, FR-007 |
| `abo/test/system/grant.cross-worker.test.ts` | FR-001–FR-009 |
| `abo/test/stubs/paymob/worker.ts` | FR-001 (harness amount sync) |
| `packages/vendor-contracts/src/grant-envelope.ts` | FR-001 (paid approval shape) |
| `specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/quickstart.md` | FR-001–FR-010 |

## 3. Harness command for this unit's tests only

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/grant.cross-worker.test.ts
```

## 4. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P4.4-01 | `worker.ts` `fetch` → `checkouts.ts` `handlePostCheckout` → `notify/intake.ts` → `work/runner.ts` `runConfirmForWorkId` → `work/grant.ts` `runDueGrantWork` → `PLATFORM.grant` → `PLATFORM_HTTP.fetch` `/v1/requests` → `checkouts.ts` `handleGetCheckout` → `billing-reads.ts` payments |
| E2E-P4.4-02 | `work/grant.ts` → `PLATFORM.grant` (`transient`) → `alert/index.ts`; clock; then `applied` |
| E2E-P4.4-03 | `work/grant.ts` → `PLATFORM.grant` (`rejected`) → park + AL-07 |
| E2E-P4.4-04 | `work/grant.ts` → `PLATFORM.grant` → thrown batch → retry `already_applied` |
| E2E-P4.4-05 | `work/grant.ts` twice → `billing-reads.ts` `GET /v1/subscription` |
| E2E-P4.4-06 | `worker.ts` `scheduled` / first fetch → `work/grant.ts` `refreshSigningKeyCheck` → `PLATFORM.listServiceKeys` → pause → resume |
| E2E-P4.4-07 | `work/grant.ts` receipt verify → `grant_outcome` |
| E2E-P4.4-08 | `notify/intake.ts` `waitUntil` → `work/grant.ts` with no clinic GET → `checkouts.ts` `handleListOpenCheckouts` |
| E2E-P4.4-09 | `worker.ts` `fetch` → `billing-reads.ts` payments |
