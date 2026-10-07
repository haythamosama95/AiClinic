# Issuer key custody, token issuance and the versioned RPC envelope

**Unit**: P5.1 · **Harnesses**: H-BK, H-FS · **Verification**: T021 and T035 green

## 1. What was implemented

The shared Supabase backend holds an Ed25519 issuer key set in `ai_internal`, signs tokens from Vault through SQL, and versions the clinic-facing issue RPCs (FR-001 through FR-012). Platform and ABO source are consumed, not modified.

- **Issuer key custody** (`backend/supabase/migrations/20261007180000_issuer_key_custody.sql`) — `ai_internal.issuer_key` rows with `kid`, status (`signing`, `next`, `retired`), validity window, and `secret_ref` into Vault. Private bytes are decrypted only inside definer functions. Clinic roles cannot read `issuer_key` or Vault. `installation_keys` and the enroll/rotate/revoke RPCs are dropped; no plaintext `secret_key` column remains (FR-002, FR-003, FR-011).
- **Three mints** — `auth_internal.issue_ai_token` (audience `ai-platform`, ≤ 600 s, `org = current_org_id()`, scopes from per-tenant `roles_permissions`), `auth_internal.issue_billing_token` (administrator only, audience `abo`, ≤ 300 s, 20 per user per 10 minutes), and internal `auth_internal.issue_feed_token` (audience `ai-platform-feed`, `sub = backend-feed`, no `org`, ≤ 120 s; no public grant) (FR-004, FR-005, FR-007, FR-009, FR-011).
- **Versioned issue RPCs** — `public.issue_ai_token(p_contract_version)` and `public.issue_billing_token(p_contract_version)` are `SECURITY DEFINER`, granted to `authenticated`, and refuse unsupported versions with `CONTRACT_VERSION_UNSUPPORTED` before authentication and before any insert. `public.rpc_success` and `public.rpc_error` carry `contract_version`. `ai.contract_versions` in `app_settings` matches `packages/vendor-contracts` (FR-004, FR-005, FR-008, FR-009).
- **Signing-kid switch** — `auth_internal.insert_issuer_kid()` creates a `next` row; `auth_internal.switch_issuer_signing_kid(p_kid)` promotes it to `signing` and retires the previous signing row in one transaction. Both are owner-only (FR-006, FR-010).
- **H-FS** (`e2e/fullstack/`) — Node runner starts local platform (`startWorker`), harness worker (`register-issuer.ts` → `VendorEntrypoint.registerIssuerKey`), ABO (`wrangler dev`), and Paymob stub; clinic calls use supabase-js; owner SQL uses `psql`. CI job `fullstack` runs the package harness (FR-010, FR-012).

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `specs/087-abo-p5-1-issuer-key-custody-token-issuance/research.md` | FR-001 |
| `specs/087-abo-p5-1-issuer-key-custody-token-issuance/data-model.md` | FR-002, FR-003, FR-007, FR-008, FR-009 |
| `specs/087-abo-p5-1-issuer-key-custody-token-issuance/quickstart.md` | FR-001–FR-012 |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | FR-002, FR-003, FR-004, FR-005, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `backend/tests/ai_keystore_rls.sql` | FR-002, FR-003, FR-011 |
| `backend/tests/issuer_rpc.sql` | FR-004, FR-005, FR-007, FR-009 |
| `backend/tests/contract_versions.mjs` | FR-008 |
| `backend/tests/ai_token_issuer.sql` | FR-003, FR-004 |
| `backend/tests/catalog/stage-02-revoke-rotate-availability.sql` | FR-003 |
| `backend/tests/catalog/stage-02-availability-and-enroll.sql` | FR-003 |
| `backend/tests/catalog/stage-06-verify-and-handoff.sql` | FR-003, FR-004 |
| `backend/tests/cross_tenant_suite.sql` | FR-003, FR-004 |
| `backend/tests/run_all_backend_tests.sh` | FR-008, FR-009 |
| `e2e/fullstack/package.json` | FR-012 |
| `e2e/fullstack/wrangler.toml` | FR-010, FR-012 |
| `e2e/fullstack/src/register-issuer.ts` | FR-010, FR-012 |
| `e2e/fullstack/test/p5-1.test.mjs` | FR-004, FR-005, FR-006, FR-009, FR-010, FR-012 |
| `.github/workflows/ci.yml` | FR-008, FR-012 |

## 3. Harness commands for this unit's tests only

### H-BK

From the repository root, against local Supabase (`supabase start` in `backend/`):

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f backend/tests/ai_keystore_rls.sql
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f backend/tests/issuer_rpc.sql
node backend/tests/contract_versions.mjs
```

### H-FS

From `e2e/fullstack/`:

```bash
npm test
```

## 4. Entry point → module chain

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
