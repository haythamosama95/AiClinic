# Tasks: Issuer key custody, token issuance and the versioned RPC envelope

**Input**: Design documents from `specs/087-abo-p5-1-issuer-key-custody-token-issuance/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P1.2 (tenant inventory, per-tenant `roles_permissions`, cross-tenant suite, `current_org_id()`, `set_active_organization`), P3.2 (AI-token verification, `tenant_binding` epoch, `VendorEntrypoint.registerIssuerKey`), and P4.1 (ABO clinic-API envelope, auth, and error rules; records conventions; alert engine; H-ABO). The Paymob stub is started as a process and not modified. Plan artifacts from `AVAILABLE_DOCS`: `research.md`, `data-model.md`. `research.md` is not a task: the R-3 spike already passed, so no Edge Function signer is added. `data-model.md` is not a task: plan already wrote it. There is no `contracts/` (the unit row has no Outputs / freezes line). `quickstart.md` is written in Documentation after the H-FS harness is green.

**Organization**: Four user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`, `[US4]`). Tests are one task per E2E id, written to fail before the behavior exists. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 36. Size L is 32–40 (rule S3). Sequencing has 34 steps. Steps 1–16 and 18–33 are one task each. Step 17 is two tasks, one per stage-02 Files row. Step 34’s harness run and its `quickstart.md` write are two tasks. The count is not padded. `run_all_backend_tests.sh`, a repository-root `npm test`, and any command other than the two unit commands in §5.1 and §9.1 are not the harness.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`, `US4`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/supabase/migrations/20261007180000_issuer_key_custody.sql`, `backend/tests/` — the Files paths in `plan.md`
- **Full-stack harness**: `e2e/fullstack/` — package, harness worker, and Node runner
- **CI**: `.github/workflows/ci.yml` — Node on job `backend-sql`, then job `fullstack`
- **AI Platform**: `ai-platform/` — consumed and not modified. `TEST_CLOCK` stays off its wrangler envs
- **ABO**: `abo/src/` — consumed and not modified. ABO runs as CLI `wrangler dev`. `ISSUER_KEYS` is process config
- **Shared package**: `packages/vendor-contracts/` — consumed (`CHANNEL_VERSIONS`, `createAccessTeam`, `createSoftwareAuthenticator`) and not modified
- **Paymob stub**: `abo/test/stubs/paymob/worker.ts` — started as a process and not modified
- **Spec Kit artifacts**: `specs/087-abo-p5-1-issuer-key-custody-token-issuance/`
- Leave `backend/supabase/migrations/20260801120000_ai_keystore_schema.sql` and `backend/supabase/migrations/20260905120300_fix_aat_lifetime_fallback.sql` unchanged. Leave `ai.availability` and the availability RPCs in place

---

## 3. Tests (H-BK)

**Purpose**: Sequencing steps 1–5. One failing test per H-BK E2E id. Titles are prefixed with the E2E id. Leave `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` uncreated.

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f backend/tests/ai_keystore_rls.sql
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f backend/tests/issuer_rpc.sql
node backend/tests/contract_versions.mjs
```

### 3.1 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — tests

**Independent Test**: E2E-P5.1-07 in harness H-BK, and E2E-P5.1-06 in harness H-FS.

- [X] T001 [US1] Add the failing test `E2E-P5.1-07` in `backend/tests/ai_keystore_rls.sql` — red test, FR-002, FR-003, FR-011, E2E-P5.1-07. Depends on nothing. Title `E2E-P5.1-07 No clinic role can read private key material and no plaintext key column remains`. As `authenticated`, `SELECT` on `ai_internal.issuer_key` and `vault.decrypted_secrets` is denied. `information_schema` has no `secret_key` column under `ai_internal`, and `installation_keys` is absent. As the database owner, `auth_internal.issue_feed_token()` has `aud` `ai-platform-feed`, `sub` `backend-feed`, no `org`, and `exp − iat` of 120 seconds. As `authenticated`, `issue_feed_token` and `switch_issuer_signing_kid` cannot be executed. The psql command fails because that custody behavior is absent.

**Checkpoint**: E2E-P5.1-07 exists and fails.

### 3.2 User Story 4 - RPC contract version (Priority: P4) — tests (part 1)

**Independent Test**: E2E-P5.1-09 in harness H-BK. Every earlier suite stays green (rule S2).

- [X] T002 [US4] Add the failing test `E2E-P5.1-04` in `backend/tests/issuer_rpc.sql` — red test, FR-009, E2E-P5.1-04. Depends on T001. Create the file. Title `E2E-P5.1-04 Version 2 raises CONTRACT_VERSION_UNSUPPORTED and rpc_result carries contract_version`. `public.issue_ai_token(2)` and `public.issue_ai_token()` raise `CONTRACT_VERSION_UNSUPPORTED`. The exception detail is `accepted_versions` `[0, 1]`. No issuance row is inserted. A prior unauthenticated session is not required. `public.issue_billing_token(1)` as an administrator returns `contract_version` 1. The psql command fails because the versioned signatures are absent.

**Checkpoint**: E2E-P5.1-04 exists and fails. E2E-P5.1-07 still fails.

### 3.3 User Story 3 - Administrator billing token (Priority: P3) — tests

**Independent Test**: E2E-P5.1-02 in harness H-FS.

- [X] T003 [US3] Add the failing test `E2E-P5.1-05` in `backend/tests/issuer_rpc.sql` — red test, FR-005, FR-007, E2E-P5.1-05. Depends on T002 (same file). Title `E2E-P5.1-05 21st billing token in 10 min is RATE_LIMITED`. One user. Twenty `public.issue_billing_token(1)` calls succeed. The 21st returns `error_code` `RATE_LIMITED` and does not insert a 21st `aud = 'abo'` row. AI rows for that user do not count. The psql command fails because the per-audience limit is absent.

**Checkpoint**: E2E-P5.1-05 exists and fails. E2E-P5.1-04 and E2E-P5.1-07 still fail.

### 3.4 User Story 2 - AI token for the active organisation (Priority: P2) — tests

**Independent Test**: E2E-P5.1-01 in harness H-FS.

- [X] T004 [US2] Add the failing test `E2E-P5.1-08` in `backend/tests/issuer_rpc.sql` — red test, FR-004, E2E-P5.1-08. Depends on T003 (same file). Title `E2E-P5.1-08 Membership switched to org B yields token org B`. `public.set_active_organization` to org B, then `public.issue_ai_token(1)`. The token `org` is B and equals `current_org_id()`. The psql command fails because the token `org` is not taken from `current_org_id()`.

**Checkpoint**: E2E-P5.1-08 exists and fails. E2E-P5.1-04, E2E-P5.1-05, and E2E-P5.1-07 still fail.

### 3.5 User Story 4 - RPC contract version (Priority: P4) — tests (part 2)

**Independent Test**: E2E-P5.1-09 in harness H-BK. Every earlier suite stays green (rule S2).

- [X] T005 [US4] Add the failing test `E2E-P5.1-09` in `backend/tests/contract_versions.mjs` — red test, FR-008, E2E-P5.1-09. Depends on T004. Title `E2E-P5.1-09 ai.contract_versions equals the package constants`. The script reads `CHANNEL_VERSIONS` out of `packages/vendor-contracts/src/version.ts` as text and passes those integers to psql. It does not copy the constants into the script. Each stored `current` equals that integer and each stored `minimum` equals `current - 1`. The node command fails because `ai.contract_versions` is absent or differs.

**Checkpoint**: E2E-P5.1-09 exists and fails. E2E-P5.1-04, E2E-P5.1-05, E2E-P5.1-07, and E2E-P5.1-08 still fail.

---

## 4. Implementation (backend)

**Purpose**: Sequencing steps 6–19. Starts after T001–T005 exist and those E2E tests fail. Within a subphase the tasks run in id order. All of T007–T015 edit only `backend/supabase/migrations/20261007180000_issuer_key_custody.sql`.

### 4.1 User Story 4 - RPC contract version (Priority: P4) — harness registration

**Independent Test**: E2E-P5.1-09 in harness H-BK. Every earlier suite stays green (rule S2).

- [X] T006 [US4] Register the H-BK files in `backend/tests/run_all_backend_tests.sh` and add Node to job `backend-sql` in `.github/workflows/ci.yml` — produces the suite registration and the Node runtime for the contract test, FR-008, FR-009, E2E-P5.1-04, E2E-P5.1-05, E2E-P5.1-08, E2E-P5.1-09. Depends on T005. Add `issuer_rpc.sql` and `node backend/tests/contract_versions.mjs`. The unit command stays the three commands in §3. Leave the `fullstack` job uncreated.

**Checkpoint**: `run_all_backend_tests.sh` lists `issuer_rpc.sql` and `contract_versions.mjs`. Job `backend-sql` can run Node. E2E-P5.1-04, E2E-P5.1-05, E2E-P5.1-07, E2E-P5.1-08, and E2E-P5.1-09 still fail.

### 4.2 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — issuer key and installation drop

**Independent Test**: E2E-P5.1-07 in harness H-BK, and E2E-P5.1-06 in harness H-FS.

- [ ] T007 [US1] Add `ai_internal.issuer_key` and `auth_internal.insert_issuer_kid` in `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` — produces the key set, Vault `secret_ref`, and the next-kid insert, FR-002, FR-010, E2E-P5.1-06, E2E-P5.1-07. Depends on T006. Create the file. Columns `kid`, `public_key`, `secret_ref`, `status`, `not_before`, `not_after`. `status` is `signing`, `next`, or `retired`. Partial unique indexes: one `signing` row, at most one `next` row. Private key bytes live in Vault under `secret_ref`. Deny-all RLS. `auth_internal.insert_issuer_kid()` returns `kid`, `public_key`, `status`, `not_before`, `not_after`. No signing row yet → insert `signing`. A signing row and no next row → insert `next`. A next row already present → return that row and insert nothing. Each key is Ed25519 and valid for 13 months, and a `next` key overlaps the `signing` key. The migration calls `insert_issuer_kid` once so one `signing` row exists. `REVOKE ALL` on this function from `PUBLIC`, `anon`, `authenticated`, and `service_role`. Leave the installation drop, the issue RPCs, and `switch_issuer_signing_kid` for later tasks in this file.

**Checkpoint**: One `signing` issuer row exists, with `secret_ref` and deny-all RLS. E2E-P5.1-07 still fails.

- [ ] T008 [US1] Drop installation keys and the enroll RPCs in `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` — produces the removal of plaintext installation custody, FR-003, E2E-P5.1-07. Depends on T007 (same file). Drop `installation_keys`, `enforce_single_installation`, the single-installation trigger, every overload of `enroll_installation_keypair`, `rotate_installation_key`, and `revoke_installation_key` in `public` and `auth_internal`, and `ai_token_issuance.installation_id`. Leave `ai.availability`.

**Checkpoint**: `installation_keys` and the enroll, rotate, and revoke RPCs are dropped. E2E-P5.1-07 still fails.

### 4.3 User Story 4 - RPC contract version (Priority: P4) — app settings

**Independent Test**: E2E-P5.1-09 in harness H-BK. Every earlier suite stays green (rule S2).

- [ ] T009 [US4] Insert the app settings in `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` — produces `ai.platform_base_url`, `ai.abo_base_url`, `ai.issuer_id`, and `ai.contract_versions`, FR-008, E2E-P5.1-09. Depends on T008 (same file). Use the key values recorded in `data-model.md`. `ai.contract_versions` stores, for each channel the backend sends or accepts, `current` and `minimum` with `minimum = current - 1`. Leave `ai.availability`.

**Checkpoint**: The four `app_settings` keys exist. E2E-P5.1-09 still fails until the stored versions match `version.ts`.

### 4.4 User Story 3 - Administrator billing token (Priority: P3) — issuance audience

**Independent Test**: E2E-P5.1-02 in harness H-FS.

- [ ] T010 [US3] Add `ai_token_issuance.aud` in `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` — produces per-audience issuance rows, FR-007, E2E-P5.1-05. Depends on T009 (same file). Add `aud` and `organization_id`. Backfill existing rows to `ai-platform`. Set `aud` `NOT NULL`. Index `(actor_staff_id, aud, iat)` where `is_deleted = false`.

**Checkpoint**: `ai_token_issuance.aud` is `NOT NULL`. E2E-P5.1-05 still fails.

### 4.5 User Story 4 - RPC contract version (Priority: P4) — rpc_result

**Independent Test**: E2E-P5.1-09 in harness H-BK. Every earlier suite stays green (rule S2).

- [ ] T011 [US4] Extend `public.rpc_result` in `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` — produces `contract_version` on the envelope, FR-009, E2E-P5.1-04. Depends on T010 (same file). `ALTER TYPE public.rpc_result ADD ATTRIBUTE contract_version integer`. Replace `public.rpc_success(jsonb)` and `public.rpc_error(text, text)` with an added `p_contract_version integer DEFAULT NULL`. The existing callers still match. Replace these five bodies so the fifth field is null, copying their logic otherwise: `auth_internal.create_patient(uuid, text, text, date, text, text, text, boolean, text)`, `auth_internal.invoke_acceptance_domain_rpc(text, jsonb)`, `auth_internal.reassign_patient_mrn(uuid, text)`, and both `auth_internal.update_patient` overloads.

**Checkpoint**: `rpc_result` has `contract_version`. E2E-P5.1-04 still fails.

### 4.6 User Story 2 - AI token for the active organisation (Priority: P2) — issue_ai_token

**Independent Test**: E2E-P5.1-01 in harness H-FS.

- [ ] T012 [US2] Replace `issue_ai_token` in `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` — produces the versioned AI mint, FR-004, E2E-P5.1-01, E2E-P5.1-08. Depends on T011 (same file). `public.issue_ai_token(p_contract_version integer DEFAULT NULL)` and `auth_internal.issue_ai_token` take that integer. Both are `SECURITY DEFINER`. Grant `public.issue_ai_token` to `authenticated`. Drop `issue_ai_token(text[])` in `public` and `auth_internal`. The public body checks the version before `auth_internal` and before any session read or insert. Null or any integer other than 0 or 1 raises `CONTRACT_VERSION_UNSUPPORTED` with detail `{"accepted_versions":[0,1]}`. The public body delegates to `auth_internal` after that check. Sign with Vault decrypt and `pgsodium.crypto_sign_detached` under the `signing` kid. Header `{alg: EdDSA, kid, typ: JWT}`. Claims: `iss` is `ai.issuer_id`; `ver` is `"2"`; `aud` is `ai-platform`; `sub` is the staff member id; `org` is `current_org_id()` and is never taken from an argument; `role` is the membership role; `branch` is the current branch; `scopes` are the granted `ai.*` permission keys for that role where `organization_id = current_org_id()` and `role = current_membership_role()`, the same keys as `20260905120300_fix_aat_lifetime_fallback.sql` lines 115–124; `exp − iat` is 600; `jti` is a UUID. A role with no granted `ai.*` key still raises `AI_ACCESS_DENIED`. The ledger row stores `aud` `ai-platform` and `organization_id`. Return type stays `text`.

**Checkpoint**: `issue_ai_token(1)` signs an AI token and `issue_ai_token(2)` raises before any insert. E2E-P5.1-04 and E2E-P5.1-08 still fail until the H-BK command is run in T021.

### 4.7 User Story 3 - Administrator billing token (Priority: P3) — issue_billing_token

**Independent Test**: E2E-P5.1-02 in harness H-FS.

- [ ] T013 [US3] Add `issue_billing_token` in `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` — produces the administrator billing mint and the per-audience limit, FR-005, FR-007, FR-009, E2E-P5.1-02, E2E-P5.1-05. Depends on T012 (same file). `public.issue_billing_token(p_contract_version integer DEFAULT NULL)` is `SECURITY DEFINER`, granted to `authenticated`, and delegates to `auth_internal` after the version check. Administrator only. Return `rpc_result` with `data` `{token, abo_base_url, expires_at}` and `contract_version` echoed. `abo_base_url` comes from `ai.abo_base_url`. `aud` is `abo`, `role` is `administrator`, `org` is `current_org_id()`, `branch` is the current branch, no `scopes`, and `exp − iat` is 300. A doctor returns `FORBIDDEN_ROLE` and inserts nothing. A missing or refused version returns `CONTRACT_VERSION_UNSUPPORTED`, `accepted_versions` in `data`, and `contract_version` 1, before authentication and before any insert. The 21st `aud = 'abo'` row in 10 minutes returns `RATE_LIMITED`. Serialize the count and the insert per user and audience.

**Checkpoint**: `issue_billing_token(1)` returns `contract_version` 1 for an administrator. E2E-P5.1-05 still fails until T021.

### 4.8 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — feed mint and signing switch

**Independent Test**: E2E-P5.1-07 in harness H-BK, and E2E-P5.1-06 in harness H-FS.

- [ ] T014 [US1] Add `auth_internal.issue_feed_token` in `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` — produces the feed mint, FR-011, E2E-P5.1-07. Depends on T013 (same file). It takes no `p_contract_version`. Header and `ver = "2"` match the other tokens. `aud` is `ai-platform-feed`, `sub` is `backend-feed`, `org` is absent, `role`, `branch`, and `scopes` are absent, `exp − iat` is 120, and `jti` is a UUID. It does not insert `ai_token_issuance`. `REVOKE ALL` from `PUBLIC`, `anon`, `authenticated`, and `service_role`.

**Checkpoint**: The owner can mint a feed token. A clinic role cannot execute it. E2E-P5.1-07 still fails until T021.

- [ ] T015 [US1] Add `auth_internal.switch_issuer_signing_kid` in `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` — produces the signing switch, FR-010, E2E-P5.1-06, E2E-P5.1-07. Depends on T014 (same file). `auth_internal.switch_issuer_signing_kid(p_kid text)` moves that `next` row to `signing` and the previous `signing` row to `retired` in one transaction. Any other `p_kid` changes nothing. `REVOKE ALL` from `PUBLIC`, `anon`, `authenticated`, and `service_role`. This is not a public RPC.

**Checkpoint**: The migration file contains the issuer key set, both issue RPCs, the feed mint, and the signing switch. E2E-P5.1-04, E2E-P5.1-05, E2E-P5.1-07, E2E-P5.1-08, and E2E-P5.1-09 still fail until T021.

### 4.9 User Story 2 - AI token for the active organisation (Priority: P2) — existing issuer SQL

**Independent Test**: E2E-P5.1-01 in harness H-FS.

- [ ] T016 [US2] Update `backend/tests/ai_token_issuer.sql` to `issue_ai_token(1)` and the `signing` kid — produces a suite that calls the new signature, FR-003, FR-004, E2E-P5.1-01, E2E-P5.1-08. Depends on T015. Call `issue_ai_token(1)` and the issuer-key signer. Leave the tenant assertions of other files for their own tasks.

**Checkpoint**: `ai_token_issuer.sql` calls `issue_ai_token(1)`.

### 4.10 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — stage-02 revoke catalog

**Independent Test**: E2E-P5.1-07 in harness H-BK, and E2E-P5.1-06 in harness H-FS.

- [ ] T017 [US1] Stop calling the dropped RPCs in `backend/tests/catalog/stage-02-revoke-rotate-availability.sql` — produces a catalog that survives the drop, FR-003, E2E-P5.1-07. Depends on T016. Availability cases stay. Leave `backend/tests/catalog/stage-02-availability-and-enroll.sql` for T018.

**Checkpoint**: `stage-02-revoke-rotate-availability.sql` no longer calls enroll, rotate, or revoke. Availability cases stay.

### 4.11 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — stage-02 enroll catalog

**Independent Test**: E2E-P5.1-07 in harness H-BK, and E2E-P5.1-06 in harness H-FS.

- [ ] T018 [US1] Stop calling enroll in `backend/tests/catalog/stage-02-availability-and-enroll.sql` — produces a catalog that survives the drop, FR-003, E2E-P5.1-07. Depends on T016. Availability cases stay. Leave `stage-02-revoke-rotate-availability.sql` for T017.

**Checkpoint**: `stage-02-availability-and-enroll.sql` no longer calls enroll. Availability cases stay.

### 4.12 User Story 2 - AI token for the active organisation (Priority: P2) — stage-06 catalog

**Independent Test**: E2E-P5.1-01 in harness H-FS.

- [ ] T019 [US2] Stop signing with `installation_keys.secret_key` in `backend/tests/catalog/stage-06-verify-and-handoff.sql` — produces a catalog that uses the issuer key, FR-003, FR-004, E2E-P5.1-01. Depends on T017 and T018. It does not read `installation_keys.secret_key`.

**Checkpoint**: `stage-06-verify-and-handoff.sql` does not read `installation_keys.secret_key`.

### 4.13 User Story 2 - AI token for the active organisation (Priority: P2) — cross-tenant suite

**Independent Test**: E2E-P5.1-01 in harness H-FS.

- [ ] T020 [US2] Update call sites in `backend/tests/cross_tenant_suite.sql` — produces a suite on the new signature, FR-003, FR-004, E2E-P5.1-01, E2E-P5.1-08. Depends on T019. Replace enroll setup with owner `insert_issuer_kid`. Replace `issue_ai_token(text[])` with `issue_ai_token(1)`. Leave the tenant assertions.

**Checkpoint**: `cross_tenant_suite.sql` uses `insert_issuer_kid` and `issue_ai_token(1)`. Tenant assertions stay.

---

## 5. Verification (H-BK)

**Purpose**: Sequencing step 20. After T007–T020, before the H-FS package. The harness is these three commands from the repository root. `run_all_backend_tests.sh` is not this task. Earlier suites are not part of this command (rule S2).

### 5.1 User Story 4 - RPC contract version (Priority: P4) — H-BK harness

**Independent Test**: E2E-P5.1-09 in harness H-BK. Every earlier suite stays green (rule S2).

- [ ] T021 [US4] Run the H-BK unit command until E2E-P5.1-04, E2E-P5.1-05, E2E-P5.1-07, E2E-P5.1-08, and E2E-P5.1-09 pass — produces the green H-BK harness, FR-002, FR-003, FR-004, FR-005, FR-007, FR-008, FR-009, FR-011, E2E-P5.1-04, E2E-P5.1-05, E2E-P5.1-07, E2E-P5.1-08, E2E-P5.1-09. Depends on T020 (and therefore on T001–T019). This task may edit only `backend/tests/ai_keystore_rls.sql`, `backend/tests/issuer_rpc.sql`, and `backend/tests/contract_versions.mjs`. It does not add an E2E id.

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f backend/tests/ai_keystore_rls.sql
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f backend/tests/issuer_rpc.sql
node backend/tests/contract_versions.mjs
```

**Checkpoint**: E2E-P5.1-04, E2E-P5.1-05, E2E-P5.1-07, E2E-P5.1-08, and E2E-P5.1-09 pass.

---

## 6. Implementation (H-FS package)

**Purpose**: Sequencing step 21. The `e2e/fullstack/` package does not exist yet. These files exist so `npm test` can fail before the runner starts the stack.

### 6.1 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — package, worker, register route

**Independent Test**: E2E-P5.1-07 in harness H-BK, and E2E-P5.1-06 in harness H-FS.

- [ ] T022 [US1] Add `e2e/fullstack/package.json`, `e2e/fullstack/wrangler.toml`, and `e2e/fullstack/src/register-issuer.ts` — produces the H-FS package and the harness route, FR-010, FR-012, E2E-P5.1-01, E2E-P5.1-02, E2E-P5.1-03, E2E-P5.1-06. Depends on T021. `package.json` depends on `file:../packages/vendor-contracts`, `@supabase/supabase-js`, and `wrangler` `~4.86.0`. Script `test` runs `node --test test/p5-1.test.mjs`. `wrangler.toml` is the harness worker. `PLATFORM` is a service binding to `ai-platform-gateway-development` with `entrypoint = "VendorEntrypoint"`. No `TEST_CLOCK`. `fetch` on `POST /register-issuer-key` calls `env.PLATFORM.registerIssuerKey` and returns the envelope. This route is not added to the platform or the ABO. Leave `e2e/fullstack/test/p5-1.test.mjs` uncreated.

**Checkpoint**: The package, the harness worker, and `register-issuer.ts` exist. The test file does not.

---

## 7. Tests (H-FS)

**Purpose**: Sequencing steps 22–25. One failing test per H-FS E2E id, all in `e2e/fullstack/test/p5-1.test.mjs`. Titles are prefixed with the E2E id. From `e2e/fullstack/`:

```bash
npm test
```

### 7.1 User Story 2 - AI token for the active organisation (Priority: P2) — tests (part 1)

**Independent Test**: E2E-P5.1-01 in harness H-FS.

- [ ] T023 [US2] Add the failing test `E2E-P5.1-01` in `e2e/fullstack/test/p5-1.test.mjs` — red test, FR-004, FR-012, E2E-P5.1-01. Depends on T022. Create the file. Title `E2E-P5.1-01 Org A member issue_ai_token(1) is accepted by the local platform and A's binding is created`. After the signing `kid` is registered and pinned, the org A member calls `issue_ai_token(1)`. `GET /v1/capabilities` returns 200. Local D1 has one `tenant_binding` for that org with `epoch` 1. Clinic calls use supabase-js. `npm test` fails because the runner does not yet accept that token.

**Checkpoint**: E2E-P5.1-01 exists and fails.

### 7.2 User Story 3 - Administrator billing token (Priority: P3) — tests

**Independent Test**: E2E-P5.1-02 in harness H-FS.

- [ ] T024 [US3] Add the failing test `E2E-P5.1-02` in `e2e/fullstack/test/p5-1.test.mjs` — red test, FR-005, FR-009, E2E-P5.1-02. Depends on T023 (same file). Title `E2E-P5.1-02 Administrator issue_billing_token(1) is accepted by the local ABO and a doctor receives FORBIDDEN_ROLE`. The administrator call returns `contract_version` 1. `GET /v1/offers` returns 200. The doctor call returns `FORBIDDEN_ROLE`. Clinic ABO calls send `Host: billing.vendor.test`. `npm test` fails because the ABO does not yet accept that token.

**Checkpoint**: E2E-P5.1-02 exists and fails. E2E-P5.1-01 still fails.

### 7.3 User Story 2 - AI token for the active organisation (Priority: P2) — tests (part 2)

**Independent Test**: E2E-P5.1-01 in harness H-FS.

- [ ] T025 [US2] Add the failing test `E2E-P5.1-03` in `e2e/fullstack/test/p5-1.test.mjs` — red test, FR-006, E2E-P5.1-03. Depends on T024 (same file). Title `E2E-P5.1-03 Billing token at the platform and AI token at the ABO are 401`. The billing token is presented to platform `GET /v1/capabilities` and the AI token to ABO `GET /v1/offers`. Both return 401. `npm test` fails because those refusals are not asserted against a running stack.

**Checkpoint**: E2E-P5.1-03 exists and fails. E2E-P5.1-01 and E2E-P5.1-02 still fail.

### 7.4 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — tests

**Independent Test**: E2E-P5.1-07 in harness H-BK, and E2E-P5.1-06 in harness H-FS.

- [ ] T026 [US1] Add the failing test `E2E-P5.1-06` in `e2e/fullstack/test/p5-1.test.mjs` — red test, FR-010, FR-012, E2E-P5.1-06. Depends on T025 (same file). Title `E2E-P5.1-06 New signing kid is accepted everywhere, old tokens stay valid, and the binding is unchanged`. Mint one AI token and one billing token on the current `kid` and record `tenant_binding.epoch`. Owner `insert_issuer_kid` creates `next`. Pin that public key and restart ABO `wrangler dev`. `registerIssuerKey` for that `kid` returns `ok`. Owner `switch_issuer_signing_kid` with that `kid`. New AI and billing tokens are accepted on `/v1/capabilities` and `/v1/offers`. The earlier tokens are still accepted. `epoch` is unchanged. The test does not sleep and does not call `retireIssuerKey`. Owner SQL uses `psql` and `DB_URL`. `npm test` fails because the switch path is not wired.

**Checkpoint**: E2E-P5.1-06 exists and fails. E2E-P5.1-01, E2E-P5.1-02, and E2E-P5.1-03 still fail.

---

## 8. Implementation (H-FS runner)

**Purpose**: Sequencing steps 26–33. Starts after T023–T026 exist and those E2E tests fail. T028–T034 edit only `e2e/fullstack/test/p5-1.test.mjs`. `supabase start` is already up (local API `http://127.0.0.1:54321`). `TEST_CLOCK` is not set.

### 8.1 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — CI job

**Independent Test**: E2E-P5.1-07 in harness H-BK, and E2E-P5.1-06 in harness H-FS.

- [ ] T027 [US1] Add job `fullstack` in `.github/workflows/ci.yml` — produces the full-stack CI job, FR-012, E2E-P5.1-01, E2E-P5.1-02, E2E-P5.1-03, E2E-P5.1-06. Depends on T026. Keep the Node change T006 made on `backend-sql`. The job checks out, installs Node, the Supabase CLI, and `psql`, runs `supabase start` in `backend/`, then `npm ci` and `npm test` in `e2e/fullstack/`.

**Checkpoint**: Job `fullstack` runs `e2e/fullstack`. E2E-P5.1-01, E2E-P5.1-02, E2E-P5.1-03, and E2E-P5.1-06 still fail.

### 8.2 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — workers and clinic users

**Independent Test**: E2E-P5.1-07 in harness H-BK, and E2E-P5.1-06 in harness H-FS.

- [ ] T028 [US1] Start the platform and the harness worker in `e2e/fullstack/test/p5-1.test.mjs` — produces `startWorker`, the Access certs mock, and the active signer row, FR-010, FR-012, E2E-P5.1-06. Depends on T027. `startWorker({ config: ai-platform/wrangler.toml, env: "development", dev: { server: { hostname: "127.0.0.1", port: 8787 }, persist: e2e/fullstack/.wrangler/platform, registry: e2e/fullstack/.wrangler/registry, mockFetch } })`. `mockFetch` is an undici `MockAgent` that answers only `GET https://access.test/cdn-cgi/access/certs` with the `createAccessTeam` certs document. Other origins still use the network. `TEST_CLOCK` is not set. `createAccessTeam({ issuer: "https://access.test" })` mints the JWT with wall-clock `iat` and `exp` (`exp` is `iat + 3600`) and `aud` `vendor-access-aud`. `createSoftwareAuthenticator("EdDSA")` signs the assertion (`up` and `uv` true, `rpId` `ops.vendor.test`, `origin` `https://ops.vendor.test`). Insert one `operator_credential` into local D1 database `ai-platform-development` with `--local --persist-to e2e/fullstack/.wrangler/platform`: `status = 'active'`, `activates_at` at or before wall-clock now, `operator_email` equal to the JWT email, `alg = 'EdDSA'`, `public_key_cose` the base64url of that authenticator's public key. `issued_at` is wall-clock now. Do not call `registerOperatorCredential`. Start the harness worker with `startWorker` on `e2e/fullstack/wrangler.toml`, the same `dev.registry`, port 8790. The four E2E tests still fail.

**Checkpoint**: The platform and the harness worker start, and one active signer row is in local D1. E2E-P5.1-01, E2E-P5.1-02, E2E-P5.1-03, and E2E-P5.1-06 still fail.

- [ ] T029 [US1] Start Paymob, ABO, and the clinic users in `e2e/fullstack/test/p5-1.test.mjs` — produces the rest of the local stack, FR-012, E2E-P5.1-01, E2E-P5.1-02. Depends on T028 (same file). Paymob: CLI `wrangler dev abo/test/stubs/paymob/worker.ts --port 8789 --ip 127.0.0.1`. The scenarios do not call it. ABO: CLI `wrangler dev --config abo/wrangler.toml --env development --port 8788 --ip 127.0.0.1`, with `PAYMOB_BASE_URL=http://127.0.0.1:8789` and `ISSUER_KEYS` set to the pinned `{kid, public_key}` list. Create the clinic users with supabase-js and sign in. Stop the processes at the end of the run. The four E2E tests still fail.

**Checkpoint**: Paymob, ABO, and signed-in clinic users exist for the run. E2E-P5.1-01, E2E-P5.1-02, E2E-P5.1-03, and E2E-P5.1-06 still fail.

### 8.3 User Story 2 - AI token for the active organisation (Priority: P2) — pin and E2E-P5.1-01

**Independent Test**: E2E-P5.1-01 in harness H-FS.

- [ ] T030 [US2] Register and pin the current `signing` public key in `e2e/fullstack/test/p5-1.test.mjs` — produces the kid the first tokens use, FR-004, FR-010, E2E-P5.1-01. Depends on T029 (same file). Do this before E2E-P5.1-01. Restart ABO `wrangler dev` after the pin. `registerIssuerKey` arguments match the frozen method: `contract_version` 1, `kid`, `public_key`, `not_before`, `not_after`, `access_jwt`, `signer_credential_id`, `operation`, `assertion`. `operation.issued_at` is wall-clock now. `operation.actor_email` is the JWT email. `operation.params` repeats `contract_version`, `access_jwt`, `kid`, `public_key`, `not_before`, and `not_after`. The call goes through `POST /register-issuer-key` on the harness worker.

**Checkpoint**: The current `signing` kid is registered and pinned, and ABO has been restarted. E2E-P5.1-01 still fails until T031.

- [ ] T031 [US2] Make E2E-P5.1-01 pass in `e2e/fullstack/test/p5-1.test.mjs` — produces the accepted AI token and epoch 1, FR-004, E2E-P5.1-01. Depends on T030 (same file). The org A member calls `issue_ai_token(1)`. `GET /v1/capabilities` returns 200. Local D1 has one `tenant_binding` for that org with `epoch` 1. E2E-P5.1-02, E2E-P5.1-03, and E2E-P5.1-06 still fail.

**Checkpoint**: E2E-P5.1-01 passes.

### 8.4 User Story 3 - Administrator billing token (Priority: P3) — E2E-P5.1-02

**Independent Test**: E2E-P5.1-02 in harness H-FS.

- [ ] T032 [US3] Make E2E-P5.1-02 pass in `e2e/fullstack/test/p5-1.test.mjs` — produces the accepted billing token and the doctor refusal, FR-005, FR-009, E2E-P5.1-02. Depends on T031 (same file). The administrator call returns `contract_version` 1. `GET /v1/offers` returns 200. The doctor call returns `FORBIDDEN_ROLE`. E2E-P5.1-01 still passes. E2E-P5.1-03 and E2E-P5.1-06 still fail.

**Checkpoint**: E2E-P5.1-02 passes. E2E-P5.1-01 still passes.

### 8.5 User Story 2 - AI token for the active organisation (Priority: P2) — E2E-P5.1-03

**Independent Test**: E2E-P5.1-01 in harness H-FS.

- [ ] T033 [US2] Make E2E-P5.1-03 pass in `e2e/fullstack/test/p5-1.test.mjs` — produces the two audience refusals, FR-006, E2E-P5.1-03. Depends on T032 (same file). The billing token at the platform and the AI token at the ABO each return 401. E2E-P5.1-01 and E2E-P5.1-02 still pass. E2E-P5.1-06 still fails.

**Checkpoint**: E2E-P5.1-03 passes. E2E-P5.1-01 and E2E-P5.1-02 still pass.

### 8.6 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — E2E-P5.1-06

**Independent Test**: E2E-P5.1-07 in harness H-BK, and E2E-P5.1-06 in harness H-FS.

- [ ] T034 [US1] Make E2E-P5.1-06 pass in `e2e/fullstack/test/p5-1.test.mjs` — produces the signing switch on the full stack, FR-010, FR-012, E2E-P5.1-06. Depends on T033 (same file). Owner `insert_issuer_kid` creates `next`. Pin that public key and restart ABO `wrangler dev`. `registerIssuerKey` for that `kid` returns `ok`. Owner `switch_issuer_signing_kid` with that `kid`. New AI and billing tokens are accepted on `/v1/capabilities` and `/v1/offers`. The earlier tokens are still accepted. `epoch` is unchanged. No `TEST_CLOCK`, no sleep, no `retireIssuerKey`. E2E-P5.1-01, E2E-P5.1-02, and E2E-P5.1-03 still pass.

**Checkpoint**: E2E-P5.1-06 passes. E2E-P5.1-01, E2E-P5.1-02, and E2E-P5.1-03 still pass.

---

## 9. Verification (H-FS)

**Purpose**: Sequencing step 34, the harness run. After T022–T034, before `quickstart.md`. The harness is `npm test` from `e2e/fullstack/`. The H-BK commands are not this task. Earlier suites are not part of this command (rule S2).

### 9.1 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — H-FS harness

**Independent Test**: E2E-P5.1-07 in harness H-BK, and E2E-P5.1-06 in harness H-FS.

- [ ] T035 [US1] Run `npm test` from `e2e/fullstack/` until E2E-P5.1-01, E2E-P5.1-02, E2E-P5.1-03, and E2E-P5.1-06 pass — produces the green H-FS harness, FR-004, FR-005, FR-006, FR-009, FR-010, FR-012, E2E-P5.1-01, E2E-P5.1-02, E2E-P5.1-03, E2E-P5.1-06. Depends on T034 (and therefore on T022–T033). This task may edit only `e2e/fullstack/test/p5-1.test.mjs`. It does not add an E2E id.

```bash
npm test
```

**Checkpoint**: E2E-P5.1-01, E2E-P5.1-02, E2E-P5.1-03, and E2E-P5.1-06 pass.

---

## 10. Documentation

**Purpose**: Sequencing step 34, the quickstart write. After the H-FS harness is green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md`, `data-model.md`, or `contracts/` task.

### 10.1 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — quickstart

**Independent Test**: E2E-P5.1-07 in harness H-BK, and E2E-P5.1-06 in harness H-FS.

- [ ] T036 [US1] Create `specs/087-abo-p5-1-issuer-key-custody-token-issuance/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, E2E-P5.1-01, E2E-P5.1-02, E2E-P5.1-03, E2E-P5.1-04, E2E-P5.1-05, E2E-P5.1-06, E2E-P5.1-07, E2E-P5.1-08, E2E-P5.1-09. Depends on T035. Sections: (1) what was implemented — issuer key custody, the three mints, the versioned issue RPCs, and H-FS; (2) files added or modified — the Files section of `plan.md`; (3) the two harness commands below, and no earlier-unit files, no combined counts, and no full-suite command; (4) the entry point → module chain per E2E id below.

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f backend/tests/ai_keystore_rls.sql
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f backend/tests/issuer_rpc.sql
node backend/tests/contract_versions.mjs
```

```bash
npm test
```

| ID | Chain |
| --- | --- |
| E2E-P5.1-01 | supabase-js `public.issue_ai_token(1)` → `auth_internal.issue_ai_token` → Vault decrypt → `pgsodium.crypto_sign_detached` → platform `GET /v1/capabilities` → `ai-platform/src/worker.ts` → `ai-platform/src/identity/index.ts` → `tenant_binding` insert epoch 1 |
| E2E-P5.1-02 | supabase-js `public.issue_billing_token(1)` → `auth_internal.issue_billing_token` → ABO `GET /v1/offers` → `abo/src/worker.ts` → `abo/src/clinic-api/auth.ts`. Doctor call stops at `FORBIDDEN_ROLE` |
| E2E-P5.1-03 | Billing token to platform `GET /v1/capabilities`; AI token to ABO `GET /v1/offers` |
| E2E-P5.1-04 | psql `public.issue_ai_token` version 2 and omitted argument → raise `CONTRACT_VERSION_UNSUPPORTED` before auth and before any insert. `public.issue_billing_token(1)` row has `contract_version` 1 |
| E2E-P5.1-05 | psql `public.issue_billing_token(1)` twenty times, then the 21st → `RATE_LIMITED` |
| E2E-P5.1-06 | Owner `auth_internal.insert_issuer_kid` → ABO `ISSUER_KEYS` restart → harness worker `PLATFORM.registerIssuerKey` → owner `auth_internal.switch_issuer_signing_kid` → new and old tokens on `GET /v1/capabilities` and `GET /v1/offers` |
| E2E-P5.1-07 | psql clinic role against `ai_internal.issuer_key` and Vault; catalog check that no plaintext key column remains; owner `auth_internal.issue_feed_token`; clinic role denied for that function and for `switch_issuer_signing_kid` |
| E2E-P5.1-08 | PostgREST `public.set_active_organization` then `public.issue_ai_token(1)` |
| E2E-P5.1-09 | `backend/tests/contract_versions.mjs` reads `packages/vendor-contracts/src/version.ts` and passes those integers into psql against `ai.contract_versions` |

**Checkpoint**: `quickstart.md` names the files, the two harness commands, and the nine chains.

---

## 11. Dependencies & Execution Order

### 11.1 Phase Dependencies

- **Tests (H-BK, §3)**: No dependencies. One failing test per H-BK E2E id, in sequencing order: E2E-P5.1-07, then E2E-P5.1-04, E2E-P5.1-05, E2E-P5.1-08, then E2E-P5.1-09. All of them fail before the migration exists.
- **Implementation (backend, §4)**: Depends on §3. Registration, then the migration in story order inside that one file, then the existing SQL suites.
- **Verification (H-BK, §5)**: Depends on §4. The three H-BK commands pass before any `e2e/fullstack/` file exists.
- **Implementation (H-FS package, §6)**: Depends on §5.
- **Tests (H-FS, §7)**: Depend on the package. One failing test per H-FS E2E id: E2E-P5.1-01, E2E-P5.1-02, E2E-P5.1-03, then E2E-P5.1-06. All of them fail before the runner starts the stack.
- **Implementation (H-FS runner, §8)**: Depends on §7. CI job, then platform and signer, then Paymob, ABO, and users, then pin, then E2E-P5.1-01, E2E-P5.1-02, E2E-P5.1-03, and E2E-P5.1-06.
- **Verification (H-FS, §9)**: Depends on §8.
- **Documentation (§10)**: Depends on §9.

### 11.2 User Story Dependencies

- **User Story 1 (P1)**: E2E-P5.1-07 is the first H-BK test. The issuer key, the installation drop, the feed mint, and the signing switch land in the migration before the H-BK harness is green. E2E-P5.1-06 is the last H-FS test and runs after E2E-P5.1-01, E2E-P5.1-02, and E2E-P5.1-03.
- **User Story 2 (P2)**: E2E-P5.1-08 follows E2E-P5.1-05 in `issuer_rpc.sql`. `issue_ai_token` follows `rpc_result`. E2E-P5.1-01 is the first H-FS test. E2E-P5.1-03 follows E2E-P5.1-02.
- **User Story 3 (P3)**: E2E-P5.1-05 follows E2E-P5.1-04 in `issuer_rpc.sql`. `issue_billing_token` follows `issue_ai_token`. E2E-P5.1-02 follows E2E-P5.1-01.
- **User Story 4 (P4)**: E2E-P5.1-04 is the first test in `issuer_rpc.sql`. E2E-P5.1-09 is its own script and follows E2E-P5.1-08. `app_settings` and `rpc_result` sit between the installation drop and `issue_ai_token`.

### 11.3 Within Each Phase

- T001 writes only `backend/tests/ai_keystore_rls.sql`.
- T002 creates `backend/tests/issuer_rpc.sql`. T003 and T004 write that same file, in that id order.
- T005 writes only `backend/tests/contract_versions.mjs`.
- T006 writes `backend/tests/run_all_backend_tests.sh` and the `backend-sql` job in `.github/workflows/ci.yml`.
- T007 creates `backend/supabase/migrations/20261007180000_issuer_key_custody.sql`. T008 through T015 write that same file, in that id order.
- T016 writes only `backend/tests/ai_token_issuer.sql`.
- T017 writes only `backend/tests/catalog/stage-02-revoke-rotate-availability.sql`. T018 writes only `backend/tests/catalog/stage-02-availability-and-enroll.sql`. Neither edits the other.
- T019 writes only `backend/tests/catalog/stage-06-verify-and-handoff.sql` after T017 and T018.
- T020 writes only `backend/tests/cross_tenant_suite.sql`.
- T021 runs after T020 and may edit only `backend/tests/ai_keystore_rls.sql`, `backend/tests/issuer_rpc.sql`, and `backend/tests/contract_versions.mjs`.
- T022 writes `e2e/fullstack/package.json`, `e2e/fullstack/wrangler.toml`, and `e2e/fullstack/src/register-issuer.ts`, and leaves the test file uncreated.
- T023 creates `e2e/fullstack/test/p5-1.test.mjs`. T024 through T026, T028 through T034, and T035 write that same file, in that id order. T027 writes only job `fullstack` in `.github/workflows/ci.yml` and keeps the T006 edit.
- T036 writes only `specs/087-abo-p5-1-issuer-key-custody-token-issuance/quickstart.md` after T035 is green.

---

## 12. Implementation Waves

### 12.1 Wave 1

- T001 [US1] — subphase: `### 3.1 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — tests` — paths: `backend/tests/ai_keystore_rls.sql`

### 12.2 Wave 2

- T002 [US4] — subphase: `### 3.2 User Story 4 - RPC contract version (Priority: P4) — tests (part 1)` — paths: `backend/tests/issuer_rpc.sql`

### 12.3 Wave 3

- T003 [US3] — subphase: `### 3.3 User Story 3 - Administrator billing token (Priority: P3) — tests` — paths: `backend/tests/issuer_rpc.sql`

### 12.4 Wave 4

- T004 [US2] — subphase: `### 3.4 User Story 2 - AI token for the active organisation (Priority: P2) — tests` — paths: `backend/tests/issuer_rpc.sql`

### 12.5 Wave 5

- T005 [US4] — subphase: `### 3.5 User Story 4 - RPC contract version (Priority: P4) — tests (part 2)` — paths: `backend/tests/contract_versions.mjs`

### 12.6 Wave 6

- T006 [US4] — subphase: `### 4.1 User Story 4 - RPC contract version (Priority: P4) — harness registration` — paths: `backend/tests/run_all_backend_tests.sh`, `.github/workflows/ci.yml`

### 12.7 Wave 7

- T007–T008 [US1] — subphase: `### 4.2 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — issuer key and installation drop` — paths: `backend/supabase/migrations/20261007180000_issuer_key_custody.sql`

### 12.8 Wave 8

- T009 [US4] — subphase: `### 4.3 User Story 4 - RPC contract version (Priority: P4) — app settings` — paths: `backend/supabase/migrations/20261007180000_issuer_key_custody.sql`

### 12.9 Wave 9

- T010 [US3] — subphase: `### 4.4 User Story 3 - Administrator billing token (Priority: P3) — issuance audience` — paths: `backend/supabase/migrations/20261007180000_issuer_key_custody.sql`

### 12.10 Wave 10

- T011 [US4] — subphase: `### 4.5 User Story 4 - RPC contract version (Priority: P4) — rpc_result` — paths: `backend/supabase/migrations/20261007180000_issuer_key_custody.sql`

### 12.11 Wave 11

- T012 [US2] — subphase: `### 4.6 User Story 2 - AI token for the active organisation (Priority: P2) — issue_ai_token` — paths: `backend/supabase/migrations/20261007180000_issuer_key_custody.sql`

### 12.12 Wave 12

- T013 [US3] — subphase: `### 4.7 User Story 3 - Administrator billing token (Priority: P3) — issue_billing_token` — paths: `backend/supabase/migrations/20261007180000_issuer_key_custody.sql`

### 12.13 Wave 13

- T014–T015 [US1] — subphase: `### 4.8 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — feed mint and signing switch` — paths: `backend/supabase/migrations/20261007180000_issuer_key_custody.sql`

### 12.14 Wave 14

- T016 [US2] — subphase: `### 4.9 User Story 2 - AI token for the active organisation (Priority: P2) — existing issuer SQL` — paths: `backend/tests/ai_token_issuer.sql`

### 12.15 Wave 15

- T017 [US1] — subphase: `### 4.10 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — stage-02 revoke catalog` — paths: `backend/tests/catalog/stage-02-revoke-rotate-availability.sql`
- T018 [US1] — subphase: `### 4.11 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — stage-02 enroll catalog` — paths: `backend/tests/catalog/stage-02-availability-and-enroll.sql`

### 12.16 Wave 16

- T019 [US2] — subphase: `### 4.12 User Story 2 - AI token for the active organisation (Priority: P2) — stage-06 catalog` — paths: `backend/tests/catalog/stage-06-verify-and-handoff.sql`

### 12.17 Wave 17

- T020 [US2] — subphase: `### 4.13 User Story 2 - AI token for the active organisation (Priority: P2) — cross-tenant suite` — paths: `backend/tests/cross_tenant_suite.sql`

### 12.18 Wave 18

- T021 [US4] — subphase: `### 5.1 User Story 4 - RPC contract version (Priority: P4) — H-BK harness` — paths: `backend/tests/ai_keystore_rls.sql`, `backend/tests/issuer_rpc.sql`, `backend/tests/contract_versions.mjs`

### 12.19 Wave 19

- T022 [US1] — subphase: `### 6.1 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — package, worker, register route` — paths: `e2e/fullstack/package.json`, `e2e/fullstack/wrangler.toml`, `e2e/fullstack/src/register-issuer.ts`

### 12.20 Wave 20

- T023 [US2] — subphase: `### 7.1 User Story 2 - AI token for the active organisation (Priority: P2) — tests (part 1)` — paths: `e2e/fullstack/test/p5-1.test.mjs`

### 12.21 Wave 21

- T024 [US3] — subphase: `### 7.2 User Story 3 - Administrator billing token (Priority: P3) — tests` — paths: `e2e/fullstack/test/p5-1.test.mjs`

### 12.22 Wave 22

- T025 [US2] — subphase: `### 7.3 User Story 2 - AI token for the active organisation (Priority: P2) — tests (part 2)` — paths: `e2e/fullstack/test/p5-1.test.mjs`

### 12.23 Wave 23

- T026 [US1] — subphase: `### 7.4 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — tests` — paths: `e2e/fullstack/test/p5-1.test.mjs`

### 12.24 Wave 24

- T027 [US1] — subphase: `### 8.1 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — CI job` — paths: `.github/workflows/ci.yml`

### 12.25 Wave 25

- T028–T029 [US1] — subphase: `### 8.2 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — workers and clinic users` — paths: `e2e/fullstack/test/p5-1.test.mjs`

### 12.26 Wave 26

- T030–T031 [US2] — subphase: `### 8.3 User Story 2 - AI token for the active organisation (Priority: P2) — pin and E2E-P5.1-01` — paths: `e2e/fullstack/test/p5-1.test.mjs`

### 12.27 Wave 27

- T032 [US3] — subphase: `### 8.4 User Story 3 - Administrator billing token (Priority: P3) — E2E-P5.1-02` — paths: `e2e/fullstack/test/p5-1.test.mjs`

### 12.28 Wave 28

- T033 [US2] — subphase: `### 8.5 User Story 2 - AI token for the active organisation (Priority: P2) — E2E-P5.1-03` — paths: `e2e/fullstack/test/p5-1.test.mjs`

### 12.29 Wave 29

- T034 [US1] — subphase: `### 8.6 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — E2E-P5.1-06` — paths: `e2e/fullstack/test/p5-1.test.mjs`

### 12.30 Wave 30

- T035 [US1] — subphase: `### 9.1 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — H-FS harness` — paths: `e2e/fullstack/test/p5-1.test.mjs`

### 12.31 Wave 31

- T036 [US1] — subphase: `### 10.1 User Story 1 - Issuer key custody and signing-kid switch (Priority: P1) — quickstart` — paths: `specs/087-abo-p5-1-issuer-key-custody-token-issuance/quickstart.md`
