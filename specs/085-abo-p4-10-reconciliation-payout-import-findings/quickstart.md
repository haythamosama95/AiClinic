# Reconciliation, payout import and findings

**Unit**: P4.10 · **Harness**: H-XW (+ H-PAY for E2E-P4.10-05 and E2E-P4.10-06) · **Verification**: T020 green

## 1. What was implemented

Daily reconciliation runs one function, `runReconciliation`, on cron `0 6 * * *` and again after each payout import. It performs eleven checks; each failure appends a `finding` and raises AL-10. Payout import is `POST /ops/payout-imports` on the existing `handleOps` path: the raw CSV is stored in R2, lines are parsed through `payoutLines` on the Paymob adapter, and reconciliation runs before the response. Resolve-finding is `POST /ops/findings/{findingId}/resolve`. New tables are `finding_resolution`, `payout_import`, and `payout_line` (append-only). `GET /ops/payout-imports` stays the existing empty response. `listGrants`, `getCoverage`, `readCoverageEvents`, `paymob_txn`, and `POST /ops/payments/{paymentId}/chargeback` are unchanged (FR-001 through FR-016).

- **Reconciliation** (`abo/src/reconciliation/run.ts`) — eleven checks, one `finding` per failing kind and subject, AL-10 via `raiseAlert`.
- **Scheduled hook** (`abo/src/worker.ts`) — `runScheduled("0 6 * * *")` calls `runReconciliation` after the R2 lock check and before `sendDueAlerts`.
- **Ops routes** (`abo/src/ops/index.ts`) — `POST /ops/payout-imports` and `POST /ops/findings/{findingId}/resolve`.
- **Alert** (`abo/src/alert/index.ts`) — `AL-10` with daily `next_send_at`, same interval as `AL-16`.
- **Provider port and adapter** (`abo/src/provider/port.ts`, `abo/src/provider/paymob/adapter.ts`) — `PayoutLine` and `payoutLines` CSV parsing with `paymob_txn` lookup.
- **Schema** (`abo/migrations/0008_reconciliation.sql`) — `finding_resolution`, `payout_import`, `payout_line`.
- **Vitest include** (`abo/vitest.cross-worker.config.ts`) — adds `test/system/reconciliation.cross-worker.test.ts` to H-XW.
- **Harness** — nine E2E scenarios in `abo/test/system/reconciliation.cross-worker.test.ts`. The harness observes every scenario; no manual steps.

### 1.1 Files this unit adds or modifies

| File | FR |
| --- | --- |
| `abo/migrations/0008_reconciliation.sql` | FR-002, FR-015, FR-016 |
| `abo/src/reconciliation/run.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-013, FR-014 |
| `abo/src/worker.ts` | FR-001, FR-002, FR-014 |
| `abo/src/alert/index.ts` | FR-002 |
| `abo/src/provider/port.ts` | FR-015 |
| `abo/src/provider/paymob/adapter.ts` | FR-008, FR-009, FR-010, FR-015 |
| `abo/src/ops/index.ts` | FR-001, FR-010, FR-015, FR-016 |
| `abo/test/fixtures/paymob/payout-unrecorded-chargeback.csv` | FR-010, FR-015 |
| `abo/test/fixtures/paymob/payout-amount-mismatch.csv` | FR-008, FR-009, FR-015 |
| `abo/test/system/reconciliation.cross-worker.test.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-013, FR-014, FR-015, FR-016 |
| `abo/vitest.cross-worker.config.ts` | FR-001, FR-014 |
| `specs/085-abo-p4-10-reconciliation-payout-import-findings/quickstart.md` | FR-001–FR-016 |

## 2. Harness command for this unit's tests only

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/reconciliation.cross-worker.test.ts
```

## 3. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P4.10-01 | `runScheduled("0 6 * * *")` → `scheduled()` → `runReconciliation`. Grants and the transfer are read through `VendorEntrypoint.listGrants` over `PLATFORM`. A clean month built through the existing payment, complimentary-grant, and transfer paths → zero `finding` rows |
| E2E-P4.10-02 | A paid grant is applied on the real platform worker with the testkit ABO key and no ABO payment. `runScheduled("0 6 * * *")` → `scheduled()` → `runReconciliation` → `listGrants`. AL-10 is `send_email`. Then `opsFetch` `POST /ops/findings/{findingId}/resolve`. Kind `grant_without_payment`. `send_email` received `AL-10`. One `finding_resolution` for that `finding_id` |
| E2E-P4.10-03 | `runScheduled("0 6 * * *")` → `runReconciliation` → `listGrants`, compared with `operator_action`. Complimentary platform grant and no ABO `operator_action` → `grant_without_operator_action`. Transfer grant with no `beginTransfer` `operator_action` and no `transferOut` `grant_request` → `transfer_without_authorisation` |
| E2E-P4.10-04 | The H-XW test clock advances more than 15 minutes, then `runScheduled("0 6 * * *")` → `runReconciliation`. Grant parked more than 15 minutes, payment `disposition` `grant`, no applied outcome → `payment_without_grant` |
| E2E-P4.10-05 | `opsFetch` `POST /ops/payout-imports` with `payout-unrecorded-chargeback.csv` → `handleOps` → `payoutLines` → `paymob_txn` → `runReconciliation`. Then `opsFetch` `POST /ops/payments/{paymentId}/chargeback`. Then `runScheduled("0 6 * * *")` → `runReconciliation`. Kind `unrecorded_reversal`. After the existing chargeback, the grant void count is 1 and the term state is `ended`. The re-run inserts no finding |
| E2E-P4.10-06 | `opsFetch` `POST /ops/payout-imports` with `payout-amount-mismatch.csv` → `payoutLines` → `runReconciliation`. Amount mismatch → `payout_unmatched`. The omitted payment → `payment_not_in_payout` |
| E2E-P4.10-07 | `runScheduled("0 6 * * *")` → `runReconciliation`. HMAC-valid success callback and no confirming inquiry → `callback_without_confirmation` |
| E2E-P4.10-08 | `runScheduled("0 6 * * *")` → `runReconciliation` compares `coverage_view` with `getCoverage` for clinics with events in the last day, and checks full reversals for a void receipt or tombstone. Tampered `coverage_view` → `feed_divergence`. Full reversal without a void receipt, effect not `none` and not `tombstone` → `reversal_not_applied` |
| E2E-P4.10-09 | `runScheduled("0 6 * * *")` → `runReconciliation` → `listGrants`. The test changes `signature` on one ABO `grant_outcome.receipt` whose `result` is `applied` or `already_applied`. The platform receipt stays as `listGrants` returns it. Kind `receipt_mismatch` and AL-10. The tampered row is not a void receipt and not a transfer receipt |
