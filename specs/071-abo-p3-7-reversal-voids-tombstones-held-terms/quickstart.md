# Reversal voids, tombstones, held terms and operator voids

## 1. What was implemented

`voidForReversal` (class M): ABO-signed reversal void with `partial` false applying term effects (`end_current`, `remove_queued`, `none`), pre-grant tombstones, `partial` true rejection (`partial_void`), idempotent replay (`already_applied` / `conflict`), and clinic coverage snapshot `held_count` / `reversed` state.

`releaseHeld` (class HP): Re-queues a held term and activates it when no term is active; assertion-challenge replay.

`voidGrant` (class HP): Operator void ending a term with `end_reason` `voided`, successor activation, and `grant_void` with `source` `operator`.

`listGrantsForVoid` (class H): Lists `grant_ledger` rows for one `operator_credential_id` inside an inclusive UTC window.

## 2. Files this unit adds or modifies

| File | Role |
| --- | --- |
| `specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/data-model.md` | `grant_void`, held terms, tombstone receipt |
| `specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/contracts/void-for-reversal.md` | `voidForReversal` contract |
| `specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/contracts/release-held-and-void-grant.md` | `releaseHeld` and `voidGrant` |
| `specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/contracts/list-grants-for-void.md` | `listGrantsForVoid` |
| `ai-platform/migrations/20261006140000_grant_void.sql` | Append-only D1 `grant_void` |
| `ai-platform/src/vendor/entrypoint.ts` | `voidForReversal`, grant `voided` gate, `releaseHeld`, `voidGrant`, `listGrantsForVoid` |
| `ai-platform/src/quota-do/coverage.ts` | `void_for_reversal`, `release_held`, `void_grant`, snapshot `held_count` / `reversed`, void ship |
| `ai-platform/src/worker.ts` | DO RPC dispatch for void, release, and operator void |
| `ai-platform/test/system/harness.ts` | `VendorMethod` names and `signCoverAbo` |
| `ai-platform/test/system/reversal-voids-held-terms.system.test.ts` | H-AP E2E-P3.7-01 through E2E-P3.7-09 |

## 3. Harness command (this unit only)

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/reversal-voids-held-terms.system.test.ts
```

## 4. Entry point → module chain per E2E id

Every scenario is asserted by H-AP; use the harness command above only.

| ID | Chain |
| --- | --- |
| E2E-P3.7-01 | `coverClinic()` → second paid `vendorCall("grant")` → `vendorCall("voidForReversal")` for the active term → `voidForReversal` on `VendorEntrypoint` → DO `void_for_reversal` `end_current` → `inspectCoverage` → `invoke` `POST /v1/requests` |
| E2E-P3.7-02 | `coverClinic()` → queued paid `vendorCall("grant")` → `vendorCall("voidForReversal")` for the queued grant → DO `remove_queued` → `inspectCoverage` |
| E2E-P3.7-03 | `coverClinic()` → `setTestClock` to `ends_at` → `runDurableObjectAlarm` → `vendorCall("voidForReversal")` → DO effect `none` → `runDurableObjectAlarm` → `inspectCoverage` and D1 `grant_void` |
| E2E-P3.7-04 | `vendorCall("voidForReversal")` before any grant → D1 `grant_void` and R2 void object, no `coverage_event` → `vendorCall("grant")` with that id → `rejected` `voided` |
| E2E-P3.7-05 | `end_current` so two terms are `held` → `vendorCall("releaseHeld")` → DO `release_held` activates the first → `vendorCall("releaseHeld")` on the remaining held term re-queues it → `inspectCoverage` |
| E2E-P3.7-06 | complimentary `vendorCall("grant")` then a queued successor → `vendorCall("voidGrant")` → DO `void_grant` → `runDurableObjectAlarm` → `inspectCoverage`, D1 `grant_void`, R2 void object |
| E2E-P3.7-07 | paid grants on `grant_ledger` → `vendorCall("listGrantsForVoid")` |
| E2E-P3.7-08 | `vendorCall("voidForReversal")` → `runDurableObjectAlarm` → replay, conflict, bad signature, `partial` true, `partial` invalid, then the unconsumed `reversal_id` with `partial` false |
| E2E-P3.7-09 | `coverClinic()` → `vendorCall("voidForReversal")` `partial` false → `runDurableObjectAlarm` → D1 `grant_void`, R2 object, `coverage_event` |
