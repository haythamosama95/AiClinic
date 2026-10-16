# Implementation Plan: Reconciliation, payout import and findings

**Branch**: `ai/085-abo-p4-10-reconciliation-payout-import-findings` | **Date**: 2026-10-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/085-abo-p4-10-reconciliation-payout-import-findings/spec.md`

## Summary

Daily reconciliation and the post-import re-run execute one function, `runReconciliation`, for the eleven 05 §3.3 checks, including `receipt_mismatch`. Each failure appends a `finding` and raises AL-10. Depends on P4.8, phase P4, size M. Import is `POST /ops/payout-imports` and resolve-finding is `POST /ops/findings/{findingId}/resolve` on the existing `handleOps` path. The Paymob adapter `payoutLines` parses the CSV body. The raw file is stored in R2.

## Technical Context

**Language/Version**: TypeScript on the existing ABO Cloudflare Worker (`abo/`).

**Primary Dependencies**: Existing `scheduled()` in `abo/src/worker.ts` for cron `0 6 * * *`. Existing `handleOps` (`abo/src/ops/index.ts`) and `opsFetch` Access session. Existing `PLATFORM` methods `listGrants`, `getCoverage`, and `readCoverageEvents`. Existing `grantIdPaid` for `grant_id = H(payment_id)`. Existing `raiseAlert` / `sendDueAlerts`. Existing `providerForId` and Paymob adapter. Existing `paymob_txn` lookup. Existing `POST /ops/payments/{paymentId}/chargeback`. Existing `recordOperatorAction` after an ABO-verified class-H `operator_action`. H-PAY stub transaction id `99001` (`abo/test/stubs/paymob/worker.ts`).

**Storage**: Existing D1 `finding` (append-only). New D1 `finding_resolution`, `payout_import`, `payout_line`. Existing R2 binding `R2`. Existing `paymob_txn`, `payment`, `grant_outcome`, `grant_request`, `operator_action`, `reversal`, `reversal_outcome`, `notification`, `coverage_view`. No change to those tables' columns.

**Testing**: H-XW for E2E-P4.10-01, 02, 03, 04, 07, 08, and 09. H-XW + H-PAY for E2E-P4.10-05 and E2E-P4.10-06. One vitest file. Titles prefixed with the E2E id. Red tests before implementation. AL-10 is observed by capturing `send_email`.

**Target Platform**: ABO worker. Daily entry is `runScheduled("0 6 * * *")` → `scheduled()`. Import and resolve are `OPS_HOST` + `/ops/*`. Platform reads go through the `PLATFORM` binding to the real platform worker. Payout CSV fixtures live under `abo/test/fixtures/paymob/`.

**Project Type**: ABO worker module extension. Codebase is `abo`. No second codebase.

**Performance Goals**: One operator and one monthly file (02 §7). The 15-minute grant park and the 7-day payout window advance on the H-XW test clock. No real sleep.

**Constraints**: One reconciliation function. The import handler calls it before the response. No second worker, hostname, or cron. `payoutLines` stays in the Paymob adapter. CSV bytes are the import body. `file_sha256` is the SHA-256 of those bytes. `r2_key` is that object's key. Column mapping is owned by the adapter and is not frozen. `receipt_mismatch` compares each `grant_outcome` receipt for `applied` or `already_applied` with the `listGrants` receipt for that `grant_id`, field for field, including `signature`. A missing `listGrants` row fails that check. Void receipts and transfer receipts are outside it. Resolve-finding is reached inside E2E-P4.10-02 and adds no E2E id. This unit does not change `listGrants`, `getCoverage`, `readCoverageEvents`, `paymob_txn`, or the chargeback route.

**Scale/Scope**: Nine H-XW scenarios. Reconciliation lives in `abo/src/reconciliation/run.ts` and is called from `scheduled()` and from the import handler.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked again against 02 §7 and constitution v1.0.0. 02 §7 records no violation for this unit.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
      — One operator imports one monthly payout file and resolves a finding. The daily run checks that clinic payments, grants, transfers, reversals, and the coverage feed still match (02 §7 principle I; spec §4.1 Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
      — The work stays in the existing ABO worker. Daily work is the existing `0 6 * * *` cron. Import and resolve are request handlers on `/ops/*`. No second worker, hostname, or cron (02 §7 principle I).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
      — Codebase is `abo`. Platform reads use the existing `PLATFORM` binding. No clinical data and no database credential (02 §7 principle II).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
      — Clinic-side state is unchanged. Vendor-side integrity is D1 append-only triggers on `finding` and on the new payout and resolution tables (02 §7 principle III).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
      — Import and resolve-finding are class H, verified by the existing Access session on `handleOps`. Each writes `operator_action` and then `recordOperatorAction`. The CSV is stored in R2 and recorded by `file_sha256`. Paid-grant comparison uses `grantIdPaid` (02 §7 principle IV).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable
      — This unit does not add an AI write path. A failed check writes a finding and raises AL-10, repeated daily. A full reversal whose effect is `none` does not write `reversal_not_applied` (02 §7 principle V; spec §4.1 Failure Handling).

## Project Structure

### Documentation (this feature)

```text
specs/085-abo-p4-10-reconciliation-payout-import-findings/
├── plan.md
├── data-model.md
├── escalations.md         # already recorded; receipt_mismatch is decided
└── quickstart.md          # implement writes this after the nine H-XW tests pass
```

`research.md` is omitted. Spikes are none. `contracts/` is omitted. Freezes has no wire shape. `tasks.md` is not created in this phase.

#### Quickstart outline

Implement writes `quickstart.md` after the harness is green. Sections only:

- What was implemented, and the files added or modified
- Harness command for this unit's tests only: `node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/reconciliation.cross-worker.test.ts` from `abo/`
- Entry point → module chain per E2E id (the Test Layout chains below)
- Manual steps: none. The harness can see every behaviour in the test plan

### Source Code (repository root)

```text
abo/migrations/0008_reconciliation.sql
abo/src/reconciliation/run.ts
abo/src/provider/port.ts
abo/src/provider/paymob/adapter.ts
abo/src/ops/index.ts
abo/src/worker.ts
abo/src/alert/index.ts
abo/test/fixtures/paymob/payout-unrecorded-chargeback.csv
abo/test/fixtures/paymob/payout-amount-mismatch.csv
abo/test/system/reconciliation.cross-worker.test.ts
abo/vitest.cross-worker.config.ts
```

**Structure Decision**: Codebase is `abo`. `runReconciliation` is the one reconciliation function. `scheduled()` calls it on `0 6 * * *`. The import route calls it before responding. `payoutLines` is added on the existing Paymob adapter and reached through `providerForId`. `listGrants`, `getCoverage`, `readCoverageEvents`, and the chargeback handler stay unchanged.

## Consumes Binding

| Consumes | Bound to | This unit |
| --- | --- | --- |
| P4.8 | None. The unit row states no Outputs / freezes line. | Not a frozen contract. This unit calls the existing `PLATFORM.listGrants`, `PLATFORM.getCoverage`, and `PLATFORM.readCoverageEvents`, reads `paymob_txn`, and calls the existing `POST /ops/payments/{paymentId}/chargeback`. It does not change those contracts. |

## Files

| Path | Change | FR |
| --- | --- | --- |
| `abo/migrations/0008_reconciliation.sql` | Create `finding_resolution`, `payout_import`, and `payout_line` with append-only abort triggers. `finding` already exists. | FR-002, FR-015, FR-016 |
| `abo/src/reconciliation/run.ts` | `runReconciliation`. Eleven checks, one `finding` per failing kind and subject, AL-10. | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-013, FR-014 |
| `abo/src/worker.ts` | On cron `0 6 * * *`, call `runReconciliation` after the R2 lock check and before the existing `sendDueAlerts`. | FR-001, FR-002, FR-014 |
| `abo/src/alert/index.ts` | Add `AL-10` to `AlertCode`. Daily `next_send_at`, same interval as `AL-16`. | FR-002 |
| `abo/src/provider/port.ts` | `PayoutLine` and `payoutLines` on `ProviderPort`. | FR-015 |
| `abo/src/provider/paymob/adapter.ts` | `payoutLines` parses the CSV and looks up `paymob_txn`. | FR-008, FR-009, FR-010, FR-015 |
| `abo/src/ops/index.ts` | `POST /ops/payout-imports` and `POST /ops/findings/{findingId}/resolve`. | FR-001, FR-010, FR-015, FR-016 |
| `abo/test/fixtures/paymob/payout-unrecorded-chargeback.csv` | H-PAY fixture for E2E-P4.10-05. | FR-010, FR-015 |
| `abo/test/fixtures/paymob/payout-amount-mismatch.csv` | H-PAY fixture for E2E-P4.10-06. | FR-008, FR-009, FR-015 |
| `abo/test/system/reconciliation.cross-worker.test.ts` | H-XW tests E2E-P4.10-01 through E2E-P4.10-09. | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-013, FR-014, FR-015, FR-016 |
| `abo/vitest.cross-worker.config.ts` | Add the new test file to the H-XW `include` list. | FR-001, FR-014 |

`GET /ops/payout-imports` stays the existing empty response. No test-plan row reads it. `abo/src/work/reversal.ts` stays as it is, including `inquiry_disagrees`.

### Reconciliation

`runReconciliation(env)` reads the ABO clock. A failing check inserts one `finding` when no row with that `kind` and `subject` exists. `finding_id` is a ULID from the existing `ulid` helper. `detected_at` is the clock. The insert also writes `fact_log` for that row. A later run that still fails does not insert a second row. A later run that passes does not delete the row. AL-10 is `raiseAlert(env, "AL-10", "AL-10:" + finding_id, finding_id)` when the row is inserted. `active` stays 1. The daily `next_send_at` repeats the email while that alert stands.

`scheduled()` for `0 6 * * *` calls `runReconciliation` after `checkR2BucketLock` and before the existing `sendDueAlerts`, so the new AL-10 is handed to `send_email` in that same run.

| Check | Kind | Subject | Pass |
| --- | --- | --- | --- |
| Payment `disposition = grant` has `grant_outcome.result` `applied` or `already_applied` for `grantIdPaid(payment_id)` within 15 minutes of `payment.confirmed_at` | `payment_without_grant` | `payment_id` | That outcome exists and its `at` is at most 15 minutes after `confirmed_at`. No outcome yet, and `confirmed_at` is not yet 15 minutes old, also passes |
| `listGrants` row with `source_kind` `paid` has `grant_id = grantIdPaid(payment_id)` of an ABO `payment` | `grant_without_payment` | `grant_id` | That payment row exists |
| `listGrants` row with `source_kind` `complimentary` matches an ABO `operator_action` | `grant_without_operator_action` | `grant_id` | Some `operator_action.action_id` has `grantIdComp(action_id) = grant_id` |
| `listGrants` row with `source_kind` `transfer` matches an HP `beginTransfer` `operator_action` and the `transferOut` package | `transfer_without_authorisation` | `grant_id` | `grant_request.source_kind = transfer` for that `grant_id`, and `operator_action.action = beginTransfer` whose `subject` is that grant's `org_id` |
| Full reversal (`is_full = 1`) has a void receipt or tombstone, unless `effect = none` | `reversal_not_applied` | `reversal_id` | `effect` is `none` or `tombstone`, or `reversal_outcome` exists |
| Payout line `kind = payment` matches a payment by `payment_id` and amount | `payout_unmatched` | `import_id` + `:` + `line_no` | `payment_id` is set and `gross_minor = payment.amount_minor` |
| Payment settled more than 7 days before the end of an imported period appears in it | `payment_not_in_payout` | `payment_id` | A `payout_line` with `kind = payment` and that `payment_id` exists on an import of that `period`, or `paid_at` is not more than 7 days before the period end |
| Payout line `kind` `refund` or `chargeback` has a recorded reversal | `unrecorded_reversal` | `import_id` + `:` + `line_no` | A `reversal` row exists for that `payment_id` |
| HMAC-valid success callback was confirmed by an inquiry | `callback_without_confirmation` | `notification_id` | `notification.hmac_valid = 1`, parsed event kind is `payment_succeeded`, and a `payment` for that `checkout_id` has `confirmation_inquiry_id` |
| For clinics with a coverage event `at` in the last 24 hours, `coverage_view.snapshot` equals `getCoverage` snapshot | `feed_divergence` | `org_id` | Canonical JSON of the stored snapshot equals canonical JSON of `getCoverage` `detail.snapshot` |
| `grant_outcome.result` `applied` or `already_applied` receipt equals the `listGrants` receipt | `receipt_mismatch` | `grant_id` | Canonical JSON equal, including `signature`, and the `listGrants` row exists |

`listGrants` and `getCoverage` are called with `contract_version` from `CHANNEL_VERSIONS.vendorEntrypoint`. `listGrants` is called with no filter. Clinics for `feed_divergence` are the `org_id` values on `readCoverageEvents` pages, starting at `after = 0`, whose event `at` is within 24 hours before the ABO clock. The comparison uses `canonicalize` from `vendor-contracts`.

`receipt_mismatch` reads `grant_outcome` joined to `grant_request`. It skips `source_kind = transfer`. It does not read `reversal_outcome`. Equality is the parsed receipt object, field for field. A missing `listGrants` row for that `grant_id` fails.

`callback_without_confirmation` loads the notification body from R2 and parses it with the existing `parseNotification` on the Paymob port. A decline or a reversal callback is not this check.

`payment_not_in_payout` uses `payout_import.period` (`YYYY-MM`). The period end is `23:59:59.999` UTC on the last day of that month. `paid_at` is the settled time. The check runs only for periods that have an import.

`detail` is the short identifier of the other side (`grant_id`, `payment_id`, `period`, `checkout_id`, or `effect`). It may be an empty string when there is no other side.

### Payout CSV

The adapter owns this header. Fixtures use it. It is not a frozen contract.

```text
transaction_id,type,gross_minor,fee_minor,net_minor,settled_at
```

`type` is `payment`, `refund`, `chargeback`, `fee`, or `other`. Amounts are integers in minor units. `settled_at` is ISO-8601. `transaction_id` is looked up as `paymob_txn.txn_id`. The line's `payment_id` is that row's `payment_id`, or null when no row exists. `PayoutLine` is `{ kind, payment_id, gross_minor, fee_minor, net_minor, settled_at }`. `capabilities().payouts` stays false.

`POST /ops/payout-imports` reads the raw body. `file_sha256` is hex SHA-256 of those bytes. `r2_key` is `payouts/` plus that hex. The object is `env.R2.put(r2_key, bytes)`. `provider_id` is `paymob`. `imported_by` is the Access email. `period` is the UTC `YYYY-MM` of the first line's `settled_at`, or the clock month when the file has no lines. Lines are inserted with `line_no` starting at 1. `payout_import`, `payout_line`, and their `fact_log` rows are written, then `operator_action` with action `Import a payout CSV` and subject `import_id`, then `recordOperatorAction`, then `runReconciliation`, then the JSON response `{ contract_version, import_id, action_id }`.

E2E-P4.10-05 fixture: one `chargeback` line, `transaction_id` `99001`, so the H-PAY success path's `paymob_txn` row resolves to the payment. E2E-P4.10-06 fixture: one `payment` line, `transaction_id` `99001`, `gross_minor` different from that payment's `amount_minor`, `settled_at` on the last day of a month. The test's omitted payment has `paid_at` more than 7 days before that month's end and is absent from the file.

### Resolve a finding

`POST /ops/findings/{findingId}/resolve` takes JSON `{ "note": "<string>" }`. Unknown `finding_id` returns the existing `not_found`. A missing string `note` returns the existing `invalid_request`. One `finding_resolution` row: `resolved_by` is the Access email, `at` is the clock. A second resolve of the same `finding_id` does not insert another row. The handler writes `operator_action` with action `Resolve a finding` and subject `finding_id`, then `recordOperatorAction`. It does not clear the alert and does not run reconciliation.

E2E-P4.10-02, after `grant_without_payment` and AL-10, uses the same `opsFetch` session to resolve that finding and asserts one `finding_resolution` row. It does not assert that AL-10 stops.

## Test Layout

Tests are written first and observed failing. Each title is prefixed with its E2E id. Harness H-XW (`abo/test/system/`, cross-worker vitest, real platform worker from source). H-PAY is the committed CSV under `abo/test/fixtures/paymob/` plus the existing Paymob stub where a line's transaction id must resolve through `paymob_txn`.

| ID | Title prefix | Entry → module chain | Assertion |
| --- | --- | --- | --- |
| E2E-P4.10-01 | `E2E-P4.10-01` | `runScheduled("0 6 * * *")` → `scheduled()` → `runReconciliation`. Grants and the transfer are read through `VendorEntrypoint.listGrants` over `PLATFORM`. | A clean month built through the existing payment, complimentary-grant, and transfer paths → zero `finding` rows. |
| E2E-P4.10-02 | `E2E-P4.10-02` | A paid grant is applied on the real platform worker with the testkit ABO key and no ABO payment. `runScheduled("0 6 * * *")` → `scheduled()` → `runReconciliation` → `listGrants`. AL-10 is `send_email`. Then `opsFetch` `POST /ops/findings/{findingId}/resolve`. | Kind `grant_without_payment`. `send_email` received `AL-10`. One `finding_resolution` for that `finding_id`. |
| E2E-P4.10-03 | `E2E-P4.10-03` | `runScheduled("0 6 * * *")` → `runReconciliation` → `listGrants`, compared with `operator_action`. | Complimentary platform grant and no ABO `operator_action` → `grant_without_operator_action`. Transfer grant with no `beginTransfer` `operator_action` and no `transferOut` `grant_request` → `transfer_without_authorisation`. |
| E2E-P4.10-04 | `E2E-P4.10-04` | The H-XW test clock advances more than 15 minutes, then `runScheduled("0 6 * * *")` → `runReconciliation`. | Grant parked more than 15 minutes, payment `disposition` `grant`, no applied outcome → `payment_without_grant`. |
| E2E-P4.10-05 | `E2E-P4.10-05` | `opsFetch` `POST /ops/payout-imports` with `payout-unrecorded-chargeback.csv` → `handleOps` → `payoutLines` → `paymob_txn` → `runReconciliation`. Then `opsFetch` `POST /ops/payments/{paymentId}/chargeback`. Then `runScheduled("0 6 * * *")` → `runReconciliation`. | Kind `unrecorded_reversal`. After the existing chargeback, the grant void count is 1 and the term state is `ended`. The re-run inserts no finding. |
| E2E-P4.10-06 | `E2E-P4.10-06` | `opsFetch` `POST /ops/payout-imports` with `payout-amount-mismatch.csv` → `payoutLines` → `runReconciliation`. | Amount mismatch → `payout_unmatched`. The omitted payment → `payment_not_in_payout`. |
| E2E-P4.10-07 | `E2E-P4.10-07` | `runScheduled("0 6 * * *")` → `runReconciliation`. | HMAC-valid success callback and no confirming inquiry → `callback_without_confirmation`. |
| E2E-P4.10-08 | `E2E-P4.10-08` | `runScheduled("0 6 * * *")` → `runReconciliation` compares `coverage_view` with `getCoverage` for clinics with events in the last day, and checks full reversals for a void receipt or tombstone. | Tampered `coverage_view` → `feed_divergence`. Full reversal without a void receipt, effect not `none` and not `tombstone` → `reversal_not_applied`. |
| E2E-P4.10-09 | `E2E-P4.10-09` | `runScheduled("0 6 * * *")` → `runReconciliation` → `listGrants`. The test changes `signature` on one ABO `grant_outcome.receipt` whose `result` is `applied` or `already_applied`. The platform receipt stays as `listGrants` returns it. | Kind `receipt_mismatch` and AL-10. The tampered row is not a void receipt and not a transfer receipt. |

## Sequencing

1. Add the H-XW test file, the vitest include, and both CSV fixtures. Run the file and observe E2E-P4.10-01 through E2E-P4.10-09 failing.
2. Add migration `0008_reconciliation.sql` for `finding_resolution`, `payout_import`, and `payout_line`.
3. Add `AL-10` to the alert code union and the daily next-send interval.
4. Add `PayoutLine` and `payoutLines` on the port and the Paymob adapter, including the `paymob_txn` lookup.
5. Add `runReconciliation` and call it from `scheduled()` on `0 6 * * *` before `sendDueAlerts`.
6. Implement the clean-month path and `payment_without_grant`, `grant_without_payment`, `grant_without_operator_action`, and `transfer_without_authorisation` so E2E-P4.10-01, E2E-P4.10-03, and E2E-P4.10-04 pass.
7. Implement `POST /ops/findings/{findingId}/resolve` so E2E-P4.10-02 passes, including AL-10 on `send_email` and one `finding_resolution`.
8. Implement `callback_without_confirmation`, `feed_divergence`, `reversal_not_applied`, and `receipt_mismatch` so E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 pass.
9. Implement `POST /ops/payout-imports` so E2E-P4.10-05 and E2E-P4.10-06 pass: R2 and SHA, `payout_line` rows, `unrecorded_reversal`, the existing chargeback, a re-run that inserts no finding, `payout_unmatched`, and `payment_not_in_payout`.
10. After all nine tests pass, implement writes `quickstart.md`. That file is not part of this phase.

## Complexity Tracking

02 §7 records no constitution violation for this unit. No row.
