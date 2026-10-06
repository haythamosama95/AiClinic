# Implementation Plan: Notification intake, inquiry, work pipeline and payment confirmation

**Branch**: `ai/078-abo-p4-3-notification-intake-inquiry-work-pipeline` | **Date**: 2026-10-07 | **Spec**: `specs/078-abo-p4-3-notification-intake-inquiry-work-pipeline/spec.md`

**Input**: Feature specification from `specs/078-abo-p4-3-notification-intake-inquiry-work-pipeline/spec.md`

## Summary

Paymob callbacks on the billing host are HMAC-checked, stored as evidence, and confirmed by inquiry into one payment, checkout events, and a `grant` work row when the disposition is `grant`. Depends on P4.2. Phase P4, size L. The R-2 outcome is in `research.md`: no live Paymob account, and inquiry sweeps stay with P4.5.

## Technical Context

**Language/Version**: TypeScript on the existing `abo/` Cloudflare Worker (wrangler, workers types, vitest workers pool already in `abo/package.json`).

**Primary Dependencies**: The consumed provider port, checkout tables, `vendor-contracts` `ulid`, `humanRef`, `sha256Hex`, and `canonicalize`, and WebCrypto HMAC-SHA512. No new library.

**Storage**: ABO D1 (`DB`) for `notification`, `inquiry_result`, `payment`, `work`, `paymob_txn`, `paymob_state_seen`, and `notify_rate`, plus the consumed `checkout`, `checkout_event`, `checkout_status`, `paymob_intention`, `fact_log`, and `alert` tables. ABO R2 (`R2`) for `evidence/` and `hmac-invalid/`.

**Testing**: H-ABO + H-PAY for E2E-P4.3-01 through E2E-P4.3-12. Titles are prefixed with the E2E id. Tests are red before the production modules exist. The ABO clock is the consumed `clockNowMs`. A local scenario spends at most 2 seconds of real time. `TEST_CLOCK` stays off production and staging wrangler envs.

**Target Platform**: `abo/` Worker. Billing hostname `SELF.fetch` for `POST /notify/paymob`, `GET /notify/paymob`, and `GET /return/paymob`. Inline `waitUntil` on the processed callback, and `runScheduled` for cron `* * * * *`.

**Project Type**: One Cloudflare Worker (`abo`). No second codebase.

**Performance Goals**: Notify body at most 1_048_576 bytes. 60 requests per 60 seconds per `CF-Connecting-IP` (missing header key `unknown`). The minute cron takes at most 50 due `confirm` rows. Inquiry abort matches the existing intention abort: 500 ms when `TEST_CLOCK` is `"1"`, otherwise 10 seconds.

**Constraints**: HMAC-SHA512 over the 20 fields in `data-model.md` §7, constant time. Lease is 60 seconds. Backoff is 1 minute, doubling to 15 minutes. Provider HTTP stays inside `abo/src/provider/paymob/client.ts`. The domain does not import the adapter. `POST /notify/paymob` does not use the clinic API version, auth, or per-token rate gates. `GET /return/paymob` has no contract-version refusal. Production routes have no fault flag. Over-cap answers HTTP 413 with an empty body. Over-limit answers HTTP 429 with an empty body. Either refusal stores nothing and enqueues nothing. Invalid HMAC stores nothing under `evidence/`.

**Scale/Scope**: One clinic’s card callbacks and one work runner. Codebase `abo` only. Grant execution stays with P4.4. Sweeps, expiry, and the reversal lifecycle stay with P4.5.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v2.0.0 and 02 §7. 02 §7 records that this design complies. No box is unchecked.

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

02 §7 I: one Worker, D1, R2, and crons; no queues or Kubernetes. This unit adds notify routes and a D1 work runner on that Worker. 02 §7 II: Paymob stays behind the provider port; the ABO holds no clinic database credential. 02 §7 III: vendor-side integrity is D1 append-only triggers, the unique work `dedupe_key`, and one D1 batch for the confirm facts; this unit does not write PostgreSQL. 02 §7 IV: TB-1 is the notify control (body cap, rate limit, constant-time HMAC, inquiry before any grant); the tenant is the checkout’s `org_id`; provider ids stay on the adapter tables; evidence bodies are not hard-deleted. 02 §7 V: inquiry timeout or rate limit retries with backoff; R2 or D1 failure on intake returns 5xx and enqueues nothing. This unit does not grant and does not call the platform, so AI stays off until P4.4.

## Project Structure

### Documentation (this feature)

```text
specs/078-abo-p4-3-notification-intake-inquiry-work-pipeline/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md          # implement writes this after the harness is green
└── tasks.md               # not created in this phase
```

`quickstart.md` sections, written after verification:

- What was implemented, and the files added or modified
- The harness command for this unit’s tests only, from `abo/`: `npx vitest run --config vitest.workers.config.ts test/system/notify.system.test.ts`
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- No manual steps; the harness observes every scenario

### Source Code (repository root)

```text
abo/
├── migrations/0003_notify_work.sql
├── src/
│   ├── worker.ts                              # modify
│   ├── alert/index.ts                         # modify
│   ├── notify/intake.ts
│   ├── work/runner.ts
│   └── provider/
│       ├── port.ts                            # modify
│       └── paymob/
│           ├── adapter.ts                     # modify
│           └── client.ts                      # modify
├── test/
│   ├── fixtures/paymob/
│   │   ├── success.json
│   │   ├── decline.json
│   │   ├── refund-parent.json
│   │   ├── refund-child.json
│   │   └── bad-hmac.json
│   ├── stubs/paymob/worker.ts                 # modify
│   └── system/
│       ├── harness.ts                         # modify
│       └── notify.system.test.ts
├── vitest.workers.config.ts                   # modify
└── wrangler.toml                              # modify
```

**Structure Decision**: All of this unit lives in `abo/`. Notify and return routes sit on the billing host beside the existing clinic API and do not pass through it. The Paymob HTTP client remains the only provider HTTP module. H-ABO’s workers config gains the existing H-PAY auxiliary worker. H-XW files stay unchanged.

## Consumes Binding

| Consumes | Existing module |
| --- | --- |
| Checkout API | `abo/src/clinic-api/checkouts.ts` (`handlePostCheckout`, `handleGetCheckout`, `handleListOpenCheckouts`) and tables `checkout`, `checkout_event`, `checkout_status`, `paymob_intention` in `abo/migrations/0002_checkout.sql`. This unit does not modify that file. Confirm reads `checkout` and `checkout_status` and inserts `checkout_event` / updates `checkout_status` from `abo/src/work/runner.ts`. |
| Provider-port interface | `abo/src/provider/port.ts` `ProviderPort` methods `capabilities`, `createCheckout`, and `cancelCheckout`. Those three signatures stay. This unit adds `parseNotification` and `inquire` on that interface. `abo/src/provider/registry.ts` `providerForId` / `PAYMOB_PROVIDER_ID` stay. `abo/src/provider/paymob/client.ts` `createPaymobIntention` stays. |
| H-PAY | `abo/test/stubs/paymob/worker.ts`. Intention routes and `mode` `ok` / `refuse` / `timeout` stay. This unit adds inquiry routes and an inquiry script on the same worker and the same base URL. |
| H-XW | `abo/test/system/cross-worker-harness.ts` and `abo/vitest.cross-worker.config.ts`. This unit does not modify them. |
| Clock, facts, alerts, refs | `abo/src/clock.ts` `clockNowMs` / `clockNowIso`. `fact_log` insert shape in `abo/src/records/append.ts`. `abo/src/alert/index.ts` `sendDueAlerts` (the sender learns `row.code`; AL-16’s one-day repeat stays). `vendor-contracts` `ulid`, `humanRef`, `sha256Hex`, `canonicalize`. |

## Files

| Path | Action | FR |
| --- | --- | --- |
| `abo/migrations/0003_notify_work.sql` | Create | FR-001, FR-002, FR-004, FR-005, FR-006, FR-007, FR-008, FR-010 |
| `abo/src/provider/port.ts` | Modify | FR-001, FR-005, FR-012, FR-013 |
| `abo/src/provider/paymob/client.ts` | Modify | FR-005, FR-008, FR-013 |
| `abo/src/provider/paymob/adapter.ts` | Modify | FR-001, FR-003, FR-004, FR-005, FR-006, FR-012, FR-013 |
| `abo/src/notify/intake.ts` | Create | FR-001, FR-002, FR-003, FR-009, FR-011, FR-012 |
| `abo/src/work/runner.ts` | Create | FR-001, FR-004, FR-005, FR-006, FR-007, FR-008, FR-010 |
| `abo/src/alert/index.ts` | Modify | FR-003, FR-005, FR-007, FR-008 |
| `abo/src/worker.ts` | Modify | FR-001, FR-008, FR-011, FR-012 |
| `abo/wrangler.toml` | Modify | FR-001, FR-013 |
| `abo/test/stubs/paymob/worker.ts` | Modify | FR-013 |
| `abo/test/fixtures/paymob/*.json` | Create | FR-003, FR-004, FR-013 |
| `abo/test/system/harness.ts` | Modify | FR-009, FR-010, FR-013 |
| `abo/test/system/notify.system.test.ts` | Create | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012 |
| `abo/vitest.workers.config.ts` | Modify | FR-013 |
| `specs/078-abo-p4-3-notification-intake-inquiry-work-pipeline/research.md` | Created this phase | FR-013 |
| `specs/078-abo-p4-3-notification-intake-inquiry-work-pipeline/data-model.md` | Created this phase | FR-001, FR-003, FR-005, FR-008 |

`quickstart.md` is not written in this phase. No `contracts/` directory: Freezes is none.

`worker.ts` `fetch` gains an `ExecutionContext`. On the billing host, `POST /notify/paymob` and `GET /notify/paymob` go to `notify/intake.ts`, and `GET /return/paymob` does too. They run before the `/v1/` clinic gates. A processed callback that enqueued `confirm` calls `ctx.waitUntil` on the runner for that row. GET notify and GET return do not. The minute branch of `scheduled` keeps export, heartbeat, alerts, and coverage refresh, and calls the runner for at most 50 due `confirm` rows. A single row failure does not throw out of the cron.

`wrangler.toml` gains `PAYMOB_HMAC_SECRET` and `PAYMOB_API_KEY` on development, staging, and production, placeholders `paymob-hmac-unconfigured` and `paymob-api-unconfigured`. No `TEST_CLOCK` var is added. No production fault binding is added.

`vitest.workers.config.ts` binds the existing `abo/test/stubs/paymob/worker.ts` as `PAYMOB_STUB`, with `PAYMOB_BASE_URL` `https://paymob.harness.test` and the test Paymob vars. H-ABO tests keep the `test/system/**/*.system.test.ts` include.

`alert/index.ts`: `sendAlertRow` uses `row.code` in the subject and the text (`{code} {detail_id}`). AL-16 still sets `next_send_at` one day ahead. AL-01 and AL-02 set it one hour ahead. AL-05 and AL-09 set it null so they send once. New `raiseAlert(env, code, alertKey, detailId)` inserts the consumed `alert` row with `unsent = 1`.

Intake, in order, for `POST /notify/paymob`: body cap, then `notify_rate`, then `parseNotification`. HTTP 413 and HTTP 429 are empty and stop. A mismatch is HTTP 401 with an empty body, an R2 object under `hmac-invalid/`, and AL-02 when 3 failures fall inside 15 minutes. A valid new body: R2 `evidence/` put, then one D1 batch inserting `notification` (`enqueued`) and the `confirm` work row. The same `dedupe_key` inserts `duplicate` and no `confirm` row. A valid body with no stored intention is `unmatched`, evidence stored, no `confirm` row. If the R2 put throws, the response is HTTP 500 and nothing is enqueued. If `DB.batch` throws, the response is HTTP 500 and nothing is enqueued.

`parseNotification` returns `{authentic, events[]}`. Events are `ProviderTxn` values from the HMAC-covered fields. `inquire({checkout_id} | {payment_id})` returns `{bound, transactions[]}`. The auth token from `POST /api/auth/tokens` with `PAYMOB_API_KEY` is cached in the isolate until an inquiry responds 401. `bound` is true only when the inquiry `order.id` equals `paymob_intention.order_id`. `merchant_order_id` is ignored. `payment_id` on `paymob_txn` is filled from the domain payment id after confirm; the Paymob transaction id stays in `txn_id`.

Confirm normalisation (04 §5.3): `success` and not pending, not refunded, not voided → `payment_succeeded`. Not success and not pending → `payment_failed` (`attempt_declined`, checkout stays `open`). `pending` → `payment_pending` on inquiry only, no payment row, confirm stays `open` with backoff. `is_refunded`, `is_voided`, or a child with `has_parent_transaction` → `reversal` on the `ProviderTxn`. The cumulative amount comes from the inquiry. A first inquiry that already shows a full refund or void writes the payment as `reversed_before_grant` and no `grant` row.

Unbound (inquiry order id differs): no payment row, `raiseAlert` AL-05, confirm `done`. Amount or currency differs from the checkout snapshot: payment `withheld_mismatch` with `mismatch_detail`, no `grant` row, AL-05. `likely_duplicate` when an earlier payment for the same `org_id` came from a checkout with the same `opened_with_coverage_through`: AL-09, disposition `grant`, `grant` work row in that batch. `late` when `checkout_status.state` is `expired` or `cancelled`. Otherwise `normal`.

The confirm batch inserts the step’s facts and their `fact_log` rows, inserts the `grant` work row when disposition is `grant`, and sets the `confirm` row to `done`, conditional on the held `lease_until`. If that batch throws, no fact is written and the row is retried (`last_error` `batch_failed`). Two runners: the conditional lease update admits one. Inquiry timeout or HTTP 429: row stays `open`, `attempts` increases, `next_attempt_at` backs off from 1 minute doubling to 15 minutes, `lease_until` cleared.

`GET /return/paymob` for any `v`, including `99`, returns a neutral HTML page (no paid or failed claim) and inserts one open `confirm` row per checkout whose status is `open`, using `dedupe_key` `confirm-schedule:{checkout_id}`, when that key is not already present. It does not write a payment. `GET /notify/paymob` authentic-checks with the same HMAC list and only inserts that schedule for the resolved checkout. It does not `waitUntil` confirm.

Harness: `setIntakeR2PutThrows` wraps `env.R2.put` so the next intake put throws. `setD1BatchThrows` wraps `env.DB.batch` so the next batch throws. `scriptPaymobInquiry` POSTs the inquiry script to the stub. Scripts: `bound_success`, `unbound`, `amount_mismatch`, `reversed`, `pending`, `timeout`, `rate_limit`. The production worker does not read these helpers.

## Test Layout

| ID | Harness | Title prefix | Entry | Proves |
| --- | --- | --- | --- | --- |
| E2E-P4.3-01 | H-ABO + H-PAY | `E2E-P4.3-01` | `SELF.fetch` `POST /notify/paymob`, billing host; inline `waitUntil`; inquiry `bound_success` | FR-001. Re-signed success fixture → notification stored; `PAY-` payment; checkout `paid`; `grant` row `open`. Also: a body of 1_048_577 bytes → HTTP 413, empty, nothing stored or enqueued |
| E2E-P4.3-02 | H-ABO + H-PAY | `E2E-P4.3-02` | Same POST | FR-002. Same body again → disposition `duplicate`; still one payment. Also: 61st request in the same 60-second window from one `CF-Connecting-IP` → HTTP 429, empty, nothing stored or enqueued. A missing `CF-Connecting-IP` uses the key `unknown` |
| E2E-P4.3-03 | H-ABO + H-PAY | `E2E-P4.3-03` | Same POST; bad-HMAC fixture | FR-003. Nothing under `evidence/`. Three failures within 15 minutes → AL-02 and a sample object under `hmac-invalid/`. An 11th failure in the same hour does not store another raw body |
| E2E-P4.3-04 | H-ABO + H-PAY | `E2E-P4.3-04` | Same POST; inline `waitUntil` | FR-004. Decline fixture → `attempt_declined`, checkout stays `open`. Later success → one payment |
| E2E-P4.3-05 | H-ABO + H-PAY | `E2E-P4.3-05` | POST then confirm via `waitUntil` or `runScheduled` `* * * * *`; inquiry `unbound`, then `amount_mismatch` | FR-005. Different order id → no payment and AL-05. Amount mismatch → `withheld_mismatch`, no `grant` row, AL-05 |
| E2E-P4.3-06 | H-ABO + H-PAY | `E2E-P4.3-06` | Same confirm path; inquiry `reversed` | FR-006. Parent-flag fixture and child-refund fixture each → `reversed_before_grant`, no `grant` row |
| E2E-P4.3-07 | H-ABO + H-PAY | `E2E-P4.3-07` | Same confirm path | FR-007. Second payment from a checkout with the same `opened_with_coverage_through` → `likely_duplicate`, AL-09, disposition `grant` |
| E2E-P4.3-08 | H-ABO + H-PAY | `E2E-P4.3-08` | `runScheduled` and inline `waitUntil`; inquiry `timeout` or `rate_limit`; `setClock` | FR-008. Row stays `open` with backoff; a later attempt succeeds. `opened_at` more than 5 minutes ago → AL-01 |
| E2E-P4.3-09 | H-ABO + H-PAY | `E2E-P4.3-09` | POST; `setIntakeR2PutThrows` and `setD1BatchThrows` | FR-009. R2 put throws → HTTP 500, nothing enqueued. D1 batch throws → HTTP 500, nothing enqueued |
| E2E-P4.3-10 | H-ABO + H-PAY | `E2E-P4.3-10` | Runner via `waitUntil` and `runScheduled`; two runners | FR-010. Confirm batch throws → no payment, row retried. Two runners → one lease wins |
| E2E-P4.3-11 | H-ABO + H-PAY | `E2E-P4.3-11` | `SELF.fetch` `GET /return/paymob?v=99` | FR-011. Neutral page, `confirm` row scheduled, no payment |
| E2E-P4.3-12 | H-ABO + H-PAY | `E2E-P4.3-12` | `SELF.fetch` `GET /notify/paymob` | FR-012. Authentic GET schedules a `confirm` row and does not write a payment |

All twelve tests live in `abo/test/system/notify.system.test.ts`. Each title starts with the E2E id. Tests are written and run first, and they fail before the implementation exists. Checkout and `paymob_intention` rows are seeded in D1 by the test; the entry point is the notify or return route. HTTP 413 and HTTP 429 are assertions inside E2E-P4.3-01 and E2E-P4.3-02. There is no thirteenth E2E id.

Module chains the quickstart will record:

- E2E-P4.3-01, 02, 04: `worker.ts` → `notify/intake.ts` → `adapter.ts` `parseNotification` → R2 and D1 → `waitUntil` → `work/runner.ts` → `adapter.ts` `inquire` → `client.ts` → H-PAY
- E2E-P4.3-03: `worker.ts` → `notify/intake.ts` → `adapter.ts` → R2 `hmac-invalid/` → `alert/index.ts`
- E2E-P4.3-05, 06, 07: the 01 chain, with the scripted inquiry result
- E2E-P4.3-08, 10: `worker.ts` `scheduled` and `waitUntil` → `work/runner.ts`
- E2E-P4.3-09: `worker.ts` → `notify/intake.ts` with the harness wrappers
- E2E-P4.3-11, 12: `worker.ts` → `notify/intake.ts` (no `waitUntil`)

## Sequencing

Tests are added and run before the production modules, and the run is expected to fail.

1. H-PAY inquiry routes and script on `abo/test/stubs/paymob/worker.ts`, fixtures under `abo/test/fixtures/paymob/`, harness fault and script helpers, and the `PAYMOB_STUB` binding on `abo/vitest.workers.config.ts`.
2. `notify.system.test.ts` with the twelve E2E titles (red).
3. Migration `0003_notify_work.sql`.
4. Port methods, Paymob inquiry client, and adapter `parseNotification` / `inquire` / HMAC.
5. `notify/intake.ts` and the `worker.ts` routes, including `waitUntil` and the minute-cron call.
6. `work/runner.ts` (lease, backoff, confirm batch, classifications, dispositions).
7. `raiseAlert` and the `sendAlertRow` code text.
8. `wrangler.toml` `PAYMOB_HMAC_SECRET` and `PAYMOB_API_KEY`.
9. Re-run `npx vitest run --config vitest.workers.config.ts test/system/notify.system.test.ts` from `abo/` until those tests are green. Then write `quickstart.md`.

`abo/src/clinic-api/checkouts.ts`, `abo/src/provider/registry.ts`, `createPaymobIntention`, `abo/test/system/cross-worker-harness.ts`, `abo/vitest.cross-worker.config.ts`, `abo/src/clock.ts`, and `abo/src/records/append.ts` stay as they are. Platform and `vendor-contracts` sources stay as they are.

## Complexity Tracking

02 §7 records no constitution violation for this design. Nothing to justify.
