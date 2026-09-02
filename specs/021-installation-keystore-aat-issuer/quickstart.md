# Quickstart: Installation keystore and AAT issuer (B1)

Slice **B1** establishes the clinic-side trust bootstrap: an installation signing key held in a
restricted `ai_internal` schema and a `SECURITY DEFINER` issuer RPC that mints short-lived
`alg: EdDSA` AI Access Tokens (AATs) for authenticated staff, deriving every §5.6 claim from
RBAC and recording each issuance.

**Scope rule:** A quickstart documents **this slice only**. List only files this slice added or
modified, only this slice's test files, and only commands that run this slice's tests. Do **not**
include prior-slice files in the review table, combined test counts from earlier slices, prior-slice
regression commands, or diffs "against the prior slice baseline". Full-suite regression (this slice
plus every prior slice) belongs in the Verification task (T021), not in `quickstart.md`.

Full requirements: [`spec.md`](spec.md). File-level traceability: [`plan.md`](plan.md).

## 1. Architecture context

This slice implements delivery-plan row **B1** (*Installation keystore and AAT issuer*) from
[`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md)
(§3.3), which maps to the clinic-backend components in
[`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md):

- **§4.2** — Installation keystore and AI token issuer RPC (restricted schema, session
  verification, RBAC-derived claims, issuance ledger, issuer rate limiting).
- **§4.2.1** — Clinic-side signing mechanism: `pgsodium` Ed25519 keypair,
  `pgsodium.crypto_sign_detached` / `crypto_sign_verify_detached`, JWS header `alg: EdDSA` +
  `kid`.
- **§5.6** — AAT claim set (`iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`,
  `iat`, `exp`, `ver`) with deliberate omissions; `scopes` derived server-side from RBAC.
- **§8.1** — Clinic-side enrollment bootstrap: generate installation keypair, store private key in
  restricted schema; additive rotation without invalidating in-flight tokens.

The **spec** freezes the keystore shape, the issuer RPC contract, the §5.6 claim set, and the rule
that `scopes` are never client-supplied. The **plan** scopes four Supabase migrations (three
originals + review overlay), two SQL/RLS test suites (keystore T01–T13; issuer T07–T16), and a
dedicated runner — `backend/` only; no Worker or Flutter changes.

## 2. What was implemented

- **`ai_internal` keystore schema** — `pgsodium` extension enabled; restricted `ai_internal`
  schema with `installation_keys` (additive rotation, `revoked_at` revocation, singleton
  `installation_id` trigger) and `ai_token_issuance` ledger tables; RLS deny policies for
  `anon`/`authenticated`; schema `USAGE` to `postgres` only at B1; config keys for AAT lifetime,
  audience, contract version, and issuer rate-limit window/ceiling.
- **`auth_internal` keypair routines** — `enroll_installation_keypair`, `rotate_installation_key`,
  and `revoke_installation_key` (`SECURITY DEFINER`, `pgsodium.crypto_sign_new_keypair`,
  `clock_timestamp` stamps); enroll rejects `ALREADY_ENROLLED` when an active key exists;
  revoke rejects `CANNOT_REVOKE_LAST_ACTIVE_KEY` when the target is the sole active key;
  re-enroll when no active keys remain is a recovery path (not reachable by revoking every key
  via the revoke RPC); enroll/rotate return `rpc_success` with `kid`,
  `installation_id`, and `public_jwk` (`OKP`/`Ed25519`/`x`/`kid`) for the §8.1 operator handoff.
  Thin `public`
  `SECURITY DEFINER` wrappers, operator-gated via `assert_owner_or_administrator()`;
  `REVOKE EXECUTE` from `PUBLIC`/`anon`/`authenticated` on internal functions.
- **`auth_internal.issue_ai_token` issuer RPC** — verifies session (`UNAUTHENTICATED` /
  `SESSION_EXPIRED`); resolves tenant/actor claims via `build_staff_claims`; derives `scopes`
  from `roles_permissions` `ai.*` (ignores `p_scopes`); mints `alg: EdDSA` JWS with
  installation-scoped signing key (`ORDER BY valid_from DESC, kid DESC`); writes issuance
  ledger; per-actor `pg_advisory_xact_lock` + rate limit (`RATE_LIMITED`). Bare exception codes
  documented in `contracts/aat-token.md` §9. `auth_internal.verify_aat` binds payload `iss` to
  the key row, returns `false` on malformed input (no throw), and does **not** check `exp`
  (B3). `public.issue_ai_token` `SECURITY DEFINER` wrapper for authenticated staff.
- **Review overlay** — `20260803140000_b1_review_resolution.sql` applies the same hardening on
  databases that already ran the original B1 migrations.

## 3. Files to review

| Path | Role |
| --- | --- |
| `backend/supabase/migrations/20260801120000_ai_keystore_schema.sql` | `pgsodium` enable, `ai_internal` schema, keystore + ledger tables, RLS deny, config keys |
| `backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql` | Enroll / rotate / revoke keypair routines + `public` wrappers (`public_jwk` return) |
| `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql` | `issue_ai_token` issuer, `verify_aat` self-test helper, `public.issue_ai_token` wrapper |
| `backend/supabase/migrations/20260803140000_b1_review_resolution.sql` | Review-resolution overlay (idempotent with updated originals) |
| `backend/tests/ai_keystore_rls.sql` | T01–T13: keystore access, `public_jwk`, rotation, verify/`iss`/malformed, admin/error paths, enroll guard, last-active revoke guard |
| `backend/tests/ai_token_issuer.sql` | T07–T16: §5.6 claims, header `alg`, omissions, exact error codes, per-actor rate limit, `exp` |

## 4. Prerequisites

- **Local Supabase stack** running with migrations applied (`backend/local/.env` present so the
  runner can source `SUPABASE_DB_PORT`; default `54322`).
- **`pgsodium`** enabled by migration `20260801120000_ai_keystore_schema.sql` (shipped in the
  `supabase/postgres` image; no manual extension step after `supabase db reset` or equivalent).

## 5. Run the automated suite

From the repository root:

```bash
bash backend/tests/run_ai_platform_trust_tests.sh
```

Expected: both suites green — `ai_keystore_rls.sql` (T01–T13, including T05b–d) and
`ai_token_issuer.sql` (T07–T16, including T07b/T08b). The runner prints `AI platform trust suite:
all checks passed.` on success.

To run the suites individually:

```bash
source backend/local/.env
export PGPASSWORD="${POSTGRES_PASSWORD:-postgres}"
psql -h 127.0.0.1 -p "${SUPABASE_DB_PORT:-54322}" -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f backend/tests/ai_keystore_rls.sql
psql -h 127.0.0.1 -p "${SUPABASE_DB_PORT:-54322}" -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f backend/tests/ai_token_issuer.sql
```

## 6. Inspect the changes

Confirm the restricted schema and tables landed:

```bash
source backend/local/.env
export PGPASSWORD="${POSTGRES_PASSWORD:-postgres}"
psql -h 127.0.0.1 -p "${SUPABASE_DB_PORT:-54322}" -U postgres -d postgres -c '\dn ai_internal'
psql -h 127.0.0.1 -p "${SUPABASE_DB_PORT:-54322}" -U postgres -d postgres \
  -c '\dt ai_internal.*'
```

Inspect the issuer RPC definition (signature, security, search path):

```bash
psql -h 127.0.0.1 -p "${SUPABASE_DB_PORT:-54322}" -U postgres -d postgres \
  -c '\df+ auth_internal.issue_ai_token'
```

Decode the JWS header of a minted AAT (the test suite mints tokens internally; this mirrors the
§4.2.1 base64url decode used in `ai_token_issuer.sql`):

```sql
-- After a successful mint via public.issue_ai_token() in an authenticated session:
SELECT convert_from(
  decode(
    rpad(
      translate(split_part('<paste-token-here>', '.', 1), '-_', '+/'),
      length(split_part('<paste-token-here>', '.', 1))
        + ((4 - length(split_part('<paste-token-here>', '.', 1)) % 4) % 4),
      '='
    ),
    'base64'
  ),
  'utf8'
)::jsonb AS header;
-- Expected shape: {"alg":"EdDSA","kid":"<kid>"}
```

Review keystore RLS deny policies and config defaults:

```bash
grep -n 'installation_keys_deny_all\|ai.aat\|ai.issuer' \
  backend/supabase/migrations/20260801120000_ai_keystore_schema.sql
```
