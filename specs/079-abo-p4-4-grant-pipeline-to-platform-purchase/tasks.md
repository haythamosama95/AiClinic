# Tasks: Grant pipeline to the platform: purchase to AI on

**Input**: Design documents from `specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P3.4 (admission answer: reservation, `term_id`, snapshot, band; clinic denial codes of 04 §4.2; CP-B) and P4.3 (the unit row states no Outputs / freezes line; the open `grant` work row). Plan artifacts from `AVAILABLE_DOCS`: `data-model.md`, `contracts/`. Those plan artifacts are already written. They are not implement tasks. `research.md` is not a task: Spikes is none, so the plan phase did not write it. `quickstart.md` is written in Documentation after verification.

**Organization**: Three user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`). Tests are one task per E2E id, written to fail before `abo/src/work/grant.ts` and `abo/src/clinic-api/billing-reads.ts` exist. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase (the `abo/` Worker already exists). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 20. Size M is 20–32 (rule S3). The count is one task per E2E id (9), one task per Files unit that is not already one of those tests and was not written in the plan phase (the vitest config + 8 production files), the unit harness (1), and `quickstart.md` (1). It is not padded. A repository-root `npm test`, and any command other than the harness command in §5.1, are not tasks.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — this unit calls `VendorEntrypoint.grant`, `VendorEntrypoint.listServiceKeys`, and `POST /v1/requests`. It does not modify `ai-platform/`
- **ABO**: `abo/` — the Files paths in `plan.md`
- **Shared package**: `packages/vendor-contracts/` — consumed (`grantIdPaid`, `subscriptionRef`, `canonicalize`, `sha256Hex`, `signCompactJws`, `verifyCompactJws`, `CHANNEL_VERSIONS`) and not modified
- **Spec Kit artifacts**: `specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/`
- Do not edit `abo/src/work/runner.ts`. Confirm, the lease take, the 50-row confirm query, and the `grant` work-row insert stay as they are. Do not edit `data-model.md` or `contracts/subscription-payments.md`. No `TEST_CLOCK` var is added to production or staging. No production fault binding is added.

---

## 3. Tests

**Purpose**: Sequencing step 1. The vitest include and bindings come first. Then one failing test per E2E id, all in `abo/test/system/grant.cross-worker.test.ts`. There is no tenth E2E id. Shared setup uses the existing H-XW helpers (`setupCrossWorkerHarness`, `billingFetch`, `mintBilling`, `pinIssuer`, `scriptPaymobStub`, `setClock`, `runScheduled`, `platformCall`, `setD1BatchThrows`). No scenario sleeps more than 2 s (rule V4). Time moves with `setClock` through the consumed `clockNowMs`.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/grant.cross-worker.test.ts
```

### 3.1 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — cross-worker bindings

**Independent Test**: E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, and E2E-P4.4-04 in harnesses H-XW and H-PAY.

- [X] T001 [US1] Add the grant test include and ABO key bindings in `abo/vitest.cross-worker.config.ts` — produces the H-XW grant bindings, FR-001, FR-007, E2E-P4.4-01, E2E-P4.4-07. Depends on nothing. Add `test/system/grant.cross-worker.test.ts` to `test.include`. Set a fixed test `ABO_GRANT_KEY` JSON `{kid, pkcs8, public_key}` with `pkcs8` and `public_key` base64url, the same shape as that config's `PLATFORM_SIGNING_KEY`. Set `PLATFORM_PUBLIC_KEYS` to a two-element JSON array of `{kid, public_key}`. The second element is the public key already in `PLATFORM_SIGNING_KEY` (`kid` `platform-test`). The first element is a different kid. Add a service binding `PLATFORM_HTTP` to the same auxiliary worker `platform` with no entrypoint, so a test can `fetch` `POST /v1/requests`. `PLATFORM` stays `entrypoint = "VendorEntrypoint"`. Do not add `TEST_CLOCK` to `abo/wrangler.toml` in this task.

**Checkpoint**: The include, `ABO_GRANT_KEY`, `PLATFORM_PUBLIC_KEYS`, and `PLATFORM_HTTP` exist. `abo/test/system/grant.cross-worker.test.ts` does not exist yet.

### 3.2 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — tests

**Independent Test**: E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, and E2E-P4.4-04 in harnesses H-XW and H-PAY.

- [X] T002 [US1] Add the failing test `E2E-P4.4-01 paid grant activates the term and completes an issuer request` in `abo/test/system/grant.cross-worker.test.ts` — red test, FR-001, E2E-P4.4-01. Depends on T001. Create the file and the shared setup: register `env.ABO_GRANT_KEY.public_key` on `PLATFORM_DB.service_key` (`status` `active`, validity wide enough for the test clock); publish platform `plan_version` `plan-pro` / `1` with `max_allowance_per_month` at least 100 and `status` `published` (the ceiling migration already sets `max_paid_grace_days` 7 and `paid_cap_rule` `proportional`); seed published offer versions with `term_count` 3 and 12 beside the fixture's 1-month offer, same plan, `allowance_credits` 100, `grace_days` 7, `grace_cap_rule` `proportional`; insert `issuer_key` for the minted issuer (`kid`, `issuer` = `ISSUER_ID`, `public_key`, `status` `active`); publish and promote a routing policy through `PLATFORM.publishRoutingPolicy` and `PLATFORM.promoteRoutingPolicy` (class H, access JWT from `mintVendorAccessJwt`) aimed at the platform fake provider. Entry: `SELF.fetch` `POST /v1/checkouts` and `POST /notify/paymob`; grant on inline `waitUntil` and `runScheduled` for cron `* * * * *`; `PLATFORM.grant`; `PLATFORM_HTTP.fetch` `POST /v1/requests` with the visit-summary invoke body that policy admits (`capability_id`, `capability_version`, `user_intent`, `context`); `GET /v1/checkouts/{id}` and `GET /v1/payments`. For term counts 1, 3, and 12: the platform term is active with full allowance; the issuer request completes (HTTP 200); checkout `shown_state` is Active; the payment is listed. Advance time only with `setClock`. The command fails because the grant module and the clinic reads are absent.

- [X] T003 [US1] Add the failing test `E2E-P4.4-02 transient for 4 days then applied starts at activation` in `abo/test/system/grant.cross-worker.test.ts` — red test, FR-002, E2E-P4.4-02. Depends on T002 (same file). Grant step on inline `waitUntil` and `runScheduled` for crons `* * * * *` and `0 * * * *`. Binding `held_for_transfer` makes frozen `grant` return `transient` (`transfer_pending`) for 4 days of test clock. Retries stay at or under 15 minutes. AL-04 repeats hourly. Then the binding is `active` and the result is `applied`. Term `starts_at` is the activation clock, not `paid_at`. Use `setClock`. Do not sleep. The command fails because the row does not retry under that cap or the term does not start at activation.

- [X] T004 [US1] Add the failing test `E2E-P4.4-03 rejected parks the grant row and raises AL-07` in `abo/test/system/grant.cross-worker.test.ts` — red test, FR-003, E2E-P4.4-03. Depends on T003 (same file). Grant step on inline `waitUntil` or `runScheduled` for cron `* * * * *`. The plan version is retired on the platform while the ABO kid stays `active`, so `grant` returns `rejected`. The work row is `parked`, AL-07 fires, and a later minute run does not take the row. The command fails because the row is retried or AL-07 does not fire.

- [X] T005 [US1] Add the failing test `E2E-P4.4-04 lost outcome retries as already_applied with one term` in `abo/test/system/grant.cross-worker.test.ts` — red test, FR-004, E2E-P4.4-04. Depends on T004 (same file). `setD1BatchThrows` after confirm has stored the payment, so the outcome batch throws after `grant` returns. No `grant_outcome` is written. The retry is `already_applied` with the same receipt. One term exists. The command fails because a second term is created or the retry is not `already_applied`.

**Checkpoint**: E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, and E2E-P4.4-04 exist and fail.

### 3.3 User Story 2 - Pause grants until the ABO key is active, and accept a rotated platform receipt key (Priority: P2) — tests

**Independent Test**: E2E-P4.4-06 and E2E-P4.4-07 in harnesses H-XW and H-PAY.

- [ ] T006 [US2] Add the failing test `E2E-P4.4-06 unregistered ABO kid pauses grant work and raises AL-23` in `abo/test/system/grant.cross-worker.test.ts` — red test, FR-006, E2E-P4.4-06. Depends on T005 (same file). Do not register `env.ABO_GRANT_KEY.public_key` on `service_key` before the resume step. `PLATFORM.listServiceKeys` runs at isolate start when `signing_key_gate` has no row, and on `runScheduled` for cron `0 * * * *`. The grant row stays `open` (not `parked`) and AL-23 fires. After the `service_key` insert and the hourly check, grant work runs. The command fails because the row is parked or grant work does not resume.

- [ ] T007 [US2] Add the failing test `E2E-P4.4-07 second configured platform kid receipts still verify` in `abo/test/system/grant.cross-worker.test.ts` — red test, FR-007, E2E-P4.4-07. Depends on T006 (same file). The receipt `kid` is the second configured platform kid (`platform-test`). `grant_outcome` is stored. A later grant still runs. The command fails because the receipt is rejected or the later grant does not run.

**Checkpoint**: E2E-P4.4-06 and E2E-P4.4-07 exist and fail. E2E-P4.4-01 through E2E-P4.4-04 still fail.

### 3.4 User Story 3 - Read subscription, payments, and Active without polling (Priority: P3) — tests

**Independent Test**: E2E-P4.4-05, E2E-P4.4-08, and E2E-P4.4-09 in harnesses H-XW and H-PAY. Earlier H-ABO, H-PAY, and H-XW suites stay green, and E2E-P4.4-01 through E2E-P4.4-04, E2E-P4.4-06, and E2E-P4.4-07 still pass.

- [ ] T008 [US3] Add the failing test `E2E-P4.4-05 second payment queues a term and subscription shows duplicate_payment` in `abo/test/system/grant.cross-worker.test.ts` — red test, FR-005, E2E-P4.4-05. Depends on T007 (same file). Open both checkouts before either payment so they share `opened_with_coverage_through`. Two paid grants via `PLATFORM.grant`. `SELF.fetch` `GET /v1/subscription` on the ABO worker `fetch`, billing hostname. The second term is queued (`snapshot.queued_count` > 0). `notices` includes `duplicate_payment`. The command fails because the second term is not queued or `duplicate_payment` is absent.

- [ ] T009 [US3] Add the failing test `E2E-P4.4-08 no clinic GET after create still shows Active on open checkouts` in `abo/test/system/grant.cross-worker.test.ts` — red test, FR-008, E2E-P4.4-08. Depends on T008 (same file). `SELF.fetch` `POST /v1/checkouts` and `POST /notify/paymob`, then the grant step, with no clinic GET until `SELF.fetch` `GET /v1/checkouts?open=1` on the billing hostname. The clinic is provisioned. `?open=1` shows Active. The command fails because the checkout is not Active.

- [ ] T010 [US3] Add the failing test `E2E-P4.4-09 payment cursor pages stay inside the tenant` in `abo/test/system/grant.cross-worker.test.ts` — red test, FR-009, E2E-P4.4-09. Depends on T009 (same file). Seed 21 `payment` rows for tenant A and one for tenant B. Do not run 21 grants. `SELF.fetch` `GET /v1/payments` with tenant A and tenant B billing tokens. A's first page has `has_more`, and `next_cursor` is that page's last `reference`. The next page follows. B's token lists none of A's payments. A `cursor` that is not A's `reference` is `invalid_request` inside this same test. The command fails because the pages do not advance or B sees A's payments.

**Checkpoint**: E2E-P4.4-05, E2E-P4.4-08, and E2E-P4.4-09 exist and fail. E2E-P4.4-01 through E2E-P4.4-04, E2E-P4.4-06, and E2E-P4.4-07 still fail.

---

## 4. Implementation

**Purpose**: Sequencing steps 2 and 3. Each step starts after T002–T010 exist and those E2E tests fail. Within a subphase the tasks run in id order. `abo/src/work/runner.ts` and `ai-platform/` stay unchanged. This unit does not change `grant`, `listServiceKeys`, or the P4.3 confirm step.

### 4.1 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — migration

**Independent Test**: E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, and E2E-P4.4-04 in harnesses H-XW and H-PAY.

- [ ] T011 [US1] Add `abo/migrations/0004_grant.sql` — produces `grant_request`, `grant_outcome`, `reversal`, and `signing_key_gate`, FR-005, FR-006, FR-009, FR-010, E2E-P4.4-01. Depends on T010. Tables, columns, and constraints are those already written in `data-model.md`. `grant_request` and `grant_outcome` are append-only (abort updates and deletes, same trigger form as `abo/migrations/0001_records.sql`). Spec columns for those two tables are the Key Entities in `spec.md`. One `grant_request` per payment whose disposition is `grant`. `reversal` is created for reads; this unit inserts none. `signing_key_gate` is the pause row FR-006 reads. Do not rewrite `data-model.md`. The harness applies this file before the grant tests.

### 4.2 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — alerts

**Independent Test**: E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, and E2E-P4.4-04 in harnesses H-XW and H-PAY.

- [ ] T012 [US1] Extend alert codes in `abo/src/alert/index.ts` — produces AL-04, AL-07, and AL-23, FR-002, FR-003, FR-006, E2E-P4.4-02, E2E-P4.4-03, E2E-P4.4-06. Depends on T010. Extend `AlertCode` with `AL-04`, `AL-07`, and `AL-23`. `nextSendAtForCode` treats those three like `AL-01`: one hour ahead. The email text stays `{code} {detail_id}`. AL-05 and AL-09 stay send-once. Do not edit `abo/src/work/grant.ts` in this task.

### 4.3 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — grant step

**Independent Test**: E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, and E2E-P4.4-04 in harnesses H-XW and H-PAY.

- [ ] T013 [US1] Add `abo/src/work/grant.ts` — produces the grant step and the signing-key check, FR-001, FR-002, FR-003, FR-004, FR-006, FR-007, FR-010, E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, E2E-P4.4-04, E2E-P4.4-06, E2E-P4.4-07. Depends on T011 and T012. Do not edit `abo/src/worker.ts`, `abo/src/notify/intake.ts`, `abo/src/alert/index.ts`, `abo/src/clinic-api/checkouts.ts`, or `abo/src/work/runner.ts` in this task. Export `refreshSigningKeyCheck` and `runDueGrantWork`.

  Signing-key check. `refreshSigningKeyCheck` calls `PLATFORM.listServiceKeys({ contract_version: CHANNEL_VERSIONS.vendorEntrypoint })`. A successful `ok` parses `detail` as the JSON array of `{kid, status, not_before, not_after}`. The ABO kid comes from `ABO_GRANT_KEY`. The check passes only when that `kid` is listed with `status` `active` and the ABO clock is within `not_before` and `not_after` inclusive. Otherwise, and when the call throws or the result is not `ok`, the gate row is `paused = 1` and AL-23 is raised with key `AL-23:{kid}` (or `AL-23:missing` when the JSON has no kid). When the check passes, `paused = 0` and that alert row's `active` is set to 0. `runDueGrantWork` reads the gate first. While `paused = 1` it does not take `grant` or `reverse` rows. Those rows stay `open`. They are not parked.

  Grant step, for one due `open` `grant` row whose `subject_id` is the payment. Skip when paused. Take the row with the same 60-second conditional lease the confirm runner uses (`lease_until` null or already past, `next_attempt_at` due). Load the payment and its checkout. Build one envelope: `contract_version` `CHANNEL_VERSIONS.vendorEntrypoint`; `grant_id` `grantIdPaid(payment_id)`; `org_id` the payment's `org_id`; `kind` `term`; `placement` `queue`; `source` `{kind: "paid", ref: payment_id}` with `operator_email` and `reason` omitted; `plan` `{plan_id, plan_version}` from the checkout; `duration` `{unit: "month", count: checkout.term_count}` (1, 3, or 12); `allowance_credits` `checkout.allowance_credits`; `grace` `{days: checkout.grace_days, cap_rule: checkout.grace_cap_rule}`; `paid_at` `payment.paid_at`; `evidence.content_sha256` `fact_log.row_sha256` for table `payment` and that `payment_id`; `evidence.approvals` one element, the operation object `{op, params, actor_email, issued_at, nonce, contract_version}` with `op` `grant`, `params` that same envelope with `evidence.approvals` omitted, `actor_email` `""`, `issued_at` `paid_at`, `nonce` `grant_id`, and `contract_version` the envelope's `contract_version`. Sign the canonical bytes of the full envelope (approvals included) with `signCompactJws` and the current `ABO_GRANT_KEY`. Call `PLATFORM.grant` with `contract_version`, `abo_kid`, `abo_signature`, and `envelope_b64` (base64 of those canonical bytes). Do not rely on a structured-clone of the envelope object.

  Outcomes. `applied` or `already_applied`, and `verifyCompactJws` succeeds for `receipt.signature` against the configured platform public key whose `kid` matches the JWS header: one D1 batch inserts `grant_request` if that `grant_id` is absent, inserts `grant_outcome`, inserts the two `fact_log` rows, and sets the work row `done` conditional on the held lease. `grant_request.assertion` is null. The outcome stores `abo_kid`, `abo_signature`, the receipt JSON, `term_ids` from the receipt, and `at` from the ABO clock. Clear AL-04 for that work id (`active = 0`). `applied` or `already_applied`, and the receipt does not verify: do not insert `grant_outcome`. Park the row (`state = parked`, `lease_until` null, `last_error` `receipt_unverified`) and raise AL-07. Still insert `grant_request` if it is absent, in that same park write. `conflict` or `rejected`: one batch inserts `grant_request` if absent and `grant_outcome` with that `result` and `at`. `abo_kid`, `abo_signature`, `receipt`, and `term_ids` are null. Park the work row and raise AL-07 with key `AL-07:{work_id}`. `transient`, or the `grant` call throws: do not insert `grant_outcome`. Leave the row `open`. Set `last_error` to `wait:{iso}` on the first such failure and keep that timestamp on later ones. Backoff is the confirm formula: 1 minute, doubling, capped at 15 minutes; when `TEST_CLOCK` is `"1"`, the delay is 0. Raise AL-04 with key `AL-04:{work_id}` once the ABO clock is at least 5 minutes after the `wait:` timestamp. A thrown outcome batch: the platform call has already returned. Release the lease, leave the row `open`, write no outcome. The retry is the same `grant_id` and the same canonical envelope.

  `runDueGrantWork` selects at most 50 due `open` `grant` rows ordered by `next_attempt_at`. It does not select `confirm` rows and does not change the confirm limit. A single row failure does not throw out of the cron. `reverse` rows are not created here; the pause check is the only `reverse` behavior. `transient` is not a `grant_outcome` result.

### 4.4 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — notify waitUntil

**Independent Test**: E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, and E2E-P4.4-04 in harnesses H-XW and H-PAY.

- [ ] T014 [US1] Run the grant step after confirm in `abo/src/notify/intake.ts` — produces the paid-callback grant kick, FR-001, FR-008, E2E-P4.4-01, E2E-P4.4-08. Depends on T013. The processed-callback `waitUntil` still runs `runConfirmForWorkId`. When that promise settles, it runs `runDueGrantWork` on the same env. HMAC, rate limit, and the confirm step are unchanged. Do not edit `abo/src/worker.ts` or `abo/src/work/grant.ts` in this task.

### 4.5 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — checkout Active

**Independent Test**: E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, and E2E-P4.4-04 in harnesses H-XW and H-PAY.

- [ ] T015 [US1] Show Active after an accepted grant in `abo/src/clinic-api/checkouts.ts` — produces checkout `shown_state` Active, FR-001, FR-008, E2E-P4.4-01, E2E-P4.4-08. Depends on T011. `POST /v1/checkouts` stays. `checkoutReadObject` still returns Waiting for `open` and Abandoned for `open_failed`. When `checkout_status.state` is `paid` or `paid_late` and that checkout's payment has a `grant_outcome.result` of `applied` or `already_applied`, `shown_state` is `Active`. Otherwise a `paid` checkout still returns no object, so `GET /v1/checkouts/{id}` stays `not_found` until the grant is accepted. `payment_reference` and `term_ref` stay null. `GET /v1/checkouts?open=1` already selects `paid` and `paid_late`; Active rows then appear. Do not edit `abo/src/work/grant.ts` in this task.

### 4.6 User Story 3 - Read subscription, payments, and Active without polling (Priority: P3) — billing reads

**Independent Test**: E2E-P4.4-05, E2E-P4.4-08, and E2E-P4.4-09 in harnesses H-XW and H-PAY. Earlier H-ABO, H-PAY, and H-XW suites stay green, and E2E-P4.4-01 through E2E-P4.4-04, E2E-P4.4-06, and E2E-P4.4-07 still pass.

- [ ] T016 [US3] Add `abo/src/clinic-api/billing-reads.ts` — produces `GET /v1/subscription` and `GET /v1/payments`, FR-005, FR-009, E2E-P4.4-05, E2E-P4.4-09. Depends on T011. Implement `contracts/subscription-payments.md` (already written). Do not rewrite that contract. `subscriptionRef` is `subscriptionRef(org)` from `vendor-contracts`. `snapshot` is `detail.snapshot` from a live `getCoverage` (`contract_version` `CHANNEL_VERSIONS.vendorEntrypoint`, `org_id` the token `org`). When that call throws or `result` is not `ok`, `snapshot` is the parsed `coverage_view.snapshot` for that `org_id`. When that row is missing, `snapshot` is null and the HTTP status is still 200. `notices` is the closed set in FR-005: `duplicate_payment` when a payment of this tenant is `likely_duplicate`; `late_payment_honoured` when one is `late`; `payment_withheld` when a disposition is `withheld_mismatch`; `reversal_recorded` when a reversal is recorded for this tenant; `terms_held` when `snapshot.held_count` > 0. A null snapshot does not include `terms_held`. Returning `reversal_recorded` and `terms_held` does not insert reversals or process them. `plan_display_name` is `copy.en.name` on the published `offer_version` that `GET /v1/offers` returns for the payment's `offer_id` (`listOffers` in `abo/src/clinic-api/offers.ts`). `offer_version` is `payment.offer_version`. `term_unit` and `term_count` are the checkout columns. `reversals` is the `reversal` rows for that `payment_id`. This unit inserts none. A page holds 20 payments. The cursor behavior E2E-P4.4-09 asserts is the one in that contract. Do not edit `abo/src/worker.ts` in this task.

### 4.7 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — worker dispatch

**Independent Test**: E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, and E2E-P4.4-04 in harnesses H-XW and H-PAY.

- [ ] T017 [US1] Dispatch grant work and the clinic reads in `abo/src/worker.ts` — produces the live entry chains, FR-001, FR-002, FR-005, FR-006, FR-008, FR-009, E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-05, E2E-P4.4-06, E2E-P4.4-08, E2E-P4.4-09. Depends on T013, T014, and T016. `Env.PLATFORM` also types `grant` and `listServiceKeys`. `GET /v1/subscription` and `GET /v1/payments` go through the existing billing version, auth, and rate gates to `billing-reads.ts`. The minute cron still runs confirm, then `runDueGrantWork`. Cron `0 * * * *` calls `refreshSigningKeyCheck` and returns. Cron `0 */6 * * *` still returns immediately. Fetch and `scheduled` call `refreshSigningKeyCheck` when `signing_key_gate` has no row, and the hourly cron always calls it. Do not edit `abo/src/work/grant.ts`, `abo/src/notify/intake.ts`, `abo/src/clinic-api/billing-reads.ts`, `abo/src/clinic-api/checkouts.ts`, or `abo/src/work/runner.ts` in this task.

### 4.8 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — wrangler keys

**Independent Test**: E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, and E2E-P4.4-04 in harnesses H-XW and H-PAY.

- [ ] T018 [US1] Add grant signing vars in `abo/wrangler.toml` — produces `ABO_GRANT_KEY` and `PLATFORM_PUBLIC_KEYS`, FR-001, FR-007, E2E-P4.4-01, E2E-P4.4-07. Depends on T010. On development, staging, and production, add `ABO_GRANT_KEY` and `PLATFORM_PUBLIC_KEYS`. Placeholders are `{}` and `[]`. `ABO_GRANT_KEY` is JSON `{kid, pkcs8, public_key}`. `pkcs8` and `public_key` are base64url, the same shape as the platform worker's `PLATFORM_SIGNING_KEY`. `PLATFORM_PUBLIC_KEYS` is a JSON array of `{kid, public_key}`. Add no `TEST_CLOCK` var. Add no production fault binding. Production placeholders fail the signing-key check closed (pause), which is the FR-006 outcome when the kid is missing.

---

## 5. Verification

**Purpose**: Sequencing step 4, before `quickstart.md`. The harness is this command from `abo/`. A repository-root `npm test` is not a task. Earlier suites are not part of this command.

### 5.1 Unit harness

**Independent Test**: E2E-P4.4-05, E2E-P4.4-08, and E2E-P4.4-09 in harnesses H-XW and H-PAY. Earlier H-ABO, H-PAY, and H-XW suites stay green, and E2E-P4.4-01 through E2E-P4.4-04, E2E-P4.4-06, and E2E-P4.4-07 still pass.

- [ ] T019 [US3] Run `node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/grant.cross-worker.test.ts` from `abo/` until E2E-P4.4-01 through E2E-P4.4-09 pass — produces the green unit harness, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, E2E-P4.4-04, E2E-P4.4-05, E2E-P4.4-06, E2E-P4.4-07, E2E-P4.4-08, E2E-P4.4-09. Depends on T015, T017, and T018 (and therefore on T001–T014 and T016). This task may edit only files under `abo/test/`.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/grant.cross-worker.test.ts
```

**Checkpoint**: E2E-P4.4-01 through E2E-P4.4-09 pass.

---

## 6. Documentation

**Purpose**: After the harness is green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md`, `data-model.md`, or `contracts/` task.

### 6.1 Quickstart

- [ ] T020 Create `specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, E2E-P4.4-04, E2E-P4.4-05, E2E-P4.4-06, E2E-P4.4-07, E2E-P4.4-08, E2E-P4.4-09. Depends on T019. Sections: (1) what was implemented, and the files added or modified; (2) the harness command below; (3) the entry point → module chain per E2E id below. No earlier-unit files, combined counts, or full-suite commands. No manual steps; the harness observes every scenario.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/grant.cross-worker.test.ts
```

| ID | Chain |
| --- | --- |
| E2E-P4.4-01 | `worker.ts` `fetch` → `checkouts.ts` `handlePostCheckout` → `notify/intake.ts` → `work/runner.ts` `runConfirmForWorkId` → `work/grant.ts` `runDueGrantWork` → `PLATFORM.grant` → `PLATFORM_HTTP.fetch` `/v1/requests` → `checkouts.ts` `handleGetCheckout` → `billing-reads.ts` payments |
| E2E-P4.4-02 | `work/grant.ts` → `PLATFORM.grant` (`transient`) → `alert/index.ts`; clock; then `applied` |
| E2E-P4.4-03 | `work/grant.ts` → `PLATFORM.grant` (`rejected`) → park + AL-07 |
| E2E-P4.4-04 | `work/grant.ts` → `PLATFORM.grant` → thrown batch → retry `already_applied` |
| E2E-P4.4-05 | `work/grant.ts` twice → `billing-reads.ts` `GET /v1/subscription` |
| E2E-P4.4-06 | `worker.ts` `scheduled` / first fetch → `work/grant.ts` `refreshSigningKeyCheck` → `PLATFORM.listServiceKeys` → pause → resume |
| E2E-P4.4-07 | `work/grant.ts` receipt verify → `grant_outcome` |
| E2E-P4.4-08 | `notify/intake.ts` `waitUntil` → `work/grant.ts` with no clinic GET → `checkouts.ts` `handleListOpenCheckouts` |
| E2E-P4.4-09 | `worker.ts` `fetch` → `billing-reads.ts` payments |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (Phase 3)**: No grant module exists yet. T001 writes `abo/vitest.cross-worker.config.ts`. T002 through T010 stay in id order in `abo/test/system/grant.cross-worker.test.ts`. T002 creates that file and the shared setup. T003 through T010 append tests to it.
- **Implementation (Phase 4)**: Starts after T010, with E2E-P4.4-01 through E2E-P4.4-09 failing. The migration and the alert codes both follow the failing tests and both finish before the grant module. The grant module finishes before notify calls it. Checkout Active and the billing reads both follow the migration. Worker dispatch follows the grant module, notify, and the billing reads. Wrangler key vars follow the failing tests.
- **Verification (Phase 5)**: Depends on T015, T017, and T018. Runs only the command in §5.1.
- **Documentation (Phase 6)**: Depends on T019 being green.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: Tests T002, T003, T004, and T005, after the vitest bindings. Implementation T011, T012, T013, T014, T015, T017, and T018. E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, and E2E-P4.4-04.
- **User Story 2 (P2)**: Tests T006 and T007 after T005, because they write the same grant test file. The signing-key check and the receipt verify are T013. Alert code AL-23 is T012. The second platform key binding is T001, and the wrangler placeholders are T018. E2E-P4.4-06 and E2E-P4.4-07.
- **User Story 3 (P3)**: Tests T008, T009, and T010 after T007, in that id order, even though E2E-P4.4-05 is numbered before E2E-P4.4-06. Billing reads are T016. Checkout Active for the unattended `?open=1` read is T015. Worker routes are T017. The notify kick that provisions with no clinic GET is T014. E2E-P4.4-05, E2E-P4.4-08, and E2E-P4.4-09, with E2E-P4.4-01 through E2E-P4.4-04, E2E-P4.4-06, and E2E-P4.4-07 still passing once T019 is green.

### 7.3 Within Each Phase

- T001 writes `abo/vitest.cross-worker.config.ts` before T002 creates `abo/test/system/grant.cross-worker.test.ts`.
- T002 through T010 all write `abo/test/system/grant.cross-worker.test.ts`, in that id order.
- T011 writes `abo/migrations/0004_grant.sql`. T012 writes only `abo/src/alert/index.ts`. Both follow T010. T013 writes `abo/src/work/grant.ts` after T011 and T012, and does not write `abo/src/worker.ts` or `abo/src/alert/index.ts`.
- T014 writes `abo/src/notify/intake.ts` after T013 and does not write `abo/src/worker.ts`.
- T015 writes `abo/src/clinic-api/checkouts.ts` after T011. T016 writes `abo/src/clinic-api/billing-reads.ts` after T011 and does not write `abo/src/worker.ts`.
- T017 writes `abo/src/worker.ts` after T013, T014, and T016, and does not write `abo/src/work/runner.ts`.
- T018 writes only `abo/wrangler.toml` after T010.
- T019 runs after T015, T017, and T018 and may edit only `abo/test/`.
- T020 writes only `specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/quickstart.md` after T019 is green.

---

## 8. Implementation Waves

### 8.1 Wave 1

- T001 [US1] — subphase: `### 3.1 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — cross-worker bindings` — paths: `abo/vitest.cross-worker.config.ts`

### 8.2 Wave 2

- T002–T005 [US1] — subphase: `### 3.2 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — tests` — paths: `abo/test/system/grant.cross-worker.test.ts`

### 8.3 Wave 3

- T006–T007 [US2] — subphase: `### 3.3 User Story 2 - Pause grants until the ABO key is active, and accept a rotated platform receipt key (Priority: P2) — tests` — paths: `abo/test/system/grant.cross-worker.test.ts`

### 8.4 Wave 4

- T008–T010 [US3] — subphase: `### 3.4 User Story 3 - Read subscription, payments, and Active without polling (Priority: P3) — tests` — paths: `abo/test/system/grant.cross-worker.test.ts`

### 8.5 Wave 5

- T011 [US1] — subphase: `### 4.1 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — migration` — paths: `abo/migrations/0004_grant.sql`
- T012 [US1] — subphase: `### 4.2 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — alerts` — paths: `abo/src/alert/index.ts`

### 8.6 Wave 6

- T013 [US1] — subphase: `### 4.3 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — grant step` — paths: `abo/src/work/grant.ts`

### 8.7 Wave 7

- T014 [US1] — subphase: `### 4.4 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — notify waitUntil` — paths: `abo/src/notify/intake.ts`

### 8.8 Wave 8

- T015 [US1] — subphase: `### 4.5 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — checkout Active` — paths: `abo/src/clinic-api/checkouts.ts`
- T016 [US3] — subphase: `### 4.6 User Story 3 - Read subscription, payments, and Active without polling (Priority: P3) — billing reads` — paths: `abo/src/clinic-api/billing-reads.ts`

### 8.9 Wave 9

- T017 [US1] — subphase: `### 4.7 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — worker dispatch` — paths: `abo/src/worker.ts`
- T018 [US1] — subphase: `### 4.8 User Story 1 - Turn a paid checkout into a live term (Priority: P1) — wrangler keys` — paths: `abo/wrangler.toml`

### 8.10 Wave 10

- T019 [US3] — subphase: `### 5.1 Unit harness` — paths: `abo/test/`

### 8.11 Wave 11

- T020 — subphase: `### 6.1 Quickstart` — paths: `specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/quickstart.md`
