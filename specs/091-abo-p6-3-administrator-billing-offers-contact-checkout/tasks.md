# Tasks: Administrator billing: offers, contact and checkout flow

**Input**: Design documents from `specs/091-abo-p6-3-administrator-billing-offers-contact-checkout/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: none. Plan artifacts from `AVAILABLE_DOCS`: none. `research.md` is omitted (no spike). `data-model.md` and `contracts/` are omitted (no entities; CP-E is not a wire shape). `quickstart.md` is written in Documentation after this unit's H-FL tests are green.

**Organization**: P6.3 is User Story 1 through User Story 4 (`[US1]`, `[US2]`, `[US3]`, `[US4]`), size L (rule S3). Branch `ai/091-abo-p6-3-administrator-billing-offers-contact-checkout`. E2E ids stay `E2E-P6.3-01` through `E2E-P6.3-07`. Tests are one task per E2E id, written to fail before the production change, plus the plan sequencing red run. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase (the `fullstack` tag already exists). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 33. Size L is 32–40 (rule S3). Plan sequencing implies 33 steps. The count is not padded.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`, `US4`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`
- **Harness H-FL**: one Dart file tagged `fullstack` at `frontend/test/integration/administrator_billing_fullstack_test.dart`. Each test pumps the shell from the renew action on `AiFeatureHostPage` or the renew or buy action on `AiDegradedView`, through the route in `frontend/lib/app/router.dart`. `UrlLauncherPlatform` records `redirect_url` and does not open a browser. Payment replays `abo/test/fixtures/paymob/success.json` or `abo/test/fixtures/paymob/decline.json` onto the running H-FS stack. The desktop never signs or posts the callback
- **Unchanged by this unit**: `frontend/lib/features/ai/presentation/pages/ai_page.dart`, `frontend/pubspec.yaml`, `frontend/lib/core/contract_versions.dart`, `backend/`, `abo/`, `ai-platform/`, `packages/vendor-contracts/`, `e2e/fullstack/`
- **Spec Kit artifacts**: `specs/091-abo-p6-3-administrator-billing-offers-contact-checkout/`

---

## 3. Tests (H-FL)

**Purpose**: Sequencing steps 1–8. One failing test per E2E id in `frontend/test/integration/administrator_billing_fullstack_test.dart`. Titles are prefixed with the E2E id. Leave the production files in **Files** unchanged through T008.

Harness command, from `frontend/`, against the running H-FS stack:

```bash
flutter test test/integration/administrator_billing_fullstack_test.dart --tags fullstack
```

That command is the unit harness. `npm test` in `e2e/fullstack` is not the harness. Do not start wrangler.

### 3.1 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — tests

**Independent Test**: E2E-P6.3-01 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T001 [US1] Add the failing test `E2E-P6.3-01` in `frontend/test/integration/administrator_billing_fullstack_test.dart` — red test, FR-001, FR-002, FR-003, FR-004, FR-006, E2E-P6.3-01. Depends on nothing. Create the file. Title `E2E-P6.3-01`. Tag the test `fullstack`. Entry is the renew action on `AiFeatureHostPage` (`ai_notice_renew`), composed from `frontend/lib/app/router.dart` and `frontend/lib/features/ai/presentation/pages/ai_page.dart`, then the billing route, offers screen, contact form, and checkout screen. `UrlLauncherPlatform` records `redirect_url` and does not open a browser. After that launch, replay `abo/test/fixtures/paymob/success.json` onto the running stack. The desktop never signs or posts the callback. Polling shows Active. The desktop calls `request_ai_status_refresh`. `get_ai_status` is active. An AI request succeeds. The test does not start wrangler. The harness command fails because the billing route and screens are absent.

**Checkpoint**: E2E-P6.3-01 exists and fails.

### 3.2 User Story 2 - Any desktop can see an open checkout (Priority: P2) — tests

**Independent Test**: E2E-P6.3-02 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T002 [US2] Add the failing test `E2E-P6.3-02` in `frontend/test/integration/administrator_billing_fullstack_test.dart` — red test, FR-005, E2E-P6.3-02. Depends on T001 (same file). Title `E2E-P6.3-02`. Tag the test `fullstack`. One test drives two in-memory clients for the same clinic, with different branch claims. Neither client writes the tenant to disk, and neither client is given a tenant to write. Each opens the billing route. The second session sees the open checkout by `reference` from `GET /v1/checkouts?open=1` and, after payment, Active. The first session is disposed while payment is in progress, and provisioning still finishes. `get_ai_status` is active on open. The harness command fails because resume by `reference` is absent. E2E-P6.3-01 still fails.

**Checkpoint**: E2E-P6.3-02 exists and fails. E2E-P6.3-01 still fails.

### 3.3 User Story 3 - The administrator sees the term and the price before paying (Priority: P3) — tests

**Independent Test**: E2E-P6.3-03, E2E-P6.3-04, and E2E-P6.3-05 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T003 [US3] Add the failing test `E2E-P6.3-03` in `frontend/test/integration/administrator_billing_fullstack_test.dart` — red test, FR-004, E2E-P6.3-03. Depends on T002 (same file). Title `E2E-P6.3-03`. Tag the test `fullstack`. Entry is the checkout screen after an active clinic posts checkout, before the system browser opens. The screen shows "starts after the current term" before `launchUrl`. The POST answer is `starts` `after_current`. The harness command fails because that sentence is absent. E2E-P6.3-01 and E2E-P6.3-02 still fail.

**Checkpoint**: E2E-P6.3-03 exists and fails.

- [ ] T004 [US3] Add the failing test `E2E-P6.3-04` in `frontend/test/integration/administrator_billing_fullstack_test.dart` — red test, FR-007, E2E-P6.3-04. Depends on T003 (same file). Title `E2E-P6.3-04`. Tag the test `fullstack`. Entry is the checkout screen on `POST /v1/checkouts`, after the running catalogue moves the sellable version. The POST of the version the screen held returns `offer_unavailable`. The screen shows the new price from a fresh offers read before any launch. The harness command fails because that price is not shown. E2E-P6.3-01 through E2E-P6.3-03 still fail.

**Checkpoint**: E2E-P6.3-04 exists and fails.

- [ ] T005 [US3] Add the failing test `E2E-P6.3-05` in `frontend/test/integration/administrator_billing_fullstack_test.dart` — red test, FR-006, FR-007, E2E-P6.3-05. Depends on T004 (same file). Title `E2E-P6.3-05`. Tag the test `fullstack`. Entry is the same checkout page, polling `GET /v1/checkouts/{id}`. Replaying `abo/test/fixtures/paymob/decline.json` leaves the page on Failed. A later `abo/test/fixtures/paymob/success.json` on that same page shows Active. The harness command fails because Failed does not stay on that page. E2E-P6.3-01 through E2E-P6.3-04 still fail.

**Checkpoint**: E2E-P6.3-03, E2E-P6.3-04, and E2E-P6.3-05 exist and fail.

### 3.4 User Story 4 - Staff have no billing entry, and an old app shows the update state (Priority: P4) — tests

**Independent Test**: E2E-P6.3-06 and E2E-P6.3-07 in harness H-FL on H-FS. Every earlier suite stays green (rule S2).

- [ ] T006 [US4] Add the failing test `E2E-P6.3-06` in `frontend/test/integration/administrator_billing_fullstack_test.dart` — red test, FR-008, E2E-P6.3-06. Depends on T005 (same file). Title `E2E-P6.3-06`. Tag the test `fullstack`. Entry is a staff session of `AiFeatureHostPage` in the app shell. The renew control and the renew or buy control are absent. The recording session client sees no `issue_billing_token` call. The harness command fails because that absence is not held. E2E-P6.3-01 through E2E-P6.3-05 still fail.

**Checkpoint**: E2E-P6.3-06 exists and fails.

- [ ] T007 [US4] Add the failing test `E2E-P6.3-07` in `frontend/test/integration/administrator_billing_fullstack_test.dart` — red test, FR-009, E2E-P6.3-07. Depends on T006 (same file). Title `E2E-P6.3-07`. Tag the test `fullstack`. Entry is the administrator billing screens, with `Abo-Contract-Version` outside the accepted pair. The ABO answers `contract_version_unsupported`. The billing screens show the app-update state and no dialog. The harness command fails because that update state is absent. E2E-P6.3-01 through E2E-P6.3-06 still fail.

**Checkpoint**: E2E-P6.3-06 and E2E-P6.3-07 exist and fail.

### 3.5 User Story 4 - Staff have no billing entry, and an old app shows the update state (Priority: P4) — red run

**Independent Test**: E2E-P6.3-06 and E2E-P6.3-07 in harness H-FL on H-FS. Every earlier suite stays green (rule S2).

- [ ] T008 [US4] Run the H-FL command and confirm E2E-P6.3-01 through E2E-P6.3-07 fail — red run, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, E2E-P6.3-01, E2E-P6.3-02, E2E-P6.3-03, E2E-P6.3-04, E2E-P6.3-05, E2E-P6.3-06, E2E-P6.3-07. Depends on T007. From `frontend/`, against the running H-FS stack, run `flutter test test/integration/administrator_billing_fullstack_test.dart --tags fullstack` and confirm E2E-P6.3-01 through E2E-P6.3-07 fail. Leave the production files unchanged. Do not edit `frontend/test/integration/administrator_billing_fullstack_test.dart` in this task. Do not run `npm test` in `e2e/fullstack`. Do not start wrangler.

**Checkpoint**: E2E-P6.3-01 through E2E-P6.3-07 fail. The billing screens do not exist yet.

---

## 4. Implementation

**Purpose**: Sequencing steps 9–31. Starts after T008 has shown the seven tests fail. Within a subphase the tasks run in id order.

### 4.1 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — strings

**Independent Test**: E2E-P6.3-01 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T009 [US1] Add the English billing strings to `frontend/lib/l10n/app_en.arb` — offers, contact, shown states, queued term, and ABO errors, FR-001, E2E-P6.3-01, E2E-P6.3-03, E2E-P6.3-04, E2E-P6.3-05. Depends on T008. English strings for the offers screen, the contact form, the checkout shown states Waiting, Failed, Paid, Active, and Abandoned, "starts after the current term", and the five ABO errors `offer_unavailable`, `billing_contact_required`, `terms_not_accepted`, `provider_unavailable`, and `rate_limited`.

**Checkpoint**: English keys for those billing strings exist. E2E-P6.3-01 still fails.

- [ ] T010 [US1] Add the Arabic strings for those keys to `frontend/lib/l10n/app_ar.arb` — the same billing keys, FR-001, E2E-P6.3-01, E2E-P6.3-03, E2E-P6.3-04, E2E-P6.3-05. Depends on T009. Arabic strings for the keys added in `frontend/lib/l10n/app_en.arb`.

**Checkpoint**: Arabic keys match the English billing keys. E2E-P6.3-01 still fails.

- [ ] T011 [US1] Regenerate `frontend/lib/l10n/app_localizations.dart`, `frontend/lib/l10n/app_localizations_en.dart`, and `frontend/lib/l10n/app_localizations_ar.dart` — generated from the arb files, FR-001, E2E-P6.3-01, E2E-P6.3-03, E2E-P6.3-04, E2E-P6.3-05. Depends on T010. Regenerate those three files from `frontend/lib/l10n/app_en.arb` and `frontend/lib/l10n/app_ar.arb` with the project's existing l10n generation so the new keys are on the localizations class.

**Checkpoint**: The generated localizations expose the billing keys. E2E-P6.3-01 still fails.

### 4.2 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — route

**Independent Test**: E2E-P6.3-01 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T012 [US1] Add the administrator billing path in `frontend/lib/app/app_routes.dart` and register it in `frontend/lib/app/router.dart` — administrator route, FR-001, FR-008, E2E-P6.3-01, E2E-P6.3-06. Depends on T011. In `frontend/lib/app/app_routes.dart`, add the administrator billing path next to the existing AI routes. In `frontend/lib/app/router.dart`, register that path. The builder opens `administrator_billing_page.dart` for an administrator and does not mint a token for anyone else. `frontend/lib/features/ai/billing/administrator_billing_page.dart` is created in T026. Do not change `frontend/lib/features/ai/presentation/pages/ai_page.dart`.

**Checkpoint**: The billing path is registered for an administrator. E2E-P6.3-01 and E2E-P6.3-06 still fail.

### 4.3 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — host renew

**Independent Test**: E2E-P6.3-01 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T013 [US1] Push the billing route from the host renew control in `frontend/lib/features/ai/host/ai_feature_host_page.dart` — `ai_notice_renew`, FR-001, FR-008, E2E-P6.3-01, E2E-P6.3-06. Depends on T012. The administrator renew control (`ai_notice_renew`) pushes the billing route. The staff notice stays the text with no purchase control.

**Checkpoint**: The administrator renew control opens the billing route. E2E-P6.3-01 still fails.

### 4.4 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — degraded renew or buy

**Independent Test**: E2E-P6.3-01 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T014 [US1] Push the billing route from the degraded renew or buy control in `frontend/lib/features/ai/degraded/ai_degraded_view.dart` — `kAiDegradedRenewOrBuyKey`, FR-001, FR-008, E2E-P6.3-01, E2E-P6.3-06. Depends on T012. The administrator renew or buy control (`kAiDegradedRenewOrBuyKey`) pushes the billing route. Staff still do not see that control.

**Checkpoint**: The administrator renew or buy control opens the billing route. E2E-P6.3-01 still fails.

### 4.5 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — token and ABO client

**Independent Test**: E2E-P6.3-01 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T015 [US1] Add the billing-token client in `frontend/lib/features/ai/billing/billing_token_client.dart` — mint on open, renew before expiry, memory only, FR-002, FR-005, FR-008, E2E-P6.3-01, E2E-P6.3-02, E2E-P6.3-06. Depends on T013 and T014. Create the file. Call `issue_billing_token` with `p_contract_version` set to `backendRpc`. Read `{token, abo_base_url, expires_at}`. Mint when the billing page is opened and again before the current token's `expires_at`. Keep the token in memory for that page only. Do not write the tenant, the token, or the checkout. Do not modify `frontend/lib/core/contract_versions.dart`.

**Checkpoint**: The token client mints and renews in memory. E2E-P6.3-01 still fails.

- [ ] T016 [US1] Add the ABO client transport in `frontend/lib/features/ai/billing/abo_client.dart` — bearer token and contract header, FR-002, E2E-P6.3-01, E2E-P6.3-07. Depends on T015. Create the file. Send `Authorization: Bearer <billing token>` and `Abo-Contract-Version` set to `aboClinic` on every call to `abo_base_url`. Do not modify `frontend/lib/core/contract_versions.dart`.

**Checkpoint**: Every ABO call sends the bearer token and `Abo-Contract-Version`. E2E-P6.3-01 still fails.

- [ ] T017 [US1] Parse offers and terms in `frontend/lib/features/ai/billing/abo_client.dart` — `GET /v1/offers`, FR-003, E2E-P6.3-01. Depends on T016 (same file). `GET /v1/offers` reads `offers[]` (`offer_id`, `version`, `plan_display_name`, `term_unit`, `term_count`, `price_minor`, `currency`, `allowance_credits`, `grace_days`, localized `copy`) and `terms` (`version` and text).

**Checkpoint**: The client reads offers and terms. E2E-P6.3-01 still fails.

- [ ] T018 [US1] Parse billing-contact read and save in `frontend/lib/features/ai/billing/abo_client.dart` — `GET` and `PUT /v1/billing-contact`, FR-004, E2E-P6.3-01. Depends on T017 (same file). `GET /v1/billing-contact` reads `version`, `name`, `email`, `phone`, or `not_found`. `PUT /v1/billing-contact` sends `client_request_id`, `name`, `email`, and `phone` in E.164 and reads the new version. The same `client_request_id` is reused for a repeated submit of the same PUT.

**Checkpoint**: The client reads and saves the billing contact. E2E-P6.3-01 still fails.

- [ ] T019 [US1] Parse checkout create, checkout read, the open list, and the error codes in `frontend/lib/features/ai/billing/abo_client.dart` — checkout JSON and ABO errors, FR-004, FR-005, FR-006, FR-007, FR-009, E2E-P6.3-01, E2E-P6.3-02, E2E-P6.3-03, E2E-P6.3-04, E2E-P6.3-05, E2E-P6.3-07. Depends on T018 (same file). `POST /v1/checkouts` sends `client_request_id`, `offer_id`, `offer_version`, and `terms_version`, and reads `checkout_id`, `reference`, `redirect_url`, `expires_at`, and `starts` (`now` or `after_current`, with `projected_start`). The same `client_request_id` is reused for a repeated submit of the same POST. `GET /v1/checkouts/{id}` is `{contract_version, reference, shown_state, offer, payment_reference, term_ref, updated_at}`. `shown_state` is `Waiting`, `Failed`, `Paid`, `Active`, or `Abandoned`. `offer` is `{offer_id, version, term_unit, term_count, charged_price_minor, currency}` with `version` the checkout's `offer_version`. `payment_reference` and `term_ref` are JSON null. `updated_at` is `checkout_status.last_event_at`. The path `{id}` is the POST `checkout_id` and is not a field of that body. `GET /v1/checkouts?open=1` is `{contract_version, checkouts}` of that same object for `checkout_status.state` of `open`, `paid`, or `paid_late`. Map `offer_unavailable` (409, body includes the current version), `billing_contact_required` (409), `terms_not_accepted` (409), `provider_unavailable` (503), `rate_limited` (429), and `contract_version_unsupported` (400, `accepted_versions`).

**Checkpoint**: The client parses checkout create, the checkout read, the open list, and the six error codes. E2E-P6.3-01 still fails.

### 4.6 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — offers and contact

**Independent Test**: E2E-P6.3-01 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T020 [US1] Build the offers screen in `frontend/lib/features/ai/billing/offers_screen.dart` — show offers and accept the current terms, FR-001, FR-003, E2E-P6.3-01. Depends on T019. Create the file. Show the offers and the terms text. The administrator accepts the current terms on this screen before checkout. Offer `copy` stays the localized text from the response.

**Checkpoint**: The offers screen shows offers and terms, and accepts the current terms. E2E-P6.3-01 still fails.

- [ ] T021 [US1] Build the billing-contact form in `frontend/lib/features/ai/billing/billing_contact_form.dart` — read, save, and stay on `billing_contact_required`, FR-001, FR-004, FR-007, E2E-P6.3-01. Depends on T020. Create the file. Show the saved contact or an empty form when the read is `not_found`. Save with the PUT. A checkout that returns `billing_contact_required` stays on this form.

**Checkpoint**: The contact form reads and saves a billing contact. E2E-P6.3-01 still fails.

### 4.7 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — checkout screen

**Independent Test**: E2E-P6.3-01 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T022 [US1] Build the checkout screen and show `shown_state` in `frontend/lib/features/ai/billing/checkout_screen.dart` — open `redirect_url` and show Waiting, Failed, Paid, Active, or Abandoned, FR-001, FR-004, FR-006, E2E-P6.3-01. Depends on T021. Create the file. Open `redirect_url` with `launchUrl` and `LaunchMode.externalApplication`. Show the derived progress state Waiting, Failed, Paid, Active, or Abandoned from `GET /v1/checkouts/{id}`.

**Checkpoint**: The checkout screen launches `redirect_url` and shows `shown_state`. E2E-P6.3-01 still fails.

### 4.8 User Story 3 - The administrator sees the term and the price before paying (Priority: P3) — queued term

**Independent Test**: E2E-P6.3-03, E2E-P6.3-04, and E2E-P6.3-05 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T023 [US3] Show "starts after the current term" before `launchUrl` in `frontend/lib/features/ai/billing/checkout_screen.dart` — `starts` `after_current`, FR-004, E2E-P6.3-03. Depends on T022 (same file). Before `url_launcher`, show whether the term queues. `starts` `after_current` shows "starts after the current term". Nothing changes now.

**Checkpoint**: E2E-P6.3-03 can show the queued-term sentence before launch. E2E-P6.3-01 still fails.

### 4.9 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — poll and refresh

**Independent Test**: E2E-P6.3-01 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T024 [US1] Poll by `checkout_id` while the shown state is Waiting or Paid in `frontend/lib/features/ai/billing/checkout_screen.dart` — one-second timer, FR-006, E2E-P6.3-01, E2E-P6.3-05. Depends on T023 (same file). Poll `GET /v1/checkouts/{id}` on a one-second timer while `shown_state` is Waiting or Paid, and stop on Failed, Active, or Abandoned.

**Checkpoint**: Checkout polling repeats only while the shown state is Waiting or Paid. E2E-P6.3-01 still fails.

- [ ] T025 [US1] On Active, call `request_ai_status_refresh` once from `frontend/lib/features/ai/billing/checkout_screen.dart` — `p_contract_version` `backendRpc`, FR-006, E2E-P6.3-01. Depends on T024 (same file). When `shown_state` is Active, call `request_ai_status_refresh` with `p_contract_version` set to `backendRpc` once. Do not modify `frontend/lib/core/contract_versions.dart`.

**Checkpoint**: Active triggers one `request_ai_status_refresh` call. E2E-P6.3-01 still fails until the page composes this screen.

### 4.10 User Story 2 - Any desktop can see an open checkout (Priority: P2) — resume

**Independent Test**: E2E-P6.3-02 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T026 [US2] Resume a listed checkout by `reference` in `frontend/lib/features/ai/billing/administrator_billing_page.dart` — open list, no tenant argument, FR-005, E2E-P6.3-02. Depends on T025. Create the file. It takes no tenant argument. It loads `GET /v1/checkouts?open=1` and, when a checkout is listed, shows that checkout by `reference` instead of starting another one. Another desktop resumes by `reference`.

**Checkpoint**: A second desktop can open a listed checkout by `reference`. E2E-P6.3-02 still fails until the route builds this page for that session.

### 4.11 User Story 3 - The administrator sees the term and the price before paying (Priority: P3) — ABO errors

**Independent Test**: E2E-P6.3-03, E2E-P6.3-04, and E2E-P6.3-05 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T027 [US3] Handle the five ABO errors and show the new price after `offer_unavailable` in `frontend/lib/features/ai/billing/checkout_screen.dart`, `frontend/lib/features/ai/billing/offers_screen.dart`, and `frontend/lib/features/ai/billing/billing_contact_form.dart` — 409, 503, and 429, FR-007, E2E-P6.3-04, E2E-P6.3-05. Depends on T026. `offer_unavailable` loads offers again and shows the new price before a launch. `terms_not_accepted` returns to the offers screen. `billing_contact_required` stays on the contact form. `provider_unavailable` is shown on the checkout screen; a later read of Abandoned is that shown state. `rate_limited` is shown on the checkout screen.

**Checkpoint**: E2E-P6.3-04 can show the new price before paying. The other four ABO errors stay on the screen the plan names.

### 4.12 User Story 4 - Staff have no billing entry, and an old app shows the update state (Priority: P4) — update state

**Independent Test**: E2E-P6.3-06 and E2E-P6.3-07 in harness H-FL on H-FS. Every earlier suite stays green (rule S2).

- [ ] T028 [US4] Show the app-update state when the ABO answers `contract_version_unsupported` in `frontend/lib/features/ai/billing/checkout_screen.dart` — inline `AiDegradedView`, no dialog, FR-009, E2E-P6.3-07. Depends on T027 (checkout screen). `contract_version_unsupported` shows `AiDegradedView` in the existing app-update mode ("Update the app to use AI"), inline, with no dialog.

**Checkpoint**: E2E-P6.3-07 can show the update state with no dialog.

### 4.13 User Story 3 - The administrator sees the term and the price before paying (Priority: P3) — failed retry

**Independent Test**: E2E-P6.3-03, E2E-P6.3-04, and E2E-P6.3-05 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T029 [US3] Keep Failed on the same checkout page so a later success shows Active in `frontend/lib/features/ai/billing/checkout_screen.dart` — decline then retry, FR-006, FR-007, E2E-P6.3-05. Depends on T028 (same file). Failed stays on this page. A later success on this page shows Active.

**Checkpoint**: E2E-P6.3-05 can move from Failed to Active on the same page.

### 4.14 User Story 4 - Staff have no billing entry, and an old app shows the update state (Priority: P4) — staff gate

**Independent Test**: E2E-P6.3-06 and E2E-P6.3-07 in harness H-FL on H-FS. Every earlier suite stays green (rule S2).

- [ ] T030 [US4] Keep the staff host free of a billing control and of a token mint in `frontend/lib/features/ai/host/ai_feature_host_page.dart` and `frontend/lib/features/ai/degraded/ai_degraded_view.dart` — no purchase control, no `issue_billing_token`, FR-008, E2E-P6.3-06. Depends on T029. The staff notice on `AiFeatureHostPage` stays the text with no purchase control. Staff still do not see `kAiDegradedRenewOrBuyKey`. Neither staff surface constructs `frontend/lib/features/ai/billing/billing_token_client.dart`.

**Checkpoint**: E2E-P6.3-06 sees no billing entry and no `issue_billing_token` call.

### 4.15 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — page composition

**Independent Test**: E2E-P6.3-01 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T031 [US1] Compose offers, contact, and checkout on `frontend/lib/features/ai/billing/administrator_billing_page.dart`, including the open-list resume — route page, FR-001, FR-005, FR-008, FR-009, E2E-P6.3-01, E2E-P6.3-02. Depends on T030. The route builds this page for an administrator. When `GET /v1/checkouts?open=1` lists a checkout, show that checkout by `reference` instead of starting another one. Otherwise sequence offers, then contact, then checkout. It takes no tenant argument. A staff session does not build it and does not construct the token client.

**Checkpoint**: The administrator route runs offers, contact, and checkout, and resumes a listed checkout by `reference`. E2E-P6.3-01 through E2E-P6.3-07 are ready for the harness.

---

## 5. Verification (H-FL)

**Purpose**: Sequencing step 32. The unit harness passes. This is not a repo-wide command.

### 5.1 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — H-FL harness

**Independent Test**: E2E-P6.3-01 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T032 [US1] Re-run the fullstack file until E2E-P6.3-01 through E2E-P6.3-07 pass — green harness, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, E2E-P6.3-01, E2E-P6.3-02, E2E-P6.3-03, E2E-P6.3-04, E2E-P6.3-05, E2E-P6.3-06, E2E-P6.3-07. Depends on T031. From `frontend/`, against the running H-FS stack, run `flutter test test/integration/administrator_billing_fullstack_test.dart --tags fullstack` until E2E-P6.3-01 through E2E-P6.3-07 pass. Fixes stay in the files this unit's **Files** table lists under `frontend/`. Do not run `npm test` in `e2e/fullstack`. Do not start wrangler. Do not edit `frontend/lib/core/contract_versions.dart`, `frontend/lib/features/ai/presentation/pages/ai_page.dart`, or `frontend/pubspec.yaml`.

**Checkpoint**: E2E-P6.3-01, E2E-P6.3-02, E2E-P6.3-03, E2E-P6.3-04, E2E-P6.3-05, E2E-P6.3-06, and E2E-P6.3-07 pass in H-FL.

---

## 6. Documentation

**Purpose**: Sequencing step 33. `quickstart.md` after the harness is green. Plan-phase `research.md`, `data-model.md`, and `contracts/` stay omitted.

### 6.1 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — quickstart

**Independent Test**: E2E-P6.3-01 in harness H-FL on H-FS, payment via the H-PAY fixture.

- [ ] T033 [US1] Write `specs/091-abo-p6-3-administrator-billing-offers-contact-checkout/quickstart.md` — unit quickstart, FR-001, FR-006, E2E-P6.3-01, E2E-P6.3-02, E2E-P6.3-03, E2E-P6.3-04, E2E-P6.3-05, E2E-P6.3-06, E2E-P6.3-07. Depends on T032. Fill only these sections: what was implemented and the files added or modified; the harness command for this unit's tests only, from `frontend/`, `flutter test test/integration/administrator_billing_fullstack_test.dart --tags fullstack`; the entry point → module chain per E2E id. Do not list earlier-unit files, combined counts, or full-suite commands. Manual steps are omitted: the harness sees this behaviour.

**Checkpoint**: `quickstart.md` names the seven H-FL ids, the unit command, and the entry chain.

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (Phase 3)**: T001 creates `frontend/test/integration/administrator_billing_fullstack_test.dart` with E2E-P6.3-01. T002 through T007 add E2E-P6.3-02 through E2E-P6.3-07 in that same file, in that id order. T008 runs the harness and confirms all seven fail before the billing screens exist.
- **Implementation (Phase 4)**: Starts after T008. English and Arabic strings, then generated localizations, then the billing path and router, then the host renew control and the degraded renew or buy control, then the billing-token client and the ABO client, then the offers screen and the contact form, then the checkout screen, the queued-term sentence, polling, and the Active refresh, then resume by `reference`, the five ABO errors, the update state, the Failed retry, the staff gate, and the page that sequences offers, contact, and checkout.
- **Verification (Phase 5)**: Starts after T031. One command from `frontend/`, as in T008, until the seven ids pass.
- **Documentation (Phase 6)**: Starts after T032 is green. One file: `quickstart.md`.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: The failing purchase test is T001. Strings, route, entry controls, token client, ABO client, offers, contact, checkout, polling, the Active refresh, and page composition are T009 through T022, T024, T025, and T031. E2E-P6.3-01 is included in the red run (T008) and the green harness (T032).
- **User Story 2 (P2)**: The failing resume test is T002, after T001. Resume by `reference` is T026, after checkout polling and the Active refresh. The page keeps that resume when T031 composes the route.
- **User Story 3 (P3)**: The failing tests are T003, T004, and T005, after T002. The queued-term sentence is T023, on the checkout screen from T022. The five ABO errors are T027. Failed staying on the same page is T029.
- **User Story 4 (P4)**: The failing tests are T006 and T007, after T005. The red run is T008. The update state is T028. The staff gate is T030, after the host and degraded controls from T013 and T014.

### 7.3 Within Each Phase

- T001 creates `frontend/test/integration/administrator_billing_fullstack_test.dart`. T002 through T007 write that same file. T008 runs the harness and does not edit that file.
- T009 writes `frontend/lib/l10n/app_en.arb`. T010 writes `frontend/lib/l10n/app_ar.arb`. T011 writes `frontend/lib/l10n/app_localizations.dart`, `frontend/lib/l10n/app_localizations_en.dart`, and `frontend/lib/l10n/app_localizations_ar.dart`. T012 writes `frontend/lib/app/app_routes.dart` and `frontend/lib/app/router.dart`. T013 writes `frontend/lib/features/ai/host/ai_feature_host_page.dart`. T014 writes `frontend/lib/features/ai/degraded/ai_degraded_view.dart`. T015 creates `frontend/lib/features/ai/billing/billing_token_client.dart`. T016 creates `frontend/lib/features/ai/billing/abo_client.dart`, and T017 through T019 write that same file. T020 creates `frontend/lib/features/ai/billing/offers_screen.dart`. T021 creates `frontend/lib/features/ai/billing/billing_contact_form.dart`. T022 creates `frontend/lib/features/ai/billing/checkout_screen.dart`, and T023 through T025, T027 through T029 write that same file. T026 creates `frontend/lib/features/ai/billing/administrator_billing_page.dart`. T027 also writes `frontend/lib/features/ai/billing/offers_screen.dart` and `frontend/lib/features/ai/billing/billing_contact_form.dart`. T030 writes `frontend/lib/features/ai/host/ai_feature_host_page.dart` and `frontend/lib/features/ai/degraded/ai_degraded_view.dart`. T031 writes `frontend/lib/features/ai/billing/administrator_billing_page.dart`.
- T032 runs after T031 and may edit only the `frontend/` files listed in this unit's **Files** table.
- T033 writes only `specs/091-abo-p6-3-administrator-billing-offers-contact-checkout/quickstart.md` after T032 is green.

---

## 8. Implementation Waves

### 8.1 Wave 1

- T001 [US1] — subphase: `### 3.1 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — tests` — paths: `frontend/test/integration/administrator_billing_fullstack_test.dart`

### 8.2 Wave 2

- T002 [US2] — subphase: `### 3.2 User Story 2 - Any desktop can see an open checkout (Priority: P2) — tests` — paths: `frontend/test/integration/administrator_billing_fullstack_test.dart`

### 8.3 Wave 3

- T003–T005 [US3] — subphase: `### 3.3 User Story 3 - The administrator sees the term and the price before paying (Priority: P3) — tests` — paths: `frontend/test/integration/administrator_billing_fullstack_test.dart`

### 8.4 Wave 4

- T006–T007 [US4] — subphase: `### 3.4 User Story 4 - Staff have no billing entry, and an old app shows the update state (Priority: P4) — tests` — paths: `frontend/test/integration/administrator_billing_fullstack_test.dart`

### 8.5 Wave 5

- T008 [US4] — subphase: `### 3.5 User Story 4 - Staff have no billing entry, and an old app shows the update state (Priority: P4) — red run` — paths: `frontend/test/integration/administrator_billing_fullstack_test.dart`

### 8.6 Wave 6

- T009–T011 [US1] — subphase: `### 4.1 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — strings` — paths: `frontend/lib/l10n/app_en.arb`, `frontend/lib/l10n/app_ar.arb`, `frontend/lib/l10n/app_localizations.dart`, `frontend/lib/l10n/app_localizations_en.dart`, `frontend/lib/l10n/app_localizations_ar.dart`

### 8.7 Wave 7

- T012 [US1] — subphase: `### 4.2 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — route` — paths: `frontend/lib/app/app_routes.dart`, `frontend/lib/app/router.dart`

### 8.8 Wave 8

- T013 [US1] — subphase: `### 4.3 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — host renew` — paths: `frontend/lib/features/ai/host/ai_feature_host_page.dart`
- T014 [US1] — subphase: `### 4.4 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — degraded renew or buy` — paths: `frontend/lib/features/ai/degraded/ai_degraded_view.dart`

### 8.9 Wave 9

- T015–T019 [US1] — subphase: `### 4.5 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — token and ABO client` — paths: `frontend/lib/features/ai/billing/billing_token_client.dart`, `frontend/lib/features/ai/billing/abo_client.dart`

### 8.10 Wave 10

- T020–T021 [US1] — subphase: `### 4.6 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — offers and contact` — paths: `frontend/lib/features/ai/billing/offers_screen.dart`, `frontend/lib/features/ai/billing/billing_contact_form.dart`

### 8.11 Wave 11

- T022 [US1] — subphase: `### 4.7 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — checkout screen` — paths: `frontend/lib/features/ai/billing/checkout_screen.dart`

### 8.12 Wave 12

- T023 [US3] — subphase: `### 4.8 User Story 3 - The administrator sees the term and the price before paying (Priority: P3) — queued term` — paths: `frontend/lib/features/ai/billing/checkout_screen.dart`

### 8.13 Wave 13

- T024–T025 [US1] — subphase: `### 4.9 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — poll and refresh` — paths: `frontend/lib/features/ai/billing/checkout_screen.dart`

### 8.14 Wave 14

- T026 [US2] — subphase: `### 4.10 User Story 2 - Any desktop can see an open checkout (Priority: P2) — resume` — paths: `frontend/lib/features/ai/billing/administrator_billing_page.dart`

### 8.15 Wave 15

- T027 [US3] — subphase: `### 4.11 User Story 3 - The administrator sees the term and the price before paying (Priority: P3) — ABO errors` — paths: `frontend/lib/features/ai/billing/checkout_screen.dart`, `frontend/lib/features/ai/billing/offers_screen.dart`, `frontend/lib/features/ai/billing/billing_contact_form.dart`

### 8.16 Wave 16

- T028 [US4] — subphase: `### 4.12 User Story 4 - Staff have no billing entry, and an old app shows the update state (Priority: P4) — update state` — paths: `frontend/lib/features/ai/billing/checkout_screen.dart`

### 8.17 Wave 17

- T029 [US3] — subphase: `### 4.13 User Story 3 - The administrator sees the term and the price before paying (Priority: P3) — failed retry` — paths: `frontend/lib/features/ai/billing/checkout_screen.dart`

### 8.18 Wave 18

- T030 [US4] — subphase: `### 4.14 User Story 4 - Staff have no billing entry, and an old app shows the update state (Priority: P4) — staff gate` — paths: `frontend/lib/features/ai/host/ai_feature_host_page.dart`, `frontend/lib/features/ai/degraded/ai_degraded_view.dart`

### 8.19 Wave 19

- T031 [US1] — subphase: `### 4.15 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — page composition` — paths: `frontend/lib/features/ai/billing/administrator_billing_page.dart`

### 8.20 Wave 20

- T032 [US1] — subphase: `### 5.1 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — H-FL harness` — paths: `frontend/lib/app/app_routes.dart`, `frontend/lib/app/router.dart`, `frontend/lib/features/ai/billing/billing_token_client.dart`, `frontend/lib/features/ai/billing/abo_client.dart`, `frontend/lib/features/ai/billing/offers_screen.dart`, `frontend/lib/features/ai/billing/billing_contact_form.dart`, `frontend/lib/features/ai/billing/checkout_screen.dart`, `frontend/lib/features/ai/billing/administrator_billing_page.dart`, `frontend/lib/features/ai/host/ai_feature_host_page.dart`, `frontend/lib/features/ai/degraded/ai_degraded_view.dart`, `frontend/lib/l10n/app_en.arb`, `frontend/lib/l10n/app_ar.arb`, `frontend/lib/l10n/app_localizations.dart`, `frontend/lib/l10n/app_localizations_en.dart`, `frontend/lib/l10n/app_localizations_ar.dart`, `frontend/test/integration/administrator_billing_fullstack_test.dart`

### 8.21 Wave 21

- T033 [US1] — subphase: `### 6.1 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1) — quickstart` — paths: `specs/091-abo-p6-3-administrator-billing-offers-contact-checkout/quickstart.md`
