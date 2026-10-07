# Sweeps, reversals and the inquiry budget

**Unit**: P4.5 · **Harnesses**: H-XW, H-PAY · **Verification**: T025 green

## 1. What was implemented

Checkout sweeps confirm payments when callbacks fail or never arrive; refunds become one reversal whose effect voids, records, or stays in review; tiered reversal inquiries find lost refunds; and a shared per-minute provider-inquiry budget of 2 serves confirm and grant work first (FR-001 through FR-014).

- **Sweep scheduling** (`abo/src/work/sweep.ts`) — minute offsets (+2, +5, +10, +20, every 10 min to expiry, final inquiry → `expired`, widening to 7 days for expired/cancelled); late payment → `paid_late`, classification `late`, AL-08; AL-03 when confirmed with no verified callback.
- **Reversal recorder** (`abo/src/work/reversal.ts`) — one `reversal` per provider refund; effects `tombstone`, `end_current`, `remove_queued`, `none`, `review_partial`; `reverse` work rows → signed `PLATFORM.voidForReversal`; `reversal_outcome`; AL-06 on every reversal; dismissal + `finding` when inquiry contradicts callback.
- **Inquiry budget** (`abo/src/work/inquiry-budget.ts`) — shared cap of 2 provider-inquiry slots per UTC minute; confirm and grant rows served before sweep inquiries; over-budget inquiries stay due.
- **Schema** (`abo/migrations/0005_reversal.sql`) — `reversal` columns, `reversal_outcome`, `finding`, and `inquiry_spend`.
- **Refund intake** (`abo/src/notify/intake.ts`) — parent-flag and child-transaction refunds; parent rewrite and dedupe key.
- **Paymob adapter** (`abo/src/provider/paymob/adapter.ts`) — parent transaction reference normalization for reversal dedupe.
- **Runner** (`abo/src/work/runner.ts`) — `paid_late` confirm path; tombstone handling on grant.
- **Checkout reads** (`abo/src/clinic-api/checkouts.ts`) — `Abandoned` for expired/cancelled with no payment; `Paid` for `paid`/`paid_late` before grant applies; `Active` when grant outcome is `applied` or `already_applied`.
- **Alerts** (`abo/src/alert/index.ts`) — AL-03, AL-06, and AL-08 (send-once path).
- **Worker dispatch** (`abo/src/worker.ts`) — minute, hourly, 6-hour, and `0 6 * * *` crons; sweep, reversal, and budget coordination.
- **Harness** — twelve E2E scenarios in `abo/test/system/sweeps.cross-worker.test.ts` (H-XW platform worker + H-PAY Paymob stub with `partial_refund` inquiry script).

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `abo/migrations/0005_reversal.sql` | FR-004, FR-007, FR-011, FR-013, FR-014 |
| `abo/src/work/reversal.ts` | FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-011, FR-013, FR-014 |
| `abo/src/work/sweep.ts` | FR-001, FR-002, FR-003, FR-009, FR-012 |
| `abo/src/work/inquiry-budget.ts` | FR-010 |
| `abo/src/work/runner.ts` | FR-001, FR-003, FR-007 |
| `abo/src/provider/paymob/adapter.ts` | FR-005, FR-013 |
| `abo/src/notify/intake.ts` | FR-004, FR-005, FR-011 |
| `abo/src/worker.ts` | FR-001, FR-003, FR-004, FR-009, FR-010, FR-012 |
| `abo/src/alert/index.ts` | FR-001, FR-003, FR-004, FR-006, FR-008, FR-013 |
| `abo/src/clinic-api/checkouts.ts` | FR-003 |
| `abo/test/stubs/paymob/worker.ts` | FR-008 |
| `abo/vitest.cross-worker.config.ts` | FR-001 |
| `abo/test/system/sweeps.cross-worker.test.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012 |
| `specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/quickstart.md` | FR-001–FR-014 |

## 3. Harness command for this unit's tests only

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/sweeps.cross-worker.test.ts
```

## 4. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P4.5-01 | `worker.ts` `scheduled` → `work/inquiry-budget.ts` → `work/sweep.ts` → `work/runner.ts` → `work/grant.ts` `runDueGrantWork` → `alert/index.ts` |
| E2E-P4.5-02 | `worker.ts` `fetch` → `notify/intake.ts` → `alert/index.ts`; then `work/sweep.ts` |
| E2E-P4.5-03 | `work/sweep.ts` → `checkout_status` `expired` → `clinic-api/checkouts.ts`; later `paid_late` → `work/grant.ts` |
| E2E-P4.5-04 | `notify/intake.ts` → `provider/paymob/adapter.ts` → `work/reversal.ts` → `PLATFORM.voidForReversal` → `clinic-api/billing-reads.ts` |
| E2E-P4.5-05 | `notify/intake.ts` → `adapter.ts` parent rewrite → `work/reversal.ts` dedupe key |
| E2E-P4.5-06 | `work/reversal.ts` effect `none` |
| E2E-P4.5-07 | `work/reversal.ts` → `PLATFORM.voidForReversal` tombstone → `work/grant.ts` `rejected` `voided` |
| E2E-P4.5-08 | `work/reversal.ts` effect `review_partial` → `alert/index.ts` |
| E2E-P4.5-09 | `worker.ts` `scheduled` hourly, 6-hour, and `0 6 * * *` → `work/sweep.ts` → `work/inquiry-budget.ts` → `work/reversal.ts` |
| E2E-P4.5-10 | `work/inquiry-budget.ts` serves `confirm` and `grant` first |
| E2E-P4.5-11 | `notify/intake.ts` → `work/reversal.ts` → `finding` |
| E2E-P4.5-12 | `notify/intake.ts` 5xx or open `confirm` row → `work/sweep.ts` inside 2–20 minutes |
