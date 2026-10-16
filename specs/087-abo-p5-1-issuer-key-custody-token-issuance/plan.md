# Implementation Plan: Issuer key custody, token issuance and the versioned RPC envelope

**Branch**: `ai/087-abo-p5-1-issuer-key-custody-token-issuance` | **Date**: 2026-10-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/087-abo-p5-1-issuer-key-custody-token-issuance/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

The shared backend keeps an Ed25519 issuer key set in `ai_internal`, signs AI, billing, and feed tokens from Vault through SQL, and versions `issue_ai_token` and `issue_billing_token`. This unit also builds harness H-FS. It is phase P5, size L, **Depends** P1.2, P3.2, and P4.1, in parallel with P4.2–P4.11 and P3.x.

## Technical Context

**Language/Version**: PostgreSQL on local Supabase for the issuer migration and H-BK. The H-FS runner is Node (`>=22`) in `e2e/fullstack/`. Platform and ABO stay the existing workers.

**Primary Dependencies**: `pgsodium` 3.1.8 and `supabase_vault` 0.3.1, already installed on local Supabase ([research.md](./research.md)). `packages/vendor-contracts` (`file:` dependency) for `CHANNEL_VERSIONS`, `createAccessTeam`, and `createSoftwareAuthenticator`. `@supabase/supabase-js` for clinic RPC calls. `wrangler` `~4.86.0` for `startWorker` and CLI `wrangler dev`. No Edge Function. No new platform or ABO library.

**Storage**: Supabase PostgreSQL for `ai_internal.issuer_key`, `ai_token_issuance`, and `app_settings`. Private key bytes live in Vault under `secret_ref`. Platform D1 `operator_credential` and `issuer_key` stay the consumed P3.2 tables. ABO `ISSUER_KEYS` stays process config.

**Testing**: H-BK for E2E-P5.1-04, 05, 07, 08, and 09 (`backend/tests/`, psql, plus one Node script that reads `packages/vendor-contracts/src/version.ts`). H-FS for E2E-P5.1-01, 02, 03, and 06 (`e2e/fullstack/`). Titles start with the E2E id (rule V3). Tests are written to fail before the behavior exists. H-FS does not sleep 10 minutes, does not call `retireIssuerKey`, and does not set `TEST_CLOCK`.

**Target Platform**: Local Supabase (`supabase start`), the platform on wrangler's local workerd through `startWorker` (same runtime as `wrangler dev`), the ABO on CLI `wrangler dev`, and the existing Paymob stub process. Clinic calls use PostgREST. Owner calls use a direct Postgres connection.

**Project Type**: Backend, plus the named H-FS wiring exception (`e2e/fullstack/`). No second product service.

**Performance Goals**: Clinic-scale minting. AI token life 600 seconds, billing token life 300 seconds, feed token life 120 seconds. Billing mint limit 20 per user per 10 minutes.

**Constraints**: Version check runs before authentication and before any write. `org` comes from `current_org_id()`. Billing mint requires membership role `administrator`. `secret_ref` is the only private-key reference. Clinic roles cannot read Vault or `issuer_key`, and cannot execute `issue_feed_token`, `insert_issuer_kid`, or `switch_issuer_signing_kid`. Platform source, platform wrangler envs, and `registerOperatorCredential`'s 24-hour pending insert stay as they are. `ai.availability` and the availability RPCs stay until P5.2.

**Scale/Scope**: Size L (rule S3: 4 user stories, backend plus the H-FS harness). Nine E2E ids. Implied task count is 34 (the sequencing below).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (version 1.0.0, rule S12). R-3 passed in [research.md](./research.md), so the Edge Function signer is not added. The same boxes hold after the data model.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  A clinic member mints an AI token for the active organisation. An administrator mints a short billing token for that organisation. Overlapping `kid`s keep a session valid across rotation (spec §4.1, 02 §7 principle I).

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  Signing stays in PostgreSQL. Vault is the existing Supabase secret store. H-FS is a test runner, not a product service. The Edge Function fallback is not used (02 §7 principle I).

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Custody, claims, rate limits, and the version check are PostgreSQL functions reached through Supabase RPCs. Flutter is out of this unit. The platform and the ABO stay consumed verifiers (spec §4.1, 02 §7 principle II).

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  Issuer rows, issuance rows, and the version refusal are written only by definer functions. `status` uniqueness is a constraint. `switch_issuer_signing_kid` is one transaction (02 §7 principle III).

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  `org` comes from `current_org_id()`. Billing requires role `administrator`. Private key material is a Vault id. Clinic roles cannot read it. Dropping `installation_keys` removes the plaintext `secret_key` column the design names (02 §3.1 Removed, 03 §4). Clinic clinical rows are not hard-deleted (02 §7 principle IV).

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit mints issuer tokens. It does not add a model call or a path from a model into PostgreSQL. Clinical work does not depend on these tokens (02 §7 principle V).

| Principle or rule | How this unit complies |
| --- | --- |
| I. Product fit and simplicity | One issuer key set on the existing Supabase project. No second deployable. |
| II. Replaceable layer boundaries | Codebase is backend plus the H-FS harness. Platform and ABO code are not modified. |
| III. Backend authority and data integrity | Issuer state and token issuance are definer RPCs keyed on `current_org_id()`. |
| IV. Secure and human-gated operations | Clinic calls are authenticated. The signing switch and the feed mint are not public RPCs. Platform `registerIssuerKey` stays class HP and is only called as that consumed method. |
| V. Operational continuity | A failed version check writes nothing. A wrong-audience token is 401 at the other service. AI being down does not block clinic records. |
| Workflow automation | No new cron and no DAG. |
| Higher operational burden | The new burden is the key set and the H-FS runner already named in 02 §6 and 06 §3 V1. |

## Project Structure

### Documentation (this feature)

```text
specs/087-abo-p5-1-issuer-key-custody-token-issuance/
├── plan.md
├── research.md          # R-3 outcome
├── data-model.md
├── spec.md
├── escalations.md
└── quickstart.md        # implement writes this after both unit commands are green
```

No `contracts/` (the unit row has no Outputs / freezes line). No `tasks.md` in this phase.

`quickstart.md` sections, written by implement after the harnesses are green:

1. What was implemented — issuer key custody, the three mints, the versioned issue RPCs, and H-FS.
2. Files added or modified — the Files section of this plan.
3. Harness commands for this unit's tests only — the two commands in Test Layout. No earlier-unit files, no combined counts, and no full-suite command.
4. Entry point → module chain per E2E id — the table below.

| E2E id | Chain |
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

### Source Code (repository root)

```text
backend/
├── supabase/migrations/20261007180000_issuer_key_custody.sql
└── tests/
    ├── ai_keystore_rls.sql
    ├── ai_token_issuer.sql
    ├── issuer_rpc.sql
    ├── contract_versions.mjs
    ├── cross_tenant_suite.sql
    ├── catalog/stage-02-revoke-rotate-availability.sql
    ├── catalog/stage-02-availability-and-enroll.sql
    ├── catalog/stage-06-verify-and-handoff.sql
    └── run_all_backend_tests.sh

e2e/fullstack/
├── package.json
├── wrangler.toml
├── src/register-issuer.ts
└── test/p5-1.test.mjs

.github/workflows/ci.yml
```

**Structure Decision**: Issuer objects and the issue RPC bodies live in one new backend migration. The feed mint is `auth_internal.issue_feed_token()`. The next-kid insert is `auth_internal.insert_issuer_kid()`. H-FS lives in `e2e/fullstack/`. Platform source and ABO source are not modified.

## Consumes Binding

| Consumes | Existing module | This unit |
| --- | --- | --- |
| P1.2 tenant inventory | Tables and policies in `backend/supabase/migrations/20261002150000_tenant_scoping.sql`, listed in `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/research.md` | Not rewritten. `issue_ai_token` still writes `organization_id` from `current_org_id()`. |
| P1.2 per-tenant `roles_permissions` | `public.roles_permissions` (`organization_id`, unique `(organization_id, role, permission_key)`) and `auth_internal.update_role_permission` / `update_role_permissions` in that migration | Read for `ai.*` scopes where `organization_id = current_org_id()` and `role = current_membership_role()`. Not modified. |
| P1.2 cross-tenant suite | `backend/tests/cross_tenant_suite.sql` | Call sites that used `enroll_installation_keypair` and `issue_ai_token(text[])` are updated to the new signature and the owner insert. Tenant assertions stay. |
| P1.2 `current_org_id()` and `set_active_organization` | `backend/supabase/migrations/20261002120000_membership_active_org.sql` | Called. Not edited. |
| P3.2 AI-token verification | `ai-platform/src/identity/index.ts` (`IssuerTokenVerifier` path on `GET /v1/capabilities`). Frozen rules in `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/contracts/ai-token-verification.md` | Presented with tokens. Not modified. |
| P3.2 `tenant_binding` (epoch) | D1 `tenant_binding` in `ai-platform/migrations/20261003130000_issuer_key_tenant_binding.sql`, created on first valid token in `ai-platform/src/identity/index.ts` | Read back from local D1. Not modified. |
| P3.2 issuer-key methods | `VendorEntrypoint.registerIssuerKey` in `ai-platform/src/vendor/entrypoint.ts`. Frozen in `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/contracts/issuer-key-methods.md` | Called over the harness service binding. `retireIssuerKey` is not called. Platform source is not modified. |
| P4.1 ABO clinic-API envelope, auth, and error rules | `abo/src/clinic-api/version.ts`, `abo/src/clinic-api/auth.ts` (`authenticateBilling`), `abo/src/clinic-api/offers.ts` | `GET /v1/offers` with `Host: billing.vendor.test`. Not modified. |
| P4.1 records conventions | `abo/src/records/append.ts`, `abo/src/records/export.ts` | Not called. Not modified. |
| P4.1 alert engine | `abo/src/alert/index.ts` (`raiseAlert`) | Not called. Not modified. |
| P4.1 H-ABO | `abo/test/system/` under `abo/vitest.workers.config.ts` | Not run as this unit's command. Not modified. |
| Paymob stub | `abo/test/stubs/paymob/worker.ts` | Started as a process. Not modified and not copied. |

## Files

| Path | Action | FR |
| --- | --- | --- |
| `specs/087-abo-p5-1-issuer-key-custody-token-issuance/research.md` | R-3 outcome. | FR-001 |
| `specs/087-abo-p5-1-issuer-key-custody-token-issuance/data-model.md` | Entities in spec §3.2. | FR-002, FR-003, FR-007, FR-008, FR-009 |
| `specs/087-abo-p5-1-issuer-key-custody-token-issuance/quickstart.md` | Implement phase, after both unit commands are green. | FR-001–FR-012 |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | Create the objects in [data-model.md](./data-model.md) and the functions below. | FR-002, FR-003, FR-004, FR-005, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `backend/tests/ai_keystore_rls.sql` | E2E-P5.1-07. | FR-002, FR-003, FR-011 |
| `backend/tests/issuer_rpc.sql` | E2E-P5.1-04, E2E-P5.1-05, E2E-P5.1-08. | FR-004, FR-005, FR-007, FR-009 |
| `backend/tests/contract_versions.mjs` | E2E-P5.1-09. Reads `version.ts` as text. Does not copy the constants into the script. | FR-008 |
| `backend/tests/ai_token_issuer.sql` | Call `issue_ai_token(1)` and the issuer-key signer. | FR-003, FR-004 |
| `backend/tests/catalog/stage-02-revoke-rotate-availability.sql` | Stop calling the dropped RPCs. Availability cases stay. | FR-003 |
| `backend/tests/catalog/stage-02-availability-and-enroll.sql` | Stop calling enroll. Availability cases stay. | FR-003 |
| `backend/tests/catalog/stage-06-verify-and-handoff.sql` | Stop signing with `installation_keys.secret_key`. | FR-003, FR-004 |
| `backend/tests/cross_tenant_suite.sql` | Replace enroll setup with owner `insert_issuer_kid`. Replace `issue_ai_token(text[])` with `issue_ai_token(1)`. Leave the tenant assertions. | FR-003, FR-004 |
| `backend/tests/run_all_backend_tests.sh` | Add `issuer_rpc.sql` and `node backend/tests/contract_versions.mjs`. | FR-008, FR-009 |
| `e2e/fullstack/package.json` | `file:../packages/vendor-contracts`, `@supabase/supabase-js`, `wrangler` `~4.86.0`. Script `test` runs `node --test test/p5-1.test.mjs`. | FR-012 |
| `e2e/fullstack/wrangler.toml` | Harness worker. `PLATFORM` service binding to `ai-platform-gateway-development`, `entrypoint = "VendorEntrypoint"`. No `TEST_CLOCK`. | FR-010, FR-012 |
| `e2e/fullstack/src/register-issuer.ts` | `fetch` on `POST /register-issuer-key` calls `env.PLATFORM.registerIssuerKey` and returns the envelope. This route is not added to the platform or the ABO. | FR-010, FR-012 |
| `e2e/fullstack/test/p5-1.test.mjs` | E2E-P5.1-01, 02, 03, and 06. | FR-004, FR-005, FR-006, FR-009, FR-010, FR-012 |
| `.github/workflows/ci.yml` | Job `fullstack` runs `e2e/fullstack`. Job `backend-sql` gains Node so `contract_versions.mjs` can read `version.ts`. | FR-008, FR-012 |

Inside the migration:

- `auth_internal.insert_issuer_kid()` returns `kid`, `public_key`, `status`, `not_before`, `not_after`. No signing row yet → insert `signing`. A signing row and no next row → insert `next`. A next row already present → return that row and insert nothing. The migration calls it once.
- `auth_internal.switch_issuer_signing_kid(p_kid text)` moves that `next` row to `signing` and the previous `signing` row to `retired` in one transaction. Any other `p_kid` changes nothing.
- `auth_internal.issue_feed_token()` takes no `p_contract_version`. `REVOKE ALL` on these three functions from `PUBLIC`, `anon`, `authenticated`, and `service_role`.
- `public.issue_ai_token(p_contract_version integer DEFAULT NULL)` and `public.issue_billing_token(p_contract_version integer DEFAULT NULL)` are `SECURITY DEFINER`, granted to `authenticated`, and delegate to `auth_internal` after the version check. Drop `issue_ai_token(text[])` in both schemas.
- `public.rpc_success(jsonb)` and `public.rpc_error(text, text)` are replaced with an added `p_contract_version integer DEFAULT NULL`. The existing callers still match. These five bodies still cast a 4-column row and are replaced in this migration so the fifth field is null: `auth_internal.create_patient(uuid, text, text, date, text, text, text, boolean, text)`, `auth_internal.invoke_acceptance_domain_rpc(text, jsonb)`, `auth_internal.reassign_patient_mrn(uuid, text)`, and both `auth_internal.update_patient` overloads. Their logic is otherwise copied from the current definitions.

`20260801120000_ai_keystore_schema.sql` and `20260905120300_fix_aat_lifetime_fallback.sql` are not edited. `ai-platform/` and `abo/src/` are not edited.

## Test Layout

### H-BK

Files: `backend/tests/ai_keystore_rls.sql`, `backend/tests/issuer_rpc.sql`, `backend/tests/contract_versions.mjs`. Titles start with the E2E id. Each test fails while the behavior it names is absent.

Unit command, from the repository root:

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f backend/tests/ai_keystore_rls.sql
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f backend/tests/issuer_rpc.sql
node backend/tests/contract_versions.mjs
```

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P5.1-04 | H-BK | Title `E2E-P5.1-04 Version 2 raises CONTRACT_VERSION_UNSUPPORTED and rpc_result carries contract_version`. `public.issue_ai_token(2)` and `public.issue_ai_token()` raise `CONTRACT_VERSION_UNSUPPORTED`. The exception detail is `accepted_versions` `[0, 1]`. No issuance row is inserted. A prior unauthenticated session is not required. `public.issue_billing_token(1)` as an administrator returns `contract_version` 1. |
| E2E-P5.1-05 | H-BK | Title `E2E-P5.1-05 21st billing token in 10 min is RATE_LIMITED`. One user. Twenty `public.issue_billing_token(1)` calls succeed. The 21st returns `error_code` `RATE_LIMITED` and does not insert a 21st `aud = 'abo'` row. AI rows for that user do not count. |
| E2E-P5.1-07 | H-BK | Title `E2E-P5.1-07 No clinic role can read private key material and no plaintext key column remains`. As `authenticated`, `SELECT` on `ai_internal.issuer_key` and `vault.decrypted_secrets` is denied. `information_schema` has no `secret_key` column under `ai_internal`, and `installation_keys` is absent. As the database owner, `auth_internal.issue_feed_token()` has `aud` `ai-platform-feed`, `sub` `backend-feed`, no `org`, and `exp − iat` of 120 seconds. As `authenticated`, `issue_feed_token` and `switch_issuer_signing_kid` cannot be executed. |
| E2E-P5.1-08 | H-BK | Title `E2E-P5.1-08 Membership switched to org B yields token org B`. `public.set_active_organization` to org B, then `public.issue_ai_token(1)`. The token `org` is B and equals `current_org_id()`. |
| E2E-P5.1-09 | H-BK | Title `E2E-P5.1-09 ai.contract_versions equals the package constants`. The script reads `CHANNEL_VERSIONS` out of `packages/vendor-contracts/src/version.ts` and passes those integers to psql. Each stored `current` equals that integer and each stored `minimum` equals `current - 1`. |

### H-FS

File: `e2e/fullstack/test/p5-1.test.mjs`. The runner creates real Auth users with supabase-js, signs in, and calls the RPCs as those users. Owner SQL uses `psql` and `DB_URL`.

Stack, started by the test and stopped at the end:

- `supabase start` is already up from the job (local API `http://127.0.0.1:54321`).
- Platform: `startWorker({ config: ai-platform/wrangler.toml, env: "development", dev: { server: { hostname: "127.0.0.1", port: 8787 }, persist: e2e/fullstack/.wrangler/platform, registry: e2e/fullstack/.wrangler/registry, mockFetch } })`. `mockFetch` is an undici `MockAgent` that answers only `GET https://access.test/cdn-cgi/access/certs` with the `createAccessTeam` certs document. Other origins still use the network. `TEST_CLOCK` is not set.
- Harness worker: `startWorker` on `e2e/fullstack/wrangler.toml`, same `dev.registry`, port 8790.
- ABO: CLI `wrangler dev --config abo/wrangler.toml --env development --port 8788 --ip 127.0.0.1`, with `PAYMOB_BASE_URL=http://127.0.0.1:8789` and `ISSUER_KEYS` set to the pinned `{kid, public_key}` list. Clinic ABO calls send `Host: billing.vendor.test`.
- Paymob: CLI `wrangler dev abo/test/stubs/paymob/worker.ts --port 8789 --ip 127.0.0.1`. The scenarios do not call it.

Signer row, before `registerIssuerKey`: `createAccessTeam({ issuer: "https://access.test" })` mints the JWT with wall-clock `iat` and `exp` (`exp` is `iat + 3600`), `aud` `vendor-access-aud`. `createSoftwareAuthenticator("EdDSA")` signs the assertion (`up` and `uv` true, `rpId` `ops.vendor.test`, `origin` `https://ops.vendor.test`). The runner inserts one `operator_credential` into local D1 database `ai-platform-development` with `--local --persist-to e2e/fullstack/.wrangler/platform`: `status = 'active'`, `activates_at` at or before wall-clock now, `operator_email` equal to the JWT email, `alg = 'EdDSA'`, `public_key_cose` the base64url of that authenticator's public key. It does not call `registerOperatorCredential`.

`registerIssuerKey` arguments match the frozen method: `contract_version` 1, `kid`, `public_key`, `not_before`, `not_after`, `access_jwt`, `signer_credential_id`, `operation`, `assertion`. `operation.issued_at` is wall-clock now. `operation.actor_email` is the JWT email. `operation.params` repeats `contract_version`, `access_jwt`, `kid`, `public_key`, `not_before`, and `not_after`.

Unit command, from `e2e/fullstack/`:

```bash
npm test
```

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P5.1-01 | H-FS | Title `E2E-P5.1-01 Org A member issue_ai_token(1) is accepted by the local platform and A's binding is created`. After the signing `kid` is registered and pinned, the org A member calls `issue_ai_token(1)`. `GET /v1/capabilities` returns 200. Local D1 has one `tenant_binding` for that org with `epoch` 1. |
| E2E-P5.1-02 | H-FS | Title `E2E-P5.1-02 Administrator issue_billing_token(1) is accepted by the local ABO and a doctor receives FORBIDDEN_ROLE`. The administrator call returns `contract_version` 1. `GET /v1/offers` returns 200. The doctor call returns `FORBIDDEN_ROLE`. |
| E2E-P5.1-03 | H-FS | Title `E2E-P5.1-03 Billing token at the platform and AI token at the ABO are 401`. |
| E2E-P5.1-06 | H-FS | Title `E2E-P5.1-06 New signing kid is accepted everywhere, old tokens stay valid, and the binding is unchanged`. Mint one AI token and one billing token on the current `kid` and record `tenant_binding.epoch`. Owner `insert_issuer_kid` creates `next`. Pin that public key and restart ABO `wrangler dev`. `registerIssuerKey` for that `kid` returns `ok`. Owner `switch_issuer_signing_kid` with that `kid`. New AI and billing tokens are accepted on `/v1/capabilities` and `/v1/offers`. The earlier tokens are still accepted. `epoch` is unchanged. The test does not sleep and does not call `retireIssuerKey`. |

## Sequencing

Tests before implementation. Each new test is observed failing before the code that makes it pass. 34 steps.

1. Add E2E-P5.1-07 to `backend/tests/ai_keystore_rls.sql`. Run that file. It fails.
2. Add `backend/tests/issuer_rpc.sql` with E2E-P5.1-04. Run it. It fails.
3. Add E2E-P5.1-05 to that file. Run it. It fails.
4. Add E2E-P5.1-08 to that file. Run it. It fails.
5. Add `backend/tests/contract_versions.mjs` for E2E-P5.1-09. Run it. It fails.
6. Register `issuer_rpc.sql` and `node backend/tests/contract_versions.mjs` in `backend/tests/run_all_backend_tests.sh`. Add Node to the `backend-sql` job. The unit command stays the three commands in Test Layout.
7. Add `20261007180000_issuer_key_custody.sql` with `ai_internal.issuer_key`, the status checks and partial unique indexes, Vault `secret_ref`, deny-all RLS, and `auth_internal.insert_issuer_kid`. Call it once so one `signing` row exists.
8. In that migration, drop `installation_keys`, `enforce_single_installation`, the single-installation trigger, every overload of `enroll_installation_keypair`, `rotate_installation_key`, and `revoke_installation_key` in `public` and `auth_internal`, and `ai_token_issuance.installation_id`.
9. Insert `ai.platform_base_url`, `ai.abo_base_url`, `ai.issuer_id`, and `ai.contract_versions` as in [data-model.md](./data-model.md). Leave `ai.availability`.
10. Add `ai_token_issuance.aud`, backfill existing rows to `ai-platform`, set `NOT NULL`, and index `(actor_staff_id, aud, iat)` where `is_deleted = false`.
11. `ALTER TYPE public.rpc_result ADD ATTRIBUTE contract_version integer`. Replace `rpc_success` and `rpc_error` with the extra argument defaulting to null. Replace the five cast sites listed in Files so the fifth field is null.
12. Replace `issue_ai_token` with `public` and `auth_internal` bodies that take `p_contract_version integer`. Drop the `text[]` signatures. The public body checks the version before `auth_internal` and before any session read or insert. Null or any integer other than 0 or 1 raises `CONTRACT_VERSION_UNSUPPORTED` with detail `{"accepted_versions":[0,1]}`. The token matches [data-model.md](./data-model.md). Scopes use the P1.2 `roles_permissions` query. A role with no granted `ai.*` key still raises `AI_ACCESS_DENIED`. The header includes `typ` `JWT`. `iss` is `ai.issuer_id`. `ver` is `"2"`. `exp − iat` is 600. The ledger row stores `aud` `ai-platform` and `organization_id`.
13. Add `issue_billing_token`. Administrator only. Return `rpc_result` with `data` `{token, abo_base_url, expires_at}` and `contract_version` echoed. A doctor returns `FORBIDDEN_ROLE` and inserts nothing. A missing or refused version returns `CONTRACT_VERSION_UNSUPPORTED`, `accepted_versions` in `data`, and `contract_version` 1, before authentication and before any insert. The 21st `aud = 'abo'` row in 10 minutes returns `RATE_LIMITED`. Serialize the count and the insert per user and audience. Token life is 300 seconds. No `scopes` claim.
14. Add `auth_internal.issue_feed_token` as in [data-model.md](./data-model.md). Revoke execute from clinic roles. It does not insert `ai_token_issuance`.
15. Add `auth_internal.switch_issuer_signing_kid`. Revoke execute from clinic roles. A `p_kid` that is not `next` changes nothing.
16. Update `backend/tests/ai_token_issuer.sql` to `issue_ai_token(1)` and the `signing` kid.
17. Update the two stage-02 catalog files so they no longer call the dropped RPCs. Keep the availability cases.
18. Update `backend/tests/catalog/stage-06-verify-and-handoff.sql` so it does not read `installation_keys.secret_key`.
19. Update `backend/tests/cross_tenant_suite.sql` call sites only, as in Files.
20. Run the H-BK unit command. E2E-P5.1-04, 05, 07, 08, and 09 pass.
21. Add `e2e/fullstack/package.json`, `wrangler.toml`, and `src/register-issuer.ts`.
22. Add E2E-P5.1-01 to `test/p5-1.test.mjs`. Run `npm test`. It fails.
23. Add E2E-P5.1-02. Run `npm test`. It fails.
24. Add E2E-P5.1-03. Run `npm test`. It fails.
25. Add E2E-P5.1-06. Run `npm test`. It fails.
26. Add the `fullstack` job to `.github/workflows/ci.yml`. It checks out, installs Node, the Supabase CLI, and `psql`, runs `supabase start` in `backend/`, then `npm ci` and `npm test` in `e2e/fullstack/`.
27. In the runner, start the platform with `startWorker` and `dev.mockFetch`, then insert the active `operator_credential` row. Start the harness worker on the shared dev registry.
28. Start the Paymob stub and ABO `wrangler dev`. Create the clinic users with supabase-js and sign in.
29. Register and pin the current `signing` public key before E2E-P5.1-01. Restart ABO after the pin.
30. E2E-P5.1-01 passes: `/v1/capabilities` is 200 and `tenant_binding.epoch` is 1.
31. E2E-P5.1-02 passes: `/v1/offers` is 200, `contract_version` is 1, and the doctor receives `FORBIDDEN_ROLE`.
32. E2E-P5.1-03 passes: both wrong-audience calls return 401.
33. E2E-P5.1-06 passes: `next` is pinned and registered, `switch_issuer_signing_kid` runs, new tokens are accepted on both services, the earlier tokens are still accepted, and `epoch` is unchanged. No `TEST_CLOCK`, no sleep, no `retireIssuerKey`.
34. Run `npm test` from `e2e/fullstack/` and confirm E2E-P5.1-01, 02, 03, and 06 pass. Write `quickstart.md` from the outline above.

## Complexity Tracking

No constitution violation is recorded for this unit in 02 §7. Nothing to justify.
