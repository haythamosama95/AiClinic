# Backend Code Review — AiClinic

**Date**: 2026-05-24  
**Scope**: All files under `backend/` (19 SQL migrations, test suite, Docker Compose, Supabase config)  
**Reviewer**: Automated deep review

---

## Executive Summary

The backend is a PostgreSQL-centric architecture using Supabase (PostgREST + GoTrue + RLS). It implements auth/RBAC (V1-1), org/branch management (V1-2), and patient management (V1-3). The design is generally solid — SECURITY DEFINER logic lives in `auth_internal`, public schema exposes INVOKER wrappers, RLS blocks direct table manipulation, and tests verify cross-org isolation.

However, I found **6 bugs**, **8 architectural flaws**, **8 future-extension concerns**, **5 security issues**, and **4 performance issues**. Severity ratings: 🔴 Critical, 🟠 High, 🟡 Medium, 🟢 Low.

---

## 1. Bugs

### 1.1 🟠 `auth_internal` functions callable by any authenticated user

**Location**: `20260521110000_auth_rbac_definer_internal_schema.sql`, line 612

```sql
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth_internal TO authenticated, service_role;
```

This grants **every authenticated user** direct execute on all `auth_internal` functions. While most functions internally call `assert_*` guards, the following are exploitable without authorization:

- `auth_internal.build_staff_claims(any_uuid)` — Any logged-in user can retrieve the staff claims (org_id, branch assignments, role) of **any other user** by UUID. This is an information disclosure vulnerability.
- `auth_internal.organization_exists()` / `auth_internal.owner_exists()` — Low-risk info leak but still unintended API surface.
- `auth_internal.normalize_username(text)` / `auth_internal.assert_valid_username(text)` — Usable for username enumeration.

**Impact**: A low-privilege `lab_staff` user can call `auth_internal.build_staff_claims('a0000000-0000-4000-8000-000000000001')` to discover the bootstrap admin's org and branch setup.

**Fix**: Replace the broad `GRANT EXECUTE ON ALL FUNCTIONS` with explicit grants only for functions that are invoked through the INVOKER wrapper call chain. Alternatively, move the grant to `service_role` only and use `SET ROLE` within the INVOKER wrappers.

---

### 1.2 🟡 Race condition in patient duplicate phone check

**Location**: `20260523150000_patient_registration_fields.sql` — `auth_internal.create_patient`

The duplicate check and INSERT are not atomic with respect to concurrent transactions:

```sql
-- Step 1: Check duplicates (another transaction could insert between here...)
v_candidates := auth_internal.find_patient_duplicate_candidates(...);
-- Step 2: INSERT
INSERT INTO public.patients (...) VALUES (...);
```

The `phone` column has **no unique index**. Two concurrent `create_patient` calls with the same phone will both pass the duplicate check and both succeed, creating true duplicates without any warning.

**Impact**: Under concurrent receptionist usage (multiple browser tabs, multiple staff), duplicate patients can be silently created.

**Fix**: Add a partial unique index `ON patients (organization_id, phone) WHERE is_deleted = false` or use an advisory lock on `(org_id, phone)` within the RPC.

---

### 1.3 🟡 Dead partial index condition after schema migration

**Location**: `20260523140000_patient_management.sql`, line 35

```sql
CREATE INDEX patients_branch_phone_idx ON public.patients (branch_id, phone)
  WHERE is_deleted = false AND phone IS NOT NULL;
```

After migration `20260523150000`, `phone` is `NOT NULL`. The `phone IS NOT NULL` filter is dead code. More importantly, the index is scoped to `branch_id` but `search_patients` can search org-wide (`organization_id` filter, not `branch_id`). The planner likely won't use this index for org-wide phone-prefix searches.

**Impact**: Org-wide phone search falls back to a sequential scan on `patients_organization_id_idx` (which doesn't include phone).

**Fix**: Add an index `ON patients (organization_id, phone) WHERE is_deleted = false` for org-wide phone-prefix searches.

---

### 1.4 🟡 `patients_branch_full_name_idx` unusable for case-insensitive search

**Location**: `20260523140000_patient_management.sql`, line 31 vs `search_patients` logic

```sql
-- Index stores full_name as-is:
CREATE INDEX patients_branch_full_name_idx ON public.patients (branch_id, full_name)
  WHERE is_deleted = false;

-- But search uses lower():
AND lower(p.full_name) LIKE '%' || v_escaped_name_query || '%' ESCAPE '\'
```

PostgreSQL cannot use a B-tree index on `full_name` for a `lower(full_name) LIKE '%...'` query. The index is effectively dead for search.

**Impact**: All name searches do a sequential scan filtered by `organization_id`. At 500+ patients this becomes noticeable.

**Fix**: Replace with a trigram index (`CREATE INDEX ... USING gin (lower(full_name) gin_trgm_ops)`) or at minimum a functional index on `lower(full_name)`.

---

### 1.5 🟢 GoTrue version mismatch in Docker Compose

**Location**: `backend/local/docker-compose.yml`, line 22

```yaml
auth:
  image: supabase/gotrue:v2.186.0
```

Migration comments explicitly state "GoTrue v2.188+ cannot scan NULL into string". The Docker Compose pins v2.186.0 which does **not** exhibit the bug the token column migrations fix. If someone upgrades GoTrue (which they should for security patches), they'd need the fix already applied — which it is. But if they regress to the pinned version, the empty-string token values are harmless but indicate a version-awareness gap.

**Impact**: Low risk currently, but indicates potential deployment confusion.

**Fix**: Update to `supabase/gotrue:v2.188.0` or later to match the assumptions in migration code.

---

### 1.6 🟢 `update_patient` cannot clear optional fields

**Location**: `20260523150000_patient_registration_fields.sql` — `auth_internal.update_patient`

```sql
IF p_gender IS NOT NULL AND NULLIF(trim(p_gender), '') IS NOT NULL THEN
  -- set gender
END IF;
-- gender = CASE WHEN v_apply_gender THEN v_gender ELSE p.gender END
```

Once a patient has `gender = 'male'`, the client **cannot** set it back to NULL. Passing `p_gender = NULL` preserves the old value; passing `p_gender = ''` also preserves it (the `NULLIF` check). The same applies to `marital_status`, `date_of_birth`, and `notes`.

**Impact**: Staff cannot correct a wrongly entered gender/marital_status by clearing it. They can only change it to another valid enum value.

**Fix**: Use a sentinel value convention (e.g., pass `'clear'` which the RPC interprets as NULL) or add explicit `p_clear_gender boolean DEFAULT false` parameters.

---

## 2. Architectural Flaws

### 2.1 🟠 No rollback / down migrations

All 19 migrations are forward-only. Supabase CLI `supabase db reset` drops everything and replays, but there's no mechanism to:
- Roll back a single failed migration in production
- Reverse a schema change without manual SQL
- Test partial rollbacks

**Recommendation**: Consider adding `-- DOWN` sections or separate down-migration files for destructive changes (DROP COLUMN, ALTER TYPE).

---

### 2.2 🟠 Destructive enum alteration in production migration

**Location**: `20260523150000_patient_registration_fields.sql`, lines 55-75

```sql
CREATE TYPE public.patient_gender_new AS ENUM ('male', 'female');
ALTER TABLE public.patients
  ALTER COLUMN gender TYPE public.patient_gender_new
  USING gender::text::public.patient_gender_new;
DROP TYPE public.patient_gender;
ALTER TYPE public.patient_gender_new RENAME TO patient_gender;
```

If **any** patient still has `gender = 'other'` or `gender = 'unknown'` at this point (e.g., the preceding UPDATE missed rows due to a filter bug), the `ALTER COLUMN TYPE` will fail with an invalid cast, leaving the database in a partially migrated state with `patient_gender_new` created but `patient_gender` still in use.

**Recommendation**: Add a pre-check `DO $$ ... IF EXISTS (SELECT 1 FROM patients WHERE gender::text IN ('other','unknown')) THEN RAISE EXCEPTION ... END IF; ... $$` before the ALTER.

---

### 2.3 🟡 Repeated function re-definitions across migrations

`auth_internal.build_staff_claims` is redefined in **5 different migrations** (migrations 7, 8, 9, 10, 11). Each `CREATE OR REPLACE` overwrites the previous version. This creates:
- Difficult-to-trace logic history (which version is "current"?)
- Risk of accidentally regressing a fix if a later migration copy-pastes an older version
- Merge conflicts when multiple feature branches touch the same function

**Recommendation**: For functions that are redefined frequently, consider a `functions/` directory with versioned definitions that are idempotently applied, rather than inline redefinition in each migration.

---

### 2.4 🟡 Single-tenant assumption deeply embedded

`build_staff_claims` determines org_id via:

```sql
SELECT o.id INTO v_org_id FROM public.organizations o
WHERE o.is_deleted = false ORDER BY o.created_at LIMIT 1;
```

A staff member belongs to exactly one organization (inferred from "first org in DB"). Multi-org support would require:
- `organization_id` on `staff_members`
- Rework of the entire claims pipeline
- Multiple JWT claims per org

**Recommendation**: Document this as a hard architectural constraint. If multi-tenancy is ever needed, plan for a full rewrite of the auth layer.

---

### 2.5 🟡 `dev_reset_clinic_installation` ships to production

**Location**: `20260521140000_dev_reset_clinic_installation.sql`

This function deletes ALL organizations, branches, assignments, settings, and audit logs. It's gated only by `is_bootstrap_admin` — which is a flag on a single staff row. There's no environment detection, no confirmation token, no "are you sure" step.

**Recommendation**: Either:
- Wrap in a conditional (`IF current_setting('app.environment', true) = 'development'`) 
- Or remove from the migration set via a `supabase/seed.sql` approach that only runs in local
- Or add a time-based safety (e.g., org must be < 1 hour old)

---

### 2.6 🟡 Audit log grows unboundedly

No retention policy, no archival mechanism, no partition strategy. The `audit_log` table will grow linearly with all clinic operations. At scale:
- Backup sizes increase
- Index maintenance slows
- SELECT queries on audit_log degrade

**Recommendation**: Add time-based partitioning (e.g., monthly) or a retention policy that archives logs older than N months to cold storage.

---

### 2.7 🟢 Permission check is a table scan per RPC call

`auth_internal.assert_permission('patients.view')` queries `roles_permissions` with:

```sql
SELECT 1 FROM public.roles_permissions rp
WHERE rp.role = v_staff.role
  AND rp.permission_key = p_permission_key
  AND rp.is_granted = true
  AND rp.is_deleted = false
```

The `UNIQUE (role, permission_key)` index helps, but this is invoked on every single RPC call. For high-frequency operations (search, get_patient), this adds a round-trip to the permission table.

**Recommendation**: Consider materializing permissions into the JWT custom claims (a `permissions` array) so RPCs can check in-memory without a DB query.

---

### 2.8 🟢 `app_settings` table exists but is never used

The `app_settings` table is created, has RLS policies, and audit triggers, but no RPC reads or writes it. No migration populates it. No test exercises it.

**Recommendation**: Either implement the settings RPCs or remove the dead table to reduce maintenance surface.

---

## 3. Security Issues

### 3.1 🔴 Plaintext passwords returned in RPC responses

**Location**: `auth_internal.create_staff_account` and `auth_internal.admin_reset_staff_password`

```sql
RETURN public.rpc_success(
  jsonb_build_object(
    'staff_member_id', v_staff_id,
    'assigned_password', p_password  -- ← plaintext password in HTTP response
  )
);
```

The password is sent back in the PostgREST JSON response. If:
- Network logging is enabled on Kong/PostgREST
- The response is cached by a CDN (unlikely for RPC but possible in misconfiguration)
- The client logs the response for debugging
- Browser devtools are open during admin usage

...the password is captured in plaintext.

**Recommendation**: Return only a success flag. The calling admin already knows the password they just typed. If "show once" UX is needed, handle it client-side only.

---

### 3.2 🟠 No password complexity enforcement in RPCs

Both `create_staff_account` and `admin_reset_staff_password` accept any non-empty string. The Supabase config sets `minimum_password_length = 6` but this only applies to GoTrue's signup/change-password endpoints — not to direct SQL-based user creation.

A admin can set a 1-character password via the RPC path.

**Recommendation**: Add server-side validation: `IF length(p_password) < 8 THEN RETURN rpc_error(...)`.

---

### 3.3 🟠 Hardcoded bootstrap credentials with fixed UUIDs

**Location**: `20260516100400_auth_rbac_seed.sql`

```sql
v_user_id uuid := 'a0000000-0000-4000-8000-000000000001';
v_email text := 'admin@admin';
v_password text := 'admin';
```

These are deterministic across all installations. An attacker who knows this project uses AiClinic can attempt `admin` / `admin` on any deployment.

**Recommendation**: 
- Generate a random password at migration time and print it to stdout
- Or require a post-install password change before any other operation
- Or read credentials from environment variables during seed

---

### 3.4 🟡 No rate limiting on RPC endpoints

PostgREST exposes all granted functions as HTTP endpoints. There's no rate limiting configured for RPC calls. An attacker with valid credentials (or a compromised lab_staff account) could:
- Brute-force patient searches
- Enumerate patient IDs via `get_patient` with sequential attempts
- DoS via expensive `search_patients` queries with max limit

**Recommendation**: Configure Kong rate-limiting plugin for `/rest/v1/rpc/*` paths, or add application-level rate tracking.

---

### 3.5 🟡 JWT custom claims not invalidated on permission change

When an admin changes a staff member's role or permissions via `update_role_permission` or `update_staff_member`, the JWT already issued to that user still contains the old claims until it expires (up to 3600 seconds).

**Impact**: A demoted user retains elevated access for up to 1 hour.

**Recommendation**: 
- Reduce JWT expiry for sensitive environments
- Or implement a token revocation check (e.g., check `staff_members.is_active` in each RPC)
- Or force session refresh after role changes (realtime notification to client)

---

## 4. Performance Issues

### 4.1 🟠 `count(*) OVER()` forces full result materialization

**Location**: `auth_internal.search_patients`

```sql
counted AS (
  SELECT f.*, count(*) OVER ()::int AS total_count
  FROM filtered f
  ORDER BY f.full_name ASC
  LIMIT v_limit OFFSET v_offset
)
```

The window function `count(*) OVER()` requires PostgreSQL to process ALL matching rows before applying LIMIT/OFFSET. For a clinic with 10,000 patients and an org-wide search with no filter, this materializes 10,000 rows to return 25.

**Recommendation**: Use a separate `SELECT count(*)` query, or return an estimated count via `EXPLAIN` row estimates, or use keyset pagination (cursor-based) instead of OFFSET.

---

### 4.2 🟡 Name search uses unindexable `LIKE '%...%'`

Leading wildcard `%` prevents B-tree index usage. The existing `patients_branch_full_name_idx` cannot accelerate this pattern.

**Recommendation**: 
- Install `pg_trgm` extension and create a GIN trigram index: `CREATE INDEX ... USING gin (lower(full_name) gin_trgm_ops)`
- Or use PostgreSQL full-text search (`to_tsvector` / `ts_query`)

---

### 4.3 🟡 `find_patient_duplicate_candidates` scans all org patients

The duplicate finder scans all non-deleted patients in the organization for each create/update call. With phone normalization happening per-row (`auth_internal.normalize_patient_phone(p.phone)` was in the older version), this is O(n).

The latest version (after `20260523150000`) compares stored normalized phone directly (`p.phone = v_normalized_phone`), which is better but still a seq-scan without a proper index on `(organization_id, phone)`.

**Recommendation**: Create `INDEX patients_org_phone_idx ON patients (organization_id, phone) WHERE is_deleted = false`.

---

### 4.4 🟢 RLS policy on `staff_members_select` joins through assignments per-row

```sql
OR EXISTS (
  SELECT 1
  FROM public.staff_branch_assignments sba
  JOIN public.branches b ON b.id = sba.branch_id
  WHERE sba.staff_member_id = staff_members.id
    AND sba.is_deleted = false
    AND b.is_deleted = false
    AND b.organization_id = public.jwt_organization_id()
)
```

For each row in `staff_members`, this correlated subquery runs. With proper indexes this is manageable, but if the organization has 50+ staff members, this executes 50+ subqueries per list-staff request.

**Recommendation**: Add `organization_id` directly to `staff_members` to simplify the RLS policy to a single column check.

---

## 5. Future Extension Concerns

### 5.1 🟠 No mechanism to transfer a patient between branches

`branch_id` on patients is set at creation and never updated by any RPC. A patient who moves to a different clinic branch requires direct DB intervention.

**Recommendation**: Add a `transfer_patient(p_patient_id, p_new_branch_id)` RPC.

---

### 5.2 🟡 No patient restore/unarchive capability

`archive_patient` sets `is_deleted = true` but there's no inverse operation. Accidentally archived patients are permanently inaccessible via the app.

**Recommendation**: Add `restore_patient(p_patient_id)` gated by `patients.delete` permission.

---

### 5.3 🟡 `staff_role` enum is hard to extend

PostgreSQL's `ALTER TYPE ... ADD VALUE` cannot run inside a transaction. Adding a new role (e.g., `nurse`, `pharmacist`) requires a non-transactional migration, making it impossible to atomically add the role AND seed its permissions.

**Recommendation**: Consider moving roles to a `staff_roles` table (rows, not enum) for runtime extensibility.

---

### 5.4 🟡 JWT branch_ids will not scale

Branch assignments are serialized as comma-separated UUIDs in the JWT:

```sql
SELECT string_agg(b.id::text, ',' ORDER BY sba.is_primary DESC, b.name)
```

Each UUID is 36 chars. A staff member assigned to 20 branches produces a 720+ char string in the JWT. JWTs have practical size limits (~8KB total). Large multi-branch organizations could hit this.

**Recommendation**: Store only the primary branch in JWT and fetch the full list from a lightweight RPC or cache.

---

### 5.5 🟡 Phone normalization loses country context

```sql
SELECT NULLIF(regexp_replace(COALESCE(p_phone, ''), '[^0-9]', '', 'g'), '');
```

This strips everything except digits. `+20 100 555 1234` becomes `201005551234`. This works for a single-country clinic but:
- Cannot distinguish `+1-201-005-5123` (US) from a coincidentally same-length Egyptian number
- No validation that the digits form a plausible phone number
- International clinics serving tourists/expats cannot reliably deduplicate

**Recommendation**: Store phones in E.164 format (e.g., `+201005551234`) with a validated country prefix.

---

### 5.6 🟢 No per-organization permission overrides

All organizations share the same global `roles_permissions` matrix. If one clinic wants receptionists to NOT have `invoices.apply_discount_above_threshold`, they must modify the global matrix — affecting the blueprint for future installations.

**Recommendation**: Add `organization_id` to `roles_permissions` (nullable = global default, non-null = org override).

---

### 5.7 🟢 No pagination metadata for cursor-based infinite scroll

`search_patients` uses OFFSET-based pagination. For mobile/desktop clients with infinite scroll, this causes:
- Duplicate results when new records are inserted between pages
- Skipped results when records are deleted between pages

**Recommendation**: Support cursor-based pagination (e.g., `WHERE full_name > :last_name ORDER BY full_name LIMIT :n`).

---

### 5.8 🟢 No soft-delete cascade or orphan cleanup

When an organization is soft-deleted, its branches, patients, staff assignments, and settings are not automatically soft-deleted. This could lead to orphaned records that still appear in queries if RLS checks only `organization_id` equality.

**Recommendation**: Add cascade triggers or periodic cleanup jobs for soft-delete propagation.

---

## 6. Test Coverage Gaps

### 6.1 Concurrent access not tested

All tests run within a single transaction (`BEGIN ... ROLLBACK`). No test verifies:
- Two simultaneous `create_patient` with same phone
- Race between `update_patient` and `archive_patient`
- JWT expiry mid-operation

### 6.2 No test for `update_organization`, `manage_create_branch`, `update_branch`

The V1-2 management RPCs have an `org_branch_management_crud.sql` test file, but it wasn't reviewed here. Ensure it covers:
- Branch code uniqueness (unique index)
- Last-active-branch deactivation prevention
- Cross-org branch creation attempt

### 6.3 No integration test for GoTrue ↔ custom claims hook

The `auth_flow_smoke.sh` tests the flow, but no test verifies that `get_custom_claims(event jsonb)` correctly merges existing JWT claims with staff claims after a schema change.

### 6.4 `dev_reset_clinic_installation` has no safety test

No test verifies that calling `dev_reset` from a non-bootstrap user fails, or that it cannot be invoked when the caller's JWT org doesn't match.

---

## 7. Configuration & Infrastructure

### 7.1 🟡 Docker Compose auth image outdated

`supabase/gotrue:v2.186.0` should be upgraded to at least v2.188+ to match migration assumptions.

### 7.2 🟢 `config.toml` references `./seed.sql` but file doesn't exist

```toml
sql_paths = ["./seed.sql"]
```

There's no `backend/supabase/seed.sql` file in the repository. If `supabase db reset` is run, the seed step will silently fail or error.

**Fix**: Either create an empty `seed.sql` or set `enabled = false` for the seed section.

### 7.3 🟢 Two parallel configs (`backend/supabase/config.toml` + `backend/local/config.toml`)

Having two configurations is confusing. The Supabase CLI uses `backend/supabase/config.toml` but the Docker Compose stack ignores it. Document which config is authoritative for which deployment mode.

---

## 8. Summary of Recommendations (Priority Order)

| # | Priority | Action |
|---|----------|--------|
| 1 | 🔴 Critical | Stop returning plaintext passwords in RPC responses |
| 2 | 🟠 High | Restrict `auth_internal` grants to specific functions only |
| 3 | 🟠 High | Add password complexity validation in RPCs |
| 4 | 🟠 High | Add unique/partial index on patient phone for duplicate prevention |
| 5 | 🟠 High | Protect `dev_reset_clinic_installation` from production use |
| 6 | 🟠 High | Add rollback plan for destructive enum migrations |
| 7 | 🟡 Medium | Fix indexes for search performance (trigram or functional) |
| 8 | 🟡 Medium | Separate count query from paginated search |
| 9 | 🟡 Medium | Add patient transfer and restore RPCs |
| 10 | 🟡 Medium | Implement audit log retention strategy |
| 11 | 🟡 Medium | Harden bootstrap credentials (random password) |
| 12 | 🟡 Medium | Add rate limiting on RPC endpoints |
| 13 | 🟢 Low | Fix GoTrue version in Docker Compose |
| 14 | 🟢 Low | Create missing `seed.sql` or disable seed config |
| 15 | 🟢 Low | Add ability to clear optional patient fields |

---

## Appendix: Migration Lineage

| # | Migration | Purpose | Notes |
|---|-----------|---------|-------|
| 1 | `20260516100000` | Core schema (tables, types, RLS enable) | Foundation |
| 2 | `20260516100100` | Audit triggers | Auto-fill created_by/updated_at |
| 3 | `20260516100200` | RLS policies | JWT-based row filtering |
| 4 | `20260516100300` | Business logic RPCs + JWT claims | SECURITY DEFINER in public |
| 5 | `20260516100400` | Permission seed + bootstrap admin | Hardcoded credentials |
| 6 | `20260521100000` | Linter fixes | search_path, revoke anon |
| 7 | `20260521110000` | Move DEFINER to auth_internal | Major refactor |
| 8 | `20260521120000` | Fix NULL token columns | GoTrue compat |
| 9 | `20260521130000` | Rename role→staff_role in JWT | PostgREST compat |
| 10 | `20260521140000` | dev_reset_clinic_installation | Dev tooling |
| 11 | `20260521150000` | Fix dev_reset WHERE clause | PostgREST compat |
| 12 | `20260521160000` | Fix create_auth_user token columns | GoTrue compat |
| 13 | `20260521170000` | Restore org lookup + fix INVOKER | Regression fix |
| 14 | `20260521190000` | Username auth (replace email) | Breaking change |
| 15 | `20260522100000` | Org/branch management RPCs | V1-2 feature |
| 16 | `20260523120000` | Fix admin permission matrix access | Hotfix |
| 17 | `20260523140000` | Patient management | V1-3 feature |
| 18 | `20260523140100` | Fix update_patient gender preservation | Hotfix |
| 19 | `20260523150000` | Registration field changes | Schema alteration |

**Note**: Migrations 7–13 (7 migrations in 1 day) indicate rapid iteration with bugs introduced and fixed in sequence. This suggests insufficient local testing before committing migrations.

---

# Second Review Cycle

**Date**: 2026-05-24 (cycle 2)  
**Scope**: All 19 SQL migrations, RLS policies, config files, auth flow, cross-function consistency  
**Focus**: Logic bugs, cross-migration regressions, defense-in-depth gaps, naming/convention issues

---

## 9. New Bugs (Cycle 2)

### 9.1 🟠 `update_branch` erases optional fields when not provided (destructive PUT semantics)

**Location**: `20260522100000_org_branch_management.sql` — `auth_internal.update_branch`

```sql
UPDATE public.branches b
SET
  name = trim(p_name),
  code = NULLIF(trim(p_code), ''),
  address = NULLIF(trim(p_address), ''),     -- ← NULL when p_address is NULL (default)
  phone = NULLIF(trim(p_phone), ''),         -- ← same
  maps_url = NULLIF(trim(p_maps_url), ''),   -- ← same
  ...
```

All optional parameters default to `NULL`. When the caller omits `p_address`, it arrives as `NULL`, `trim(NULL)` = `NULL`, `NULLIF(NULL, '')` = `NULL` → the branch's address is **erased**.

Compare with `update_organization` which correctly preserves old values:
```sql
logo_url = COALESCE(NULLIF(trim(p_logo_url), ''), o.logo_url),
```

**Impact**: A Flutter form that only sends `name` and `code` (e.g., quick rename) silently wipes `address`, `phone`, and `maps_url` from the branch.

**Fix**: Use the same COALESCE-preservation pattern:
```sql
address = COALESCE(NULLIF(trim(p_address), ''), b.address),
phone = COALESCE(NULLIF(trim(p_phone), ''), b.phone),
maps_url = COALESCE(NULLIF(trim(p_maps_url), ''), b.maps_url),
```

---

### 9.2 🟡 `normalize_username` and `assert_valid_username` missing `SET search_path`

**Location**: `20260521190000_staff_username_auth.sql`, lines 7–38

```sql
CREATE OR REPLACE FUNCTION auth_internal.normalize_username(p_username text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(trim(p_username));
$$;

CREATE OR REPLACE FUNCTION auth_internal.assert_valid_username(p_username text)
RETURNS void
LANGUAGE plpgsql
AS $$
```

Both functions were created **after** migration 6 (linter fixes for rule 0011: `function_search_path_mutable`), yet neither sets `search_path`. This violates the convention established for every other function in the codebase and will be flagged by the Supabase Security Advisor.

**Impact**: Low exploitation risk (these only use built-in functions), but inconsistent and will generate linter warnings.

**Fix**: Add `SET search_path = ''` to both function definitions.

---

### 9.3 🟡 `search_patients` doesn't return `gender` or `marital_status` in list results

**Location**: `20260523140000_patient_management.sql` — `auth_internal.search_patients` (not updated in migration 19)

The search response includes:
```sql
'id', c.id, 'full_name', c.full_name, 'phone', c.phone,
'date_of_birth', c.date_of_birth, 'branch_id', c.branch_id, 'branch_name', c.branch_name
```

But omits `gender` and `marital_status` (added in migration 19). The `get_patient` detail RPC returns both. If the list view or any filter needs to display gender badges or marital status tags, an extra `get_patient` call per row is required.

**Impact**: Flutter list page may need `gender`/`marital_status` for UI display or filtering. Currently requires N+1 calls.

**Fix**: Add `p.gender::text` and `p.marital_status::text` to the `search_patients` SELECT and JSON output.

---

### 9.4 🟡 `set_staff_active` allows deactivating the sole owner (no last-owner guard)

**Location**: `20260522100000_org_branch_management.sql` — `auth_internal.set_staff_active`

Compare `set_branch_active` which explicitly prevents deactivating the last active branch:
```sql
IF v_active_count <= 1 THEN
  RETURN public.rpc_error('LAST_ACTIVE_BRANCH', ...);
END IF;
```

`set_staff_active` has **no equivalent check**. An administrator with `settings.manage_staff` can:
1. Deactivate all owner accounts
2. Leave only non-owner staff (including themselves) with no way to re-create owners
3. The only recovery path is direct database access by the bootstrap admin

Similarly, `update_staff_member` allows demoting the sole owner to `receptionist` (it only checks for promotion *to* owner, not demotion *from* owner).

**Impact**: Accidental or malicious owner lockout with no self-service recovery.

**Fix**: In `set_staff_active` (when `p_is_active = false`) and in `update_staff_member` (when changing `p_role` away from `owner`), check:
```sql
IF v_target.role = 'owner' THEN
  IF (SELECT count(*) FROM staff_members WHERE role = 'owner' AND is_active AND NOT is_deleted AND id != p_staff_member_id) < 1 THEN
    RETURN rpc_error('LAST_OWNER', 'Cannot deactivate or demote the last active owner.');
  END IF;
END IF;
```

---

### 9.5 🟢 `audit_log.timestamp` column name inconsistent with all other tables

**Location**: `20260516100000_auth_rbac_schema.sql`, line 194

Every other table uses `created_at` for the creation timestamp. The `audit_log` table uses `timestamp`:

```sql
timestamp timestamptz NOT NULL DEFAULT now()
```

This breaks the naming convention and causes confusion. The proposed `cleanup_audit_log` fix in the first review references `created_at` — which doesn't exist on this table.

**Impact**: Any future code referencing `audit_log.created_at` will fail. Developers must remember the exception.

**Fix**: Rename the column: `ALTER TABLE audit_log RENAME COLUMN timestamp TO created_at;` and update the index accordingly. Alternatively, document the exception prominently.

---

### 9.6 🟢 `set_branch_active` doesn't check if branch is already in the target state

**Location**: `20260522100000_org_branch_management.sql` — `auth_internal.set_branch_active`

Calling `set_branch_active(branch_id, true)` on an already-active branch still performs an UPDATE and writes an audit log entry (`branch.reactivate`). This creates misleading audit trails.

**Impact**: Noisy audit log with redundant entries. No data corruption but confusing for audit review.

**Fix**: Add an early return if `v_branch.is_active = p_is_active`:
```sql
IF v_branch.is_active = p_is_active THEN
  RETURN rpc_success(jsonb_build_object('branch_id', p_branch_id, 'is_active', p_is_active));
END IF;
```

---

## 10. New Security Issues (Cycle 2)

### 10.1 🟠 `set_branch_active` org fallback bypasses JWT org validation

**Location**: `20260522100000_org_branch_management.sql`, lines 330–337

```sql
v_org_id := public.jwt_organization_id();

IF v_org_id IS NULL THEN
  SELECT b.organization_id
  INTO v_org_id
  FROM public.branches b
  WHERE b.id = p_branch_id
    AND b.is_deleted = false;
END IF;
```

When `jwt_organization_id()` returns NULL (e.g., bootstrap admin during `setup_required = true`), the function falls back to the branch's own org. This means a bootstrap admin (who has `settings.manage_branches` permission) can activate/deactivate branches in **any** organization by passing any branch UUID — the org is not validated against the caller's JWT.

No other management RPC has this fallback pattern.

**Impact**: Bootstrap admin can manipulate branches outside their intended org scope.

**Fix**: Fail fast when org is null:
```sql
IF v_org_id IS NULL THEN
  RETURN rpc_error('ORG_SETUP_INCOMPLETE', 'Organization context is required.');
END IF;
```

---

### 10.2 🟠 `admin_reset_staff_password` allows resetting bootstrap admin's password

**Location**: `20260521110000_auth_rbac_definer_internal_schema.sql` — `auth_internal.admin_reset_staff_password`

The cross-org check verifies the target has a branch assignment in the caller's org. The bootstrap admin **does** have a branch assignment (auto-assigned during first branch creation). An owner or administrator can:

1. Call `admin_reset_staff_password(bootstrap_admin_staff_id, 'new_pass')`
2. Log in as the bootstrap admin
3. Gain `is_bootstrap_admin = true` which bypasses permission checks pre-org and grants access to `dev_reset_clinic_installation`

**Impact**: Privilege escalation to bootstrap admin, including ability to wipe the entire installation.

**Fix**: Add a guard in `admin_reset_staff_password`:
```sql
IF v_target.is_bootstrap_admin AND v_target.auth_user_id != auth.uid() THEN
  RETURN rpc_error('FORBIDDEN', 'The bootstrap administrator password cannot be reset by other staff.');
END IF;
```

---

### 10.3 🟡 Broad `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES` to `authenticated`

**Location**: `20260516100200_auth_rbac_rls.sql`, line 28

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
```

This grants full DML on **every current and future** public table (via `ALL TABLES`). While RLS policies block unauthorized access, this is fragile:

- Any new table added without enabling RLS is wide open
- If `ALTER TABLE ... DISABLE ROW LEVEL SECURITY` is accidentally run, all data is exposed
- Any permissive INSERT/UPDATE/DELETE policy added to `audit_log` would allow direct writes

**Impact**: Low risk today (RLS is enabled on all tables), but creates a landmine for future development.

**Fix**: Replace with explicit per-table grants:
```sql
GRANT SELECT ON public.organizations TO authenticated;
GRANT SELECT, UPDATE ON public.organizations TO authenticated;
-- etc. per table with only required operations
```
Or at minimum, add a migration that revokes DML on audit_log:
```sql
REVOKE INSERT, UPDATE, DELETE ON public.audit_log FROM authenticated;
```

---

### 10.4 🟡 `.env.example` contains well-known Supabase demo JWT tokens

**Location**: `backend/local/.env.example`

```env
SUPABASE_JWT_SECRET=your-super-secret-jwt-token-with-at-least-32-characters-long
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIs...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIs...
```

The anon key and service_role key are the **publicly documented Supabase demo JWTs** (the same ones in every Supabase quickstart guide). The JWT secret is a readable placeholder string. If any deployment accidentally uses these values:
- The service_role key (which bypasses RLS) is publicly known
- Anyone can forge valid JWTs with the placeholder secret

**Impact**: Not a bug in local dev, but a deployment trap. Unlike random secrets that would fail visibly, these tokens actually work.

**Fix**: 
- Add a startup check that rejects the well-known demo secrets in production
- Or generate random secrets in the `.env.example` with a clear `CHANGEME` tag
- Add a comment: `# WARNING: These are PUBLIC demo keys. NEVER use in production.`

---

## 11. New Architectural Issues (Cycle 2)

### 11.1 🟡 Inconsistent data access: staff via RLS, patients via RPC-only

Staff members are read through direct table SELECT filtered by RLS policies. Patients are accessed exclusively through RPCs (`search_patients`, `get_patient`) that control the response shape.

This creates two problems:
1. **Schema coupling**: The Flutter client receives raw `staff_members` columns (including `is_bootstrap_admin`, `is_deleted`, `auth_user_id`) through RLS, while patient data has a controlled contract. If the `staff_members` table structure changes, the client breaks.
2. **Inconsistent security model**: Patient access has granular RPC-level permission checks (`patients.view`). Staff access relies on RLS policies that check org membership but not a specific permission key — any authenticated user in the org can SELECT staff members.

**Recommendation**: Add a `get_staff_members` RPC wrapper (similar to `search_patients`) that returns a controlled JSON shape and enforces `settings.manage_staff` for listing beyond self.

---

### 11.2 🟡 `audit_log` has no explicit write-deny policies

**Location**: `20260516100200_auth_rbac_rls.sql`

Only a SELECT policy exists for `audit_log`. INSERT, UPDATE, and DELETE rely on implicit RLS deny (no policy = deny all). However, combined with the broad table grant (issue 10.3), this is a single misconfiguration away from allowing direct audit tampering.

**Recommendation**: Add explicit deny policies:
```sql
CREATE POLICY audit_log_insert ON public.audit_log FOR INSERT TO authenticated WITH CHECK (false);
CREATE POLICY audit_log_update ON public.audit_log FOR UPDATE TO authenticated USING (false);
CREATE POLICY audit_log_delete ON public.audit_log FOR DELETE TO authenticated USING (false);
```

---

### 11.3 🟢 `staff_branch_assignments` SELECT policy limits admin visibility

**Location**: `20260516100200_auth_rbac_rls.sql`, lines 244–256

The RLS policy only shows assignments for branches the caller is assigned to:
```sql
USING (
  is_deleted = false
  AND branch_id = ANY (public.jwt_branch_ids())
)
```

An admin at Branch A managing staff at Branch B cannot see Branch B's assignments through direct table queries (the RLS blocks it). RPCs bypass this via SECURITY DEFINER, but any Flutter widget querying `staff_branch_assignments` directly would see incomplete data.

**Recommendation**: Add an org-level override for administrators:
```sql
OR (
  EXISTS (
    SELECT 1 FROM public.current_staff_member_row() sm
    WHERE sm.role IN ('owner', 'administrator')
  )
  AND branch_id IN (
    SELECT b.id FROM public.branches b
    WHERE b.organization_id = public.jwt_organization_id()
  )
)
```

---

## 12. Summary of Cycle 2 Recommendations (Priority Order)

| # | Priority | Issue | Action |
|---|----------|-------|--------|
| C2-1 | 🟠 High | `update_branch` data loss (9.1) | Use COALESCE preservation for optional fields |
| C2-2 | 🟠 High | Bootstrap admin password hijack (10.2) | Block non-self reset of bootstrap admin |
| C2-3 | 🟠 High | `set_branch_active` org bypass (10.1) | Fail fast when JWT org is null |
| C2-4 | 🟡 Medium | Last-owner guard missing (9.4) | Add owner count check in deactivate/demote |
| C2-5 | 🟡 Medium | Broad table DML grants (10.3) | Restrict to per-table grants or add audit_log revoke |
| C2-6 | 🟡 Medium | `search_patients` missing fields (9.3) | Add gender and marital_status to response |
| C2-7 | 🟡 Medium | Username functions missing search_path (9.2) | Add `SET search_path = ''` |
| C2-8 | 🟡 Medium | Audit log write-deny policies (11.2) | Add explicit deny INSERT/UPDATE/DELETE |
| C2-9 | 🟡 Medium | Demo JWT tokens in .env.example (10.4) | Add warnings and production guard |
| C2-10 | 🟢 Low | Audit log column naming (9.5) | Rename `timestamp` to `created_at` |
| C2-11 | 🟢 Low | Branch state change no-op audit noise (9.6) | Check current state before updating |
| C2-12 | 🟢 Low | Staff access pattern inconsistency (11.1) | Consider get_staff_members RPC |
| C2-13 | 🟢 Low | Branch assignments RLS visibility (11.3) | Add admin org-level override |
