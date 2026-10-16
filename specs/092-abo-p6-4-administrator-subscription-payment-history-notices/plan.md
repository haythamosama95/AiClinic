# Implementation Plan: Administrator subscription, payment history and commercial notices

**Branch**: `ai/092-abo-p6-4-administrator-subscription-payment-history-notices` | **Date**: 2026-10-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/092-abo-p6-4-administrator-subscription-payment-history-notices/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

An administrator opens the subscription page from the live desktop shell and reads this clinic's plan, dates, allowance, queued and held counts, subscription reference, commercial notices, and payment history, including "contact support" with that reference. This is phase P6, size M, and **Depends** P6.3.

## Technical Context

**Language/Version**: Dart / Flutter stable. Desktop app in `frontend/`.

**Primary Dependencies**: The existing `AboClient` and `BillingTokenClient` in `frontend/lib/features/ai/billing/`, the existing `RpcResult` in `frontend/lib/core/rpc/rpc_result.dart`, and `get_ai_billing_status(p_contract_version)` with `p_contract_version` set to `backendRpc`. The ABO calls are `GET /v1/subscription` and `GET /v1/payments`, on the billing token's `abo_base_url`, with `Authorization: Bearer <billing token>` and `Abo-Contract-Version` set to `aboClinic`. No new library. The route `AppRoutes.aiAdministratorBilling` already opens `AdministratorBillingPage`.

**Storage**: N/A. This unit defines no entities. The tenant is the token's `org` only. The desktop stores nothing for that tenant.

**Testing**: Harness H-FL on H-FS. One new Dart file tagged `fullstack` under `frontend/test/integration/`. No `integration_test/` driver (OQ-6). Titles start with the E2E id (rule V3). The five tests are written to fail before the production changes. The arrange step uses the existing checkout and the Paymob success fixture `abo/test/fixtures/paymob/success.json`. It does not insert `payment` or `reversal` rows. `TEST_CLOCK` stays unset. The test does not sleep for the hourly checkout window or for `expires_at`. The tests do not start wrangler and do not run `npm test` in `e2e/fullstack/`.

**Target Platform**: Flutter desktop. The subscription page is `AdministratorBillingPage`, opened from the renew action on `AiFeatureHostPage` (key `ai_notice_renew`) and from `AiDegradedView`.

**Project Type**: Frontend. The unit row names no wiring exception. This unit does not change `backend/`, `abo/`, `ai-platform/`, `packages/vendor-contracts/`, or `e2e/fullstack/`.

**Performance Goals**: The subscription read runs when the page opens. Payment history loads one page of 20 and requests the next page only from the next-page control. The desktop does not poll subscription or payments.

**Constraints**: The page shows this tenant's subscription and payments. A caller who is not an `administrator` is outside this page; `get_ai_billing_status` already returns `FORBIDDEN_ROLE` with no status payload. Offers, billing contact, checkout, and polling stay the P6.3 step machine on the same page. This unit does not record payments, reversals, or grants. Null copied columns stay null. There is no `remaining` field. `terms_held` is shown only when `GET /v1/subscription` includes it. A cursor that is not a reference of this tenant is `invalid_request`.

**Scale/Scope**: Size M (rule S3: two user stories, one codebase, five E2E ids). Implied task count is 22 (the sequencing below).

`GET /v1/subscription` is `{contract_version, subscription_ref, snapshot, notices}`. `subscription_ref` is `AIC-` plus the leading 8 Crockford base-32 characters of SHA-256(`"sub-ref:"` ‖ the token's `org`). `snapshot` is the §1.7 object from a live `getCoverage`; when that call fails it is this tenant's `coverage_view.snapshot`; when that row is also absent, `snapshot` is null and the response is still that object. `notices` is the closed set of code strings: `duplicate_payment`, `late_payment_honoured`, `payment_withheld`, `reversal_recorded`, and `terms_held` only when `snapshot.held_count` > 0.

`GET /v1/payments` is `{contract_version, payments, next_cursor, has_more}`. Each payment is `{reference, paid_at, amount_minor, currency, plan_display_name, offer_version, term_unit, term_count, classification, reversals}`. `classification` is `normal`, `likely_duplicate`, or `late`. Each reversal is `{reference, amount_minor, kind, is_full}` and `kind` is `refund`, `void`, `chargeback`, or `unknown`. A page holds 20 payments of this tenant, ordered by `paid_at` ascending and then `reference` ascending. The first request omits `cursor`. Otherwise `cursor` is the previous response's `next_cursor`, that string unchanged (the `PAY-` reference). `next_cursor` is empty when `payments` is empty. `has_more` is true when another payment of this tenant follows the page.

`get_ai_billing_status` returns the §3.2 status view plus flat `data` fields `plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, `used`, `queued_count`, `held_count`, `subscription_ref`, and `abo_base_url`. Plan is `plan_display_name`. Dates are `starts_at`, `ends_at`, and `grace_ends_at`. Allowance figures are `allowance` and `used`. Status `ended_reversed` is the notice raised when the state is `reversed`. When the projection row is absent, or a copied column is null, that JSON value is null.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). Spikes are none, so there is no `research.md`. Freezes are none, so there is no `contracts/` directory. The spec defines no entities, so there is no `data-model.md`. The same boxes hold after this plan. This unit adds no constitution violation, so Complexity Tracking stays empty.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  A clinic administrator reads this clinic's subscription, commercial notices, and payment history, and can contact support with the subscription reference. Another clinic's subscription and payments are not shown (spec §4.1, 02 §7 principle I).

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The change is the Flutter desktop. Subscription and payment reads stay on the existing ABO and the existing status RPC. No new worker, queue, or service (02 §7 principle I).

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Flutter owns the subscription page, commercial notices, payment history, and "contact support". Supabase exposes `get_ai_billing_status`. The ABO exposes `GET /v1/subscription` and `GET /v1/payments`. This unit does not record payments, reversals, or grants (spec §4.1, 02 §7 principle II).

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit defines no tables. `get_ai_billing_status` stays the existing administrator RPC. The desktop calls it and reads the ABO. Clinic-side integrity stays in PostgreSQL (spec §4.1, 02 §7 principle III).

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  The page is the administrator billing route. Subscription and payment reads are for this tenant. Organisation A's administrator never sees B's subscription or payments. The desktop deletes nothing (spec §4.1, 04 §2.2, 02 §7 principle IV).

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  The page only reads. When live coverage fails, the subscription response still returns, using `coverage_view.snapshot` or a null `snapshot`. Clinical work is not hard-locked (spec §4.1, 02 §7 principle V).

| Principle or rule | How this unit complies |
| --- | --- |
| I. Product fit and simplicity | One administrator subscription page on the existing desktop shell. |
| II. Replaceable layer boundaries | Codebase is frontend. The ABO and the status RPC remain the source of the reads. |
| III. Backend authority and data integrity | No tables. The page shows the values the RPC and the ABO return, including nulls. |
| IV. Secure and human-gated operations | The route is the administrator billing page. The tenant comes from the session. |
| V. Operational continuity | A failed live coverage read still returns the subscription object. Notices stay inline. |
| Workflow automation | The next page is one control and one read. No scheduler and no queue. |
| Higher operational burden | No new operational part. The Dart tests extend harness H-FL. |

## Project Structure

### Documentation (this feature)

```text
specs/092-abo-p6-4-administrator-subscription-payment-history-notices/
├── plan.md
├── spec.md
├── escalations.md
└── quickstart.md          # after this unit's H-FL tests are green; outline below
```

`research.md` is omitted. Spikes are none. `data-model.md` is omitted. The spec defines no entities. `contracts/` is omitted. This unit freezes no wire shape.

`quickstart.md` is not written in this phase. After the harness is green, implement fills only these sections:

- What was implemented, and the files added or modified
- Harness command for this unit's tests only, from `frontend/`:
  - `flutter test test/integration/administrator_subscription_fullstack_test.dart --tags fullstack`
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- Manual steps only if the harness cannot see the behaviour (none are expected)

### Source Code (repository root)

```text
frontend/lib/features/ai/billing/abo_client.dart
frontend/lib/features/ai/billing/subscription_summary.dart
frontend/lib/features/ai/billing/commercial_notices.dart
frontend/lib/features/ai/billing/payment_history.dart
frontend/lib/features/ai/billing/administrator_billing_page.dart
frontend/test/integration/administrator_subscription_fullstack_test.dart
```

**Structure Decision**: Frontend only. `AdministratorBillingPage` stays the route body. It keeps the P6.3 offers, contact, and checkout steps, and composes the subscription summary, commercial notices, and payment history on that page. `AboClient` gains the two reads. The existing checkout, contact, and offers methods stay. H-FL for these five ids is the new tagged fullstack file. `frontend/lib/app/router.dart`, `frontend/lib/app/app_routes.dart`, `AiFeatureHostPage`, and `AiDegradedView` already open this page and are not modified.

## Consumes Binding

| Consumes | Existing module | This unit |
| --- | --- | --- |
| P6.3 CP-E | The administrator thread already on `AdministratorBillingPage`: `BillingTokenClient`, the existing `AboClient` checkout methods, `OffersScreen`, `BillingContactForm`, and `CheckoutScreen`, opened from `ai_notice_renew` on `AiFeatureHostPage` and from `AiDegradedView`. The route is `AppRoutes.aiAdministratorBilling`. | Composes the new reads on that page. Does not rewrite the checkout, contact, or offers thread, and does not change those methods. |

## Files

| Path | Action | FR |
| --- | --- | --- |
| `frontend/lib/features/ai/billing/abo_client.dart` | Modify. Add `GET /v1/subscription` and `GET /v1/payments`. Leave `getOffers`, billing contact, checkout create, checkout read, and the open list as they are. The subscription body is `{contract_version, subscription_ref, snapshot, notices}`. The payments body is `{contract_version, payments, next_cursor, has_more}` with the payment and reversal fields in Technical Context. The first payments call omits `cursor`. A later call sets `cursor` to the previous `next_cursor`, unchanged. A response code `invalid_request` is surfaced on that call | FR-001, FR-003, FR-004 |
| `frontend/lib/features/ai/billing/subscription_summary.dart` | Create. Call `get_ai_billing_status` with `p_contract_version` set to `backendRpc` through the existing `RpcResult`, and `GET /v1/subscription` through `AboClient`. Show `plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, `used`, `queued_count`, `held_count`, and `subscription_ref`. Show "contact support" with that `subscription_ref`. Show `ended_reversed` when the status-view notices include that code. A null copied field stays null. Do not show a remaining figure. A null `snapshot` still leaves the subscription object on screen. The widget takes no organisation id | FR-001, FR-002, FR-005 |
| `frontend/lib/features/ai/billing/commercial_notices.dart` | Create. Show the `notices` code strings from `GET /v1/subscription`, including `duplicate_payment`, `late_payment_honoured`, `payment_withheld`, `reversal_recorded`, and `terms_held` when that array contains them. Do not add `terms_held` when the array omits it | FR-002 |
| `frontend/lib/features/ai/billing/payment_history.dart` | Create. Show each payment's `reference`, `paid_at`, `amount_minor`, `currency`, `plan_display_name`, `offer_version`, `term_unit`, `term_count`, `classification`, and `reversals` (`reference`, `amount_minor`, `kind`, `is_full`). Keep the response order. The first load omits `cursor`. An explicit next-page control is shown when `has_more` is true; it requests `GET /v1/payments` with `cursor` set to `next_cursor` and appends that page | FR-003, FR-004 |
| `frontend/lib/features/ai/billing/administrator_billing_page.dart` | Modify. Compose `subscription_summary.dart`, `commercial_notices.dart`, and `payment_history.dart` on the existing page. Leave the offers, contact, and checkout steps, the token client, and the open-checkout resume as they are | FR-001, FR-002, FR-003, FR-004, FR-005 |
| `frontend/test/integration/administrator_subscription_fullstack_test.dart` | Create. Tagged `fullstack`. Five tests, titles prefixed `E2E-P6.4-01` through `E2E-P6.4-05` | FR-001, FR-002, FR-003, FR-004, FR-005 |
| `specs/092-abo-p6-4-administrator-subscription-payment-history-notices/quickstart.md` | Create after this unit's H-FL tests are green | FR-001, FR-003, FR-004 |

`BillingTokenClient`, `OffersScreen`, `BillingContactForm`, `CheckoutScreen`, `router.dart`, `app_routes.dart`, `AiFeatureHostPage`, and `AiDegradedView` stay as P6.3 left them.

## Test Layout

Harness H-FL on H-FS. One new file, tagged `fullstack`. Each test opens `AdministratorBillingPage` from the renew action (`ai_notice_renew`) in the app shell, through the existing route. The arrange step runs before that open. It drives `POST /v1/checkouts` and replays `abo/test/fixtures/paymob/success.json` onto the running stack, with that fixture's transaction id and order id set to the checkout's. It reads the checkout's existing `paymob_intention.order_id` from the local ABO D1 under `e2e/fullstack/.wrangler/abo`. It does not insert `payment` or `reversal` rows. `TEST_CLOCK` stays unset. The test does not boot wrangler. A row is one test (rule V3). Each new test is red before the production change it names. No `integration_test/` driver.

| ID | Title prefix | Entry → chain | Assertion |
| --- | --- | --- | --- |
| E2E-P6.4-01 | `E2E-P6.4-01` | Two `POST /v1/checkouts` opened together so they share `opened_with_coverage_through`, then the success fixture on each, then the renew action → `AdministratorBillingPage` → subscription summary, commercial notices, payment history | The page shows `duplicate_payment`. History shows both payments and the second is `likely_duplicate`. Queued count is 1 |
| E2E-P6.4-02 | `E2E-P6.4-02` | One paid checkout, then `abo/test/fixtures/paymob/refund-parent.json` for that checkout's transaction id and order id, then the same page | The page shows `reversal_recorded` and `terms_held`. History shows the reversal. Status is `ended_reversed` |
| E2E-P6.4-03 | `E2E-P6.4-03` | One open checkout whose `checkout_status.state` is set to `cancelled` in the local ABO D1, then the success fixture. A second checkout whose Paymob stub inquiry is `amount_mismatch` (`POST` `{inquiry: "amount_mismatch"}` to the running stub at `PAYMOB_URL`, default `http://127.0.0.1:8789/__script`), then the success fixture. Then the same page | The late payment shows `late_payment_honoured`. The withheld mismatch shows `payment_withheld` |
| E2E-P6.4-04 | `E2E-P6.4-04` | Three batches of 10. Each payment is its own `POST /v1/checkouts` with a new `client_request_id` and a success fixture whose transaction id and order id are that checkout's. After each batch of 10, and before the next checkout, set `fact_log.created_at` for those checkout facts (`"table" = 'checkout'`, `key` = `checkout_id`) to more than one hour before wall-clock now. Then the payment history on the same page and its next-page control | Paging covers 30 payments. The first page holds 20, ordered as returned. The control requests the next page with `cursor` set to `next_cursor` and the page appends it |
| E2E-P6.4-05 | `E2E-P6.4-05` | Organisation A's administrator session of that same page, after A and B each have a subscription and a payment | A never sees B's `subscription_ref` or payment references |

## Sequencing

Tests before implementation. The new tests are observed failing, then the desktop changes, then those tests pass. Implied task count: 22.

1. Add the failing `E2E-P6.4-01` test in `administrator_subscription_fullstack_test.dart`.
2. Add the failing `E2E-P6.4-02` test in the same file.
3. Add the failing `E2E-P6.4-03` test in the same file, including the `cancelled` checkout-status update and the amount-mismatch stub script.
4. Add the failing `E2E-P6.4-04` test in the same file, including the three batches and the `fact_log.created_at` update.
5. Add the failing `E2E-P6.4-05` test in the same file.
6. From `frontend/`, run `flutter test test/integration/administrator_subscription_fullstack_test.dart --tags fullstack` against the running H-FS stack and confirm E2E-P6.4-01 through E2E-P6.4-05 fail.
7. Add `GET /v1/subscription` parsing on `AboClient`. Leave the existing methods unchanged.
8. Add `GET /v1/payments` parsing on `AboClient`. Omit `cursor` on the first call.
9. Pass `cursor` as the previous `next_cursor`, unchanged, and surface `invalid_request`.
10. Call `get_ai_billing_status` from the subscription summary and read the flat `data` fields. Leave a null value null. Do not add `remaining`.
11. Show plan, dates, allowance, used, queued count, held count, and `subscription_ref`.
12. Show "contact support" with that `subscription_ref`.
13. Show `ended_reversed` when the status-view notices include that code.
14. Keep the summary on screen when `snapshot` is null.
15. Build the commercial-notices widget from the subscription `notices` array, without adding `terms_held`.
16. Build the payment-history widget for the payment fields, classification, and reversals, in response order.
17. Add the next-page control that appends when `has_more` is true.
18. Give the summary and the history no organisation argument; they use the signed-in session only.
19. Compose the summary, the notices, and the history on `AdministratorBillingPage` without changing the checkout steps.
20. Re-run the fullstack file until E2E-P6.4-01 through E2E-P6.4-05 pass.
21. Confirm the P6.3 billing page still reaches offers, contact, and checkout on that same route.
22. Write `quickstart.md` from the outline in Project Structure.

## Complexity Tracking

No constitution violation is recorded in 02 §7 for this unit. Nothing to justify.
