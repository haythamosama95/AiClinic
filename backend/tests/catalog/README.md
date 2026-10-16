# Catalog SQL harness (frozen)

pgTAP/psql analog of Phase 0 for catalog scenarios that run against **local
Supabase** (`127.0.0.1:54322`), not the Worker vitest pool.

Stage writers implement `S02-*`, `S06-*`, `S08-061`…`069`, `S11-022`…`029` as
`stage-*.sql` files in this directory. Do **not** modify:

- this harness (`harness.sql`, `run.sh`, `harness-smoke.sql`)
- `ai-platform/src/` or `ai-platform/test/e2e/**`
- `backend/supabase/migrations/`
- the old trust suite `backend/tests/*.sql` / `backend/tests/run_*.sh`

## 1. File skeleton

```sql
BEGIN;

\ir harness.sql
-- or: \i harness.sql  (cwd must be backend/tests/catalog)

SELECT pg_temp.catalog_common_setup();

-- optional extra setup, then impersonate:
-- SELECT pg_temp.set_authenticated_session(
--   (SELECT value FROM catalog_setup WHERE key = 'doctor_auth')
-- );

DO $$
DECLARE
  -- …
BEGIN
  PERFORM pg_temp.record('S02-001 — Availability flag returns the seeded default before any enrollment', true, 'ok');
END;
$$;

SELECT test_name, passed, detail FROM catalog_results ORDER BY test_name;
SELECT pg_temp.fail_if_any();
ROLLBACK;
```

Name every `pg_temp.record` id as `Sxx-NNN — …` (em dash), matching the catalog
chapter. `fail_if_any` RAISES listing failed `test_name` values, same as
`backend/tests/ai_keystore_rls.sql`.

## 2. Frozen helper API (`pg_temp.*`)

| Helper | Purpose |
| --- | --- |
| `set_authenticated_session(p_user_id uuid, p_exp_epoch bigint DEFAULT NULL)` | `role=authenticated` + JWT `sub`/`role`. Pass `p_exp_epoch` for Stage 06 `SESSION_EXPIRED` (unix seconds). Omit `exp` when NULL. |
| `set_anon_session()` | `role=anon`, no JWT claims. |
| `reset_postgres()` | Superuser; clears JWT claims. Use before inspecting `ai_internal`. |
| `reset_keystore()` | Catalog empty-keystore [SEED]: delete issuance + keys; restore `ai.availability` to `{"enrolled": false, "platform_base_url": null}`. Leaves session as postgres. |
| `catalog_common_setup()` | Isolate prior fixtures (`auth_internal.delete_clinic_test_fixtures`), BOOT JWT, `bootstrap_finish_setup` (Sunrise Dental / Nadia / Omar). Uses the 12-arg wrapper and the column-default Mon–Sat 09:00–17:00 schedule because `branches.working_schedule` is NOT NULL. Empty keystore after setup. Stashes ids in `catalog_setup`. Leaves session as postgres. |
| `decode_jws_header(p_token text)` / `decode_jws_payload(p_token text)` | Compact-JWS segment decode (copied from `ai_keystore_rls.sql`). |
| `record(p_id text, p_passed boolean, p_detail text)` | Upsert into `catalog_results`. |
| `fail_if_any()` | `RAISE EXCEPTION` listing failed `test_name` if any row has `passed = false`. |

### 2.1 `catalog_setup` keys (`key text`, `value uuid`)

| key | Meaning |
| --- | --- |
| `org` | Sunrise Dental Clinic `organizations.id` |
| `branch` | Main Branch `branches.id` |
| `admin` | Nadia Karim `staff_members.id` |
| `doctor` | Omar Haddad `staff_members.id` |
| `admin_auth` | Nadia's `auth.users.id` (JWT `sub`) |
| `doctor_auth` | Omar's `auth.users.id` |
| `boot` | Seeded bootstrap staff `b0000000-0000-4000-8000-000000000001` |
| `boot_auth` | Seeded bootstrap auth user `a0000000-0000-4000-8000-000000000001` |

BOOT is the migration-seeded administrator (`admin@admin`), not created by
setup. Look up `auth_user_id` from `catalog_setup` / `staff_members` — never
hard-code Nadia/Omar uuids.

## 3. Assertions (Register 5)

- **#12.** Assert SQLSTATE `42501` (GRANT denial) and `P0001` (raised contract
  codes such as `UNAUTHENTICATED` / `SESSION_EXPIRED`). Do not assert PostgREST
  HTTP 401/403 bodies.
- **#15.** Enroll/rotate/sign need `pgsodium`. Run only against local Supabase
  CLI (`SUPABASE_DB_PORT`, default `54322`), not bare Postgres.

`issue_ai_token` returns `text` and RAISES contract codes (`P0001`); it is not
an `rpc_result` envelope (Stage 06 §1).

## 4. Run command

Local DB must already be up. From the repo root:

```bash
bash backend/tests/catalog/run.sh
```

The runner sources `backend/local/.env`, uses `POSTGRES_PASSWORD` /
`SUPABASE_DB_PORT`, and executes `harness-smoke.sql` plus every
`stage-*.sql` with `psql -v ON_ERROR_STOP=1`. It prints PASS/FAIL per file.
It does **not** start Worker vitest.

Single file (cwd = this directory so `\i harness.sql` resolves):

```bash
cd backend/tests/catalog
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f harness-smoke.sql
```
