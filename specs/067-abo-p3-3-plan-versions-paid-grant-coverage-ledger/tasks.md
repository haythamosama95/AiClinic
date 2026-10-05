# Tasks: Plan versions, paid-grant intake and the per-clinic coverage ledger

**Input**: Design documents from `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `data-model.md`, `contracts/` (`AVAILABLE_DOCS`: `data-model.md`, `contracts/`). There is no `research.md`. `quickstart.md` is written in Documentation after verification.

**Organization**: Four user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`, `[US4]`). Tests are one task per E2E id in the spec Test plan, written to fail before `publishPlanVersion` and `grant` exist. Test Layout names no extra test. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase: the worker already exists. No Foundational phase (the prerequisite is P3.2, already merged, listed in Consumes Binding). No Polish phase. Task ids follow plan Sequencing, so `T001` is step 1. Sections group by user story, so ids are not in numeric order in the file. Sequencing step 31 is the review's earlier-suite run and is not a task.

**Task count**: 31. Size L is 32–40 (rule S3). The count is twelve E2E tasks (Sequencing steps 1–12), seventeen implementation steps (13–29), one verification task (step 30, this unit's harness only), and `quickstart.md` (step 32). It is not padded.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`, `US4`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — `migrations/20261003140000_plan_version_paid_grant_coverage.sql`, `schema.snap.sql`, `src/coverage/calendar.ts`, `src/quota-do/index.ts`, `src/worker.ts`, `src/vendor/entrypoint.ts`, `src/alert/index.ts`, `src/admission/index.ts`, `src/credit/index.ts`, `src/pipeline/index.ts`, `src/usage-summary/index.ts`, `src/control/quota-inspect.ts`, `wrangler.toml`, both vitest configs, H-AP `test/system/`, and the e2e harness and test files named in the tasks below
- **ABO**: `abo/` — this unit does not change it
- **Shared package**: `packages/vendor-contracts/` — consumed and not modified (rule S7)
- **Full-stack harness**: `e2e/fullstack/` — this unit does not change it
- **Spec Kit artifacts**: `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/`
- This unit's Files section names the `ai-platform` paths above and `quickstart.md`. `data-model.md` and `contracts/` stay plan-phase artifacts. `src/identity/index.ts`, `src/config-cache/index.ts`, `src/vendor/contract-version.ts`, and `packages/vendor-contracts/**` stay as they are. The quota JSON blob helpers stay. `/control/entitle` stays (rule S9).

---

## 3. Tests

**Purpose**: One failing test per E2E id, under H-AP, in Sequencing order. Every test is added to `ai-platform/test/system/paid-grant-coverage.system.test.ts`. The unit command is that file only. `T001` also extends `VendorMethod` in `ai-platform/test/system/harness.ts`. HP calls reuse `mintVendorAccessJwt`, `encodeVendorAssertion`, `createSoftwareAuthenticator`, and `setTestClock` the way `issuer-tokens.system.test.ts` reaches an active credential. The ABO signer is `createAboGrantSigner` from `vendor-contracts/testkit`. Alarm tests import `runDurableObjectAlarm` from `cloudflare:test`.

### 3.1 User Story 1 - Apply a paid grant (Priority: P1)

**Independent Test**: E2E-P3.3-01, E2E-P3.3-02, E2E-P3.3-03, E2E-P3.3-05, E2E-P3.3-06, and E2E-P3.3-09 in harness H-AP (test clock). E2E-P3.3-11 and E2E-P3.3-12 in harness H-AP (`GatewayObject.fetch`).

Tasks below are this story's tests in Sequencing order. They append to one file, with User Story 2, 3, and 4 tests between some of them. Section 7 lists that global order.

#### 3.1.1 User Story 1 - Apply a paid grant (part 1)

- [X] T001 [US1] Add the failing test `E2E-P3.3-01 Publish plan v1 then a paid grant for a new org is applied, the receipt verifies, and the term is active` in `ai-platform/test/system/paid-grant-coverage.system.test.ts`, and extend `VendorMethod` in `ai-platform/test/system/harness.ts` — produces the red test and the method names, satisfies FR-001, FR-004, FR-005, FR-006, FR-007, and FR-010, proved by E2E-P3.3-01. `vendorCall` gains `publishPlanVersion`, `registerServiceKey`, `revokeServiceKey`, `listServiceKeys`, `retirePlanVersion`, `grant`, `getCoverage`, `listGrants`, and `readCoverageEvents`. The test calls `vendorCall` `publishPlanVersion` and `registerServiceKey`, then `vendorCall` `grant` with the testkit ABO key. `result` is `applied`. `verifyReceiptSignature` accepts the receipt with the platform public key. The DO term is `active` with `starts_at` equal to the test clock. Run:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/paid-grant-coverage.system.test.ts
```

The run fails because `publishPlanVersion` and `grant` are not on `VendorEntrypoint`. Do not modify `packages/vendor-contracts`.

- [X] T002 [US1] Add the failing test `E2E-P3.3-02 The same grant resent is already_applied with the identical receipt and one ledger row` in `ai-platform/test/system/paid-grant-coverage.system.test.ts` — produces the red test, satisfies FR-005 and FR-008, proved by E2E-P3.3-02. Depends on T001 (same file). The second `vendorCall` `grant` is `already_applied` and the receipt JSON equals the first. `runDurableObjectAlarm` then leaves one `grant_ledger` row for that `grant_id`. The unit command fails on the missing `grant` replay and the missing alarm ship.

- [X] T003 [US1] Add the failing test `E2E-P3.3-03 The same grant_id with a changed allowance is conflict and nothing changes` in `ai-platform/test/system/paid-grant-coverage.system.test.ts` — produces the red test, satisfies FR-008, proved by E2E-P3.3-03. Depends on T002 (same file). `result` is `conflict`. Term count, `hot.clinic_seq`, and the stored envelope hash stay as they were. The unit command fails on the missing conflict path.

- [X] T005 [US1] Add the failing test `E2E-P3.3-05 An unregistered signing kid is transient unknown_kid and a revoked kid is rejected bad_signature` in `ai-platform/test/system/paid-grant-coverage.system.test.ts` — produces the red test, satisfies FR-004 and FR-007, proved by E2E-P3.3-05. Depends on T004 (same file). The unknown-kid `grant` is `transient`, `detail` `unknown_kid`, and writes nothing. After `revokeServiceKey`, that key's `grant` is `rejected` `bad_signature`. The unit command fails on the missing kid checks and `revokeServiceKey`.

- [X] T006 [US1] Add the failing test `E2E-P3.3-06 Unpublished plan, allowance or grace over the bound, paid unit day, and placement immediate are refused` in `ai-platform/test/system/paid-grant-coverage.system.test.ts` — produces the red test, satisfies FR-007, proved by E2E-P3.3-06. Depends on T005 (same file). The results are `plan_not_published`, `exceeds_plan_bound` for allowance above max times months and for grace of 8 days, `unit_not_allowed`, and `placement_not_supported`. Each writes nothing. The unit command fails on the missing bound checks.

**Checkpoint**: E2E-P3.3-01, E2E-P3.3-02, E2E-P3.3-03, E2E-P3.3-05, and E2E-P3.3-06 exist and fail.

#### 3.1.2 User Story 1 - Apply a paid grant (part 2)

- [ ] T009 [US1] Add the failing test `E2E-P3.3-09 A grant at 31 January 10:00 ends 28 February 10:00, or 29 February in a leap year, and the staging scale makes a month 30 minutes` in `ai-platform/test/system/paid-grant-coverage.system.test.ts` — produces the red test, satisfies FR-010, proved by E2E-P3.3-09. Depends on T008 (same file). One test, not three. `setTestClock("2026-01-31T10:00:00.000Z")` with `DURATION_SCALE` unset ends `2026-02-28T10:00:00.000Z`. `setTestClock("2024-01-31T10:00:00.000Z")` ends `2024-02-29T10:00:00.000Z`. With `env.DURATION_SCALE` set only around the 30-minute grant, a monthly term's `ends_at` is 30 minutes after `starts_at`. No `sleep` over 2 s. The unit command fails on the missing calendar.

- [ ] T011 [US1] Add the failing test `E2E-P3.3-11 A Worker to DO RPC with the current contract version is accepted and the answer echoes it` in `ai-platform/test/system/paid-grant-coverage.system.test.ts` — produces the red test, satisfies FR-003, proved by E2E-P3.3-11. Depends on T010 (same file). `fetch` POST on the real DO binding (`env.DO.get(env.DO.idFromName(...)).fetch`) with `contract_version` 1 and `kind` `inspect` returns JSON whose `contract_version` is 1. The unit command fails because `GatewayObject.fetch` does not echo `contract_version`.

- [ ] T012 [US1] Add the failing test `E2E-P3.3-12 A Worker to DO RPC with contract_version missing or 2 is rejected contract_version_unsupported before any write` in `ai-platform/test/system/paid-grant-coverage.system.test.ts` — produces the red test, satisfies FR-003, proved by E2E-P3.3-12. Depends on T011 (same file). One test covers both calls. Both return `result` `rejected`, `code` `contract_version_unsupported`, and `accepted_versions` `[0, 1]`. DO SQL tables are unchanged and the JSON blob is unchanged. The unit command fails because a missing version is still dispatched.

**Checkpoint**: E2E-P3.3-09, E2E-P3.3-11, and E2E-P3.3-12 exist and fail. User Story 1's eight tests are red.

### 3.2 User Story 2 - Read queued coverage (Priority: P2)

**Independent Test**: E2E-P3.3-04 in harness H-AP.

- [X] T004 [US2] Add the failing test `E2E-P3.3-04 A second paid grant is queued without dates and getCoverage shows queued_count 1 and coverage_through extended` in `ai-platform/test/system/paid-grant-coverage.system.test.ts` — produces the red test, satisfies FR-010 and FR-014, proved by E2E-P3.3-04. Depends on T003 (same file). The new `term` row has null `starts_at` and `ends_at`. `getCoverage` is `ok`, `code` is empty, `receipt` is absent, and `detail` JSON has `queued_count` 1 and a `coverage_through` later than the active term's `ends_at`. The unit command fails on the missing queue and `getCoverage`.

**Checkpoint**: E2E-P3.3-04 exists and fails.

### 3.3 User Story 3 - Retire a plan version (Priority: P3)

**Independent Test**: E2E-P3.3-10 in harness H-AP.

- [ ] T010 [US3] Add the failing test `E2E-P3.3-10 retirePlanVersion refuses the next grant on that version and the existing term keeps its snapshot` in `ai-platform/test/system/paid-grant-coverage.system.test.ts` — produces the red test, satisfies FR-006 and FR-015, proved by E2E-P3.3-10. Depends on T009 (same file). `retirePlanVersion` is `ok`. The next paid `grant` that names that version is `rejected` `plan_not_published`. The existing term's `plan_snapshot` is unchanged. The unit command fails on the missing `retirePlanVersion`.

**Checkpoint**: E2E-P3.3-10 exists and fails.

### 3.4 User Story 4 - Ship the coverage outbox (Priority: P4)

**Independent Test**: E2E-P3.3-07 and E2E-P3.3-08 in harness H-AP (test clock and DO alarm). Every earlier suite stays green (rule S2).

- [ ] T007 [US4] Add the failing test `E2E-P3.3-07 After the alarm, coverage events, the ledger, the mirror, and R2 exist, and readCoverageEvents pages by feed_seq` in `ai-platform/test/system/paid-grant-coverage.system.test.ts` — produces the red test, satisfies FR-011, FR-012, and FR-016, proved by E2E-P3.3-07. Depends on T006 (same file). `clinic_seq` rises across the new `coverage_event` rows. `readCoverageEvents` is `ok` and `detail` JSON lists those events in ascending `feed_seq`. An R2 object exists at `grant-ledger/<grant_id>.ndjson`. The unit command fails on the missing alarm ship and `readCoverageEvents`.

- [ ] T008 [US4] Add the failing test `E2E-P3.3-08 AL-11 email per grant carries the decoded operation and org, and the fourth paid grant within 24 hours raises AL-17` in `ai-platform/test/system/paid-grant-coverage.system.test.ts` — produces the red test, satisfies FR-013, proved by E2E-P3.3-08. Depends on T007 (same file). After `runDurableObjectAlarm`, captured `send_email` text is the AL-11 body. The fourth paid `grant` for that org, then the alarm, adds an AL-17 email. The grant `result` is still `applied`. No `sleep` over 2 s. The unit command fails on the missing AL-11 and AL-17 emails.

**Checkpoint**: E2E-P3.3-07 and E2E-P3.3-08 exist and fail. The "every earlier suite stays green" sentence on this story's Independent Test line is the review's run, not these tasks.

---

## 4. Implementation

**Purpose**: Sequencing steps 13–29. Each step starts after T001–T012 exist and fail. Within a story the tasks are in Sequencing order. Section 7 lists the global order, including tasks that sit under another story's heading.

### 4.1 User Story 1 - Apply a paid grant (Priority: P1)

**Independent Test**: E2E-P3.3-01, E2E-P3.3-02, E2E-P3.3-03, E2E-P3.3-05, E2E-P3.3-06, and E2E-P3.3-09 in harness H-AP (test clock). E2E-P3.3-11 and E2E-P3.3-12 in harness H-AP (`GatewayObject.fetch`).

#### 4.1.1 User Story 1 - Apply a paid grant (part 1)

- [ ] T013 [US1] Add `ai-platform/migrations/20261003140000_plan_version_paid_grant_coverage.sql`, replace `ai-platform/schema.snap.sql`, and add the new tables to `PLATFORM_ENTITIES` in `ai-platform/test/migrations.test.ts` — produces the D1 tables and the snapshot, satisfies FR-004, FR-006, FR-011, and FR-012, proved by E2E-P3.3-01, E2E-P3.3-02, and E2E-P3.3-07. Depends on T012. Tables are `service_key`, `plan_version`, `coverage_event`, `grant_ledger`, and `coverage_mirror`, with the indexes in `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/data-model.md`. `service_key` stores `kid`, `service` (`abo`), `public_key`, `status` (`active`, `revoked`), `not_before`, `not_after`, `registered_by`, and `assertion_sha256`. `plan_version` stores `plan_id`, `version`, `display_name`, `capabilities` (JSON array of capability id strings), `max_cost_class`, `concurrency_limit`, `max_allowance_per_month`, `status` (`published`, `retired`), `published_by`, and `assertion_sha256`. `coverage_event` stores `feed_seq` (autoincrement), `event_id` (unique), `org_id`, `installation_id`, `binding_epoch`, `clinic_seq`, `kind`, `snapshot`, and `at`, and is never purged. `grant_ledger` stores `grant_id`, `origin_grant_id`, `org_id`, `installation_id`, `kind`, `source_kind`, `operator_credential_id`, `envelope_sha256`, `receipt`, and `applied_at`, and is append-only, with indexes on `(org_id, applied_at)`, `(origin_grant_id)`, and `(operator_credential_id, applied_at)`. `coverage_mirror` stores `installation_id`, `org_id`, `binding_epoch`, `clinic_seq`, `state`, `suspended`, `hard_stop_at`, and `term_snapshot`. `schema.snap.sql` becomes the post-migration dump. The twelve E2E tests still fail.

- [ ] T014 [US1] Apply `ai-platform/migrations/20261003140000_plan_version_paid_grant_coverage.sql` after `20261003130000_issuer_key_tenant_binding.sql` — produces a schema the resets can use, satisfies FR-004, FR-006, FR-011, and FR-012, proved by E2E-P3.3-01 and E2E-P3.3-07. Depends on T013. Apply it from `ai-platform/test/system/harness.ts`, `ai-platform/test/e2e/harness/d1.ts`, and every other test file that applies `20261003130000_issuer_key_tenant_binding.sql`: `ai-platform/test/worker-request-orchestrator.test.ts`, `ai-platform/test/token-contract-control.test.ts`, `ai-platform/test/usage-summary.test.ts`, `ai-platform/test/retention.test.ts`, `ai-platform/test/plan-catalogue.test.ts`, `ai-platform/test/identity.test.ts`, `ai-platform/test/entitle-grant.test.ts`, `ai-platform/test/config-readers.test.ts`, `ai-platform/test/discovery-http.test.ts`, and `ai-platform/test/control.test.ts`. Reset deletes `service_key`, `plan_version`, `coverage_event`, `grant_ledger`, and `coverage_mirror`. `ai-platform/test/migrations.test.ts` stays the T013 `PLATFORM_ENTITIES` update. The new E2E file uses the system harness. The twelve E2E tests still fail.

- [ ] T015 [US1] Add `ai-platform/src/coverage/calendar.ts` — produces unscaled month and day arithmetic, satisfies FR-010, proved by E2E-P3.3-09. Depends on T014. `ends_at` = add(`calendar_start`, `duration_unit`, `duration_count`). Months keep the same day-of-month and time in UTC, clamped to the last day of a shorter month. Days are exact multiples of 24 hours. The staging scale is T029. E2E-P3.3-09 still fails on the missing grant path.

- [ ] T016 [US1] Negotiate the DO contract version at the start of `GatewayObject.fetch` in `ai-platform/src/worker.ts`, and send the current version from the existing callers — produces the accept-and-echo path and the before-write refusal, satisfies FR-003, proved by E2E-P3.3-11 and E2E-P3.3-12. Depends on T015. Before any storage read or write, `negotiate(CHANNEL_VERSIONS.platformDo, contract_version)`. Missing or unsupported, including 2, returns the refusal in `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/do-schema.md` and writes nothing. A supported call echoes that version on the JSON answer. The DO accepts N and N−1 and answers in the version the call used. At launch that accepted pair is `[0, 1]`. Add `contract_version: CHANNEL_VERSIONS.platformDo` to the DO bodies in `ai-platform/src/admission/index.ts`, `ai-platform/src/credit/index.ts`, `ai-platform/src/pipeline/index.ts`, `ai-platform/src/usage-summary/index.ts`, `ai-platform/src/control/quota-inspect.ts`, and the direct fetch in `ai-platform/test/usage-summary.test.ts`. `gatewayObjectRpc` in `ai-platform/test/e2e/harness/gateway-object.ts` sets the same field when the body omits it. A DO JSON equality assertion that fails only because `contract_version` was added to an existing kind's answer is updated to expect that field. Outcomes of `admission`, `credit`, `release`, and `inspect` stay as they are. This unit does not map a DO version refusal to `coverage_unknown`. E2E-P3.3-11 and E2E-P3.3-12 pass.

- [ ] T017 [US1] On the first `GatewayObject.fetch` that has passed the version check, create `hot`, `term`, `grant`, and `outbox` in `ai-platform/src/quota-do/index.ts` — produces the per-clinic DO tables, satisfies FR-001 and FR-002, proved by E2E-P3.3-01. Depends on T016. `CREATE TABLE IF NOT EXISTS` runs inside `blockConcurrencyWhile`. `GatewayObject.fetch` in `ai-platform/src/worker.ts` calls that creation. Leave the `state` blob and `admissionRPC`, `creditRPC`, `releaseRPC`, and `inspectRPC` in place. `hot` includes `binding_epoch`, `clinic_seq`, `next_alarm_at`, `used`, and `active_term_id`. `term` stores `term_id`, `grant_id`, `origin_grant_id`, `position`, `state`, `end_reason`, `plan_snapshot` (JSON object `{plan_id, version, display_name, capabilities, max_cost_class, concurrency_limit}`; `capabilities` is that version's JSON array of capability id strings, copied unchanged), `allowance`, `used_final`, `duration_unit`, `duration_count`, `grace_days`, `grace_cap`, `calendar_start`, `starts_at`, `ends_at`, `grace_ends_at`, and `ended_at`. `grant` stores `grant_id`, `kind` (`term`, `term_adjustment`), `source_kind`, `envelope_sha256`, `envelope`, `evidence`, `receipt`, `applied_at`, `voided_at`, and `void_reason`. `outbox` stores `seq`, `kind` (`coverage_event`, `grant_ledger`, `usage_adjustment`, `alert`), and `payload`. The other ten E2E tests still fail. E2E-P3.3-11 and E2E-P3.3-12 stay green.

**Checkpoint**: E2E-P3.3-11 and E2E-P3.3-12 pass at T016. The other ten E2E tests still fail.

#### 4.1.2 User Story 1 - Apply a paid grant (part 2)

- [ ] T018 [US1] Add `PLATFORM_SIGNING_KEY` to the three wrangler env var blocks and to both vitest binding sets, and add `DURATION_SCALE` only for staging — produces the receipt key and the staging scale switch, satisfies FR-005 and FR-010, proved by E2E-P3.3-01 and E2E-P3.3-09. Depends on T017. Files: `ai-platform/wrangler.toml`, `ai-platform/vitest.workers.config.ts`, and `ai-platform/vitest.e2e.config.ts`. The key value is the local stand-in JSON in `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/receipt-production.md`. `DURATION_SCALE` = `staging` only under `[env.staging.vars]`. Development, production, and both vitest configs omit `DURATION_SCALE`. No `TEST_CLOCK` in wrangler. E2E-P3.3-01 still fails on the missing grant path.

- [ ] T019 [US1] Add `registerServiceKey`, `revokeServiceKey`, and `listServiceKeys` in `ai-platform/src/vendor/entrypoint.ts` — produces the service-key methods, satisfies FR-004, proved by E2E-P3.3-01 and E2E-P3.3-05. Depends on T018. Results match `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/service-key-methods.md`. Register and revoke are class HP. List is class M. They do not record a grant or a reversal. A successful call is `ok`: `code` is empty, `receipt` is absent, and `detail` is the JSON text of the `service_key` row for register and revoke, or a JSON array of `{kid, status, not_before, not_after}` for every row, including `revoked`, for list. `registerServiceKey` takes `kid`, `public_key`, `not_before`, and `not_after`. It inserts `status` `active`, sets `service` to `abo`, stores `public_key` unchanged, sets `registered_by` to the Access email, and sets `assertion_sha256` to the assertion challenge hash. The same `kid` with the same `public_key` is `ok` again and does not insert another row or change `status` or the stored validity. The same `kid` with a different `public_key` is `conflict` with code `public_key_mismatch` and `detail` empty. A `public_key` that is not the base64url encoding of a raw 32-byte Ed25519 public key is `rejected` with code `public_key_invalid` and `detail` empty. `revokeServiceKey` takes `kid`. It sets `status` to `revoked`, and it is `ok` when the row is already `revoked`. It is the only writer of `revoked`. A missing `kid` is `rejected` with code `kid_not_found` and `detail` empty. There is no `retiring` status. E2E-P3.3-05 still fails until `grant` checks the key. The Test plan assigns no E2E id to `listServiceKeys`, `public_key_mismatch`, `public_key_invalid`, or `kid_not_found`. Do not add one.

- [ ] T020 [US1] Raise service-key AL-13 from `ai-platform/src/alert/index.ts`, called by `ai-platform/src/vendor/entrypoint.ts` — produces the registration and revocation alert, satisfies FR-004, proved by E2E-P3.3-01 and E2E-P3.3-05. Depends on T019. Do not change the credential or issuer-key AL-13 bodies. AL-13's body carries the decoded operation and its target. The repeat is once. Unsent retry rebuilds an `AL-13:service_key:` key from `service_key` and `control_audit`. The Test plan assigns no E2E id to the AL-13 email. Do not add one, and do not extend E2E-P3.3-01 or E2E-P3.3-05 to assert it.

- [ ] T022 [US1] Implement paid `grant` checks in `ai-platform/src/vendor/entrypoint.ts` through validation step 3, before any binding or DO write — produces the refusal path, satisfies FR-007 and FR-009, proved by E2E-P3.3-05 and E2E-P3.3-06. Depends on T021 (same file). Results match `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/grant-paid.md`. `grant` is class M. Beyond `contract_version` the input is the grant envelope, `abo_kid`, and `abo_signature`. `source.kind` `paid` selects class M and an ABO signature. The platform validates in order and answers `rejected` with the named code: (1) `contract_version` is supported and the envelope's canonical hash matches the signed hash (`bad_signature`); every grant requires `evidence.approvals` to hold at least 1 element, and a shorter list is `rejected` with `approvals_required` and `detail` empty; (2) the ABO signature verifies against the named `service_key` — an unknown `kid` answers `transient` with `detail` `unknown_kid` and writes nothing, and a revoked or expired `kid` answers `rejected` with `bad_signature`; a `kid` is expired when `status` is `active` and now is before `not_before` or after `not_after`; (3) the plan version is `published` (`plan_not_published`), including a `retired` version; the source, unit, and count are allowed (`unit_not_allowed`); for `paid`, `allowance_credits` ≤ `max_allowance_per_month` × months and grace follows the grace row (`exceeds_plan_bound`). Paid duration is `{unit: month, count: 1, 3, or 12}`. Paid grace is `{days ≤ 7, cap_rule: proportional}`. Eight grace days is `exceeds_plan_bound`. A paid unit `day` is `unit_not_allowed`. `placement` `immediate` and `replace` are `placement_not_supported`. A paid `term_adjustment` source is rejected at launch. `allowance_credits` is an integer ≥ 1. Vendor-method version checks keep using `negotiate(CHANNEL_VERSIONS.vendorEntrypoint, …)` before authentication and before any write. E2E-P3.3-05 and E2E-P3.3-06 pass. The Test plan assigns no E2E id to `approvals_required` or `bad_signature` from a hash mismatch. Do not add one.

- [ ] T023 [US1] After those checks, resolve or insert the active binding for `org_id` — produces the binding step, satisfies FR-007, proved by E2E-P3.3-01. Depends on T022. Use the column list in `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/contracts/tenant-binding.md`. A paid grant for an org with no active row inserts one `installation` and one `epoch` 1 `active` binding. Do not edit `ai-platform/src/identity/index.ts`. Do not edit `resolveInstallationId`, the 50-per-day cap, or AL-20. A unique conflict re-reads the active row. E2E-P3.3-01 still fails until T024 places the term.

**Checkpoint**: E2E-P3.3-05 and E2E-P3.3-06 pass at T022. E2E-P3.3-01 still fails.

#### 4.1.3 User Story 1 - Apply a paid grant (part 3)

- [ ] T024 [US1] Add DO kind `apply_grant` in `ai-platform/src/quota-do/index.ts`, called from `GatewayObject.fetch` in `ai-platform/src/worker.ts` — produces placement, the stored receipt, and the outbox rows, satisfies FR-005, FR-008, FR-010, and FR-011, proved by E2E-P3.3-01, E2E-P3.3-03, E2E-P3.3-09, and E2E-P3.3-10. Depends on T023. Place the term, sign the receipt with `PLATFORM_SIGNING_KEY` via `signCompactJws`, and write `grant`, `term`, `hot`, and `outbox` in one `blockConcurrencyWhile`. The receipt is `{contract_version, grant_id, installation_id, org_id, result, term_ids, applied_at, ledger_seq, envelope_sha256, kid, signature}`. `signature` is a compact JWS: header `{alg: "EdDSA", kid}` naming the platform key, payload the RFC 8785 canonical receipt with `signature` omitted, and the third segment the base64url Ed25519 signature. `ledger_seq` is the integer `clinic_seq` on the `grant_applied` coverage event. It is not a `grant_ledger` column. `receipt` is present when `result` is `applied` or `already_applied`. The same `grant_id` with the same `envelope_sha256` returns the stored receipt and writes nothing else (`already_applied`). A different hash returns `conflict` and writes nothing. A term grant with no active, grace, or unheld queued term becomes `active` with `starts_at` = `calendar_start` = now. A grant while an active or queued term exists becomes `queued`, appended at the end, and stores a duration, not dates. A grant during grace becomes `active` with `calendar_start` equal to the grace term's `ends_at`, and that grace term ends `renewed`. There is no `not_pending` refusal. `ends_at` uses `ai-platform/src/coverage/calendar.ts`. The platform snapshots the published plan version into `term.plan_snapshot`. On success the DO stores the envelope and evidence and writes the coverage events into the outbox in the order `term_ended`, `term_activated`, `grant_applied`, skipping any the grant does not emit. A paid grant emits `grant_applied`, and also `term_activated` when placement leaves the new term `active`, and `term_ended` when placement ends the grace term. A grant that only queues emits `grant_applied` alone. Each event carries the clinic's full coverage snapshot after the change. For a paid grant the snapshot's `clinic_seq` equals that event's `clinic_seq`, and `at` is the UTC ISO-8601 time of the grant. The alarm is set to the earliest of the next boundary (`ends_at`, `grace_ends_at`) or a pending outbox, and `setAlarm` runs only when that time moves. E2E-P3.3-01, E2E-P3.3-03, the unscaled half of E2E-P3.3-09, and E2E-P3.3-10 pass. The 30-minute half of E2E-P3.3-09 still fails.

- [ ] T029 [US1] Honour `env.DURATION_SCALE` inside `ai-platform/src/coverage/calendar.ts` — produces the staging scale, satisfies FR-010, proved by E2E-P3.3-09. Depends on T028. Staging maps 1 month to 30 minutes and 1 day to 1 minute. Every duration is computed in unscaled units and then scaled. Production has no scale. E2E-P3.3-09 passes.

**Checkpoint**: E2E-P3.3-01, E2E-P3.3-03, and E2E-P3.3-10 pass at T024. The unscaled half of E2E-P3.3-09 passes at T024. E2E-P3.3-09 passes at T029.

### 4.2 User Story 2 - Read queued coverage (Priority: P2)

**Independent Test**: E2E-P3.3-04 in harness H-AP.

- [ ] T026 [US2] Add `getCoverage` in `ai-platform/src/vendor/entrypoint.ts` and DO kind `read_coverage` in `ai-platform/src/quota-do/index.ts` — produces the coverage read, satisfies FR-014 and FR-010, proved by E2E-P3.3-04. Depends on T025. `getCoverage` is class M. Beyond `contract_version` it takes `org_id`. A successful call is `ok`: `code` is empty, `receipt` is absent, and `detail` is the JSON text of `{snapshot, queued_terms, recent_terms}`. The snapshot carries `contract_version`, `state`, `reason` (`none`, `expired`, `grace_exhausted`, `exhausted`, `reversed`, `transferred`, `transfer_pending`) for a non-available state, `suspended`, `term` (null, or `{ref, plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used, band}` with `band` `ok`, `75`, `90`, or `exhausted`), `queued_count`, `held_count`, `coverage_through`, `binding_epoch`, and `clinic_seq`. `coverage_through` is the projected end of coverage assuming no exhaustion. The snapshot has no prices, payment references, or provider ids. `queued_terms` are the unheld terms in state `queued`, in ascending `position`. Each is `{plan_id, plan_version, plan_display_name, duration_unit, duration_count}` and has no dates. `recent_terms` are at most the last 12 terms whose state is `active`, `grace`, or `ended`, highest `position` first. Fewer than 12 returns those that exist. Each is `{term_id, state, plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used}`. `used` is `hot.used` when the term is `hot.active_term_id`, and `used_final` otherwise. Results match `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/get-coverage.md`. E2E-P3.3-04 passes.

**Checkpoint**: E2E-P3.3-04 passes at T026.

### 4.3 User Story 3 - Retire a plan version (Priority: P3)

**Independent Test**: E2E-P3.3-10 in harness H-AP.

- [ ] T021 [US3] Add `publishPlanVersion` and `retirePlanVersion` in `ai-platform/src/vendor/entrypoint.ts` — produces plan publish and retire, satisfies FR-006 and FR-015, proved by E2E-P3.3-01 and E2E-P3.3-10. Depends on T020 (same file). Results match `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/plan-version-methods.md`. Both are class HP. They do not record a grant or a reversal. A successful call is `ok`: `code` is empty, `receipt` is absent, and `detail` is the JSON text of the `plan_version` row. `publishPlanVersion` takes `plan_id`, `version`, `display_name`, `capabilities`, `max_cost_class`, `concurrency_limit`, and `max_allowance_per_month`. It inserts `status` `published`, sets `published_by` to the Access email, and sets `assertion_sha256` to the assertion challenge hash. The same `(plan_id, version)` with the same values in those content fields is `ok` again and does not insert another row or change `status` or those fields. The same pair with a different value in any of those fields is `conflict` with code `plan_version_mismatch` and `detail` empty, and the stored row is unchanged. Content fields stay immutable once published. `retirePlanVersion` takes `plan_id` and `version`. It sets `status` from `published` to `retired`, and it is `ok` when the row is already `retired`. It is the only writer of `retired`. A missing `(plan_id, version)` is `rejected` with code `plan_version_not_found` and `detail` empty. The next paid grant that names a retired version is refused at T022, and the existing term keeps its `plan_snapshot` at T024. E2E-P3.3-10 stays red until T024. The Test plan assigns no E2E id to `plan_version_mismatch` or `plan_version_not_found`. Do not add one.

**Checkpoint**: E2E-P3.3-10 stays red until T024. `publishPlanVersion` is on the entrypoint for User Story 1's grant.

### 4.4 User Story 4 - Ship the coverage outbox (Priority: P4)

**Independent Test**: E2E-P3.3-07 and E2E-P3.3-08 in harness H-AP (test clock and DO alarm). Every earlier suite stays green (rule S2).

- [ ] T025 [US4] Add `GatewayObject.alarm` in `ai-platform/src/worker.ts`, shipping through `ai-platform/src/quota-do/index.ts` — produces the outbox ship, satisfies FR-011, FR-012, and FR-008, proved by E2E-P3.3-02 and E2E-P3.3-07. Depends on T024. Ship outbox rows as `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/coverage-event.md` describes, then delete them. The alarm ships to D1 (`coverage_event`, `grant_ledger`, `grant_void`, `coverage_mirror`, `usage_event` for `usage_adjustment`, `platform_alert`) with `INSERT OR IGNORE` on event id or `request_id`, then deletes the shipped rows, and writes the R2 `grant-ledger/` object. `coverage_mirror` is replaced only by a higher `(binding_epoch, clinic_seq)` pair. `setAlarm` runs only when `next_alarm_at` changes. A grant object is `grant-ledger/<grant_id>.ndjson`: one JSON line `{grant_id, origin_grant_id, org_id, installation_id, kind, source_kind, operator_credential_id, envelope_sha256, applied_at, receipt}`. A void object is `grant-ledger/<grant_id>.void.ndjson` and does not replace the grant object. `coverage_event.kind` is `grant_applied`, `grant_voided`, `term_activated`, `term_ended`, `term_held`, `term_released`, `grace_started`, `band_crossed`, `suspension_changed`, or `transfer`. E2E-P3.3-02 passes. E2E-P3.3-07 still fails on the missing `readCoverageEvents` method.

- [ ] T027 [US4] Add `listGrants` and `readCoverageEvents` in `ai-platform/src/vendor/entrypoint.ts` — produces the ledger and feed reads, satisfies FR-016, proved by E2E-P3.3-07. Depends on T026. Both are class M. `listGrants` filters are `org_id`, `source_kind`, `credential_id`, `applied_from`, and `applied_to`. `credential_id` matches `operator_credential_id`. `applied_from` and `applied_to` are inclusive UTC ISO-8601 bounds on `applied_at`. An omitted filter does not constrain that column. A successful call is `ok`: `code` is empty, the envelope `receipt` is absent, and `detail` is the JSON text of the matching `grant_ledger` rows, ordered by `applied_at` then `grant_id` ascending. Each row's `receipt` is the §1.6 receipt object. `readCoverageEvents` takes `after` and `limit`. A successful call is `ok`: `code` is empty, `receipt` is absent, and `detail` is the JSON text of `{after, events, next_after, has_more}`. Each event is `{event_id, feed_seq, org_id, installation_id, binding_epoch, clinic_seq, kind, at, snapshot}`, unsigned. The page contains events with `feed_seq` greater than `after`, in ascending `feed_seq`, at most `limit`. `next_after` is the last returned `feed_seq`, or `after` when the page is empty. `has_more` is true when a further event exists. A missing `limit`, or a `limit` outside 1 through 200, is `rejected` with `limit_invalid` and `detail` empty, and no events are returned. A `limit` of 200 is accepted. Results match `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/list-grants.md` and `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/read-coverage-events.md`. E2E-P3.3-07 passes. The Test plan assigns no E2E id to `listGrants` or to `limit_invalid`. Do not add one.

- [ ] T028 [US4] On apply, enqueue AL-11 and, when the velocity condition holds, AL-17, and send them from the alarm through `ai-platform/src/alert/index.ts` — produces the two grant alerts, satisfies FR-013, proved by E2E-P3.3-08. Depends on T027. The apply path is `ai-platform/src/quota-do/index.ts` and `ai-platform/src/vendor/entrypoint.ts`. AL-11 is raised once per grant. The body carries the decoded operation and its target; for a paid grant that target includes the org. More than 3 paid grants for one clinic in 24 hours, or more than 20 across all clinics in an hour, raises AL-17. The 4th paid grant for one clinic within 24 hours is that condition. The grant is still applied. AL-17's `next_send_at` is one hour ahead, and the repeat is hourly. `runFiveMinuteCron` retries a due AL-17 without changing the AL-20 path. E2E-P3.3-08 passes. The Test plan assigns no E2E id to the 20-grants-in-an-hour arm. Do not add one.

**Checkpoint**: E2E-P3.3-02 passes at T025. E2E-P3.3-07 passes at T027. E2E-P3.3-08 passes at T028. The "every earlier suite stays green" sentence on this story's Independent Test line is the review's run, not these tasks.

---

## 5. Verification

**Purpose**: The unit harness named in Test Layout passes. Earlier suites are the review's run (rule S2). This task does not name that run.

- [ ] T030 Run harness H-AP for this unit and confirm E2E-P3.3-01 through E2E-P3.3-12 pass together — produces the green run, satisfies FR-001 through FR-016 and SC-001, proved by E2E-P3.3-01 through E2E-P3.3-12. Depends on T013 through T029 (and therefore on T001–T012). `ai-platform/src/identity/index.ts`, `ai-platform/src/config-cache/index.ts`, `ai-platform/src/vendor/contract-version.ts`, and `packages/vendor-contracts/**` stay unchanged. The quota JSON blob and `/control/entitle` stay (rule S9). SC-002 is the review's run of earlier suites, not this command.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/paid-grant-coverage.system.test.ts
```

---

## 6. Documentation

**Purpose**: Written after T030 is green (rule S8). The plan leaves `quickstart.md` for implement. `data-model.md` and `contracts/` stay plan-phase artifacts. No other doc task.

- [ ] T031 Create `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, satisfies FR-001 through FR-016, proved by E2E-P3.3-01 through E2E-P3.3-12. Depends on T030. Sections: (1) what was implemented — paid `grant`, plan-version and service-key methods, the DO tables, the alarm ship, the calendar, and the coverage reads; (2) files this unit adds or modifies — the Files section of `plan.md`, with no earlier-unit files and no combined counts; (3) harness command for this unit's tests only — the command below; (4) how to inspect the change — read `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/quota-do/index.ts`, `GatewayObject.fetch` and `GatewayObject.alarm` in `ai-platform/src/worker.ts`, `ai-platform/src/coverage/calendar.ts`, `ai-platform/src/alert/index.ts`, `PLATFORM_SIGNING_KEY` and `DURATION_SCALE` in `ai-platform/wrangler.toml`, and the H-AP output; (5) the entry point → module chain per E2E id below. Every scenario is asserted by H-AP, so this file records harness commands only.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/paid-grant-coverage.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

| ID | Chain |
| --- | --- |
| E2E-P3.3-01 | `vendorCall` `publishPlanVersion` then `registerServiceKey` then `grant` → `src/vendor/entrypoint.ts` → binding insert → `GatewayObject.fetch` `apply_grant` → `src/coverage/calendar.ts` → `signCompactJws` |
| E2E-P3.3-02 | `vendorCall` `grant` twice → `runDurableObjectAlarm` → `GatewayObject.alarm` → `grant_ledger` |
| E2E-P3.3-03 | `vendorCall` `grant` with a changed allowance → DO `conflict` |
| E2E-P3.3-04 | `vendorCall` `grant` twice → `vendorCall` `getCoverage` → DO `read_coverage` |
| E2E-P3.3-05 | `vendorCall` `grant` with an unknown `kid`; `vendorCall` `revokeServiceKey` then `grant` |
| E2E-P3.3-06 | `vendorCall` `grant` for each named refusal |
| E2E-P3.3-07 | `vendorCall` `grant` → `runDurableObjectAlarm` → D1 and R2 → `vendorCall` `readCoverageEvents` |
| E2E-P3.3-08 | `vendorCall` `grant` → `runDurableObjectAlarm` → `src/alert/index.ts` AL-11; a fourth paid grant → AL-17 |
| E2E-P3.3-09 | `setTestClock` → `vendorCall` `grant` → `src/coverage/calendar.ts`; the 30-minute case sets `env.DURATION_SCALE` for that call only |
| E2E-P3.3-10 | `vendorCall` `retirePlanVersion` → `vendorCall` `grant` → existing `term.plan_snapshot` |
| E2E-P3.3-11 | `env.DO.get(env.DO.idFromName(...)).fetch` POST with `contract_version` 1 → `negotiate(CHANNEL_VERSIONS.platformDo)` → echoed `contract_version` |
| E2E-P3.3-12 | The same `fetch` with `contract_version` missing or 2 → `rejected` `contract_version_unsupported` before any DO write |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (T001–T012)**: No Setup phase. T001 starts immediately. It extends `VendorMethod`, then adds E2E-P3.3-01. The other tests append in Sequencing order and are observed failing before T013: T001, T002, T003, T004, T005, T006, T007, T008, T009, T010, T011, T012.
- **Implementation (T013–T029)**: Starts after T001–T012 exist and fail. Order is Sequencing: T013 through T029, including T021 under User Story 3 and T025, T026, T027, and T028 under User Stories 4 and 2.
- **Verification (T030)**: After every implementation task.
- **Documentation (T031)**: After T030 is green.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: T001 starts immediately. T002 and T003 append next. T005 waits on T004. T006 waits on T005. T009 waits on T008. T011 waits on T010. T012 waits on T011. Those tests do not wait on another story's implementation. T013 waits until T012 has added the last failing test. T014 through T020 follow in order. T022 waits on T021, because the grant checks read `plan_version`. T023 waits on T022. T024 waits on T023. T029 waits on T028, because Sequencing places the scale after the alerts. E2E-P3.3-11 and E2E-P3.3-12 pass at T016. E2E-P3.3-05 and E2E-P3.3-06 pass at T022. E2E-P3.3-01, E2E-P3.3-03, the unscaled half of E2E-P3.3-09, and E2E-P3.3-10 pass at T024. E2E-P3.3-09 passes at T029. E2E-P3.3-02 passes at T025.
- **User Story 2 (P2)**: T004 waits on T003 because both append to the same file. It does not wait on User Story 1's implementation. The spec says the queue is visible only after User Story 1 has placed an active term, so T026 waits on T024, and Sequencing also places it after T025. E2E-P3.3-04 passes at T026.
- **User Story 3 (P3)**: T010 waits on T009. That test does not wait on User Story 1's modules. T021 waits on T020. User Story 1's grant checks (T022) wait on T021, because Sequencing step 21 is the plan-version pair and step 22 is the grant. E2E-P3.3-10 passes at T024, when `apply_grant` leaves the existing term's `plan_snapshot` in place.
- **User Story 4 (P4)**: T007 waits on T006. T008 waits on T007. Those tests do not wait on another story's modules. The alarm ships records User Story 1 wrote, so T025 waits on T024. T027 waits on T026. T028 waits on T027. E2E-P3.3-02 passes at T025. E2E-P3.3-07 passes at T027. E2E-P3.3-08 passes at T028. The "every earlier suite stays green" sentence on this story's Independent Test line is Sequencing step 31, the review's run, not T030.

### 7.3 Parallel Opportunities

- T001–T012 are not `[P]`. They all write `ai-platform/test/system/paid-grant-coverage.system.test.ts`. T001 also writes `ai-platform/test/system/harness.ts`. A pair in another story is not parallel with these, because Sequencing appends every E2E to that one file.
- T013 writes the migration, `ai-platform/schema.snap.sql`, and `ai-platform/test/migrations.test.ts` as one step. T014 writes the harnesses and the listed test files and waits on T013. T015 writes `ai-platform/src/coverage/calendar.ts` and waits on T014. T016 writes `ai-platform/src/worker.ts` and the DO callers and waits on T015. Sequencing does not launch those steps together.
- T017 and T024 and T025 share `ai-platform/src/quota-do/index.ts`. T016, T025, and the alarm path share `ai-platform/src/worker.ts`. They stay in Sequencing order.
- T018 writes `ai-platform/wrangler.toml` and both vitest configs. T019, T020, T021, T022, T023, T026, and T027 share `ai-platform/src/vendor/entrypoint.ts`. T020 and T028 share `ai-platform/src/alert/index.ts`. T014 and T016 both edit `ai-platform/test/usage-summary.test.ts`; T016 waits until T014 has finished. T029 returns to `ai-platform/src/coverage/calendar.ts` after T015.
- T030 and T031 are single tasks. T031 waits until T030 is green.
- No task in this unit is `[P]`.

```bash
# Two User Story 1 test tasks. Both append to
# ai-platform/test/system/paid-grant-coverage.system.test.ts, so they are not [P].
# Sequencing writes T001, then T002.
Task: "T001 [US1] Add the failing test E2E-P3.3-01 in ai-platform/test/system/paid-grant-coverage.system.test.ts"
Task: "T002 [US1] Add the failing test E2E-P3.3-02 in ai-platform/test/system/paid-grant-coverage.system.test.ts"
```
