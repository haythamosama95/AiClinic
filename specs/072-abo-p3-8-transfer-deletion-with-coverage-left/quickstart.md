# Transfer, deletion with coverage left, and ledger retention

## 1. What was implemented

`beginTransfer` (class HP): Authorises a clinic move, retires the source binding, creates the destination installation and binding with `awaiting_transfer`, and records a `transfer` row.

`transferOut` and `transferIn` (class M): Saga steps that build the coverage package, end terms on the source with `transferred`, apply terms on the destination, emit transfer coverage events and ledger rows, and return the §1.6 transfer receipt. Retries are `already_applied`; `transferIn` before `transferOut` is `transient` with `detail` `awaiting_transfer_out`.

`deleteInstallation` (class HP): Marks the installation deleted, runs purge retention, holds the binding when coverage remains (`held_for_transfer`, `transfer_pending`, AL-18), or retires it when no terms remain. Repeat calls are idempotent.

Transfer lineage on `voidForReversal`: Chooses the destination installation from the latest `grant_ledger` row for the paid grant before calling the existing `void_for_reversal` DO kind.

Purge retention: `purgeByInstallationId` keeps the installation row (`status` `deleted`), entitlements, bindings, ledgers, coverage events, transfers, and usage for unended terms.

## 2. Files this unit adds or modifies

| File | Role |
| --- | --- |
| `specs/072-abo-p3-8-transfer-deletion-with-coverage-left/data-model.md` | `transfer`, `transfer_step`, held binding, purge retention |
| `ai-platform/migrations/20261006150000_transfer.sql` | D1 `transfer` and `transfer_step` |
| `ai-platform/src/coverage/transfer.ts` | Binding re-creation, package build, transfer steps |
| `ai-platform/src/vendor/entrypoint.ts` | `beginTransfer`, `transferOut`, `transferIn`, `deleteInstallation`, void lineage, held retire after `voidGrant` |
| `ai-platform/src/quota-do/coverage.ts` | DO `transfer_out` / `transfer_in`, `awaiting_transfer` grant refusal, transferred snapshot |
| `ai-platform/src/quota-do/index.ts` | Admission `transfer_pending` refusal |
| `ai-platform/src/worker.ts` | DO dispatch, daily AL-18 for held bindings |
| `ai-platform/src/identity/index.ts` | Epoch on re-bind; held binding reads |
| `ai-platform/src/config-cache/index.ts` | `held_for_transfer` binding reader |
| `ai-platform/src/alert/index.ts` | AL-11 transfer complete, AL-18 deletion held |
| `ai-platform/src/retention/index.ts` | Ledger retention on purge |
| `ai-platform/test/system/harness.ts` | `VendorMethod` names for transfer and delete |
| `ai-platform/test/system/transfer-deletion.system.test.ts` | H-AP E2E-P3.8-01 through E2E-P3.8-08 |
| `ai-platform/test/retention.test.ts` | Purge kept-row expectations |
| `ai-platform/test/system/lifecycle-interplay.system.test.ts` | SYS-2.4 kept-row expectations |
| `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts` | Stage-03 purge kept-row expectations |

## 3. Harness command (this unit only)

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/transfer-deletion.system.test.ts
```

## 4. Entry point → module chain per E2E id

Every scenario is asserted by H-AP; use the harness command above only.

| ID | Chain |
| --- | --- |
| E2E-P3.8-01 | `coverClinic()` → queued paid `vendorCall("grant")` → `vendorCall("beginTransfer")` → `vendorCall("transferOut")` → `vendorCall("transferIn")` on `VendorEntrypoint` → `src/coverage/transfer.ts` → DO `transfer_out` / `transfer_in` → `getCoverage` on the old installation → `vendorCall("grant")` on the old installation → `coverage_event.binding_epoch` and captured AL-11 |
| E2E-P3.8-02 | `beginTransfer` so the new DO is `awaiting_transfer` → `vendorCall("grant")` → `vendorCall("transferIn")` → `vendorCall("grant")` again → `inspectCoverage` on the new installation |
| E2E-P3.8-03 | `vendorCall("transferOut")` and `vendorCall("transferIn")` retried with the same `transfer_id`; `vendorCall("transferIn")` before `transferOut` |
| E2E-P3.8-04 | `vendorCall("deleteInstallation")` → `SELF.fetch` `POST /v1/requests` → `vendorCall("grant")` → issuer token on a clinic `/v1/*` route → captured AL-18 → `setTestClock` plus one day → `runScheduled("0 3 * * *")` → `vendorCall("beginTransfer")` from the held binding |
| E2E-P3.8-05 | `vendorCall("deleteInstallation")` with no coverage → issuer token on a clinic `/v1/*` route → `tenant_binding.epoch` |
| E2E-P3.8-06 | `vendorCall("deleteInstallation")` with coverage → `vendorCall("voidGrant")` for the remaining grants → issuer token on a clinic `/v1/*` route |
| E2E-P3.8-07 | Transfer a paid grant → `vendorCall("voidForReversal")` → `inspectCoverage` on the new installation |
| E2E-P3.8-08 | `vendorCall("deleteInstallation")` → `purgeByInstallationId` → D1 counts for `grant_ledger`, `grant_void`, `coverage_event`, `transfer`, `installation`, and unended-term `usage_event` |
