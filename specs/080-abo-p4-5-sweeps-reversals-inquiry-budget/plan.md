# Implementation Plan: Sweeps, reversals and the inquiry budget

**Branch**: `ai/080-abo-p4-5-sweeps-reversals-inquiry-budget` | **Date**: 2026-10-07 | **Spec**: `specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/spec.md`

**Input**: Feature specification from `specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/spec.md`

## Summary

Checkout sweeps confirm a payment when the callback never does, and refunds become one reversal whose effect voids, records, or stays in review. Depends on P4.4 and P3.7. Phase P4, size L. The shared provider-inquiry budget is 2. Spikes are none, so this phase does not write `research.md`.

## Technical Context

**Language/Version**: TypeScript on the existing `abo/` Cloudflare Worker (wrangler, workers types, vitest workers pool already in `abo/package.json`).

**Primary Dependencies**: Consumed `vendor-contracts` `canonicalize`, `sha256Hex`, `signCompactJws`, `verifyCompactJws`, `humanRef`, `paymentId`, `grantIdPaid`, `ulid`, and `CHANNEL_VERSIONS`. WebCrypto Ed25519 via the existing ABO grant key. No new library.

**Storage**: ABO D1 (`DB`) and the existing R2 evidence objects. This unit adds columns on `reversal`, plus `reversal_outcome`, `finding`, and `inquiry_spend`. It uses the existing `work`, `payment`, `checkout`, `checkout_status`, `checkout_event`, `notification`, `paymob_txn`, `grant_request`, `grant_outcome`, `signing_key_gate`, `fact_log`, and `alert` tables. It does not write PostgreSQL.

**Testing**: H-XW + H-PAY for E2E-P4.5-01 through E2E-P4.5-12. Titles are prefixed with the E2E id. Tests are red before the production modules exist. The ABO clock is the consumed `clockNowMs`. A local scenario spends at most 2 seconds of real time. `TEST_CLOCK` stays off production and staging wrangler envs.

**Target Platform**: `abo/` Worker. Billing hostname `SELF.fetch` for `POST /notify/paymob` and `GET /v1/subscription`. `scheduled` for crons `* * * * *`, `0 * * * *`, `0 */6 * * *`, and `0 6 * * *`. `VendorEntrypoint.voidForReversal` over the existing `PLATFORM` service binding. The grant step a sweep reaches is the existing `runDueGrantWork`.

**Project Type**: One Cloudflare Worker (`abo`). No second codebase. No wiring exception.

**Performance Goals**: One shared cap of 2 provider-inquiry slots per UTC minute. Due work rows stay on the existing `(state, next_attempt_at)` index. The minute cron still takes at most 50 due work rows. Confirm and grant rows are served before sweep inquiries. An inquiry that does not fit stays due.

**Constraints**: `reversal` and `reversal_outcome` are append-only. One provider refund inserts one `reversal`. `is_full` is true when `cumulative_reversed_minor` is at least the payment's `amount_minor`. The dedupe key is `paymob`, the parent transaction reference inside `payment_id`, normalized state `reversal`, and that cumulative. `voidForReversal` is called with `partial` false only for effects `tombstone`, `end_current`, and `remove_queued`. This unit does not change `voidForReversal`, `releaseHeld`, `listGrantsForVoid`, or the frozen subscription and payments response builders. No spike, no config surface, and no second cap.

**Scale/Scope**: Clinic checkout recovery, refund effects, and the three reversal-inquiry tiers up to 180 days. Codebase `abo` only. Manual chargeback stays with P4.7. Payout `unrecorded_reversal` stays with P4.10. Operator retry of a parked `reverse` row stays with P4.6.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against `.specify/memory/constitution.md` (Version 1.0.0) and 02 §7. 02 §7 records that this design complies. No box is unchecked.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

02 §7 I: one Worker, D1, R2, and the crons already declared in `abo/wrangler.toml`. This unit adds sweep and reversal work rows on that Worker. The inquiry cap is the integer 2. No queue and no Kubernetes. 02 §7 II: the ABO still holds no clinic database credential and calls the platform only through the existing `PLATFORM` binding. 02 §7 III: vendor-side integrity is D1 append-only triggers on `reversal`, `reversal_outcome`, and `finding`, and the unique reversal dedupe key. This unit does not write PostgreSQL. 02 §7 IV: refunds are provider notifications and inquiries; `voidForReversal` stays the frozen signed method; clinic reads stay on the billing token's `org`. 02 §7 V: a blocked, HMAC-failed, or crashed callback is recovered by the sweep; a transient void retries; over-budget inquiries stay due. Lapsing AI is unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/
├── plan.md
├── data-model.md
├── quickstart.md              # implement writes this after the harness is green
└── tasks.md                   # not created in this phase
```

`quickstart.md` sections, written after verification:

- What was implemented, and the files added or modified
- The harness command for this unit’s tests only, from `abo/`: `node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/sweeps.cross-worker.test.ts`
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- No manual steps; the harness observes every scenario

### Source Code (repository root)

```text
abo/
├── migrations/0005_reversal.sql
├── src/
│   ├── worker.ts
│   ├── alert/index.ts
│   ├── clinic-api/checkouts.ts
│   ├── notify/intake.ts
│   ├── provider/paymob/adapter.ts
│   └── work/
│       ├── inquiry-budget.ts
│       ├── reversal.ts
│       ├── runner.ts
│       └── sweep.ts
├── test/
│   ├── stubs/paymob/worker.ts
│   └── system/sweeps.cross-worker.test.ts
└── vitest.cross-worker.config.ts
```

**Structure Decision**: All of this unit lives in `abo/`. The minute cron, the hourly cron, the 6-hour cron, and the 06:00 UTC cron stay in `worker.ts` `scheduled`. Sweep scheduling and tier selection live in `work/sweep.ts`. Reversal facts, effects, and `voidForReversal` live in `work/reversal.ts`. The cap of 2 lives in `work/inquiry-budget.ts`, which the minute cron and the notify `waitUntil` both call. `GET /v1/subscription` stays the P4.4 builder. The platform worker is not modified. H-XW and H-PAY stay the harnesses P4.2 built; the Paymob stub gains one partial-refund inquiry script.

## Consumes Binding

| Consumes | Existing module |
| --- | --- |
| P4.4 subscription and payments responses. CP-C | `abo/src/clinic-api/billing-reads.ts` `handleGetSubscription` and `handleGetPayments`. Notices `reversal_recorded` and `terms_held` are already emitted when a `reversal` row exists for the tenant and when `snapshot.held_count` > 0. This unit inserts `reversal` rows and lets the frozen platform void raise `held_count`. It does not modify `billing-reads.ts`. CP-C stays the purchase path: `abo/src/work/runner.ts` confirm insert of a `grant` work row, then `abo/src/work/grant.ts` `runDueGrantWork`. This unit calls `runDueGrantWork`. It does not change the grant envelope or the `grant` method. |
| P3.7 void, release, and listing methods; the tombstone rule | `ai-platform/src/vendor/entrypoint.ts` `voidForReversal`, `releaseHeld`, and `listGrantsForVoid`. A full void whose `grant_id` is absent from `grant_ledger` writes `grant_void` and the R2 void object (the tombstone). A later `grant` of that id is `rejected` with `voided`. This unit calls `voidForReversal` only. It does not modify `ai-platform/`. |

## Files

| Path | Action | FR |
| --- | --- | --- |
| `abo/migrations/0005_reversal.sql` | Create | FR-004, FR-007, FR-011, FR-013, FR-014 |
| `abo/src/work/reversal.ts` | Create | FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-011, FR-013, FR-014 |
| `abo/src/work/sweep.ts` | Create | FR-001, FR-002, FR-003, FR-009, FR-012 |
| `abo/src/work/inquiry-budget.ts` | Create | FR-010 |
| `abo/src/work/runner.ts` | Modify | FR-001, FR-003, FR-007 |
| `abo/src/provider/paymob/adapter.ts` | Modify | FR-005, FR-013 |
| `abo/src/notify/intake.ts` | Modify | FR-004, FR-005, FR-011 |
| `abo/src/worker.ts` | Modify | FR-001, FR-003, FR-004, FR-009, FR-010, FR-012 |
| `abo/src/alert/index.ts` | Modify | FR-001, FR-003, FR-004, FR-006, FR-008, FR-013 |
| `abo/src/clinic-api/checkouts.ts` | Modify | FR-003 |
| `abo/test/stubs/paymob/worker.ts` | Modify | FR-008 |
| `abo/vitest.cross-worker.config.ts` | Modify | FR-001 |
| `abo/test/system/sweeps.cross-worker.test.ts` | Create | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012 |
| `specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/data-model.md` | Created this phase | FR-010, FR-013, FR-014 |

`quickstart.md` is not written in this phase. `research.md` is not written: Spikes is none. `contracts/` is not written: Freezes is none.

`wrangler.toml` crons are already `* * * * *`, `0 * * * *`, `0 */6 * * *`, and `0 6 * * *`. This unit adds no binding and no `TEST_CLOCK` var.

`alert/index.ts`: extend `AlertCode` with `AL-03`, `AL-06`, and `AL-08`. `nextSendAtForCode` returns null for those three, the same send-once path as `AL-05` and `AL-09`. Email text stays `{code} {detail_id}`.

`checkouts.ts`: `expired` and `cancelled` with no payment show `Abandoned`. `paid` and `paid_late` show `Paid` while that checkout's grant outcome is not `applied` or `already_applied`, and `Active` when it is. `open` stays `Waiting`. `open_failed` stays `Abandoned`.

`vitest.cross-worker.config.ts` adds `test/system/sweeps.cross-worker.test.ts` to `test.include`. The unit command still names only that file.

`inquiry-budget.ts` is the minute coordinator.

One UTC minute, taken from the ABO clock as `YYYY-MM-DDTHH:MM`, has a row in `inquiry_spend`. `spent` starts at 0. The cap is 2. A confirm row that reaches `inquire`, a grant row that is run, and a sweep row that reaches `inquire` each take one slot. Order while `spent` < 2:

1. Due `open` `confirm` rows, oldest `next_attempt_at` first. Each row that reaches `inquire` consumes one slot.
2. Due `open` `grant` rows, same order. Running a grant row consumes one slot. The call is still `runDueGrantWork` for that row only, so the grant envelope is unchanged.
3. Due `open` `sweep_checkout` and `sweep_payment` rows, same order. Each `inquire` consumes one slot.

`reverse` rows are not inquiry slots. After the inquiry pass, the same minute run takes due `open` `reverse` rows, still at most 50 due work rows in the whole run, and skips them when `signing_key_gate.paused` is 1. They stay `open`. A row that does not get a slot keeps `state` `open` and its `next_attempt_at`. It is not deleted and not marked `done`.

`sweep.ts` schedules checkout inquiries from the `opened` checkout event's `at` (clock zero):

- +2, +5, +10, and +20 minutes
- then every 10 minutes while the due time is strictly before `expires_at`
- one final inquiry at `expires_at`

Each due offset is one `sweep_checkout` row, `dedupe_key` `sweep_checkout:{checkout_id}:{offset_ms}`, `subject_id` the checkout, `next_attempt_at` that instant. The minute coordinator runs it. A bound unpaid final inquiry sets `checkout_status.state` to `expired`. After `expired` or `cancelled`, three further rows are due at `expires_at` plus 1 day, 3 days, and 7 days (the widening window). No sweep inquiry is scheduled after 7 days. A payment confirmed while the checkout is `expired` or `cancelled` is `paid_late`, classification `late`, granted from the checkout snapshot through the existing grant row, and raises `AL-08` once with key `AL-08:{checkout_id}`. A sweep confirmation with no `notification` row of `hmac_valid` 1 for that checkout raises `AL-03` once with key `AL-03:{payment_id}`. The +2, +5, +10, and +20 rows still run after the payment exists; a second success does not insert a second payment.

`reversal.ts` records provider refunds.

A child notification is rewritten onto the parent before the key is formed. The parent transaction reference is `paymob_txn.txn_id` for that order where `parent_txn_id` is null, or `parent_transaction.id` on the inquiry when the callback has `has_parent_transaction` and that row is missing. `payment_id` is `paymentId("paymob", parentRef)`. The callback's own id is never the payment id when it is a child.

The dedupe key is `paymob:{parentRef}:reversal:{cumulative_reversed_minor}`. The cumulative is the inquiry's `refunded_amount_cents` (or the full amount when the inquiry shows a void). `reversal_id` is the hex SHA-256 of `reversal:` ‖ that key, so the platform's hex-64 check accepts it. `reference` is `humanRef("REV", reversal_id)`. A second insert with the same `dedupe_key` does not write a row and does not raise `AL-06` again. `source` `vendor` is rejected and writes nothing. This unit writes `source` `provider`, `kind` `refund`, `recorded_by` `abo`, and `detected_via` `notification` or `inquiry`.

`is_full` follows the cumulative test above. Effect, from the grant lineage, using `grantIdPaid(payment_id)` and `getCoverage` (`recent_terms` matched on `grant_outcome.term_ids`):

- `is_full` false → `review_partial`. No `reverse` row. No `voidForReversal`. `AL-06` once.
- No `grant_outcome` of `applied` or `already_applied` → `tombstone`.
- Matching `recent_terms` state `active` or `grace` → `end_current`.
- Matching `recent_terms` state `ended` → `none`. No `voidForReversal`. `AL-06` once.
- Applied grant whose term id is not in `recent_terms` → `remove_queued` (queued and held terms are absent from that list).

`tombstone`, `end_current`, and `remove_queued` insert one `reverse` row, `dedupe_key` `reverse:{reversal_id}`, only after an inquiry agrees. Agree means the inquiry shows a reversal for that parent whose cumulative is at least the recorded cumulative. Disagree means it does not: insert one `finding` (`kind` `inquiry_disagrees`, `subject` the `reversal_id`) and do not insert `reverse`. The reversal row stays. No void.

The `reverse` row calls `PLATFORM.voidForReversal` with `contract_version` `CHANNEL_VERSIONS.vendorEntrypoint`, `grant_id` `grantIdPaid(payment_id)`, `reversal_id`, `reason` the effect name, `evidence_sha256`, `partial` false, `abo_kid`, and `abo_signature`. The signature is `signCompactJws` over `canonicalize` of `{contract_version, grant_id, reversal_id, reason, evidence_sha256, partial}`, using `ABO_GRANT_KEY`, the same key the grant step uses. `applied` or `already_applied` with a receipt that verifies against `PLATFORM_PUBLIC_KEYS` inserts `reversal_outcome` and sets the work row `done`. A receipt that does not verify parks the row. `transient` or a thrown call leaves the row `open` with the confirm backoff (0 when `TEST_CLOCK` is `"1"`). `conflict` or `rejected` parks the row. This unit does not retry a parked row.

A sweep or tier inquiry that finds a refund on an existing payment uses the same recorder with `detected_via` `inquiry`. It does not insert a payment.

`adapter.ts`: `has_parent_transaction` sets `provider_parent_txn_id` and computes `payment_id` from the parent reference above. The port interface is unchanged.

`intake.ts`: an authentic refund callback stores the notification and calls the reversal recorder. It does not insert a payment. The inline `waitUntil` still runs the confirm path for a payment callback, then `runDueGrantWork`, and both inquiry calls go through the budget coordinator. HMAC failure behavior is unchanged.

`runner.ts`: a sweep success for an `expired` or `cancelled` checkout writes classification `late`, disposition `grant`, checkout state `paid_late`, and the `grant` work row `grant:{payment_id}`. An open checkout still writes `paid` and classification `normal` unless the existing duplicate rule applies. The existing first-inquiry `reversed_before_grant` branch still inserts no `grant` row. It also calls the reversal recorder so a full reversal before apply takes the tombstone edge. The pre-payment partial retry (`partial_reversal`) stays as it is.

`worker.ts`: `Env.PLATFORM` also types `voidForReversal`. The minute cron calls the budget coordinator instead of calling `runDueConfirmWork` and `runDueGrantWork` unbounded. Cron `0 * * * *` still runs `refreshSigningKeyCheck`, then enqueues the hourly reversal population (payment `confirmed_at` within 7 days, or `grantIdPaid` has no `applied` / `already_applied` outcome). Cron `0 */6 * * *` enqueues payments whose term is active, grace, queued, or held. Cron `0 6 * * *` still runs the R2 lock check and due alerts, and selects the daily population: paid, older than the hourly and 6-hour populations, at most 180 days old, whose slot equals the UTC epoch-day modulo 7. Slot is `BigInt("0x" + payment_id) % 7n`. The due minute is that same integer modulo 1440, added to 06:00 UTC, stored on `next_attempt_at`. The minute coordinator runs those rows and does not drop them.

`test/stubs/paymob/worker.ts`: inquiry script `partial_refund` returns `is_refunded` true and `refunded_amount_cents` `"400"` while `amount_cents` stays `"800"`. Existing `reversed`, `bound_success`, and `rate_limit` scripts stay.

## Test Layout

| ID | Harness | Title prefix | Entry | Proves |
| --- | --- | --- | --- | --- |
| E2E-P4.5-01 | H-XW + H-PAY | `E2E-P4.5-01` | `runScheduled` `* * * * *` at +2, +5, +10, and +20 minutes from the `opened` event; Paymob stub inquiry; `runDueGrantWork` | FR-001. The stub delivers no `POST /notify/paymob`. The +2 inquiry confirms one payment and the grant step runs. `AL-03` once. The later three offsets still inquire and do not insert a second payment |
| E2E-P4.5-02 | H-XW + H-PAY | `E2E-P4.5-02` | `SELF.fetch` `POST /notify/paymob` with `bad-hmac.json`; then `runScheduled` `* * * * *` | FR-002. Three bad-HMAC callbacks raise `AL-02`. The sweep still confirms the payments by inquiry |
| E2E-P4.5-03 | H-XW + H-PAY | `E2E-P4.5-03` | `runScheduled` `* * * * *` at `expires_at`, then at `expires_at` + 3 days; stub inquiry; grant step | FR-003. Unpaid final inquiry sets `expired` and `GET /v1/checkouts/{id}` shows `Abandoned`. The day-3 inquiry sets `paid_late`, classification `late`, grants from the checkout snapshot, shows `Paid` before the grant applies, and raises `AL-08` once |
| E2E-P4.5-04 | H-XW + H-PAY | `E2E-P4.5-04` | `SELF.fetch` `POST /notify/paymob` with `refund-parent.json` on the payment that funds the active term, a queued term behind it; `runScheduled` `* * * * *` for the `reverse` row; `PLATFORM.voidForReversal`; `GET /v1/subscription` | FR-004. One reversal, no new payment, effect `end_current`, term ended, queued term held, `AL-06` once, notice `terms_held` |
| E2E-P4.5-05 | H-XW + H-PAY | `E2E-P4.5-05` | `SELF.fetch` `POST /notify/paymob` with `refund-child.json` after the parent-flag reversal of the same payment | FR-005. Same effect as FR-004. The dedupe key leaves a single `reversal` row |
| E2E-P4.5-06 | H-XW + H-PAY | `E2E-P4.5-06` | `SELF.fetch` `POST /notify/paymob` refund fixture for a payment whose term is `ended`; `runScheduled` `* * * * *` | FR-006. Effect `none`. The reversal is recorded, `AL-06` fires once, `voidForReversal` is not called, and the term stays `ended` |
| E2E-P4.5-07 | H-XW + H-PAY | `E2E-P4.5-07` | `SELF.fetch` `POST /notify/paymob` full-refund fixture while the `grant` row is `open` or `parked`; `voidForReversal`; later `runDueGrantWork` | FR-007. Effect `tombstone`. The platform stores the void before the grant. The later grant is `rejected` with `voided`. That grant work row becomes `done` |
| E2E-P4.5-08 | H-XW + H-PAY | `E2E-P4.5-08` | `SELF.fetch` `POST /notify/paymob` partial-refund fixture; stub inquiry `partial_refund`; `runScheduled` `* * * * *` | FR-008. Effect `review_partial`. No `reverse` row, no `voidForReversal`, `AL-06` once |
| E2E-P4.5-09 | H-XW + H-PAY | `E2E-P4.5-09` | `runScheduled` `0 * * * *` for a 3-day-old payment, `0 */6 * * *` for a payment funding an active term, and `0 6 * * *` for a 100-day-old payment whose `payment_id` slot is today's UTC epoch-day modulo 7; then the minute cron at that daily row's `next_attempt_at`. Stub inquiry `reversed` | FR-009. Each tier records one reversal with `detected_via` `inquiry` and does not record a payment. The daily test advances the clock to the stored due minute |
| E2E-P4.5-10 | H-XW + H-PAY | `E2E-P4.5-10` | `runScheduled` `* * * * *` with more than 2 due provider inquiries, including one due `confirm` row and one due `grant` row | FR-010. Those two rows are served. The extra sweep row stays `open` and due. `inquiry_spend.spent` for that minute is 2 |
| E2E-P4.5-11 | H-XW + H-PAY | `E2E-P4.5-11` | `SELF.fetch` `POST /notify/paymob` refund fixture, then `runScheduled` with the stub on `bound_success` so the inquiry is not a refund | FR-011. A `finding` with `kind` `inquiry_disagrees` exists for that `reversal_id`. No `voidForReversal` |
| E2E-P4.5-12 | H-XW + H-PAY | `E2E-P4.5-12` | `SELF.fetch` `POST /notify/paymob` that answers 5xx or leaves the `confirm` row `open`; `runScheduled` `* * * * *` with the clock between +2 and +20 minutes from `opened` | FR-012. The sweep inquires in that window and can confirm the payment |

All twelve tests live in `abo/test/system/sweeps.cross-worker.test.ts`. Each title starts with the E2E id. Tests are written and run first, and they fail before `abo/src/work/sweep.ts`, `abo/src/work/reversal.ts`, and `abo/src/work/inquiry-budget.ts` exist.

Shared setup uses the existing H-XW helpers (`setupCrossWorkerHarness`, `billingFetch`, `mintBilling`, `scriptPaymobStub`, `setClock`, `runScheduled`, `platformCall`). Register the test ABO key on `service_key` the same way E2E-P4.4-01 does, so `voidForReversal` and the grant step can sign. E2E-P4.5-01 does not post a callback. E2E-P4.5-09 searches a parent transaction id until `paymentId("paymob", txnId)` is in today's slot, then ages that payment 100 days on the test clock.

Module chains the quickstart will record:

- E2E-P4.5-01: `worker.ts` `scheduled` → `work/inquiry-budget.ts` → `work/sweep.ts` → `work/runner.ts` → `work/grant.ts` `runDueGrantWork` → `alert/index.ts`
- E2E-P4.5-02: `worker.ts` `fetch` → `notify/intake.ts` → `alert/index.ts`; then `work/sweep.ts`
- E2E-P4.5-03: `work/sweep.ts` → `checkout_status` `expired` → `clinic-api/checkouts.ts`; later `paid_late` → `work/grant.ts`
- E2E-P4.5-04: `notify/intake.ts` → `provider/paymob/adapter.ts` → `work/reversal.ts` → `PLATFORM.voidForReversal` → `clinic-api/billing-reads.ts`
- E2E-P4.5-05: `notify/intake.ts` → `adapter.ts` parent rewrite → `work/reversal.ts` dedupe key
- E2E-P4.5-06: `work/reversal.ts` effect `none`
- E2E-P4.5-07: `work/reversal.ts` → `PLATFORM.voidForReversal` tombstone → `work/grant.ts` `rejected` `voided`
- E2E-P4.5-08: `work/reversal.ts` effect `review_partial` → `alert/index.ts`
- E2E-P4.5-09: `worker.ts` `scheduled` hourly, 6-hour, and `0 6 * * *` → `work/sweep.ts` → `work/inquiry-budget.ts` → `work/reversal.ts`
- E2E-P4.5-10: `work/inquiry-budget.ts` serves `confirm` and `grant` first
- E2E-P4.5-11: `notify/intake.ts` → `work/reversal.ts` → `finding`
- E2E-P4.5-12: `notify/intake.ts` 5xx or open `confirm` row → `work/sweep.ts` inside 2–20 minutes

## Sequencing

1. Add `abo/test/system/sweeps.cross-worker.test.ts` and the vitest include. Extend the Paymob stub with `partial_refund`. Run the harness command. The twelve tests fail because the sweep, reversal, and budget modules are absent.
2. Add `abo/migrations/0005_reversal.sql`, `abo/src/work/reversal.ts`, and the adapter parent rewrite. Wire refund callbacks in `notify/intake.ts`. Extend `AL-03`, `AL-06`, and `AL-08`.
3. Add `abo/src/work/sweep.ts` and `abo/src/work/inquiry-budget.ts`. Point the minute, hourly, 6-hour, and daily crons at them from `worker.ts`. Teach `runner.ts` the `paid_late` / `late` sweep success and the tombstone call on `reversed_before_grant`. Update checkout shown state.
4. Re-run the same harness command until E2E-P4.5-01 through E2E-P4.5-12 pass. Earlier suites are not part of this command.

The file list above is the whole change. A tasks breakdown of these files and the twelve scenarios stays under 40. It is not padded up to the L-band floor.

## Complexity Tracking

02 §7 records no constitution violation for this design. Nothing is entered here.
