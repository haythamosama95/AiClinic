# Tasks: Administrator subscription, payment history and commercial notices

**Input**: Design documents from `specs/092-abo-p6-4-administrator-subscription-payment-history-notices/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P6.3 (CP-E). Plan artifacts from `AVAILABLE_DOCS`: none. `research.md` is omitted (no spike). `data-model.md` and `contracts/` are omitted (no entities; this unit freezes no wire shape). `quickstart.md` is written in Documentation after this unit's H-FL tests are green.

**Organization**: P6.4 is User Story 1 and User Story 2 (`[US1]`, `[US2]`), size M (rule S3). Branch `ai/092-abo-p6-4-administrator-subscription-payment-history-notices`. E2E ids stay `E2E-P6.4-01` through `E2E-P6.4-05`. Tests are one task per E2E id, written to fail before the production change, plus the plan sequencing red run. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase (the billing feature and the `fullstack` tag already exist). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 21. Size M is 20–32 (rule S3). Plan sequencing implies 22 steps. The green re-run and the P6.3 route confirmation are one verification task. The count is not padded.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`
- **Harness H-FL**: one Dart file tagged `fullstack` at `frontend/test/integration/administrator_subscription_fullstack_test.dart`. Each test opens `AdministratorBillingPage` from the renew action on `AiFeatureHostPage` (key `ai_notice_renew`) through the existing route `AppRoutes.aiAdministratorBilling`. The arrange step runs before that open. It drives `POST /v1/checkouts` and replays `abo/test/fixtures/paymob/success.json` onto the running H-FS stack, with that fixture's transaction id and order id set to the checkout's. It reads the checkout's existing `paymob_intention.order_id` from the local ABO D1 under `e2e/fullstack/.wrangler/abo`. It does not insert `payment` or `reversal` rows. `TEST_CLOCK` stays unset. The test does not sleep for the hourly checkout window or for `expires_at`. The test does not boot wrangler. No `integration_test/` driver (OQ-6)
- **Unchanged by this unit**: `BillingTokenClient`, `OffersScreen`, `BillingContactForm`, `CheckoutScreen`, `frontend/lib/app/router.dart`, `frontend/lib/app/app_routes.dart`, `AiFeatureHostPage`, `AiDegradedView`, `backend/`, `abo/`, `ai-platform/`, `packages/vendor-contracts/`, `e2e/fullstack/`
- **Spec Kit artifacts**: `specs/092-abo-p6-4-administrator-subscription-payment-history-notices/`

---

## 3. Tests (H-FL)

**Purpose**: Sequencing steps 1–6. One failing test per E2E id in `frontend/test/integration/administrator_subscription_fullstack_test.dart`. Titles are prefixed with the E2E id. Leave the production files in **Files** unchanged through T006.

Harness command, from `frontend/`, against the running H-FS stack:

```bash
flutter test test/integration/administrator_subscription_fullstack_test.dart --tags fullstack
```

That command is the unit harness. `npm test` in `e2e/fullstack` is not the harness. Do not start wrangler.

### 3.1 User Story 1 - An administrator reads the subscription and its commercial notices (Priority: P1) — tests

**Independent Test**: E2E-P6.4-01, E2E-P6.4-02, and E2E-P6.4-03 in harness H-FL on H-FS.

- [ ] T001 [US1] Add the failing test `E2E-P6.4-01` in `frontend/test/integration/administrator_subscription_fullstack_test.dart` — red test, FR-001, FR-002, FR-003, E2E-P6.4-01. Depends on nothing. Create the file. Title `E2E-P6.4-01`. Tag the test `fullstack`. Arrange two `POST /v1/checkouts` opened together so they share `opened_with_coverage_through`, then replay `abo/test/fixtures/paymob/success.json` on each, with that fixture's transaction id and order id set to the checkout's. Read `paymob_intention.order_id` from the local ABO D1 under `e2e/fullstack/.wrangler/abo`. Do not insert `payment` or `reversal` rows. `TEST_CLOCK` stays unset. Do not boot wrangler. Then open `AdministratorBillingPage` from `ai_notice_renew`. The page shows `duplicate_payment`. History shows both payments and the second is `likely_duplicate`. Queued count is 1. The harness command fails because the subscription summary, commercial notices, and payment history are absent.

**Checkpoint**: E2E-P6.4-01 exists and fails.

- [ ] T002 [US1] Add the failing test `E2E-P6.4-02` in `frontend/test/integration/administrator_subscription_fullstack_test.dart` — red test, FR-001, FR-002, FR-003, E2E-P6.4-02. Depends on T001 (same file). Title `E2E-P6.4-02`. Tag the test `fullstack`. Arrange one paid checkout, then replay `abo/test/fixtures/paymob/refund-parent.json` for that checkout's transaction id and order id. Do not insert `payment` or `reversal` rows. `TEST_CLOCK` stays unset. Do not boot wrangler. Then open the same page. The page shows `reversal_recorded` and `terms_held`. History shows the reversal. Status is `ended_reversed`. The harness command fails because those notices, the reversal, and that status are absent. E2E-P6.4-01 still fails.

**Checkpoint**: E2E-P6.4-01 and E2E-P6.4-02 exist and fail.

- [ ] T003 [US1] Add the failing test `E2E-P6.4-03` in `frontend/test/integration/administrator_subscription_fullstack_test.dart` — red test, FR-002, E2E-P6.4-03. Depends on T002 (same file). Title `E2E-P6.4-03`. Tag the test `fullstack`. Arrange one open checkout, set that checkout's `checkout_status.state` to `cancelled` in the local ABO D1, then replay the success fixture. Arrange a second checkout whose Paymob stub inquiry is `amount_mismatch` (`POST` `{inquiry: "amount_mismatch"}` to the running stub at `PAYMOB_URL`, default `http://127.0.0.1:8789/__script`), then the success fixture. Do not insert `payment` or `reversal` rows. `TEST_CLOCK` stays unset. Do not sleep for `expires_at`. Do not boot wrangler. Then open the same page. The late payment shows `late_payment_honoured`. The withheld mismatch shows `payment_withheld`. The harness command fails because those notices are absent. E2E-P6.4-01 and E2E-P6.4-02 still fail.

**Checkpoint**: E2E-P6.4-01, E2E-P6.4-02, and E2E-P6.4-03 exist and fail.

### 3.2 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2) — tests

**Independent Test**: E2E-P6.4-04 and E2E-P6.4-05 in harness H-FL on H-FS. Every earlier suite stays green (rule S2).

- [ ] T004 [US2] Add the failing test `E2E-P6.4-04` in `frontend/test/integration/administrator_subscription_fullstack_test.dart` — red test, FR-004, E2E-P6.4-04. Depends on T003 (same file). Title `E2E-P6.4-04`. Tag the test `fullstack`. Arrange three batches of 10. Each payment is its own `POST /v1/checkouts` with a new `client_request_id` and a success fixture whose transaction id and order id are that checkout's. After each batch of 10, and before the next checkout, set `fact_log.created_at` for those checkout facts (`"table" = 'checkout'`, `key` = `checkout_id`) to more than one hour before wall-clock now. Do not insert `payment` or `reversal` rows. `TEST_CLOCK` stays unset. Do not sleep for the hourly window. Do not boot wrangler. Then open payment history on the same page. Paging covers 30 payments. The first page holds 20, ordered as returned. The next-page control requests the next page with `cursor` set to `next_cursor` and the page appends it. The harness command fails because that control is absent. E2E-P6.4-01 through E2E-P6.4-03 still fail.

**Checkpoint**: E2E-P6.4-04 exists and fails.

- [ ] T005 [US2] Add the failing test `E2E-P6.4-05` in `frontend/test/integration/administrator_subscription_fullstack_test.dart` — red test, FR-005, E2E-P6.4-05. Depends on T004 (same file). Title `E2E-P6.4-05`. Tag the test `fullstack`. Arrange a subscription and a payment for organisation A and for organisation B through the same checkout and success fixture. Do not insert `payment` or `reversal` rows. `TEST_CLOCK` stays unset. Do not boot wrangler. Open organisation A's administrator session of the same page. A never sees B's `subscription_ref` or payment references. The harness command fails because that boundary is not held. E2E-P6.4-01 through E2E-P6.4-04 still fail.

**Checkpoint**: E2E-P6.4-04 and E2E-P6.4-05 exist and fail.

### 3.3 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2) — red run

**Independent Test**: E2E-P6.4-04 and E2E-P6.4-05 in harness H-FL on H-FS. Every earlier suite stays green (rule S2).

- [ ] T006 [US2] Run the H-FL command and confirm E2E-P6.4-01 through E2E-P6.4-05 fail — red run, FR-001, FR-002, FR-003, FR-004, FR-005, E2E-P6.4-01, E2E-P6.4-02, E2E-P6.4-03, E2E-P6.4-04, E2E-P6.4-05. Depends on T005. From `frontend/`, against the running H-FS stack, run `flutter test test/integration/administrator_subscription_fullstack_test.dart --tags fullstack` and confirm E2E-P6.4-01 through E2E-P6.4-05 fail. Leave the production files unchanged. Do not edit `frontend/test/integration/administrator_subscription_fullstack_test.dart` in this task. Do not run `npm test` in `e2e/fullstack`. Do not start wrangler.

**Checkpoint**: E2E-P6.4-01 through E2E-P6.4-05 fail. The subscription summary, commercial notices, and payment history do not exist yet.

---

## 4. Implementation

**Purpose**: Sequencing steps 7–19. Starts after T006 has shown the five tests fail. Within a subphase the tasks run in id order.

### 4.1 User Story 1 - An administrator reads the subscription and its commercial notices (Priority: P1) — subscription and payments reads

**Independent Test**: E2E-P6.4-01, E2E-P6.4-02, and E2E-P6.4-03 in harness H-FL on H-FS.

- [ ] T007 [US1] Add `GET /v1/subscription` parsing on `frontend/lib/features/ai/billing/abo_client.dart` — subscription body, FR-001, FR-002, E2E-P6.4-01, E2E-P6.4-02, E2E-P6.4-03. Depends on T006. Parse `{contract_version, subscription_ref, snapshot, notices}`. `notices` is the closed set of code strings the response returns. Leave `getOffers`, billing contact, checkout create, checkout read, and the open list unchanged.

**Checkpoint**: The client parses `GET /v1/subscription`. E2E-P6.4-01 still fails.

- [ ] T008 [US1] Add `GET /v1/payments` parsing on `frontend/lib/features/ai/billing/abo_client.dart` — payments body, first call omits `cursor`, FR-003, E2E-P6.4-01, E2E-P6.4-02. Depends on T007 (same file). Parse `{contract_version, payments, next_cursor, has_more}`. Each payment is `{reference, paid_at, amount_minor, currency, plan_display_name, offer_version, term_unit, term_count, classification, reversals}`. `classification` is `normal`, `likely_duplicate`, or `late`. Each reversal is `{reference, amount_minor, kind, is_full}` and `kind` is `refund`, `void`, `chargeback`, or `unknown`. The first call omits `cursor`. Leave the existing methods unchanged.

**Checkpoint**: The client parses the first payments page with no `cursor`. E2E-P6.4-01 still fails.

### 4.2 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2) — payments cursor

**Independent Test**: E2E-P6.4-04 and E2E-P6.4-05 in harness H-FL on H-FS. Every earlier suite stays green (rule S2).

- [ ] T009 [US2] Pass `cursor` as the previous `next_cursor` on `frontend/lib/features/ai/billing/abo_client.dart` — unchanged cursor, surface `invalid_request`, FR-004, E2E-P6.4-04. Depends on T008 (same file). A later `GET /v1/payments` sets `cursor` to the previous `next_cursor`, that string unchanged. A response code `invalid_request` is surfaced on that call. Leave the existing methods unchanged.

**Checkpoint**: The client sends the previous `next_cursor` and surfaces `invalid_request`. E2E-P6.4-04 still fails.

### 4.3 User Story 1 - An administrator reads the subscription and its commercial notices (Priority: P1) — subscription summary

**Independent Test**: E2E-P6.4-01, E2E-P6.4-02, and E2E-P6.4-03 in harness H-FL on H-FS.

- [ ] T010 [US1] Call `get_ai_billing_status` and `GET /v1/subscription` from `frontend/lib/features/ai/billing/subscription_summary.dart` — flat `data` fields, null stays null, FR-001, E2E-P6.4-01, E2E-P6.4-02. Depends on T009. Create the file. Call `get_ai_billing_status` with `p_contract_version` set to `backendRpc` through the existing `RpcResult`, and `GET /v1/subscription` through `AboClient`. Read `plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, `used`, `queued_count`, `held_count`, and `subscription_ref`. A null copied field stays null. Do not add a `remaining` figure.

**Checkpoint**: The summary loads the status RPC and the subscription read. E2E-P6.4-01 still fails.

- [ ] T011 [US1] Show plan, dates, allowance, used, queued count, held count, and `subscription_ref` in `frontend/lib/features/ai/billing/subscription_summary.dart` — summary fields, FR-001, E2E-P6.4-01. Depends on T010 (same file). Show `plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, `used`, `queued_count`, `held_count`, and `subscription_ref`.

**Checkpoint**: Those summary fields are on screen. E2E-P6.4-01 still fails.

- [ ] T012 [US1] Show "contact support" with `subscription_ref` in `frontend/lib/features/ai/billing/subscription_summary.dart` — support line, FR-001, E2E-P6.4-01. Depends on T011 (same file). Show "contact support" with that `subscription_ref`.

**Checkpoint**: "contact support" shows the subscription reference. E2E-P6.4-01 still fails.

- [ ] T013 [US1] Show `ended_reversed` in `frontend/lib/features/ai/billing/subscription_summary.dart` — status-view notice, FR-002, E2E-P6.4-02. Depends on T012 (same file). Show `ended_reversed` when the status-view notices include that code.

**Checkpoint**: Status `ended_reversed` is shown when that notice is present. E2E-P6.4-02 still fails.

- [ ] T014 [US1] Keep the summary on screen when `snapshot` is null in `frontend/lib/features/ai/billing/subscription_summary.dart` — null snapshot, FR-001, E2E-P6.4-01. Depends on T013 (same file). A null `snapshot` still leaves the subscription object on screen.

**Checkpoint**: A null `snapshot` still leaves the subscription summary on screen. E2E-P6.4-01 still fails.

### 4.4 User Story 1 - An administrator reads the subscription and its commercial notices (Priority: P1) — commercial notices

**Independent Test**: E2E-P6.4-01, E2E-P6.4-02, and E2E-P6.4-03 in harness H-FL on H-FS.

- [ ] T015 [US1] Build the commercial-notices widget in `frontend/lib/features/ai/billing/commercial_notices.dart` — notices array, FR-002, E2E-P6.4-01, E2E-P6.4-02, E2E-P6.4-03. Depends on T014. Create the file. Show the `notices` code strings from `GET /v1/subscription`, including `duplicate_payment`, `late_payment_honoured`, `payment_withheld`, `reversal_recorded`, and `terms_held` when that array contains them. Do not add `terms_held` when the array omits it.

**Checkpoint**: Commercial notices render the subscription `notices` array. E2E-P6.4-01, E2E-P6.4-02, and E2E-P6.4-03 still fail.

### 4.5 User Story 1 - An administrator reads the subscription and its commercial notices (Priority: P1) — payment history fields

**Independent Test**: E2E-P6.4-01, E2E-P6.4-02, and E2E-P6.4-03 in harness H-FL on H-FS.

- [ ] T016 [US1] Build the payment-history widget in `frontend/lib/features/ai/billing/payment_history.dart` — payment fields, classification, and reversals, FR-003, E2E-P6.4-01, E2E-P6.4-02. Depends on T008. Create the file. Show each payment's `reference`, `paid_at`, `amount_minor`, `currency`, `plan_display_name`, `offer_version`, `term_unit`, `term_count`, `classification`, and `reversals` (`reference`, `amount_minor`, `kind`, `is_full`). Keep the response order. The first load omits `cursor`.

**Checkpoint**: Payment history shows the payment fields, classification, and reversals in response order. E2E-P6.4-01 and E2E-P6.4-02 still fail.

### 4.6 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2) — next page

**Independent Test**: E2E-P6.4-04 and E2E-P6.4-05 in harness H-FL on H-FS. Every earlier suite stays green (rule S2).

- [ ] T017 [US2] Add the next-page control in `frontend/lib/features/ai/billing/payment_history.dart` — append when `has_more` is true, FR-004, E2E-P6.4-04. Depends on T016 (same file). An explicit next-page control is shown when `has_more` is true. It requests `GET /v1/payments` with `cursor` set to `next_cursor` and appends that page.

**Checkpoint**: The next-page control appends the following page. E2E-P6.4-04 still fails.

### 4.7 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2) — session tenant

**Independent Test**: E2E-P6.4-04 and E2E-P6.4-05 in harness H-FL on H-FS. Every earlier suite stays green (rule S2).

- [ ] T018 [US2] Give the summary and the history no organisation argument in `frontend/lib/features/ai/billing/subscription_summary.dart` and `frontend/lib/features/ai/billing/payment_history.dart` — signed-in session only, FR-005, E2E-P6.4-05. Depends on T014 and T017. Neither widget takes an organisation id. Both use the signed-in session only.

**Checkpoint**: The summary and the history take no organisation argument. E2E-P6.4-05 still fails.

### 4.8 User Story 1 - An administrator reads the subscription and its commercial notices (Priority: P1) — page composition

**Independent Test**: E2E-P6.4-01, E2E-P6.4-02, and E2E-P6.4-03 in harness H-FL on H-FS.

- [ ] T019 [US1] Compose the summary, the notices, and the history on `frontend/lib/features/ai/billing/administrator_billing_page.dart` — existing page, FR-001, FR-002, FR-003, FR-004, FR-005, E2E-P6.4-01, E2E-P6.4-02, E2E-P6.4-03, E2E-P6.4-04, E2E-P6.4-05. Depends on T015 and T018. Compose `subscription_summary.dart`, `commercial_notices.dart`, and `payment_history.dart` on the existing page. Leave the offers, contact, and checkout steps, the token client, and the open-checkout resume as they are.

**Checkpoint**: The administrator billing page shows the summary, the notices, and the history. E2E-P6.4-01 through E2E-P6.4-05 are ready for the harness.

---

## 5. Verification (H-FL)

**Purpose**: Sequencing steps 20–21. The unit harness passes, and the P6.3 offers, contact, and checkout steps remain on that route. This is not a repo-wide command.

### 5.1 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2) — H-FL harness

**Independent Test**: E2E-P6.4-04 and E2E-P6.4-05 in harness H-FL on H-FS. Every earlier suite stays green (rule S2).

- [ ] T020 [US2] Re-run the fullstack file until E2E-P6.4-01 through E2E-P6.4-05 pass, and confirm the P6.3 billing page still reaches offers, contact, and checkout — green harness, FR-001, FR-002, FR-003, FR-004, FR-005, E2E-P6.4-01, E2E-P6.4-02, E2E-P6.4-03, E2E-P6.4-04, E2E-P6.4-05. Depends on T019. From `frontend/`, against the running H-FS stack, run `flutter test test/integration/administrator_subscription_fullstack_test.dart --tags fullstack` until E2E-P6.4-01 through E2E-P6.4-05 pass. Confirm the P6.3 billing page still reaches offers, contact, and checkout on that same route. Fixes stay in the files this unit's **Files** table lists under `frontend/`. Do not run `npm test` in `e2e/fullstack`. Do not start wrangler.

**Checkpoint**: E2E-P6.4-01, E2E-P6.4-02, E2E-P6.4-03, E2E-P6.4-04, and E2E-P6.4-05 pass in H-FL. Offers, contact, and checkout remain on the same route.

---

## 6. Documentation

**Purpose**: Sequencing step 22. `quickstart.md` after the harness is green. Plan-phase `research.md`, `data-model.md`, and `contracts/` stay omitted.

### 6.1 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2) — quickstart

**Independent Test**: E2E-P6.4-04 and E2E-P6.4-05 in harness H-FL on H-FS. Every earlier suite stays green (rule S2).

- [ ] T021 [US2] Write `specs/092-abo-p6-4-administrator-subscription-payment-history-notices/quickstart.md` — unit quickstart, FR-001, FR-003, FR-004, E2E-P6.4-01, E2E-P6.4-02, E2E-P6.4-03, E2E-P6.4-04, E2E-P6.4-05. Depends on T020. Fill only these sections: what was implemented and the files added or modified; the harness command for this unit's tests only, from `frontend/`, `flutter test test/integration/administrator_subscription_fullstack_test.dart --tags fullstack`; the entry point → module chain per E2E id. Do not list earlier-unit files, combined counts, or full-suite commands. Manual steps are omitted: the harness sees this behaviour.

**Checkpoint**: `quickstart.md` names the five H-FL ids, the unit command, and the entry chain.

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (Phase 3)**: T001 creates `frontend/test/integration/administrator_subscription_fullstack_test.dart` with E2E-P6.4-01. T002 and T003 add E2E-P6.4-02 and E2E-P6.4-03 in that same file. T004 and T005 add E2E-P6.4-04 and E2E-P6.4-05. T006 runs the harness and confirms all five fail before any production file in **Files** changes.
- **Implementation (Phase 4)**: Starts after T006. `AboClient` gains `GET /v1/subscription`, then `GET /v1/payments` with the first call omitting `cursor`, then the later call passing `cursor` and surfacing `invalid_request`. The subscription summary then loads the status RPC and the subscription read, shows the summary fields, shows "contact support", shows `ended_reversed`, and stays on screen when `snapshot` is null. Commercial notices and the payment-history fields follow that summary. The next-page control follows the history fields. The summary and the history then take no organisation argument. The existing administrator billing page composes the three widgets and leaves offers, contact, and checkout in place.
- **Verification (Phase 5)**: Starts after T019. One command from `frontend/`, as in T006, until the five ids pass, and a confirmation that offers, contact, and checkout remain on that route.
- **Documentation (Phase 6)**: Starts after T020 is green. One file: `quickstart.md`.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: The failing subscription tests are T001, T002, and T003. The subscription read, the first payments read, the summary, the notices, the history fields, and page composition are T007, T008, T010 through T016, and T019. E2E-P6.4-01, E2E-P6.4-02, and E2E-P6.4-03 are included in the red run (T006) and the green harness (T020).
- **User Story 2 (P2)**: The failing paging and clinic-boundary tests are T004 and T005, after the User Story 1 tests. The red run is T006. The payments cursor is T009, after the first payments read. The next-page control is T017, after the history fields. The session-only widgets are T018. E2E-P6.4-04 and E2E-P6.4-05 are included in the red run (T006) and the green harness (T020).

### 7.3 Within Each Phase

- T001 creates `frontend/test/integration/administrator_subscription_fullstack_test.dart`. T002 through T005 write that same file in id order. T006 runs the harness and does not edit that file.
- T007 and T008 write `frontend/lib/features/ai/billing/abo_client.dart`. T009 writes that same file. T010 creates `frontend/lib/features/ai/billing/subscription_summary.dart`, and T011 through T014 write that same file. T015 creates `frontend/lib/features/ai/billing/commercial_notices.dart`. T016 creates `frontend/lib/features/ai/billing/payment_history.dart`. T016 depends on T008 and does not read `commercial_notices.dart`. T017 writes `payment_history.dart`. T018 writes `subscription_summary.dart` and `payment_history.dart`. T019 writes `frontend/lib/features/ai/billing/administrator_billing_page.dart`.
- T020 runs after T019 and may edit only the `frontend/` files listed in this unit's **Files** table.
- T021 writes only `specs/092-abo-p6-4-administrator-subscription-payment-history-notices/quickstart.md` after T020 is green.

---

## 8. Implementation Waves

Commercial notices and the payment-history fields share no path and both follow the subscription summary, so that wave has two bullets. Every other subphase is serial with the one before it.

### 8.1 Wave 1

- T001–T003 [US1] — subphase: `### 3.1 User Story 1 - An administrator reads the subscription and its commercial notices (Priority: P1) — tests` — paths: `frontend/test/integration/administrator_subscription_fullstack_test.dart`

### 8.2 Wave 2

- T004–T005 [US2] — subphase: `### 3.2 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2) — tests` — paths: `frontend/test/integration/administrator_subscription_fullstack_test.dart`

### 8.3 Wave 3

- T006 [US2] — subphase: `### 3.3 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2) — red run` — paths: `frontend/test/integration/administrator_subscription_fullstack_test.dart`

### 8.4 Wave 4

- T007–T008 [US1] — subphase: `### 4.1 User Story 1 - An administrator reads the subscription and its commercial notices (Priority: P1) — subscription and payments reads` — paths: `frontend/lib/features/ai/billing/abo_client.dart`

### 8.5 Wave 5

- T009 [US2] — subphase: `### 4.2 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2) — payments cursor` — paths: `frontend/lib/features/ai/billing/abo_client.dart`

### 8.6 Wave 6

- T010–T014 [US1] — subphase: `### 4.3 User Story 1 - An administrator reads the subscription and its commercial notices (Priority: P1) — subscription summary` — paths: `frontend/lib/features/ai/billing/subscription_summary.dart`

### 8.7 Wave 7

- T015 [US1] — subphase: `### 4.4 User Story 1 - An administrator reads the subscription and its commercial notices (Priority: P1) — commercial notices` — paths: `frontend/lib/features/ai/billing/commercial_notices.dart`
- T016 [US1] — subphase: `### 4.5 User Story 1 - An administrator reads the subscription and its commercial notices (Priority: P1) — payment history fields` — paths: `frontend/lib/features/ai/billing/payment_history.dart`

### 8.8 Wave 8

- T017 [US2] — subphase: `### 4.6 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2) — next page` — paths: `frontend/lib/features/ai/billing/payment_history.dart`

### 8.9 Wave 9

- T018 [US2] — subphase: `### 4.7 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2) — session tenant` — paths: `frontend/lib/features/ai/billing/subscription_summary.dart`, `frontend/lib/features/ai/billing/payment_history.dart`

### 8.10 Wave 10

- T019 [US1] — subphase: `### 4.8 User Story 1 - An administrator reads the subscription and its commercial notices (Priority: P1) — page composition` — paths: `frontend/lib/features/ai/billing/administrator_billing_page.dart`

### 8.11 Wave 11

- T020 [US2] — subphase: `### 5.1 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2) — H-FL harness` — paths: `frontend/lib/features/ai/billing/abo_client.dart`, `frontend/lib/features/ai/billing/subscription_summary.dart`, `frontend/lib/features/ai/billing/commercial_notices.dart`, `frontend/lib/features/ai/billing/payment_history.dart`, `frontend/lib/features/ai/billing/administrator_billing_page.dart`, `frontend/test/integration/administrator_subscription_fullstack_test.dart`

### 8.12 Wave 12

- T021 [US2] — subphase: `### 6.1 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2) — quickstart` — paths: `specs/092-abo-p6-4-administrator-subscription-payment-history-notices/quickstart.md`
