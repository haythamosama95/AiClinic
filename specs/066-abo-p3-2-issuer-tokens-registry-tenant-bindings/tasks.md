# Tasks: Issuer tokens, issuer-key registry and tenant bindings

**Input**: Design documents from `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `data-model.md`, `contracts/` (`AVAILABLE_DOCS`: `data-model.md`, `contracts/`). There is no `research.md`. `quickstart.md` is written in Documentation after verification.

**Organization**: Three user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`). Tests are one task per E2E id in the spec Test plan, written to fail before `registerIssuerKey` and `IssuerTokenVerifier` exist. Test Layout names no extra test. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase: the worker already exists. No Foundational phase (the prerequisite is P3.1, already merged, listed in Consumes Binding). No Polish phase. Task ids follow plan Sequencing. Sequencing step 25 is the review's earlier-suite run and is not a task.

**Task count**: 25. Size M is 20–32 (rule S3). The count is eight E2E tasks (Sequencing steps 1–8), fifteen implementation steps (9–23), one verification task (step 24, this unit's harness only), and `quickstart.md` (step 26). It is not padded.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — the migration, `schema.snap.sql`, `src/vendor/entrypoint.ts`, `src/alert/index.ts`, `src/identity/index.ts`, `src/config-cache/index.ts`, `src/discovery/index.ts`, `src/journal/index.ts`, `src/worker.ts`, `src/usage-summary/index.ts`, `src/control/lifecycle.ts`, `src/control/index.ts`, `src/retention/index.ts`, `src/platform-vocabulary.ts`, `wrangler.toml`, both vitest configs, H-AP `test/system/`, and the e2e harness and stage files named in the tasks below
- **ABO**: `abo/` — this unit does not change it
- **Shared package**: `packages/vendor-contracts/` — consumed and not modified (rule S7)
- **Full-stack harness**: `e2e/fullstack/` — this unit does not change it
- **Spec Kit artifacts**: `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/`
- This unit's Files section names the `ai-platform` paths above and `quickstart.md`. `data-model.md` and `contracts/` stay plan-phase artifacts. `src/admission/index.ts`, `src/capability/index.ts`, `src/entitlement/index.ts`, `src/control/token-contract.ts`, `src/alert/email.ts`, `src/clock.ts`, `migrations/20260731120000_platform_schema.sql`, and `migrations/20260803120000_token_contract.sql` stay as they are. `/control/entitle` stays (rule S9).

---

## 3. Tests

**Purpose**: One failing test per E2E id, under H-AP, in Sequencing order. Every test is added to `ai-platform/test/system/issuer-tokens.system.test.ts`. The unit command is that file only. Reuse `vendorCall`, `setTestClock`, and email capture already in `ai-platform/test/system/harness.ts`. Clinic fetches send `Aip-Contract-Version: 1`.

### 3.1 User Story 1 - Issuer-key registry (Priority: P1)

**Independent Test**: E2E-P3.2-08 in harness H-AP.

- [ ] T001 [US1] Add the failing test `E2E-P3.2-08 AL-13 on issuer-key registration carries the decoded operation and kid` in `ai-platform/test/system/issuer-tokens.system.test.ts` — produces the red test, satisfies FR-001, FR-002, and FR-003, proved by E2E-P3.2-08. `vendorCall("registerIssuerKey", …)` uses the same Access JWT and WebAuthn assertion helpers as the H-AP vendor tests. Input beyond `contract_version` is `kid`, `public_key`, `not_before`, and `not_after`. `public_key` is the base64url encoding of a raw 32-byte Ed25519 public key. `result` is `ok`, `code` is `""`, `receipt` is absent, and `detail` is the `issuer_key` row JSON with `status` `active`. Captured email `text` is JSON with `code` `"AL-13"`, that `kid`, and the decoded `operation`. Run:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/issuer-tokens.system.test.ts
```

The run fails because `registerIssuerKey` is not on `VendorEntrypoint`. Do not modify `packages/vendor-contracts`.

**Checkpoint**: E2E-P3.2-08 exists and fails.

### 3.2 User Story 2 - Issuer-token verification and tenant binding (Priority: P2)

**Independent Test**: E2E-P3.2-01, E2E-P3.2-02, E2E-P3.2-03, E2E-P3.2-04, E2E-P3.2-05, and E2E-P3.2-06 in harness H-AP.

Tasks below are in Sequencing order. They append to the file T001 created.

#### 3.2.1 User Story 2 - Issuer-token verification and tenant binding (part 1)

- [ ] T002 [US2] Add the failing test `E2E-P3.2-01 Token from a registered kid for a new org with ver 2 authenticates; installation and binding epoch 1 are created; a second token resolves the same installation` in `ai-platform/test/system/issuer-tokens.system.test.ts` — produces the red test, satisfies FR-004, FR-005, FR-007, FR-008, and FR-009, proved by E2E-P3.2-01. Depends on T001 (same file). `vendorCall` `registerIssuerKey`, then `SELF.fetch` `GET /v1/capabilities` with a compact JWS whose header is `alg` `EdDSA`, `kid`, and `typ` `JWT`, and whose claims are `iss` = `ISSUER_ID`, `aud` = `ai-platform`, `ver` = `"2"`, and lifetime at most 600 s. The response is 200. D1 has one `installation` (`status` `active`, `display_name` `""`, `region` `""`, `enrolled_at` the UTC ISO-8601 insert time) and one `tenant_binding` (`status` `active`, `epoch` 1, `created_at` that same time). A second token for that org returns 200 and the same `installation_id`, with no second binding. The unit command fails on the missing verifier and the missing binding write.

- [ ] T003 [US2] Add the failing test `E2E-P3.2-02 Unknown kid is 401 unauthenticated; a kid revoked through HP is rejected after one config-cache TTL` in `ai-platform/test/system/issuer-tokens.system.test.ts` — produces the red test, satisfies FR-006, FR-011, and FR-019, proved by E2E-P3.2-02. Depends on T002 (same file). An unknown `kid` on `GET /v1/capabilities` is 401 `unauthenticated` and inserts nothing. A registered `kid` is fetched once so the cache holds the active row. `vendorCall` `revokeIssuerKey` is `ok`, `code` `""`, `receipt` absent, and `detail` is the row with `status` `revoked`. A fetch before the TTL still accepts. `setTestClock` moves now by `CONFIG_CACHE_TTL_MS` plus one millisecond. The next fetch is 401. No `sleep` over 2 s. The unit command fails on the missing revoke method and verifier.

- [ ] T004 [US2] Add the failing test `E2E-P3.2-03 aud abo or ai-platform-feed, lifetime 601 seconds, or ver 1 is 401 before any installation or tenant_binding write` in `ai-platform/test/system/issuer-tokens.system.test.ts` — produces the red test, satisfies FR-005 and FR-011, proved by E2E-P3.2-03. Depends on T003 (same file). Four `GET /v1/capabilities` calls, one for each defect: `aud` `abo`, `aud` `ai-platform-feed`, lifetime 601 s, and `ver` `"1"`. Each response is 401. `installation` and `tenant_binding` counts are unchanged. The unit command fails on the missing verifier.

- [ ] T005 [US2] Add the failing test `E2E-P3.2-04 Tokens of two active kids are accepted; a retiring kid is accepted until not_after and the tenant binding is unchanged` in `ai-platform/test/system/issuer-tokens.system.test.ts` — produces the red test, satisfies FR-004, FR-013, and FR-018, proved by E2E-P3.2-04. Depends on T004 (same file). Both kids return 200. `vendorCall` `retireIssuerKey` is `ok` and `detail` has `status` `retiring`. The retiring `kid` still returns 200 while now is before `not_after`. `tenant_binding` `epoch`, `installation_id`, and `created_at` are unchanged. The unit command fails on the missing retire method and verifier.

- [ ] T006 [US2] Add the failing test `E2E-P3.2-05 The 51st new-org creation within 24 hours is 401 unauthenticated, inserts nothing, and raises AL-20` in `ai-platform/test/system/issuer-tokens.system.test.ts` — produces the red test, satisfies FR-008 and FR-014, proved by E2E-P3.2-05. Depends on T005 (same file). `setTestClock` stays inside that 24 h window. Fifty new orgs each create one epoch-1 binding. The 51st `GET /v1/capabilities` is 401 `unauthenticated`. The epoch-1 count stays 50. Captured email `text` is `{"code":"AL-20"}` and `platform_alert.code` is `AL-20`. No `sleep` over 2 s. The unit command fails on the missing cap and AL-20.

**Checkpoint**: E2E-P3.2-01, E2E-P3.2-02, E2E-P3.2-03, E2E-P3.2-04, and E2E-P3.2-05 exist and fail.

#### 3.2.2 User Story 2 - Issuer-token verification and tenant binding (part 2)

- [ ] T007 [US2] Add the failing test `E2E-P3.2-06 GET /v1/requests/{ref} with the owner org token is 200 and another org token is not found` in `ai-platform/test/system/issuer-tokens.system.test.ts` — produces the red test, satisfies FR-009 and FR-010, proved by E2E-P3.2-06. Depends on T006 (same file). After two orgs exist, the test inserts one `ai_request` row for the owner `installation_id`. `GET /v1/requests/{reference}` with the owner token, header `Aip-Contract-Version: 1`, is 200. The same reference with the other org's token is 404. The unit command fails on the missing verifier.

**Checkpoint**: E2E-P3.2-06 exists and fails. User Story 2's six tests are red.

### 3.3 User Story 3 - Enrollment removal and harness migration (Priority: P3)

**Independent Test**: E2E-P3.2-07 in harness H-AP. Every earlier suite stays green (rule S2).

- [ ] T008 [US3] Add the failing test `E2E-P3.2-07 POST /control/installations/{id}/enroll is 404 and installation_key is gone` in `ai-platform/test/system/issuer-tokens.system.test.ts` — produces the red test, satisfies FR-015, proved by E2E-P3.2-07. Depends on T007 (same file). `SELF.fetch` `POST /control/installations/{id}/enroll` is 404. `sqlite_master` has no `installation_key` row. The unit command fails because enroll still exists and `installation_key` is still in the schema.

**Checkpoint**: E2E-P3.2-07 exists and fails.

---

## 4. Implementation

**Purpose**: Sequencing steps 9–23. Each step starts after T001–T008 exist and fail. Within a story the tasks are in Sequencing order.

### 4.1 User Story 1 - Issuer-key registry (Priority: P1)

**Independent Test**: E2E-P3.2-08 in harness H-AP.

#### 4.1.1 User Story 1 - Issuer-key registry (part 1)

- [ ] T009 [US1] Add `ai-platform/migrations/20261003130000_issuer_key_tenant_binding.sql`, replace `ai-platform/schema.snap.sql`, and update `PLATFORM_ENTITIES` in `ai-platform/test/migrations.test.ts` — produces the D1 tables and the snapshot, satisfies FR-001, FR-005, FR-007, FR-009, and FR-015, proved by E2E-P3.2-08, E2E-P3.2-01, and E2E-P3.2-07. Depends on T008. `issuer_key` has `kid`, `issuer`, `public_key`, `status` (`active`, `retiring`, `revoked`), `not_before`, `not_after`, `registered_by`, and `assertion_sha256`. `public_key` stores the base64url encoding of the raw 32-byte Ed25519 public key. `tenant_binding` has `org_id`, `installation_id`, `epoch`, `status` (`active`, `held_for_transfer`, `retired`), `retired_at`, `reason`, and `created_at`, plus partial unique index `tenant_binding_one_live_org` so at most one row per `org_id` is `active` or `held_for_transfer`. The migration drops `installation_key`, retires `token_contract` version `1`, and inserts version `2`. `installation` columns stay. `schema.snap.sql` becomes the post-migration `CREATE TABLE` dump so `T-A5-13 schema_snapshot_matches` stays green. `PLATFORM_ENTITIES` drops `installation_key` and adds `issuer_key` and `tenant_binding`. Leave `migrations/20260731120000_platform_schema.sql` and `migrations/20260803120000_token_contract.sql` unchanged. The eight E2E tests still fail.

- [ ] T010 [US1] Apply `ai-platform/migrations/20261003130000_issuer_key_tenant_binding.sql` from `ai-platform/test/system/harness.ts` and `ai-platform/test/e2e/harness/d1.ts` — produces a schema the H-AP resets can use, satisfies FR-001, FR-005, FR-007, and FR-015, proved by E2E-P3.2-01 and E2E-P3.2-07. Depends on T009. The only harness that applies `20261003120000_operator_credential_and_platform_alert.sql` today is `ai-platform/test/system/harness.ts`; apply the new file there and in `ai-platform/test/e2e/harness/d1.ts`. Reset lists drop `installation_key` and include `issuer_key` and `tenant_binding`: `PLATFORM_TABLES` and the `DELETE` batch in `ai-platform/test/system/harness.ts`, the `DELETE` batch in `ai-platform/test/e2e/harness/d1.ts`, and `PLATFORM_TABLES` in `ai-platform/test/e2e/harness/env.ts`. Delete `tenant_binding` before `installation`. After a reset deletes `token_contract`, the reseed inserts version `2` with `retired_at` NULL and version `1` with `retired_at` set, in both harnesses, so the reset does not put version `1` back as the current row. The eight E2E tests still fail.

- [ ] T011 [US1] Add `ISSUER_ID` = `issuer-test` under `[env.development.vars]`, `[env.staging.vars]`, and `[env.production.vars]` in `ai-platform/wrangler.toml`, and to the Miniflare bindings in `ai-platform/vitest.workers.config.ts` and `ai-platform/vitest.e2e.config.ts` — produces the issuer id the registry stores and the verifier compares, satisfies FR-002 and FR-004, proved by E2E-P3.2-08 and E2E-P3.2-01. Depends on T010. `ai-platform/vitest.e2e.config.ts` also gains the H-AP `VENDOR` self binding (`serviceBindings.VENDOR` = `{ name: kCurrentWorker, entrypoint: "VendorEntrypoint" }`) and the existing Access, WebAuthn, and `ALERT_EMAIL_TO` bindings (`ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`, `WEBAUTHN_RP_ID`, `WEBAUTHN_ORIGIN`, `ALERT_EMAIL_TO`) so `newClinic()` can call `registerIssuerKey`. `TEST_CLOCK` stays only on `ai-platform/vitest.workers.config.ts`. The workers config already has `VENDOR`, Access, WebAuthn, `ALERT_EMAIL_TO`, and `TEST_CLOCK`; this task adds `ISSUER_ID` there. E2E-P3.2-08 still fails on the missing method.

- [ ] T012 [US1] Add `registerIssuerKey` to `METHOD_CLASS` as HP in `ai-platform/src/vendor/entrypoint.ts` — produces registration, satisfies FR-002 and FR-021, proved by E2E-P3.2-08. Depends on T011. Reuse the existing HP checks (`negotiate`, Access JWT, WebAuthn assertion). Beyond `contract_version`, the input is `kid`, `public_key`, `not_before`, and `not_after`. `ok` inserts `status` `active`, stores `public_key` unchanged, sets `issuer` to `ISSUER_ID`, `registered_by` to the Access email, and `assertion_sha256` to the assertion challenge hash. `detail` is the JSON text of the `issuer_key` row, `code` is empty, and `receipt` is absent. The same `kid` with the same `public_key` is `ok` again and does not insert another row or change `status`. The same `kid` with a different `public_key` is `conflict` with code `public_key_mismatch` and empty `detail`. A `public_key` that is not the base64url encoding of a raw 32-byte Ed25519 public key is `rejected` with code `public_key_invalid` and empty `detail`. This call does not set `retiring`. E2E-P3.2-08 still fails until T015 sends AL-13. The Test plan assigns no E2E id to the mismatch, invalid-key, or same-key replay results; do not add one.

- [ ] T013 [US1] Add `retireIssuerKey` and `revokeIssuerKey` as HP in `ai-platform/src/vendor/entrypoint.ts` — produces retire and revoke, satisfies FR-018 and FR-019, proved by E2E-P3.2-04 and E2E-P3.2-02. Depends on T012 (same file). Beyond `contract_version`, the input is `kid`. `retireIssuerKey` is the only writer of `retiring`: `ok` sets `status` from `active` to `retiring`, and `ok` when the row is already `retiring`. A `revoked` row stays `revoked` and the result is `rejected` with code `kid_revoked` and empty `detail`. `revokeIssuerKey` sets `status` to `revoked`, `ok` when the row is already `revoked`, and does not set `retiring`. A missing `kid` on either method is `rejected` with code `kid_not_found` and empty `detail`. On `ok`, `detail` is the JSON text of the `issuer_key` row, `code` is empty, and `receipt` is absent. E2E-P3.2-02 and E2E-P3.2-04 stay red until the verifier reads the row. The Test plan assigns no E2E id to `kid_not_found` or `kid_revoked`; do not add one.

**Checkpoint**: E2E-P3.2-08 still fails. E2E-P3.2-01 through E2E-P3.2-07 still fail.

#### 4.1.2 User Story 1 - Issuer-key registry (part 2)

- [ ] T014 [US1] Add `listIssuerKeys` to `METHOD_CLASS` as M in `ai-platform/src/vendor/entrypoint.ts` — produces the active and retiring list, satisfies FR-020 and FR-021, proved by the issuer-key success envelope E2E-P3.2-08 asserts for register. Depends on T013 (same file). It takes no input beyond `contract_version`. Reuse the existing class M checks. The result is `ok`. `detail` is the JSON text of `{kid, public_key, status, not_before, not_after}` for each `issuer_key` with `status` `active` or `retiring`, ordered by `kid`. `receipt` is absent and `code` is empty. The Test plan assigns no E2E id to `listIssuerKeys`. Do not add one, and do not extend E2E-P3.2-08 to call this method.

- [ ] T015 [US1] Raise issuer-key AL-13 and AL-20 from `ai-platform/src/alert/index.ts`, called by `ai-platform/src/vendor/entrypoint.ts` for AL-13 — produces the two alerts, satisfies FR-003 and FR-014, proved by E2E-P3.2-08 and E2E-P3.2-05. Depends on T014. Leave the credential `Al13Body` unchanged. Issuer-key AL-13 and AL-20 are separate JSON objects. On registration the alert carries the decoded operation and `kid`. The repeat is once. Unsent retry rebuilds an `AL-13:issuer_key:` key from `issuer_key` and `control_audit`. AL-20 uses `next_send_at` as `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/contracts/tenant-binding.md` describes, and the repeat interval is daily. `ai-platform/src/alert/email.ts` stays the only `env.SEND_EMAIL.send` call. E2E-P3.2-08 passes. E2E-P3.2-05 stays red until T018 enforces the cap.

**Checkpoint**: E2E-P3.2-08 passes at T015.

### 4.2 User Story 2 - Issuer-token verification and tenant binding (Priority: P2)

**Independent Test**: E2E-P3.2-01, E2E-P3.2-02, E2E-P3.2-03, E2E-P3.2-04, E2E-P3.2-05, and E2E-P3.2-06 in harness H-AP.

- [ ] T016 [US2] Replace `EnrolledKeyVerifier` with `IssuerTokenVerifier` in `ai-platform/src/identity/index.ts` — produces the issuer-token verifier, satisfies FR-004, FR-005, FR-011, and FR-012, proved by E2E-P3.2-01, E2E-P3.2-02, E2E-P3.2-03, and E2E-P3.2-04. Depends on T015. Use the check order in `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/contracts/ai-token-verification.md`. Checks: `kid` is in `issuer_key` and is `active` or `retiring` within validity; `iss` equals `ISSUER_ID`; `aud` matches the route (AI audience `ai-platform`); lifetime at most 600 s; clock skew matches the check at `src/identity/index.ts:283-296`; `ver` is `"2"`. A token with `ver` `"1"`, `aud` `abo`, `aud` `ai-platform-feed`, or lifetime 601 s is 401 before `org` is resolved and before any `installation` or `tenant_binding` write. An unknown `kid` is 401 `unauthenticated`. `VerifyContext` gains `issuerId`. `now` stays seconds. Replay stays on `principal.jti` in the Durable Object. The eight E2E tests still fail until T017 wires this class.

- [ ] T017 [US2] Add config-cache kinds `issuer_keys` and `tenant_bindings` in `ai-platform/src/config-cache/index.ts`, and construct `IssuerTokenVerifier` from `ai-platform/src/discovery/index.ts`, `authenticateGetRequest` in `ai-platform/src/journal/index.ts`, `createProductionPreAccept` in `ai-platform/src/worker.ts`, and `ai-platform/src/usage-summary/index.ts` — produces the cache and the live call path, satisfies FR-004, FR-006, FR-008, FR-009, and FR-010, proved by E2E-P3.2-01, E2E-P3.2-02, E2E-P3.2-03, and E2E-P3.2-04. Depends on T016. Remove the `keys` reader. Keep the `plans` and `entitlements` readers. Add no coverage reader. `loadConfig` takes an optional `nowMs` and defaults to `Date.now()` so admission, capability, and entitlement keep their current calls. The verifier passes `ctx.now * 1000`. Callers pass `ISSUER_ID` and set `now` from `clockNowSeconds`. This task includes the first-seen insert: a valid token for an unknown org writes `installation` (`org_id` from the token, a new platform clinic UUID, `status` `active`, `display_name` `""`, `region` `""`, `enrolled_at` the UTC ISO-8601 insert time) and `tenant_binding` (`status` `active`, `epoch` 1, `created_at` that same time). A second token for that org resolves `Principal.installationId` through that binding and does not insert another row. The 50-per-day cap is T018. `src/admission/index.ts`, `src/capability/index.ts`, and `src/entitlement/index.ts` stay unchanged. E2E-P3.2-01, E2E-P3.2-02, E2E-P3.2-03, and E2E-P3.2-04 pass.

- [ ] T018 [US2] Enforce the 50-creations-per-day cap on the first-seen path in `ai-platform/src/identity/index.ts` and raise AL-20 through `ai-platform/src/alert/index.ts` — produces the cap and the refusal, satisfies FR-008, FR-009, FR-010, and FR-014, proved by E2E-P3.2-05 and E2E-P3.2-06. Depends on T015 and T017. The count is `tenant_binding` rows with `epoch` 1 whose `created_at` falls in the last 24 hours. The 51st attempt inserts nothing, the clinic route answers 401 `unauthenticated`, and the platform raises AL-20. `GET /v1/requests/{reference}` returns 200 for the owner installation and 404 for another org. E2E-P3.2-05 and E2E-P3.2-06 pass. E2E-P3.2-01 through E2E-P3.2-04 stay green.

**Checkpoint**: E2E-P3.2-01, E2E-P3.2-02, E2E-P3.2-03, and E2E-P3.2-04 pass at T017. E2E-P3.2-05 and E2E-P3.2-06 pass at T018.

### 4.3 User Story 3 - Enrollment removal and harness migration (Priority: P3)

**Independent Test**: E2E-P3.2-07 in harness H-AP. Every earlier suite stays green (rule S2).

- [ ] T019 [US3] Remove `handleEnroll`, `handleRotate`, `handleRevokeKey`, and `INSTALLATION_KEY_TTL_DAYS` from `ai-platform/src/control/lifecycle.ts`, remove `enroll`, `rotate`, and `revoke-key` from the control route pattern and switch in `ai-platform/src/control/index.ts`, remove the `DELETE FROM installation_key` statement in `ai-platform/src/retention/index.ts`, and rename `INSTALLATION_KEY_ALGORITHM` to `ISSUER_KEY_ALGORITHM` in `ai-platform/src/platform-vocabulary.ts` — produces enroll removal and the issuer-key algorithm constant, satisfies FR-015 and FR-016, proved by E2E-P3.2-07. Depends on T018. The `entitlement` and `installation` deletes in that retention function stay. The constant value stays `"EdDSA"`. `isSupportedInstallationKeyAlgorithm` compares against `ISSUER_KEY_ALGORITHM`. `PLAN_TIERS`, `planTierMeetsMinimum`, and `isKnownPlanTier` stay. `/control/entitle` and the other `/control/*` routes stay. `POST /control/installations/{id}/enroll` is 404. Re-run the unit command and confirm E2E-P3.2-01 through E2E-P3.2-08 pass together:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/issuer-tokens.system.test.ts
```

- [ ] T020 [US3] Add `newClinic()` and issuer-token minting to `ai-platform/test/system/harness.ts` — produces the H-AP clinic setup that replaces enroll, satisfies FR-017, proved by E2E-P3.2-01. Depends on T019. `enrollScenario` becomes `newClinic()`. It registers one harness issuer key through `vendorCall("registerIssuerKey", …)` and mints issuer tokens (`iss` = `ISSUER_ID`, `aud` = `ai-platform`, `ver` = `"2"`, header `alg` `EdDSA`, `kid`, `typ` `JWT`). It presents one token on `GET /v1/capabilities` with `Aip-Contract-Version: 1`, reads `installation_id` from `tenant_binding`, and writes that id back onto the scenario. `entitleScenario` then uses that id. The platform assigns the id. `setupPromotedFakePolicy` calls `newClinic()` and then `entitleScenario`. E2E-P3.2-01 through E2E-P3.2-08 stay green.

- [ ] T021 [US3] Point the system suites at `newClinic()` and the returned `installation_id` — produces migrated H-AP suites, satisfies FR-017, proved by E2E-P3.2-01. Depends on T020. Files: `ai-platform/test/system/settlement-integrity.system.test.ts`, `ai-platform/test/system/quota-admission-interplay.system.test.ts`, `ai-platform/test/system/contract-version.system.test.ts`, `ai-platform/test/system/failure-taxonomy-matrix.system.test.ts`, `ai-platform/test/system/golden-journey.system.test.ts`, `ai-platform/test/system/routing-policy-traffic.system.test.ts`, `ai-platform/test/system/lifecycle-interplay.system.test.ts`, `ai-platform/test/system/entitlement-grant-interplay.system.test.ts`, `ai-platform/test/system/token-contract-rotation.system.test.ts`, and `ai-platform/test/system/capability-lifecycle.system.test.ts`. `token-contract-rotation.system.test.ts` also keeps version `2` current and version `1` retired (FR-005). Suites whose subject is enroll, rotate, or revoke-key assert HTTP 404 and do not touch `installation_key`. Other enrolling suites call `newClinic()`, then the existing entitle path.

- [ ] T022 [US3] Add the same `newClinic()` behavior to `ai-platform/test/e2e/harness/control.ts`, mint issuer tokens from `ai-platform/test/e2e/harness/aat.ts`, and drop the `installation_key` fault target in `ai-platform/test/e2e/harness/faults.ts` — produces the e2e harness token path, satisfies FR-004, FR-015, and FR-017, proved by E2E-P3.2-01 and E2E-P3.2-07. Depends on T021. Minted claims match T020 (`iss` = `ISSUER_ID`, `aud` = `ai-platform`, `ver` = `"2"`). `TOKEN_CONTRACT_VER` in `ai-platform/test/e2e/harness/env.ts` becomes `"2"`. The fault helper no longer accepts target `installation_key`.

- [ ] T023 [US3] Migrate the remaining Files test rows — produces suites that call `newClinic()` or expect 404, satisfies FR-004, FR-005, FR-006, FR-010, FR-012, FR-015, and FR-017, proved by E2E-P3.2-07 and E2E-P3.2-01. Depends on T022. Enrolling e2e stages call `newClinic()`. Enroll, rotate, and revoke-key assertions expect 404. Unit fixtures stop inserting `installation_key` and stop constructing `EnrolledKeyVerifier`. `ai-platform/test/worker-entry.test.ts` expects 404 for the enroll URL. `ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts` keeps the existing replay rules (FR-012). `ai-platform/test/e2e/stage-12-get-auth.test.ts` keeps owner-org `GET /v1/requests/{reference}` on the issuer token (FR-010). Files: `ai-platform/test/e2e/harness/scenario.ts`, `ai-platform/test/e2e/harness/index.ts`, `ai-platform/test/worker-entry.test.ts`, `ai-platform/test/worker-request-orchestrator.test.ts`, `ai-platform/test/discovery-http.test.ts`, `ai-platform/test/identity.test.ts`, `ai-platform/test/token-contract-rotation.test.ts`, `ai-platform/test/token-contract-control.test.ts`, `ai-platform/test/config-readers.test.ts`, `ai-platform/test/config-cache.test.ts`, `ai-platform/test/usage-summary.test.ts`, `ai-platform/test/control.test.ts`, `ai-platform/test/retention.test.ts`, `ai-platform/test/plan-catalogue.test.ts`, `ai-platform/test/entitle-grant.test.ts`, `ai-platform/test/cohort-activate-promote.test.ts`, `ai-platform/test/capability.test.ts`, `ai-platform/test/capability-deprecation.test.ts`, `ai-platform/test/routing-policy-canary.test.ts`, `ai-platform/test/entitlement.test.ts`, `ai-platform/test/e2e/stage-00-auth-schema-cron-happy.test.ts`, `ai-platform/test/e2e/stage-00-boot-bindings-routing.test.ts`, `ai-platform/test/e2e/stage-01-auth-validation.test.ts`, `ai-platform/test/e2e/stage-03-enroll-validation.test.ts`, `ai-platform/test/e2e/stage-03-lifecycle-rotate.test.ts`, `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts`, `ai-platform/test/e2e/stage-03-auth-routing.test.ts`, `ai-platform/test/e2e/stage-04-entitle-auth-period.test.ts`, `ai-platform/test/e2e/stage-04-entitle-happy-cohort-activate.test.ts`, `ai-platform/test/e2e/stage-04-entitle-quota-grants-validation.test.ts`, `ai-platform/test/e2e/stage-04-cohort-promote-deprecate.test.ts`, `ai-platform/test/e2e/stage-04-deprecate-retire-auth.test.ts`, `ai-platform/test/e2e/stage-05-filters-kill-switch.test.ts`, `ai-platform/test/e2e/stage-05-rollback-serving.test.ts`, `ai-platform/test/e2e/stage-05-canary-promote.test.ts`, `ai-platform/test/e2e/stage-07-etag-cache.test.ts`, `ai-platform/test/e2e/stage-07-entitlement-filters.test.ts`, `ai-platform/test/e2e/stage-07-routing-identity.test.ts`, `ai-platform/test/e2e/stage-08-guard-sse-adapter.test.ts`, `ai-platform/test/e2e/stage-09-adapter-identity.test.ts`, `ai-platform/test/e2e/stage-09-admission-journal-compose.test.ts`, `ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts`, `ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts`, `ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts`, `ai-platform/test/e2e/stage-11-completed-failed-cancelled.test.ts`, `ai-platform/test/e2e/stage-12-get-auth.test.ts`, `ai-platform/test/e2e/stage-12-get-lookup.test.ts`, `ai-platform/test/e2e/stage-12-support-lookup.test.ts`, `ai-platform/test/e2e/stage-12-quota-inspect-dashboard.test.ts`, `ai-platform/test/e2e/stage-X-ledger-reconciliation-sweep.test.ts`, `ai-platform/test/e2e/stage-X-credit-inspect-do-rpc.test.ts`, and `ai-platform/test/e2e/phase-00-exemplars.test.ts`.

**Checkpoint**: E2E-P3.2-07 passes at T019. E2E-P3.2-01 through E2E-P3.2-08 stay green through T023.

---

## 5. Verification

**Purpose**: The unit harness named in Test Layout passes. Earlier suites are the review's run (rule S2). This task does not name that run.

- [ ] T024 Run harness H-AP for this unit and confirm E2E-P3.2-01 through E2E-P3.2-08 pass together — produces the green run, satisfies FR-001 through FR-021 and SC-001, proved by E2E-P3.2-01 through E2E-P3.2-08. Depends on T009 and T023 (and therefore on T001–T022). `src/admission/index.ts`, `src/capability/index.ts`, and `src/entitlement/index.ts` are untouched. Consumes contracts and `packages/vendor-contracts/**` stay unchanged. SC-002 is the review's run of earlier suites, not this command.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/issuer-tokens.system.test.ts
```

---

## 6. Documentation

**Purpose**: Written after T024 is green (rule S8). The plan leaves `quickstart.md` for implement. `data-model.md` and `contracts/` stay plan-phase artifacts. No other doc task.

- [ ] T025 Create `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, satisfies FR-001 through FR-021, proved by E2E-P3.2-01 through E2E-P3.2-08. Depends on T024. Sections: (1) what was implemented — issuer-key methods, `issuer_key` and `tenant_binding`, the issuer-token verifier, enroll removal, and H-AP `newClinic()`; (2) files this unit adds or modifies — the Files section of `plan.md`, with no earlier-unit files and no combined counts; (3) harness command for this unit's tests only — the command below; (4) how to inspect the change — read `ai-platform/src/vendor/entrypoint.ts`, `IssuerTokenVerifier` in `ai-platform/src/identity/index.ts`, the `issuer_keys` and `tenant_bindings` kinds in `ai-platform/src/config-cache/index.ts`, `ISSUER_ID` in `ai-platform/wrangler.toml`, and the H-AP output; (5) the entry point → module chain per E2E id below. Every scenario is asserted by H-AP, so this file records harness commands only.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/issuer-tokens.system.test.ts
```

Earlier suites stay out of this command (rule S8).

| ID | Chain |
| --- | --- |
| E2E-P3.2-01 | `SELF.fetch` `GET /v1/capabilities` → `src/discovery/index.ts` → `IssuerTokenVerifier` → `src/config-cache` `issuer_key` → D1 insert of `installation` and `tenant_binding` epoch 1 → a second fetch resolves the same `installation_id` |
| E2E-P3.2-02 | Unknown `kid` on `GET /v1/capabilities` → verifier → 401 `unauthenticated`. `vendorCall` `revokeIssuerKey` → `src/vendor/entrypoint.ts` → `issuer_key.status` `revoked`. A fetch inside the TTL still accepts the cached row. `setTestClock` advances one TTL → the next fetch reads `revoked` and returns 401 |
| E2E-P3.2-03 | `GET /v1/capabilities` with `aud` `abo` or `ai-platform-feed`, lifetime 601 s, or `ver` `"1"` → verifier checks in `contracts/ai-token-verification.md` → 401 before any `installation` or `tenant_binding` insert |
| E2E-P3.2-04 | Two `registerIssuerKey` calls → two `GET /v1/capabilities` tokens accepted → `vendorCall` `retireIssuerKey` → retiring `kid` still accepted → `tenant_binding` row unchanged |
| E2E-P3.2-05 | Fifty first-seen orgs via `GET /v1/capabilities` inside one test-clock window → the 51st fetch inserts nothing, returns 401 `unauthenticated`, and `src/alert/index.ts` sends AL-20 |
| E2E-P3.2-06 | `SELF.fetch` `GET /v1/requests/{reference}` → `authenticateGetRequest` → `IssuerTokenVerifier` → `getRequest` returns 200 for the owner installation and 404 for another org |
| E2E-P3.2-07 | `SELF.fetch` `POST /control/installations/{id}/enroll` → `src/worker.ts` 404. D1 has no `installation_key` table |
| E2E-P3.2-08 | `vendorCall` `registerIssuerKey` → HP checks in `src/vendor/entrypoint.ts` → `issuer_key` insert → `src/alert/index.ts` AL-13 email with `code`, `kid`, and `operation` |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (T001–T008)**: No Setup phase. T001 starts immediately. T002 through T008 append to `ai-platform/test/system/issuer-tokens.system.test.ts` in Sequencing order and are observed failing before T009.
- **Implementation (T009–T023)**: Starts after T001–T008 exist and fail. Order is Sequencing: T009, T010, T011, then T012 through T015 on `ai-platform/src/vendor/entrypoint.ts`, then T016, T017, T018, then T019 through T023.
- **Verification (T024)**: After every implementation task.
- **Documentation (T025)**: After T024 is green.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: T001 starts immediately. T009 waits until T008 has added the last failing test. T010 waits on T009. T011 waits on T010. T012 through T015 follow in order on the entrypoint, and T015 also edits `ai-platform/src/alert/index.ts`. E2E-P3.2-08 passes at T015. User Story 2's verifier waits on that alert module because T018 raises AL-20 through it.
- **User Story 2 (P2)**: Tests T002 through T007 wait on T001 because they append to the same file. They do not wait on User Story 1's implementation. The spec says this story accepts a token only after User Story 1 has registered the `kid`, so T016 waits on T015. T017 waits on T016. T018 waits on T015 and T017. E2E-P3.2-01, E2E-P3.2-02, E2E-P3.2-03, and E2E-P3.2-04 pass at T017. E2E-P3.2-05 and E2E-P3.2-06 pass at T018.
- **User Story 3 (P3)**: T008 waits on T007. That test does not wait on User Story 2's modules. T019 waits on T018, because its re-run confirms E2E-P3.2-01 through E2E-P3.2-08 together. T020 waits on T019. T021 waits on T020. T022 waits on T021. T023 waits on T022. E2E-P3.2-07 passes at T019. The "every earlier suite stays green" sentence on this story's Independent Test line is the review's run, not T024.

### 7.3 Parallel Opportunities

- T001–T008 are not `[P]`. They all write `ai-platform/test/system/issuer-tokens.system.test.ts`. A pair in another story is not parallel with these, because Sequencing appends every E2E to that one file.
- T009 writes the migration, `ai-platform/schema.snap.sql`, and `ai-platform/test/migrations.test.ts` as one step. T010 writes the two harnesses and `ai-platform/test/e2e/harness/env.ts` and waits on T009. T011 writes `ai-platform/wrangler.toml` and both vitest configs and waits on T010. Sequencing does not launch those steps together.
- T012–T015 share `ai-platform/src/vendor/entrypoint.ts`. They are not `[P]` with each other. T015 also writes `ai-platform/src/alert/index.ts`.
- T016 writes `ai-platform/src/identity/index.ts`. T017 writes `ai-platform/src/config-cache/index.ts`, `ai-platform/src/discovery/index.ts`, `ai-platform/src/journal/index.ts`, `ai-platform/src/worker.ts`, and `ai-platform/src/usage-summary/index.ts`, and it waits on T016. T018 returns to `ai-platform/src/identity/index.ts` and `ai-platform/src/alert/index.ts`.
- T019 writes `ai-platform/src/control/lifecycle.ts`, `ai-platform/src/control/index.ts`, `ai-platform/src/retention/index.ts`, and `ai-platform/src/platform-vocabulary.ts`. T020 through T023 edit harness and suite files in Sequencing order. T022 and T010 both touch `ai-platform/test/e2e/harness/env.ts`; T022 waits until T010 has finished.
- T024 and T025 are single tasks. T025 waits until T024 is green.
- No task in this unit is `[P]`.

```bash
# Two User Story 2 test tasks. Both append to
# ai-platform/test/system/issuer-tokens.system.test.ts, so they are not [P].
# Sequencing writes T002, then T003.
Task: "T002 [US2] Add the failing test E2E-P3.2-01 in ai-platform/test/system/issuer-tokens.system.test.ts"
Task: "T003 [US2] Add the failing test E2E-P3.2-02 in ai-platform/test/system/issuer-tokens.system.test.ts"
```
