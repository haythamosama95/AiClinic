# Tasks: ABO skeleton, records layer, billing-token auth and catalogue reads

**Input**: Design documents from `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P2.2 (CP-A, `packages/vendor-contracts/` frozen). Plan artifacts from `AVAILABLE_DOCS`: `data-model.md`, `contracts/` (`contracts/clinic-api.md`). There is no `research.md` (**Spikes** is None). `data-model.md` and `contracts/clinic-api.md` are already written in plan; they are not implement tasks. `quickstart.md` is written in Documentation after verification.

**Organization**: Four user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`, `[US4]`). Tests are one task per E2E id in Sequencing steps 4–13, plus the wrangler clock test Test Layout names (step 14), written to fail before the gates, the catalogue, the exporter, and the alert engine exist. Titles start with the E2E id (rule V3), except the clock config test, whose title Test Layout sets without an E2E id. Nothing ships before P8 (rule S2). No Foundational phase. No Polish phase. Task ids follow plan Sequencing. Each Sequencing step is one task. The count is not padded (rule S3).

**Task count**: 30. Size L is 32–40 (rule S3). The count is Sequencing steps 1–30: scaffold, clock, and harness (1–3), ten E2E tests (4–13), the wrangler clock test (14), implementation (15–28), the H-ABO harness (29), and `quickstart.md` (30). It is not padded. `npm test` in other packages, and any command that runs more than `abo/test/system`, are not tasks.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`, `US4`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — this unit does not change it. DevDependency versions are copied from `ai-platform/package.json`
- **ABO**: `abo/` — the Files paths in `plan.md`
- **Shared package**: `packages/vendor-contracts/` — consumed and not modified
- **Spec Kit artifacts**: `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/`
- **CI**: `.github/workflows/ci.yml` — add job `abo-system` only
- Do not edit `packages/vendor-contracts/**`, `backend/`, `frontend/`, or `ai-platform/`. Do not add checkouts, offer publication, erasure, the operator console, notification intake, the pipeline, provider adapters, or reconciliation matching.

---

## 3. Setup

**Purpose**: Sequencing steps 1–3. The `abo/` Worker does not exist yet. These tasks exist so H-ABO can run and the tests in Phase 4 fail before the gates, the catalogue, the exporter, and the alert engine exist.

### 3.1 Scaffold, clock, and harness

- [X] T001 [US1] Add the `abo/` package scaffold and a stub worker — produces the Worker project, FR-001, FR-002, FR-010, E2E-P4.1-01. Depends on nothing. Files: `abo/package.json`, `abo/package-lock.json`, `abo/tsconfig.json`, `abo/wrangler.toml`, `abo/vitest.workers.config.ts`, `abo/src/worker.ts`. `package.json` depends on `vendor-contracts` at `file:../packages/vendor-contracts` and uses the same devDependency versions as `ai-platform/package.json`. Script `test` is `vitest run --config vitest.workers.config.ts test/system`. Generate `abo/package-lock.json` from that manifest. `tsconfig.json` is TypeScript ESM for the Workers runtime. `wrangler.toml`: `name` `abo`, `main` `src/worker.ts`, `compatibility_date` `2026-05-03`, `workers_dev = false`, `preview_urls = false`, `[observability] enabled = true`. Envs `development`, `staging`, and `production`. Each env binds D1 `DB`, R2 `R2`, and `send_email` `SEND_EMAIL` with `destination_address` `alerts@clinic.invalid`. Vars: `BILLING_HOST` `billing.vendor.test`, `OPS_HOST` `ops.vendor.test`, `HEARTBEAT_URL` `https://heartbeat.test/ping`, `ALERT_EMAIL_TO` `alerts@clinic.invalid`, `ISSUER_ID` `issuer-test`, `ISSUER_KEYS` `[]`, `CLOUDFLARE_ACCOUNT_ID`, `R2_BUCKET_NAME`. `R2_LOCK_READ_TOKEN` is a secret name on staging and production and a vitest binding in development tests. Crons on every env: `* * * * *`, `0 * * * *`, `0 */6 * * *`, `0 6 * * *`. No env's wrangler text contains `TEST_CLOCK`. `vitest.workers.config.ts` sets `wrangler.environment` to `development`, binds `TEST_CLOCK` to `"1"`, and includes `test/system/**/*.system.test.ts`. `abo/src/worker.ts` exports `fetch` and `scheduled`. `fetch` returns HTTP 404 with a non-empty body. `scheduled` does nothing.

- [X] T002 [US4] Add `abo/src/clock.ts` — produces the ABO clock, FR-010, E2E-P4.1-08, E2E-P4.1-10. Depends on T001. `clockNowMs` and `clockNowIso`. When `TEST_CLOCK` is `"1"`, read `harness_test_clock.now_iso` for `id` `default`. Otherwise use `Date.now()`. A missing table returns `Date.now()`.

- [X] T003 [US1] Add `abo/test/system/harness.ts` — produces H-ABO helpers, FR-004, FR-009, FR-010, E2E-P4.1-02, E2E-P4.1-08, E2E-P4.1-10. Depends on T002. Billing and ops `SELF.fetch` helpers, `createIssuer` mint helpers (`mintBilling`, `mintAi`), D1 `applySql` / migration apply, R2 get/put helpers, `runScheduled(cron)`, `send_email` capture and a fail switch, heartbeat fetch capture, and the lock-rules GET with the default body. `setLockRulesBody` replaces that body for one scenario. `pinIssuer` inserts into `harness_issuer_pin`. `setClock` writes `harness_test_clock`. Hosts are `billing.vendor.test` and `ops.vendor.test`. The lock GET is `GET https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/r2/buckets/{R2_BUCKET_NAME}/lock`. Unless a test sets another body, the body is `{"success":true,"result":{"rules":[{"enabled":true,"condition":{"type":"Indefinite"},"prefix":"ledger/"}]}}`.

**Checkpoint**: The stub worker and H-ABO helpers exist. Catalogue behavior is still absent.

---

## 4. Tests

**Purpose**: Sequencing steps 4–14. One failing test per E2E id, then the clock config test. Story sections follow that order. E2E-P4.1-01 through E2E-P4.1-10 are added to `abo/test/system/catalogue.system.test.ts`. The clock test is added to `abo/test/system/wrangler-clock.system.test.ts`. Both run under `abo/vitest.workers.config.ts`. No scenario sleeps more than 2 s (rule V4). Time moves with `setClock` through `abo/src/clock.ts`.

```bash
cd abo && npx vitest run --config vitest.workers.config.ts test/system
```

### 4.1 User Story 1 - Gate clinic calls with version and billing token (Priority: P1) (part 1)

**Independent Test**: E2E-P4.1-01, E2E-P4.1-02, and E2E-P4.1-09 in harness H-ABO.

- [X] T004 [US1] Add the failing test `E2E-P4.1-01 missing or unsupported Abo-Contract-Version is 400 before auth` in `abo/test/system/catalogue.system.test.ts` — red test, FR-003, E2E-P4.1-01. Depends on T003. `SELF.fetch` `/v1/offers` on the billing host and `/ops/lookup` on the ops host, each with an invalid bearer and no `Abo-Contract-Version`, then again with `Abo-Contract-Version: 2`. Both are HTTP 400 `contract_version_unsupported`. Body is `{code, message, contract_version, accepted_versions}` with `contract_version` 1 and `accepted_versions` `[0, 1]`. Response header `Abo-Contract-Version` is `1`. `token_use` and `billing_contact` stay unchanged. The harness command fails because the response is not 400 `contract_version_unsupported`.

- [X] T005 [US1] Add the failing test `E2E-P4.1-02 AI token and unpinned kid are 401 and doctor is 403` in `abo/test/system/catalogue.system.test.ts` — red test, FR-004, E2E-P4.1-02. Depends on T004 (same file). Header `Abo-Contract-Version: 1` on the billing host. `mintAi` → 401 `unauthenticated`. `mintBilling` from an issuer whose kid is not in `harness_issuer_pin` → 401 `unauthenticated`. `mintBilling` with `role` `doctor` on a pinned kid → 403 `forbidden_role`. The harness command fails because the three tokens are not refused as specified.

**Checkpoint**: E2E-P4.1-01 and E2E-P4.1-02 exist and fail.

### 4.2 User Story 2 - Keep billing routes and ops routes on their hosts (Priority: P2)

**Independent Test**: E2E-P4.1-06 in harness H-ABO.

- [X] T006 [US2] Add the failing test `E2E-P4.1-06 cross-host paths are 404 before version and auth` in `abo/test/system/catalogue.system.test.ts` — red test, FR-002, E2E-P4.1-06. Depends on T005 (same file). `/ops/lookup` on the billing host and `/v1/offers` on the ops host → HTTP 404, empty body, no `Abo-Contract-Version` response header. A missing version header on those crossings still yields that 404. No D1 write. The harness command fails because the crossings are not an empty 404.

**Checkpoint**: E2E-P4.1-06 exists and fails.

### 4.3 User Story 1 - Gate clinic calls with version and billing token (Priority: P1) (part 2)

**Independent Test**: E2E-P4.1-01, E2E-P4.1-02, and E2E-P4.1-09 in harness H-ABO.

- [X] T007 [US1] Add the failing test `E2E-P4.1-09 the 61st request with one billing token is 429` in `abo/test/system/catalogue.system.test.ts` — red test, FR-005, E2E-P4.1-09. Depends on T006 (same file). The same pinned administrator token on `GET /v1/offers` is accepted 60 times. The 61st is HTTP 429 `rate_limited`. `token_use.hits` stays 60. The harness command fails because the 61st request is not 429.

**Checkpoint**: E2E-P4.1-01, E2E-P4.1-02, and E2E-P4.1-09 exist and fail.

### 4.4 User Story 3 - Read sellable offers and keep a billing contact (Priority: P3)

**Independent Test**: E2E-P4.1-03, E2E-P4.1-04, and E2E-P4.1-05 in harness H-ABO.

- [X] T008 [US3] Add the failing test `E2E-P4.1-03 GET offers lists the sellable latest version and echoes version 1` in `abo/test/system/catalogue.system.test.ts` — red test, FR-003, FR-006, E2E-P4.1-03. Depends on T007 (same file). After the fixture, `GET /v1/offers` returns the published offer's latest version, `plan_display_name`, terms `version` and text, and omits the retired offer and the older price. Response header `Abo-Contract-Version` is `1` and body `contract_version` is `1`. The harness command fails because `GET /v1/offers` does not list the sellable version.

- [X] T009 [US3] Add the failing test `E2E-P4.1-04 PUT billing contact is idempotent and rejects a non-E.164 phone` in `abo/test/system/catalogue.system.test.ts` — red test, FR-007, E2E-P4.1-04. Depends on T008 (same file). Two `PUT`s with the same `client_request_id` leave one row at version 1. A new `client_request_id` creates version 2. Phone `12345` → 422 `invalid_request` and does not insert a version. The harness command fails because the contact versions and the 422 are absent.

- [X] T010 [US3] Add the failing test `E2E-P4.1-05 tenant B does not receive tenant A contact` in `abo/test/system/catalogue.system.test.ts` — red test, FR-007, E2E-P4.1-05. Depends on T009 (same file). After A has a contact, B's `GET` is `not_found`. B's `PUT` whose body includes A's `org` stores B's `org` from the token. A's `GET` still returns A's contact. The harness command fails because tenant isolation is absent.

**Checkpoint**: E2E-P4.1-03, E2E-P4.1-04, and E2E-P4.1-05 exist and fail.

### 4.5 User Story 4 - Export facts, raise AL-16, and ping the heartbeat (Priority: P4)

**Independent Test**: E2E-P4.1-07, E2E-P4.1-08, and E2E-P4.1-10 in harness H-ABO. E2E-P4.1-01 through E2E-P4.1-06 and E2E-P4.1-09 still pass.

- [ ] T011 [US4] Add the failing test `E2E-P4.1-07 append-only rejects update and delete and the minute cron exports facts` in `abo/test/system/catalogue.system.test.ts` — red test, FR-008, E2E-P4.1-07. Depends on T010 (same file). `UPDATE` and `DELETE` on `offer` abort. An append insert has one `fact_log` row. `runScheduled("* * * * *")` writes R2 `ledger/<fact_seq>.ndjson` in `fact_seq` order, one JSON line, and the object text has no `name`, `email`, or `phone`. The harness command fails because UPDATE/DELETE are not aborted and `ledger/` is empty.

- [ ] T012 [US4] Add the failing test `E2E-P4.1-08 export lag raises AL-16 once then daily and a failed send is retried` in `abo/test/system/catalogue.system.test.ts` — red test, FR-009, E2E-P4.1-08. Depends on T011 (same file). With the default lock body, advance the clock more than one hour past an unexported fact and run the minute cron: one AL-16 email whose body is the code and that `fact_seq`. Advance the clock 24 hours and run the minute cron again: a second email. A `send_email` failure leaves the alert due; the next minute run sends it. The daily cron with the default lock body does not send a lock AL-16. The daily cron with `{"success":true,"result":{"rules":[]}}` sends a lock AL-16 whose body is the code and `r2-lock`. A non-success lock response sends no lock AL-16. The harness command fails because AL-16 is not sent.

- [ ] T013 [US4] Add the failing test `E2E-P4.1-10 minute cron pings the heartbeat URL` in `abo/test/system/catalogue.system.test.ts` — red test, FR-010, E2E-P4.1-10. Depends on T012 (same file). `runScheduled("* * * * *")` performs one outbound fetch to `HEARTBEAT_URL`. The harness command fails because the heartbeat URL is not fetched.

- [ ] T014 [US4] Add `P4.1 production and staging wrangler envs carry no TEST_CLOCK` in `abo/test/system/wrangler-clock.system.test.ts` — red-suite test, FR-010. Depends on T013. It reads `abo/wrangler.toml` and asserts the `[env.production]` and `[env.staging]` text do not contain `TEST_CLOCK`. Test Layout names this file and does not assign it an E2E id. Run the harness command. E2E-P4.1-01 through E2E-P4.1-10 still fail. This config assertion matches the wrangler text from T001.

**Checkpoint**: E2E-P4.1-07, E2E-P4.1-08, and E2E-P4.1-10 exist and fail. The wrangler clock test exists. E2E-P4.1-01 through E2E-P4.1-06 and E2E-P4.1-09 still fail.

---

## 5. Implementation

**Purpose**: Sequencing steps 15–28. Each step starts after T004–T014 exist and the ten E2E tests fail. Within a subphase the tasks run in id order. `packages/vendor-contracts/**` stays unchanged. Hourly and 6-hourly crons stay declared and do no other job.

### 5.1 User Story 2 - Keep billing routes and ops routes on their hosts (Priority: P2)

**Independent Test**: E2E-P4.1-06 in harness H-ABO.

- [ ] T015 [US2] Reject cross-host paths in `abo/src/worker.ts` — produces the host gate, FR-002, E2E-P4.1-06. Depends on T014. Resolve the host from the `Host` header against `BILLING_HOST` and `OPS_HOST`. The billing host accepts `/v1/`, `/notify/`, and `/return/`. The ops host accepts `/ops/`. `/ops/` on the billing host and `/v1/` on the ops host return HTTP 404 with an empty body and perform no version check, no auth, and no write. Any other path on the matching host returns the same empty 404 in this unit.

### 5.2 User Story 1 - Gate clinic calls with version and billing token (Priority: P1)

**Independent Test**: E2E-P4.1-01, E2E-P4.1-02, and E2E-P4.1-09 in harness H-ABO.

- [ ] T016 [US1] Check `Abo-Contract-Version` in `abo/src/clinic-api/version.ts` — produces the version refusal, FR-003, E2E-P4.1-01, E2E-P4.1-03. Depends on T015. Also edit `abo/src/worker.ts` so `/v1/` and `/ops/` call this module only after the host gate. On `/v1/` and `/ops/` only, parse `Abo-Contract-Version`. Missing or non-integer becomes `null`. Current N is `CHANNEL_VERSIONS.aboClinic` for `/v1/` and `CHANNEL_VERSIONS.aboConsole` for `/ops/` (both 1). Call `negotiate`. On failure respond 400 with `code` `contract_version_unsupported`, `message` `contract_version_unsupported`, `contract_version` N, `accepted_versions` from `acceptedVersions(N)`, and header `Abo-Contract-Version` N. Write nothing. A successful response echoes the request version on header `Abo-Contract-Version` and in `contract_version`.

- [ ] T017 [US1] Verify the billing token in `abo/src/clinic-api/auth.ts` — produces token refusal, FR-004, E2E-P4.1-02. Depends on T016. Also edit `abo/src/worker.ts` so `/v1/` calls this module after the version gate. Read `kid` from the JWT header. Load pins from `harness_issuer_pin` when `TEST_CLOCK` is `"1"` and that table has rows; otherwise parse `ISSUER_KEYS` as `{kid, public_key}[]` (`public_key` is base64url of the raw 32-byte Ed25519 key). An unknown `kid` is 401 `unauthenticated`. Import the pinned key and call `validateTokenClaims` with `audience` `"abo"` and `issuerId` `ISSUER_ID`. `ok: true` accepts the token. On `ok: false`, verify the Ed25519 signature over the 04 §2.1 signing input with that pinned key. A bad signature is 401. A good signature with `aud` other than `abo`, `ver` other than `"2"`, or `exp - iat` outside 0..300 is 401. A good signature whose `role` is not `administrator` is 403 `forbidden_role`. Any other failure is 401. Do not fetch keys from the platform. H-ABO mints tokens with `createIssuer` from the frozen testkit.

- [ ] T018 [US1] Count token use in `abo/src/clinic-api/rate.ts` — produces the 60-request cap, FR-005, E2E-P4.1-09. Depends on T017. Also edit `abo/src/worker.ts` so a token that `auth.ts` accepted calls this module before catalogue handlers. If `token_use.hits` for that `jti` is already 60, respond 429 `rate_limited` and leave the row at 60. Otherwise increment `hits` and continue. The version refusal and the 401/403 paths do not write `token_use`.

### 5.3 User Story 4 - Export facts, raise AL-16, and ping the heartbeat (Priority: P4) (part 1)

**Independent Test**: E2E-P4.1-07, E2E-P4.1-08, and E2E-P4.1-10 in harness H-ABO. E2E-P4.1-01 through E2E-P4.1-06 and E2E-P4.1-09 still pass.

- [ ] T019 [US4] Add `abo/migrations/0001_records.sql` — produces the D1 tables, keys, indexes, and abort triggers, FR-006, FR-007, FR-008, FR-009, E2E-P4.1-03, E2E-P4.1-04, E2E-P4.1-07, E2E-P4.1-08, E2E-P4.1-09. Depends on T018. Tables, keys, indexes, and abort triggers are those in `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/data-model.md`, including `token_use` for T018. The harness applies this file before catalogue tests.

- [ ] T020 [US4] Append facts in `abo/src/records/append.ts` — produces the append-only insert, FR-008, E2E-P4.1-07. Depends on T019. Insert one append-only row and one `fact_log` row in a single D1 batch. `row_sha256` is `sha256Hex(canonicalize(row))`. `created_at` is `clockNowIso`. Ids that the spec calls ULIDs use `ulid(clockNowMs(), 10 random bytes)`.

### 5.4 User Story 3 - Read sellable offers and keep a billing contact (Priority: P3) (part 1)

**Independent Test**: E2E-P4.1-03, E2E-P4.1-04, and E2E-P4.1-05 in harness H-ABO.

- [ ] T021 [US3] List sellable offers from `abo/fixtures/offers.json` and `abo/src/clinic-api/offers.ts` — produces the offers read, FR-006, E2E-P4.1-03. Depends on T020. Do not edit `abo/src/worker.ts` in this task. The harness loads the fixture through `append.ts` and puts the terms text in R2 at `text_r2_key`. `GET /v1/offers` returns the shape in `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/contracts/clinic-api.md`. `plan_display_name` is `copy.en.name`. Terms `text` is the R2 object decoded as UTF-8. A retired offer is absent. T027 connects this module from `fetch`.

### 5.5 User Story 3 - Read sellable offers and keep a billing contact (Priority: P3) (part 2)

**Independent Test**: E2E-P4.1-03, E2E-P4.1-04, and E2E-P4.1-05 in harness H-ABO.

- [ ] T022 [US3] Read and replace the billing contact in `abo/src/clinic-api/billing-contact.ts` — produces contact versions, FR-007, E2E-P4.1-04, E2E-P4.1-05. Depends on T020. Do not edit `abo/src/worker.ts` in this task. `GET` and `PUT` follow `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/contracts/clinic-api.md`. `contact_sha256` is `sha256Hex(canonicalize({name, email, phone}))`. E.164 is `^\+[1-9][0-9]{1,14}$`. The same `client_request_id` for one `org_id` returns the stored version and does not insert. `created_by_sub` is the token `sub`. `contract_version` on the row is the accepted request version. The tenant is the token `org`. An `org` in the body is ignored. `GET` when the tenant has no contact returns `not_found`. T027 connects this module from `fetch`.

### 5.6 User Story 4 - Export facts, raise AL-16, and ping the heartbeat (Priority: P4) (part 2)

**Independent Test**: E2E-P4.1-07, E2E-P4.1-08, and E2E-P4.1-10 in harness H-ABO. E2E-P4.1-01 through E2E-P4.1-06 and E2E-P4.1-09 still pass.

- [ ] T023 [US4] Export facts in `abo/src/records/export.ts` — produces the minute ledger copy, FR-008, E2E-P4.1-07. Depends on T020. The minute cron selects `fact_log` rows with no `fact_export` row, ascending `fact_seq`, and puts each at `ledger/<fact_seq>.ndjson` as one JSON line of `{fact_seq, table, key, row_sha256}`. Then it inserts `fact_export`. A failed put stops the run so a later `fact_seq` is not written first. Objects contain no contact values. T027 calls this from the minute cron.

- [ ] T024 [US4] Send alerts in `abo/src/alert/index.ts` — produces dedupe, send, and retry, FR-009, E2E-P4.1-08. Depends on T019. One `alert` row per `alert_key`. A due row is sent through `SEND_EMAIL` to `ALERT_EMAIL_TO`. The body is the code and the ids named in `data-model.md`, with no contact values. Success sets `last_sent_at` and `next_send_at` 24 hours later. A thrown send leaves `unsent` at 1 so the next scheduled run retries.

- [ ] T025 [US4] Mark export lag due in `abo/src/alert/index.ts` — produces the stall condition, FR-009, E2E-P4.1-08. Depends on T024 (same file). On the minute cron, after export, if the oldest unexported `fact_log.created_at` is more than one hour before `clockNowMs`, mark `AL-16:export-lag` due. When no such fact remains, set that row `active` 0 so it is not sent again. T027 calls this after export.

- [ ] T026 [US4] Read the bucket lock in `abo/src/alert/lock.ts` — produces the daily lock check, FR-009, E2E-P4.1-08. Depends on T024. Do not edit `abo/src/worker.ts` in this task. GET `https://api.cloudflare.com/client/v4/accounts/{account_id}/r2/buckets/{bucket_name}/lock` with `Authorization: Bearer` and `R2_LOCK_READ_TOKEN`. `account_id` is `CLOUDFLARE_ACCOUNT_ID`. `bucket_name` is `R2_BUCKET_NAME`. The Worker sends no other method to that URL. The lock is present when `success` is true and `result.rules` contains an enabled rule whose `condition.type` is `Indefinite` and whose `prefix` is `ledger/` or `""`. Present clears `AL-16:r2-lock` (`active` 0). `success` true with no such rule marks that alert due. Any other outcome, including a thrown fetch, changes nothing about that alert. T027 calls this from the daily cron only.

- [ ] T027 [US4] Dispatch `fetch` catalogue routes and `scheduled` in `abo/src/worker.ts` — produces the live entry chains, FR-001, FR-006, FR-007, FR-008, FR-009, FR-010, E2E-P4.1-03, E2E-P4.1-04, E2E-P4.1-05, E2E-P4.1-07, E2E-P4.1-08, E2E-P4.1-10. Depends on T021, T022, T023, T024, T025, and T026. After the rate gate, `GET /v1/offers` calls `offers.ts`, and `GET`/`PUT /v1/billing-contact` calls `billing-contact.ts`. The minute cron, after export and the lag check, pings `HEARTBEAT_URL` with `fetch` and then sends due alerts. The daily cron `0 6 * * *` runs the lock check and then sends due alerts. `0 * * * *` and `0 */6 * * *` return without export, lock, alert, or heartbeat work.

### 5.7 User Story 4 - Export facts, raise AL-16, and ping the heartbeat (Priority: P4) (part 3)

**Independent Test**: E2E-P4.1-07, E2E-P4.1-08, and E2E-P4.1-10 in harness H-ABO. E2E-P4.1-01 through E2E-P4.1-06 and E2E-P4.1-09 still pass.

- [ ] T028 [US4] Add job `abo-system` to `.github/workflows/ci.yml` — produces the ABO system CI job, FR-010, E2E-P4.1-10. Depends on T027. `ubuntu-latest`, `working-directory: abo`, Node 22, `npm ci`, `npm test`. Leave the existing jobs in that file unchanged.

---

## 6. Verification

**Purpose**: Sequencing step 29. The harness command in Test Layout passes. This command is the harness for this unit. A repository-root `npm test`, and `npm test` in any other package, are not tasks.

### 6.1 Unit harness

**Independent Test**: E2E-P4.1-07, E2E-P4.1-08, and E2E-P4.1-10 in harness H-ABO. E2E-P4.1-01 through E2E-P4.1-06 and E2E-P4.1-09 still pass.

- [ ] T029 [US4] Run harness H-ABO and confirm E2E-P4.1-01 through E2E-P4.1-10 and the wrangler clock test pass — produces the green `abo/test/system` suite, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, E2E-P4.1-01, E2E-P4.1-02, E2E-P4.1-03, E2E-P4.1-04, E2E-P4.1-05, E2E-P4.1-06, E2E-P4.1-07, E2E-P4.1-08, E2E-P4.1-09, E2E-P4.1-10. Depends on T015 through T028 (and therefore on T001–T014). This task may edit only files under `abo/test/system/`. `packages/vendor-contracts/**` stays unchanged.

```bash
cd abo && npx vitest run --config vitest.workers.config.ts test/system
```

**Checkpoint**: E2E-P4.1-01 through E2E-P4.1-10 and `P4.1 production and staging wrangler envs carry no TEST_CLOCK` pass.

---

## 7. Documentation

**Purpose**: Sequencing step 30. Written after T029 is green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md`, `data-model.md`, or `contracts/` task.

### 7.1 Quickstart

- [ ] T030 Create `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001 through FR-010, E2E-P4.1-01 through E2E-P4.1-10. Depends on T029. Sections: (1) what was implemented — the `abo/` Worker: host gate, contract version, billing-token auth, `GET /v1/offers`, `GET`/`PUT /v1/billing-contact`, records export, AL-16, and the heartbeat; (2) files this unit adds or modifies — the Files section of `plan.md`; (3) the harness command below; (4) the entry point → module chain per E2E id below. `npm test` in other packages, and any command that runs more than `abo/test/system`, stay out of this file (rule S8).

```bash
cd abo && npx vitest run --config vitest.workers.config.ts test/system
```

| ID | Chain |
| --- | --- |
| E2E-P4.1-01 | `SELF.fetch` → `worker.ts` host gate → `clinic-api/version.ts` (`negotiate`) → 400 body. No auth module and no D1 write. |
| E2E-P4.1-02 | `SELF.fetch` → host gate → version gate → `clinic-api/auth.ts` (`validateTokenClaims`, pinned `ISSUER_KEYS`) → 401 or 403. |
| E2E-P4.1-03 | `SELF.fetch` `GET /v1/offers` → host, version, auth, `clinic-api/rate.ts` → `clinic-api/offers.ts` → D1 sellable rows → R2 terms text. |
| E2E-P4.1-04 | `SELF.fetch` `PUT /v1/billing-contact` → the same gate → `clinic-api/billing-contact.ts` → D1 `billing_contact`. |
| E2E-P4.1-05 | `SELF.fetch` `GET`/`PUT /v1/billing-contact` → the same gate → `billing-contact.ts` filtered by the token `org`. |
| E2E-P4.1-06 | `SELF.fetch` → `worker.ts` host gate → 404 empty body. Version and auth do not run. |
| E2E-P4.1-07 | D1 `UPDATE`/`DELETE` hit the abort triggers. `records/append.ts` writes `fact_log`. `runScheduled` minute → `records/export.ts` → R2 `ledger/<fact_seq>.ndjson`. |
| E2E-P4.1-08 | `runScheduled` → `clock.ts` → `alert/index.ts` export-lag and `alert/lock.ts` GET → `SEND_EMAIL` capture. |
| E2E-P4.1-09 | `SELF.fetch` → host, version, auth → `clinic-api/rate.ts` → 429 when `token_use.hits` is 60. |
| E2E-P4.1-10 | `runScheduled` minute → `worker.ts` → outbound fetch to `HEARTBEAT_URL`. |

---

## 8. Dependencies & Execution Order

### 8.1 Phase Dependencies

- **Setup (Phase 3)**: No dependencies. T001, then T002, then T003. The stub `fetch` and `scheduled` exist before any test.
- **Tests (Phase 4)**: Depend on T003. Order is E2E-P4.1-01, E2E-P4.1-02, E2E-P4.1-06, E2E-P4.1-09, E2E-P4.1-03, E2E-P4.1-04, E2E-P4.1-05, E2E-P4.1-07, E2E-P4.1-08, E2E-P4.1-10, then the wrangler clock test. T004–T013 all write `abo/test/system/catalogue.system.test.ts`. T014 writes `abo/test/system/wrangler-clock.system.test.ts` after T013.
- **Implementation (Phase 5)**: Starts after T014, with the ten E2E tests failing. Host gate, then version, auth, and rate, then the migration and append writer, then offers and billing contact, then export, the alert engine, the lag mark, the lock GET, scheduled dispatch, then the CI job.
- **Verification (Phase 6)**: Depends on T028. Runs only `cd abo && npx vitest run --config vitest.workers.config.ts test/system`.
- **Documentation (Phase 7)**: Depends on T029 being green.

### 8.2 User Story Dependencies

- **User Story 1 (P1)**: Tests T004, T005, and T007. Implementation T016, T017, and T018 after the host gate. E2E-P4.1-01, E2E-P4.1-02, and E2E-P4.1-09.
- **User Story 2 (P2)**: Test T006 after T005, because it writes the same catalogue file. Implementation T015 is the first behavior after the tests, before the version gate. E2E-P4.1-06.
- **User Story 3 (P3)**: Tests T008, T009, and T010 after T007. Implementation T021 and T022 after T020. Both follow append. T021 writes `abo/fixtures/offers.json` and `abo/src/clinic-api/offers.ts`. T022 writes `abo/src/clinic-api/billing-contact.ts`. Neither writes `abo/src/worker.ts`. T027 connects both from `fetch`. E2E-P4.1-03, E2E-P4.1-04, and E2E-P4.1-05.
- **User Story 4 (P4)**: Tests T011, T012, T013, and T014. Implementation T019, T020, T023, T024, T025, T026, T027, and T028. T023 writes `abo/src/records/export.ts`. T024 and T025 write `abo/src/alert/index.ts` in that order. T026 writes `abo/src/alert/lock.ts`. T027 writes `abo/src/worker.ts` after those modules exist. E2E-P4.1-07, E2E-P4.1-08, and E2E-P4.1-10, with E2E-P4.1-01 through E2E-P4.1-06 and E2E-P4.1-09 still passing.

### 8.3 Within Each Phase

- T001 writes the package, wrangler, vitest config, and stub `abo/src/worker.ts` before T002 reads `TEST_CLOCK`.
- T003 writes `abo/test/system/harness.ts` after `abo/src/clock.ts`.
- T004 through T013 stay in id order in `abo/test/system/catalogue.system.test.ts`.
- T015, T016, T017, T018, and T027 all write `abo/src/worker.ts`, in that id order. T016 also writes `abo/src/clinic-api/version.ts`. T017 also writes `abo/src/clinic-api/auth.ts`. T018 also writes `abo/src/clinic-api/rate.ts`.
- T019 writes `abo/migrations/0001_records.sql` before T020 writes `abo/src/records/append.ts`.
- T025 follows T024 on `abo/src/alert/index.ts`. T027 follows T023, T025, and T026.
- T028 writes only `.github/workflows/ci.yml` after T027.
- T029 runs after T028 and may edit only `abo/test/system/`.
- T030 writes only `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/quickstart.md` after T029 is green.

---

## 9. Implementation Waves

### 9.1 Wave 1

- T001–T003 — subphase: `### 3.1 Scaffold, clock, and harness` — paths: `abo/package.json`, `abo/package-lock.json`, `abo/tsconfig.json`, `abo/wrangler.toml`, `abo/vitest.workers.config.ts`, `abo/src/worker.ts`, `abo/src/clock.ts`, `abo/test/system/harness.ts`

### 9.2 Wave 2

- T004–T005 [US1] — subphase: `### 4.1 User Story 1 - Gate clinic calls with version and billing token (Priority: P1) (part 1)` — paths: `abo/test/system/catalogue.system.test.ts`

### 9.3 Wave 3

- T006 [US2] — subphase: `### 4.2 User Story 2 - Keep billing routes and ops routes on their hosts (Priority: P2)` — paths: `abo/test/system/catalogue.system.test.ts`

### 9.4 Wave 4

- T007 [US1] — subphase: `### 4.3 User Story 1 - Gate clinic calls with version and billing token (Priority: P1) (part 2)` — paths: `abo/test/system/catalogue.system.test.ts`

### 9.5 Wave 5

- T008–T010 [US3] — subphase: `### 4.4 User Story 3 - Read sellable offers and keep a billing contact (Priority: P3)` — paths: `abo/test/system/catalogue.system.test.ts`

### 9.6 Wave 6

- T011–T014 [US4] — subphase: `### 4.5 User Story 4 - Export facts, raise AL-16, and ping the heartbeat (Priority: P4)` — paths: `abo/test/system/catalogue.system.test.ts`, `abo/test/system/wrangler-clock.system.test.ts`

### 9.7 Wave 7

- T015 [US2] — subphase: `### 5.1 User Story 2 - Keep billing routes and ops routes on their hosts (Priority: P2)` — paths: `abo/src/worker.ts`

### 9.8 Wave 8

- T016–T018 [US1] — subphase: `### 5.2 User Story 1 - Gate clinic calls with version and billing token (Priority: P1)` — paths: `abo/src/worker.ts`, `abo/src/clinic-api/version.ts`, `abo/src/clinic-api/auth.ts`, `abo/src/clinic-api/rate.ts`

### 9.9 Wave 9

- T019–T020 [US4] — subphase: `### 5.3 User Story 4 - Export facts, raise AL-16, and ping the heartbeat (Priority: P4) (part 1)` — paths: `abo/migrations/0001_records.sql`, `abo/src/records/append.ts`

### 9.10 Wave 10

- T021 [US3] — subphase: `### 5.4 User Story 3 - Read sellable offers and keep a billing contact (Priority: P3) (part 1)` — paths: `abo/fixtures/offers.json`, `abo/src/clinic-api/offers.ts`
- T022 [US3] — subphase: `### 5.5 User Story 3 - Read sellable offers and keep a billing contact (Priority: P3) (part 2)` — paths: `abo/src/clinic-api/billing-contact.ts`

### 9.11 Wave 11

- T023–T027 [US4] — subphase: `### 5.6 User Story 4 - Export facts, raise AL-16, and ping the heartbeat (Priority: P4) (part 2)` — paths: `abo/src/records/export.ts`, `abo/src/alert/index.ts`, `abo/src/alert/lock.ts`, `abo/src/worker.ts`

### 9.12 Wave 12

- T028 [US4] — subphase: `### 5.7 User Story 4 - Export facts, raise AL-16, and ping the heartbeat (Priority: P4) (part 3)` — paths: `.github/workflows/ci.yml`

### 9.13 Wave 13

- T029 [US4] — subphase: `### 6.1 Unit harness` — paths: `abo/test/system/`

### 9.14 Wave 14

- T030 — subphase: `### 7.1 Quickstart` — paths: `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/quickstart.md`
