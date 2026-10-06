# Tasks: Checkout creation, Paymob intention, coverage view and the cross-worker harness

**Input**: Design documents from `specs/077-abo-p4-2-checkout-paymob-intention/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P4.1 (ABO clinic API, records, H-ABO) and P3.3 (platform plan versions, paid grant, coverage methods the plan names). Plan artifacts from `AVAILABLE_DOCS`: `research.md`, `data-model.md`, `contracts/` (`contracts/checkout-api.md`, `contracts/provider-port.md`, `contracts/harness.md`). Those three plan artifacts are already written. They are not implement tasks. `research.md` already records the R-2 outcome (expiration 1800 s, `expires_at` = creation plus 30 minutes, checked on the H-PAY stub). `quickstart.md` is written in Documentation after verification.

**Organization**: Four user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`, `[US4]`). Tests are one task per E2E id, written to fail before the checkout routes, the Paymob adapter, and the coverage-view refresh exist. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase (the `abo/` Worker already exists). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 30. Size L is 32–40 (rule S3). The count is one task per E2E id (9), one task per Files unit that is not already one of those tests and was not written in the plan phase (8 harness files + 11 production files), the unit harness (1), and `quickstart.md` (1). It is not padded. `npm test` in other packages, and any command that runs more than `npm run test:cross-worker` and `npm run test:import-boundary` from `abo/`, are not tasks.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`, `US4`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — consumed through the real `VendorEntrypoint`. This unit does not change platform source
- **ABO**: `abo/` — the Files paths in `plan.md`
- **Shared package**: `packages/vendor-contracts/` — consumed and not modified
- **Spec Kit artifacts**: `specs/077-abo-p4-2-checkout-paymob-intention/`
- **CI**: `.github/workflows/ci.yml` — add jobs `abo-cross-worker` and `abo-import-boundary` only
- Do not edit `packages/vendor-contracts/**`, `backend/`, `frontend/`, or `ai-platform/src/**`. Do not edit `abo/vitest.workers.config.ts`, `abo/src/clinic-api/auth.ts`, `abo/src/clinic-api/version.ts`, `abo/src/clinic-api/rate.ts`, `abo/src/clinic-api/offers.ts`, `abo/src/clinic-api/billing-contact.ts`, `abo/src/records/append.ts`, `abo/src/alert/`, `abo/src/clock.ts`, or `abo/test/system/harness.ts`. Do not add notification intake, inquiry, HMAC, `paymob_txn`, sweeps, operator cancel, or a live Paymob test-account call.

---

## 3. Tests

**Purpose**: Sequencing step 1. Harness files the red tests import come first. Then one failing test per E2E id. E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-04, E2E-P4.2-05, E2E-P4.2-06, and E2E-P4.2-07 are added to `abo/test/system/checkout.cross-worker.test.ts`. E2E-P4.2-03 is added to `abo/test/system/checkout-throw.cross-worker.test.ts`. E2E-P4.2-08 is added to `abo/test/system/coverage-view.cross-worker.test.ts`. E2E-P4.2-09 is added to `abo/test/import-boundary/boundary.test.mjs`. Column lists, wire bodies, and harness routes that this file does not spell out are those in `data-model.md` and `contracts/`. No scenario sleeps more than 2 s (rule V4). Time moves with `setClock` through the consumed `clockNowMs`.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts
cd abo && npx vitest run --config vitest.platform-throw.config.ts
```

### 3.1 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — stubs and configs

**Independent Test**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06 in harnesses H-XW and H-PAY.

- [X] T001 [US1] Add the H-PAY stub in `abo/test/stubs/paymob/worker.ts` — produces the intention and auth-token endpoints, FR-001, FR-005, FR-009, E2E-P4.2-01, E2E-P4.2-05. Depends on nothing. Auxiliary worker scripted per test. `POST /v1/intention/` records the JSON body. An auth-token endpoint is present. Default mode returns the success body in `contracts/harness.md` so the adapter can store `intention_id`, the order id, and `client_secret`. Modes `refuse` and `timeout` match E2E-P4.2-05. The recorded body is what E2E-P4.2-01 reads for piastres, `special_reference`, and `expiration`.

- [X] T002 [US1] Add the platform-throw stub in `abo/test/stubs/platform-throw/worker.ts` — produces the forced `getCoverage` failure, FR-003, E2E-P4.2-03. Depends on nothing. Bound as `PLATFORM` with `entrypoint = "VendorEntrypoint"` by T005. `getCoverage` throws, except when the org id ends with `aa`, where the result is the consumed `transient` envelope whose detail is `unavailable`. Other entrypoint methods throw.

- [X] T003 [US1] Add `abo/test/system/cross-worker-harness.ts` — produces the H-XW helper, FR-002, FR-009, E2E-P4.2-02. Depends on nothing. Imports `mintBilling`, `setClock`, and the `SELF` fetch helpers from `abo/test/system/harness.ts` and does not modify that file. Billing host is the consumed `BILLING_HOST`. Binds the real ai-platform worker, built by T006, as `PLATFORM` with `entrypoint = "VendorEntrypoint"`. Bindings and routes that this task does not spell out are those in `contracts/harness.md`.

- [X] T004 [US1] Add `abo/vitest.cross-worker.config.ts` — produces the H-XW vitest config, FR-002, FR-009, E2E-P4.2-02, E2E-P4.2-08. Depends on T003. Separate from `abo/vitest.workers.config.ts`, so `test/system/**/*.system.test.ts` is not included. `wrangler.environment` is `development`. `TEST_CLOCK` is `"1"`. Includes `abo/test/system/checkout.cross-worker.test.ts` and `abo/test/system/coverage-view.cross-worker.test.ts`. The `PLATFORM` binding is the real auxiliary worker from T003 and `contracts/harness.md`. The Paymob binding is the T001 stub.

- [X] T005 [US1] Add `abo/vitest.platform-throw.config.ts` — produces the throw-config vitest file, FR-003, FR-009, E2E-P4.2-03. Depends on T002. Separate from `abo/vitest.workers.config.ts` and from T004. `TEST_CLOCK` is `"1"`. Includes only `abo/test/system/checkout-throw.cross-worker.test.ts`. `PLATFORM` is the T002 stub, not the real ai-platform worker.

### 3.2 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — build script

**Independent Test**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06 in harnesses H-XW and H-PAY.

- [X] T006 [US1] Add `abo/scripts/build-platform-for-hxw.mjs` — produces the platform build H-XW runs first, FR-002, FR-009, E2E-P4.2-02, E2E-P4.2-08. Depends on T004. Builds the ai-platform worker from source before the cross-worker vitest run. Does not modify `ai-platform/` source. T027 calls this script from `test:cross-worker`.

### 3.3 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — tests (part 1)

**Independent Test**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06 in harnesses H-XW and H-PAY.

- [X] T007 [US1] Add the failing test `E2E-P4.2-01 checkout 201 redirect_url CK reference expires_at +30 min` in `abo/test/system/checkout.cross-worker.test.ts` — red test, FR-001, E2E-P4.2-01. Depends on T001, T004, and T006. `SELF.fetch` `POST /v1/checkouts` on the billing host with `Abo-Contract-Version: 1` and `mintBilling` for an administrator who has a billing contact and the current terms. Body includes `client_request_id`, the current sellable `offer_id`, `offer_version`, and `terms_version`. Response is HTTP 201 with `redirect_url`, a `CK-` `reference`, and `expires_at` equal to the ABO clock plus 30 minutes. The H-PAY recorded body has the amount in piastres, `special_reference` equal to that reference, and `expiration` 1800. The stored checkout `billing_token_jti` equals the token `jti`. Advance time only with `setClock`. The command fails because the route is not the 201 above.

- [X] T008 [US1] Add the failing test `E2E-P4.2-02 active coverage starts after_current` in `abo/test/system/checkout.cross-worker.test.ts` — red test, FR-002, E2E-P4.2-02. Depends on T007 (same file). The clinic has active coverage on the real platform worker, set up as `contracts/harness.md` describes for `getCoverage`. `POST /v1/checkouts` returns `starts` `after_current` and `projected_start` equal to `coverage_through`. The command fails because `starts` is not `after_current`.

- [X] T009 [US1] Add the failing test `E2E-P4.2-03 throw and transient use coverage_view` in `abo/test/system/checkout-throw.cross-worker.test.ts` — red test, FR-003, E2E-P4.2-03. Depends on T005. Insert the `coverage_view` row in D1, then `POST /v1/checkouts` while `PLATFORM` throws. The checkout is still created and `coverage_source` is `view`. A second org whose id ends with `aa` gets `getCoverage` `transient` and the same `view` fallback. The minute cron is not this test. The command fails because `coverage_source` is not `view`.

- [X] T010 [US1] Add the failing test `E2E-P4.2-04 superseded offer missing contact stale terms` in `abo/test/system/checkout.cross-worker.test.ts` — red test, FR-004, E2E-P4.2-04. Depends on T008 (same file). A superseded `offer_version` is HTTP 409 `offer_unavailable` and the body includes `current_version`. No billing contact is `billing_contact_required`. A `terms_version` that is not current is `terms_not_accepted`. None of the three writes a checkout row. The command fails because those codes are not returned.

- [X] T011 [US1] Add the failing test `E2E-P4.2-05 provider refuse and timeout are Abandoned` in `abo/test/system/checkout.cross-worker.test.ts` — red test, FR-005, E2E-P4.2-05. Depends on T010 (same file). Script the H-PAY stub to `refuse`, then a second checkout to `timeout`. Each response is HTTP 503 `provider_unavailable`. Each stores a `checkout_event` of kind `open_failed`. The shown state is Abandoned. The command fails because the response is not 503 `provider_unavailable`.

**Checkpoint**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, and E2E-P4.2-05 exist and fail.

### 3.4 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — tests (part 2)

**Independent Test**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06 in harnesses H-XW and H-PAY.

- [X] T012 [US1] Add the failing test `E2E-P4.2-06 same client_request_id and the 11th checkout` in `abo/test/system/checkout.cross-worker.test.ts` — red test, FR-006, E2E-P4.2-06. Depends on T011 (same file). The same `client_request_id` returns the same `checkout_id`. The 11th distinct `client_request_id` in that clock hour is HTTP 429 `rate_limited`. Use `setClock` for the hour. Do not sleep. The command fails because the 11th id is not 429.

**Checkpoint**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06 exist and fail.

### 3.5 User Story 2 - Read one checkout and list open checkouts (Priority: P2) — tests

**Independent Test**: E2E-P4.2-07 in harnesses H-XW and H-PAY.

- [X] T013 [US2] Add the failing test `E2E-P4.2-07 other tenant 404 and two open checkouts listed` in `abo/test/system/checkout.cross-worker.test.ts` — red test, FR-007, E2E-P4.2-07. Depends on T012 (same file). `SELF.fetch` `GET /v1/checkouts/{id}` and `GET /v1/checkouts?open=1` on the billing host. Administrator B requesting A's checkout id gets HTTP 404 `not_found`. Tenant A with two open checkouts receives both from `?open=1`. The command fails because B's GET is not 404.

**Checkpoint**: E2E-P4.2-07 exists and fails.

### 3.6 User Story 3 - Copy platform coverage onto the minute cron (Priority: P3) — tests

**Independent Test**: E2E-P4.2-08 in harness H-XW.

- [X] T014 [US3] Add the failing test `E2E-P4.2-08 minute cron updates coverage_view and ignores an older pair` in `abo/test/system/coverage-view.cross-worker.test.ts` — red test, FR-008, E2E-P4.2-08. Depends on T004 and T006. `runScheduled` for cron `* * * * *` against the real `PLATFORM` `VendorEntrypoint`. After platform grant events (setup in `contracts/harness.md`), `coverage_view` is updated and `feed_cursor` holds the last `feed_seq`. The test then raises the stored `(binding_epoch, clinic_seq)` and resets `feed_cursor`. The next cron run does not replace the snapshot with the older pair. The command fails because `coverage_view` is unchanged.

**Checkpoint**: E2E-P4.2-08 exists and fails.

### 3.7 User Story 4 - Fail the import-boundary check on a domain import (Priority: P4) — tests

**Independent Test**: E2E-P4.2-09 on the import-boundary CI check. E2E-P4.2-01 through E2E-P4.2-08 still pass.

- [X] T015 [US4] Add the failing test `E2E-P4.2-09 domain import of the adapter fails the boundary check` in `abo/test/import-boundary/boundary.test.mjs` — red test, FR-009, E2E-P4.2-09. Depends on T006. Run with `node --test test/import-boundary/boundary.test.mjs` from `abo/`. The test runs `abo/scripts/check-import-boundary.mjs` on `abo/test/fixtures/import-boundary/bad` and expects exit 1. The title starts with `E2E-P4.2-09`. The command fails because the script is not present yet.

**Checkpoint**: E2E-P4.2-09 exists and fails.

### 3.8 User Story 4 - Fail the import-boundary check on a domain import (Priority: P4) — boundary script and fixture

**Independent Test**: E2E-P4.2-09 on the import-boundary CI check. E2E-P4.2-01 through E2E-P4.2-08 still pass.

- [X] T016 [US4] Add `abo/scripts/check-import-boundary.mjs` — produces the G6 check, FR-009, E2E-P4.2-09. Depends on T015. The argument is a tree root (`src` or the bad fixture). Exit 1 when any module other than `abo/src/provider/paymob/adapter.ts` imports `abo/src/provider/paymob/client.ts`, or when a module outside `abo/src/provider/` imports `abo/src/provider/paymob/adapter.ts`. Domain modules may import `abo/src/provider/port.ts` and `abo/src/provider/registry.ts`. The same rules apply to a fixture tree whose imports name those paymob paths.

- [X] T017 [US4] Add the bad fixture under `abo/test/fixtures/import-boundary/bad/src/` — produces the domain-imports-adapter tree, FR-009, E2E-P4.2-09. Depends on T016. One domain module imports the Paymob adapter path. It sits outside the worker bundle. `node scripts/check-import-boundary.mjs test/fixtures/import-boundary/bad` from `abo/` exits 1. T015 then passes on that fixture. E2E-P4.2-01 through E2E-P4.2-08 still fail.

**Checkpoint**: E2E-P4.2-09 fails the bad fixture. E2E-P4.2-01 through E2E-P4.2-08 still fail.

---

## 4. Implementation

**Purpose**: Sequencing steps 2–7. Each step starts after T007–T015 exist and those E2E tests fail (T015 passes once T016 and T017 exist). Within a subphase the tasks run in id order. `packages/vendor-contracts/**` and `ai-platform/src/**` stay unchanged. Checkout and `checkout_event` inserts go through the consumed `abo/src/records/append.ts` without modifying that file. The consumed per-token limit of 60 stays in `abo/src/clinic-api/rate.ts`.

### 4.1 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — migration

**Independent Test**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06 in harnesses H-XW and H-PAY.

- [X] T018 [US1] Add `abo/migrations/0002_checkout.sql` — produces the checkout and coverage tables, FR-001, FR-005, FR-008, E2E-P4.2-01, E2E-P4.2-05, E2E-P4.2-08. Depends on T017. Tables `checkout`, `checkout_event`, `checkout_status`, `paymob_intention`, `coverage_view`, and `feed_cursor`. Spec columns: checkout `checkout_id`, `reference`, `org_id`, `created_by_sub`, `client_request_id` unique per org, `offer_id`, `offer_version`, the FR-001 snapshot fields, `opened_with_coverage_through`, `coverage_source`, `provider_id`, `initiator`, `expires_at`, and `billing_token_jti`; `checkout_event` `checkout_id`, `kind`, `source`, `ref`, `actor`, `at`; `checkout_status` `checkout_id`, `state`, `last_event_at`; `paymob_intention` `checkout_id`, `intention_id`, `order_id`, `client_secret`, `special_reference`, `expires_at`; `coverage_view` `org_id`, `binding_epoch`, `clinic_seq`, `snapshot`; `feed_cursor` the last platform `feed_seq`. Keys, indexes, and append-only abort triggers for the append-only facts follow `data-model.md` and the trigger form in `abo/migrations/0001_records.sql`. The harness applies this file before the checkout tests.

### 4.2 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — provider port

**Independent Test**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06 in harnesses H-XW and H-PAY.

- [X] T019 [US1] Add `abo/src/provider/port.ts` — produces the provider port, FR-005, E2E-P4.2-05. Depends on T018. Declares `capabilities`, `createCheckout`, and `cancelCheckout`. Method shapes are those in `contracts/provider-port.md`. This file imports neither `client.ts` nor `adapter.ts`.

### 4.3 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — Paymob HTTP client

**Independent Test**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06 in harnesses H-XW and H-PAY.

- [X] T020 [US1] Add `abo/src/provider/paymob/client.ts` — produces the only provider HTTP module, FR-001, FR-009, E2E-P4.2-01. Depends on T018. `POST /v1/intention/` to `PAYMOB_BASE_URL` with `Authorization: Token <PAYMOB_SECRET_KEY>`. Body fields are those in `contracts/provider-port.md`, including amount in piastres, currency EGP, the card integration id, one item, `billing_data` from the payer, `special_reference`, `expiration` 1800, the notification URL, and `return_url`. When `TEST_CLOCK` is `"1"`, abort that call after 500 ms. This file is the only module that performs provider HTTP.

### 4.4 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — Paymob adapter

**Independent Test**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06 in harnesses H-XW and H-PAY.

- [ ] T021 [US1] Add `abo/src/provider/paymob/adapter.ts` — produces `createCheckout`, `capabilities`, and `cancelCheckout`, FR-001, FR-005, FR-009, E2E-P4.2-01, E2E-P4.2-05. Depends on T019 and T020. `createCheckout` calls the client, writes `paymob_intention`, and returns `redirect_url` for Unified Checkout with `PAYMOB_PUBLIC_KEY` and `client_secret` as `contracts/provider-port.md` describes. `return_url` carries `v` = `CHANNEL_VERSIONS.paymobReturn` (1). `cancelCheckout` returns `unsupported`. `capabilities` returns `{methods, cancel_checkout, refunds, mandates, payouts, pending_notifications}` with the values in `contracts/provider-port.md`. Only this file imports `client.ts`. The domain does not import this file.

### 4.5 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — provider registry

**Independent Test**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06 in harnesses H-XW and H-PAY.

- [ ] T022 [US1] Add `abo/src/provider/registry.ts` — produces adapter selection, FR-001, FR-005, E2E-P4.2-01. Depends on T021. Selects the Paymob adapter by `provider_id`. The id string is the one in `data-model.md` and `contracts/provider-port.md`. Callers outside `abo/src/provider/` use this module and `port.ts`, not the adapter.

### 4.6 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — checkout handlers

**Independent Test**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06 in harnesses H-XW and H-PAY.

- [ ] T023 [US1] Add `abo/src/clinic-api/checkouts.ts` — produces create and read handlers, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, E2E-P4.2-06, E2E-P4.2-07. Depends on T018 and T022. Do not edit `abo/src/worker.ts` in this task. `POST /v1/checkouts` takes `client_request_id`, `offer_id`, `offer_version`, and `terms_version`. Require a billing contact and the current terms version, read through the consumed offers and billing-contact modules without modifying those files. A superseded `offer_version` is HTTP 409 `offer_unavailable` with `current_version`. No contact is `billing_contact_required`. A stale `terms_version` is `terms_not_accepted`. Those three write no checkout. On success, store the FR-001 snapshot, `initiator` `payer`, `provider_id`, and `billing_token_jti` from `BillingClaims.jti`. `expires_at` is `clockNowMs` plus 30 minutes. Reference uses consumed `humanRef` and starts with `CK-`. The same `client_request_id` for the token `org` returns the stored checkout and does not call the provider again. The 11th distinct `client_request_id` in the clock hour is HTTP 429 `rate_limited` and writes nothing. `starts` comes from live `PLATFORM.getCoverage`. Active coverage sets `starts` `after_current`, `projected_start` and `opened_with_coverage_through` to `coverage_through`, and `coverage_source` `live`. If `getCoverage` throws, fails, or answers `transient`, still create the checkout, read `opened_with_coverage_through` from `coverage_view`, and set `coverage_source` `view`. Provider refusal or timeout stores state `open_failed`, a `checkout_event` kind `open_failed` with source `system`, responds HTTP 503 `provider_unavailable`, and the shown state is Abandoned. Success stores state `open`, a `checkout_event` kind `opened` with source `system`, and the shown state Waiting, and responds HTTP 201 with `checkout_id`, `reference`, `redirect_url`, `expires_at`, and `starts` (`projected_start` when `after_current`). `GET /v1/checkouts/{id}` returns `reference`, the shown state, an offer summary, `payment_reference`, `term_ref`, and `updated_at` as `contracts/checkout-api.md` describes. Shown state at this stage is Waiting or Abandoned. `GET /v1/checkouts?open=1` lists this tenant's open checkouts. The tenant is the token `org` only. Another tenant's id is HTTP 404 `not_found`. A new checkout leaves an existing open checkout payable. Responses use `clinicJsonResponse` and `clinicErrorResponse`. The body does not include `intention_id`, the Paymob order id, or `client_secret`. T025 connects these handlers from `fetch`.

### 4.7 User Story 3 - Copy platform coverage onto the minute cron (Priority: P3) — coverage view

**Independent Test**: E2E-P4.2-08 in harness H-XW.

- [ ] T024 [US3] Add `abo/src/coverage/view.ts` — produces `refreshCoverageView`, FR-003, FR-008, E2E-P4.2-08. Depends on T018. Do not edit `abo/src/worker.ts` in this task. Call `PLATFORM.readCoverageEvents`. Update `coverage_view` (`org_id`, `binding_epoch`, `clinic_seq`, `snapshot`) and set `feed_cursor` to the last `feed_seq` read. Replace the stored snapshot only when `(binding_epoch, clinic_seq)` is greater than the stored pair. An older pair is ignored. A higher `binding_epoch` wins when `clinic_seq` restarts at 1. Snapshot checks use consumed `validateCoverageSnapshot` and `validateFeedEvent`. T025 calls `refreshCoverageView` from the minute cron.

### 4.8 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — worker dispatch

**Independent Test**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06 in harnesses H-XW and H-PAY.

- [ ] T025 [US1] Dispatch checkout routes and the minute coverage refresh in `abo/src/worker.ts` — produces the live entry chains, FR-001, FR-002, FR-007, FR-008, E2E-P4.2-01, E2E-P4.2-07, E2E-P4.2-08. Depends on T023 and T024. Keep the consumed host, version, auth, and per-token rate gates. On the billing host, after those gates, dispatch `POST /v1/checkouts`, `GET /v1/checkouts/{id}`, and `GET /v1/checkouts?open=1` to `checkouts.ts`. On the minute cron `* * * * *`, keep export, heartbeat, and alerts, and call `refreshCoverageView`. A throw from the platform feed is caught so those consumed minute steps still run.

### 4.9 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — wrangler bindings

**Independent Test**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06 in harnesses H-XW and H-PAY.

- [ ] T026 [US1] Bind Paymob and `PLATFORM` in `abo/wrangler.toml` — produces the runtime bindings, FR-001, FR-002, E2E-P4.2-01, E2E-P4.2-02. Depends on T025. On `development`, `staging`, and `production`, add `PAYMOB_BASE_URL`, `PAYMOB_SECRET_KEY`, `PAYMOB_PUBLIC_KEY`, and `PAYMOB_CARD_INTEGRATION_ID`, plus a `PLATFORM` service binding with `entrypoint = "VendorEntrypoint"` to `ai-platform-gateway-development`, `ai-platform-gateway-staging`, and `ai-platform-gateway-production` respectively. Add no `TEST_CLOCK` var.

### 4.10 User Story 4 - Fail the import-boundary check on a domain import (Priority: P4) — package scripts

**Independent Test**: E2E-P4.2-09 on the import-boundary CI check. E2E-P4.2-01 through E2E-P4.2-08 still pass.

- [ ] T027 [US4] Add the harness scripts in `abo/package.json` — produces the two unit commands, FR-009, E2E-P4.2-09. Depends on T006, T016, and T025. `test:cross-worker` runs `node scripts/build-platform-for-hxw.mjs`, then `vitest run --config vitest.cross-worker.config.ts`, then `vitest run --config vitest.platform-throw.config.ts`. `test:import-boundary` runs `node scripts/check-import-boundary.mjs src` and `node --test test/import-boundary/boundary.test.mjs`. Leave the existing `test` script unchanged.

### 4.11 User Story 4 - Fail the import-boundary check on a domain import (Priority: P4) — CI jobs

**Independent Test**: E2E-P4.2-09 on the import-boundary CI check. E2E-P4.2-01 through E2E-P4.2-08 still pass.

- [ ] T028 [US4] Add jobs `abo-cross-worker` and `abo-import-boundary` to `.github/workflows/ci.yml` — produces the two CI jobs, FR-009, E2E-P4.2-09. Depends on T027. `abo-cross-worker` runs `npm ci` in `abo/` and in `ai-platform/`, then `npm run test:cross-worker` from `abo/`. `abo-import-boundary` runs `npm run test:import-boundary` from `abo/`. Leave the existing jobs in that file unchanged.

---

## 5. Verification

**Purpose**: Sequencing step 8, before `quickstart.md`. The harness is these two commands from `abo/`. A repository-root `npm test`, and `npm test` in any other package, are not tasks.

### 5.1 Unit harness

**Independent Test**: E2E-P4.2-09 on the import-boundary CI check. E2E-P4.2-01 through E2E-P4.2-08 still pass.

- [ ] T029 [US4] Run `npm run test:cross-worker` and `npm run test:import-boundary` from `abo/` until E2E-P4.2-01 through E2E-P4.2-09 pass — produces the green unit harness, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, E2E-P4.2-06, E2E-P4.2-07, E2E-P4.2-08, E2E-P4.2-09. Depends on T026 and T028 (and therefore on T001–T025 and T027). This task may edit only files under `abo/test/`. `packages/vendor-contracts/**` and `ai-platform/src/**` stay unchanged.

```bash
cd abo && npm run test:cross-worker
cd abo && npm run test:import-boundary
```

**Checkpoint**: E2E-P4.2-01 through E2E-P4.2-09 pass.

---

## 6. Documentation

**Purpose**: Sequencing step 8, after the harness is green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md`, `data-model.md`, or `contracts/` task.

### 6.1 Quickstart

- [ ] T030 Create `specs/077-abo-p4-2-checkout-paymob-intention/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, E2E-P4.2-06, E2E-P4.2-07, E2E-P4.2-08, E2E-P4.2-09. Depends on T029. Sections: (1) what was implemented, and the files added or modified; (2) the two harness commands below; (3) the entry point → module chain per E2E id below. No earlier-unit files, combined counts, or full-suite commands. No manual steps.

```bash
cd abo && npm run test:cross-worker
cd abo && npm run test:import-boundary
```

| ID | Chain |
| --- | --- |
| E2E-P4.2-01 | `worker.ts` → `checkouts.ts` → `registry.ts` → `adapter.ts` → `client.ts` → H-PAY |
| E2E-P4.2-02 | That chain, plus `PLATFORM.getCoverage` |
| E2E-P4.2-03 | `checkouts.ts` reads `coverage_view` after the throw or `transient` result |
| E2E-P4.2-04 | `worker.ts` → `checkouts.ts` → `registry.ts` → `adapter.ts` → `client.ts` → H-PAY |
| E2E-P4.2-05 | `worker.ts` → `checkouts.ts` → `registry.ts` → `adapter.ts` → `client.ts` → H-PAY |
| E2E-P4.2-06 | `worker.ts` → `checkouts.ts` → `registry.ts` → `adapter.ts` → `client.ts` → H-PAY |
| E2E-P4.2-07 | `worker.ts` → `checkouts.ts` read paths |
| E2E-P4.2-08 | `worker.ts` `scheduled` → `coverage/view.ts` → `PLATFORM.readCoverageEvents` |
| E2E-P4.2-09 | `check-import-boundary.mjs` on the fixture tree |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (Phase 3)**: No production checkout module exists yet. T001, T002, and T003 touch different new files and are ordered T001 then T002 then T003 inside that subphase. T004 follows T003. T005 follows T002. T006 follows T004. T007 through T013 stay in id order in `abo/test/system/checkout.cross-worker.test.ts`, with T009 in `abo/test/system/checkout-throw.cross-worker.test.ts` after T005 and before T010. T014 writes `abo/test/system/coverage-view.cross-worker.test.ts` after T004 and T006. T015 writes `abo/test/import-boundary/boundary.test.mjs` before T016 and T017.
- **Implementation (Phase 4)**: Starts after T017, with E2E-P4.2-01 through E2E-P4.2-08 failing and E2E-P4.2-09 failing the bad fixture. Migration, then the port and the Paymob client (different files, both before the adapter), then the adapter, then the registry, then checkout handlers, then `refreshCoverageView`, then `worker.ts` dispatch, then wrangler bindings and `package.json` scripts (different files, both before CI), then the CI jobs.
- **Verification (Phase 5)**: Depends on T026 and T028. Runs only the two commands in §5.1.
- **Documentation (Phase 6)**: Depends on T029 being green.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: Tests T007, T008, T009, T010, T011, and T012, after the stubs, configs, and build script. Implementation T018 through T023, T025, and T026. E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06.
- **User Story 2 (P2)**: Test T013 after T012, because it writes the same checkout test file. The GET handlers are T023 in `abo/src/clinic-api/checkouts.ts`, and T025 connects them from `fetch`. E2E-P4.2-07.
- **User Story 3 (P3)**: Test T014 after T006. Implementation T024 writes `abo/src/coverage/view.ts` and does not write `abo/src/worker.ts`. T025 calls `refreshCoverageView` from the minute cron after T024. E2E-P4.2-08.
- **User Story 4 (P4)**: Test T015, then T016 and T017. Implementation T027 and T028 after the checkout path exists so `test:cross-worker` has a worker to run. E2E-P4.2-09, with E2E-P4.2-01 through E2E-P4.2-08 still passing once T029 is green.

### 7.3 Within Each Phase

- T001 writes `abo/test/stubs/paymob/worker.ts`. T002 writes `abo/test/stubs/platform-throw/worker.ts`. T003 writes `abo/test/system/cross-worker-harness.ts`. T004 writes `abo/vitest.cross-worker.config.ts` after T003. T005 writes `abo/vitest.platform-throw.config.ts` after T002.
- T006 writes `abo/scripts/build-platform-for-hxw.mjs` after T004.
- T007, T008, T010, T011, T012, and T013 all write `abo/test/system/checkout.cross-worker.test.ts`, in that id order. T009 writes `abo/test/system/checkout-throw.cross-worker.test.ts`.
- T014 writes `abo/test/system/coverage-view.cross-worker.test.ts`. T015 writes `abo/test/import-boundary/boundary.test.mjs`. T016 writes `abo/scripts/check-import-boundary.mjs`. T017 writes `abo/test/fixtures/import-boundary/bad/src/`.
- T018 writes `abo/migrations/0002_checkout.sql` before T019, T020, T023, and T024.
- T019 writes `abo/src/provider/port.ts`. T020 writes `abo/src/provider/paymob/client.ts`. Both follow T018 and both finish before T021. T021 writes `abo/src/provider/paymob/adapter.ts`. T022 writes `abo/src/provider/registry.ts` after T021.
- T023 writes `abo/src/clinic-api/checkouts.ts` and does not write `abo/src/worker.ts`. T024 writes `abo/src/coverage/view.ts` and does not write `abo/src/worker.ts`. T025 writes `abo/src/worker.ts` after T023 and T024.
- T026 writes only `abo/wrangler.toml` after T025. T027 writes only `abo/package.json` after T006, T016, and T025. T028 writes only `.github/workflows/ci.yml` after T027.
- T029 runs after T026 and T028 and may edit only `abo/test/`.
- T030 writes only `specs/077-abo-p4-2-checkout-paymob-intention/quickstart.md` after T029 is green.

---

## 8. Implementation Waves

### 8.1 Wave 1

- T001–T005 [US1] — subphase: `### 3.1 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — stubs and configs` — paths: `abo/test/stubs/paymob/worker.ts`, `abo/test/stubs/platform-throw/worker.ts`, `abo/test/system/cross-worker-harness.ts`, `abo/vitest.cross-worker.config.ts`, `abo/vitest.platform-throw.config.ts`

### 8.2 Wave 2

- T006 [US1] — subphase: `### 3.2 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — build script` — paths: `abo/scripts/build-platform-for-hxw.mjs`

### 8.3 Wave 3

- T007–T011 [US1] — subphase: `### 3.3 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — tests (part 1)` — paths: `abo/test/system/checkout.cross-worker.test.ts`, `abo/test/system/checkout-throw.cross-worker.test.ts`

### 8.4 Wave 4

- T012 [US1] — subphase: `### 3.4 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — tests (part 2)` — paths: `abo/test/system/checkout.cross-worker.test.ts`

### 8.5 Wave 5

- T013 [US2] — subphase: `### 3.5 User Story 2 - Read one checkout and list open checkouts (Priority: P2) — tests` — paths: `abo/test/system/checkout.cross-worker.test.ts`

### 8.6 Wave 6

- T014 [US3] — subphase: `### 3.6 User Story 3 - Copy platform coverage onto the minute cron (Priority: P3) — tests` — paths: `abo/test/system/coverage-view.cross-worker.test.ts`

### 8.7 Wave 7

- T015 [US4] — subphase: `### 3.7 User Story 4 - Fail the import-boundary check on a domain import (Priority: P4) — tests` — paths: `abo/test/import-boundary/boundary.test.mjs`

### 8.8 Wave 8

- T016–T017 [US4] — subphase: `### 3.8 User Story 4 - Fail the import-boundary check on a domain import (Priority: P4) — boundary script and fixture` — paths: `abo/scripts/check-import-boundary.mjs`, `abo/test/fixtures/import-boundary/bad/src/`

### 8.9 Wave 9

- T018 [US1] — subphase: `### 4.1 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — migration` — paths: `abo/migrations/0002_checkout.sql`

### 8.10 Wave 10

- T019 [US1] — subphase: `### 4.2 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — provider port` — paths: `abo/src/provider/port.ts`
- T020 [US1] — subphase: `### 4.3 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — Paymob HTTP client` — paths: `abo/src/provider/paymob/client.ts`

### 8.11 Wave 11

- T021 [US1] — subphase: `### 4.4 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — Paymob adapter` — paths: `abo/src/provider/paymob/adapter.ts`

### 8.12 Wave 12

- T022 [US1] — subphase: `### 4.5 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — provider registry` — paths: `abo/src/provider/registry.ts`

### 8.13 Wave 13

- T023 [US1] — subphase: `### 4.6 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — checkout handlers` — paths: `abo/src/clinic-api/checkouts.ts`

### 8.14 Wave 14

- T024 [US3] — subphase: `### 4.7 User Story 3 - Copy platform coverage onto the minute cron (Priority: P3) — coverage view` — paths: `abo/src/coverage/view.ts`

### 8.15 Wave 15

- T025 [US1] — subphase: `### 4.8 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — worker dispatch` — paths: `abo/src/worker.ts`

### 8.16 Wave 16

- T026 [US1] — subphase: `### 4.9 User Story 1 - Open a checkout and a Paymob intention (Priority: P1) — wrangler bindings` — paths: `abo/wrangler.toml`
- T027 [US4] — subphase: `### 4.10 User Story 4 - Fail the import-boundary check on a domain import (Priority: P4) — package scripts` — paths: `abo/package.json`

### 8.17 Wave 17

- T028 [US4] — subphase: `### 4.11 User Story 4 - Fail the import-boundary check on a domain import (Priority: P4) — CI jobs` — paths: `.github/workflows/ci.yml`

### 8.18 Wave 18

- T029 [US4] — subphase: `### 5.1 Unit harness` — paths: `abo/test/`

### 8.19 Wave 19

- T030 — subphase: `### 6.1 Quickstart` — paths: `specs/077-abo-p4-2-checkout-paymob-intention/quickstart.md`
