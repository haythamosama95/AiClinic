# Phase 00 — Catalog SQL harness

Frozen pgTAP/psql analog of Phase 0 for catalog scenarios that run against
local Supabase. No Worker vitest, no stage scenario files, no commits.

## 1. Files created

| Path | Role |
| --- | --- |
| `backend/tests/catalog/harness.sql` | Includable `pg_temp.*` helpers + temp tables |
| `backend/tests/catalog/README.md` | Frozen API for stage writers |
| `backend/tests/catalog/run.sh` | psql runner (`-v ON_ERROR_STOP=1`) |
| `backend/tests/catalog/harness-smoke.sql` | Harness proof (not a catalog scenario) |
| `backend/tests/catalog/reports/phase-00-sql-harness.md` | This report |

Not created: `stage-*.sql` (Stage 02/06/08/11 writers).

Not modified: `ai-platform/src/`, `ai-platform/test/e2e/**`,
`backend/supabase/migrations/`, existing `backend/tests/*.sql` /
`backend/tests/run_*.sh`.

## 2. Frozen API

Writers: `BEGIN;` → `\ir harness.sql` → `SELECT pg_temp.catalog_common_setup();`
→ `pg_temp.record('S02-001 — …', …)` → `SELECT pg_temp.fail_if_any();` →
`ROLLBACK;`.

### 2.1 Helpers (`pg_temp.*`)

| Helper | Behavior |
| --- | --- |
| `set_authenticated_session(uuid, exp bigint DEFAULT NULL)` | JWT claim injection (`sub` + `role`; optional `exp` for Stage 06) |
| `set_anon_session()` | `role=anon`, claims cleared |
| `reset_postgres()` | Superuser, claims cleared |
| `reset_keystore()` | Catalog empty-keystore [SEED]: delete `ai_token_issuance` + `installation_keys`; restore `ai.availability` |
| `catalog_common_setup()` | Isolate fixtures (`delete_clinic_test_fixtures` + leftover `nadia_karim`/`omar_haddad` auth rows), BOOT session, `bootstrap_finish_setup` (Sunrise Dental / Nadia / Omar), empty keystore |
| `decode_jws_header` / `decode_jws_payload` | Copied from `backend/tests/ai_keystore_rls.sql` |
| `record(id, passed, detail)` | Upsert `catalog_results` |
| `fail_if_any()` | `RAISE EXCEPTION` listing failed `test_name` |

### 2.2 Temp tables

- `catalog_results (test_name text PRIMARY KEY, passed boolean, detail text)`
- `catalog_setup (key text PRIMARY KEY, value uuid)` — keys: `org`, `branch`,
  `admin`, `doctor`, `admin_auth`, `doctor_auth`, `boot`, `boot_auth`

### 2.3 Setup adaptations vs Stage 02 text

Stage 02's 11-arg `bootstrap_finish_setup(...)` is ambiguous against the live
11-arg and 12-arg public wrappers. The harness calls the 12-arg function and
passes the column-default Mon–Sat 09:00–17:00 working schedule because
`branches.working_schedule` is NOT NULL.

### 2.4 Registers

- **Register 5 #12:** writers assert SQLSTATE `42501` / `P0001`, not PostgREST HTTP.
- **Register 5 #15:** enroll/rotate/sign require local Supabase (pgsodium).

## 3. Run command

```bash
bash backend/tests/catalog/run.sh
```

Sources `backend/local/.env` (`POSTGRES_PASSWORD`, `SUPABASE_DB_PORT=54322`).
Runs `harness-smoke.sql` then `stage-*.sql`. Does not invoke Worker vitest.

## 4. Smoke result

```
PASS  harness-smoke.sql
catalog SQL harness: 1 passed, 0 failed.
```

| Id | Result |
| --- | --- |
| `HARNESS-001 — bootstrap admin exists` | pass (seeded BOOT `a000…0001` / `b000…0001`) |
| `HARNESS-002 — common setup stashes Sunrise ids` | pass (org/branch/Nadia/Omar) |
| `HARNESS-003 — empty keystore after reset` | pass (`keys=0 issuance=0`, availability flag default) |

Re-run also passed (fixture isolation). `fail_if_any` did not raise; transaction
`ROLLBACK`.
