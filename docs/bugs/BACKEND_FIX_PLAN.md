# Backend Fix Plan — AiClinic

**Date**: 2026-05-24  
**Source**: `backend/BACKEND_CODE_REVIEW.md`  
**Scope**: All issues identified — 6 bugs, 8 architectural flaws, 5 security issues, 4 performance issues, 8 future-extension concerns, 4 test gaps, 3 config issues

---

## Migration Strategy

All fixes will be delivered as **new forward-only migrations** appended after the existing 19 migrations. Each fix section specifies its migration file name. Fixes are grouped into logical migrations to minimize file count while maintaining atomic changesets.

**Naming convention**: `20260524HHMMSS_fix_<description>.sql`

---

## Priority 1 — Critical

### Fix 1: Stop returning plaintext passwords in RPC responses

**Review Issue**: 3.1 — `create_staff_account` and `admin_reset_staff_password` return `assigned_password` in the JSON response body.

**Migration**: `20260524100000_fix_remove_plaintext_password_from_responses.sql`

**Detailed Steps**:

1. Redefine `auth_internal.create_staff_account` with `CREATE OR REPLACE FUNCTION`:
   - Remove `'assigned_password', p_password` from the `jsonb_build_object` in the RETURN statement.
   - Return only `staff_member_id` and `username` in the success payload.

2. Redefine `auth_internal.admin_reset_staff_password` with `CREATE OR REPLACE FUNCTION`:
   - Remove `'new_password', p_new_password` from the success response.
   - Return only `staff_member_id` and a `'password_reset', true` flag.

3. Redefine the corresponding public INVOKER wrappers if they relay the inner response directly (they do — just pass-through, no additional filtering needed since the inner function changes).

**Code Change (create_staff_account)**:
```sql
-- BEFORE:
RETURN public.rpc_success(
  jsonb_build_object(
    'staff_member_id', v_staff_id,
    'assigned_password', p_password
  )
);

-- AFTER:
RETURN public.rpc_success(
  jsonb_build_object(
    'staff_member_id', v_staff_id,
    'username', v_username
  )
);
```

**Code Change (admin_reset_staff_password)**:
```sql
-- BEFORE:
RETURN public.rpc_success(
  jsonb_build_object(
    'staff_member_id', p_staff_member_id,
    'new_password', p_new_password
  )
);

-- AFTER:
RETURN public.rpc_success(
  jsonb_build_object(
    'staff_member_id', p_staff_member_id,
    'password_reset', true
  )
);
```

**Frontend Impact**: Update any Flutter code that reads `assigned_password` or `new_password` from RPC responses. The admin UI should display the password from the local form state (what they just typed), not from the server response.

**Verification**:
- Call `create_staff_account` and confirm response JSON has no password field.
- Call `admin_reset_staff_password` and confirm response has only the boolean flag.

---

## Priority 2 — High

### Fix 2: Restrict `auth_internal` grants to specific functions only

**Review Issue**: 1.1 — Blanket `GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth_internal TO authenticated` exposes helper functions like `build_staff_claims`, `organization_exists`, `normalize_username`.

**Migration**: `20260524100100_fix_restrict_auth_internal_grants.sql`

**Detailed Steps**:

1. Revoke the blanket grant:
```sql
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA auth_internal FROM authenticated;
```

2. Set default privileges so new functions are NOT auto-granted:
```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA auth_internal
  REVOKE EXECUTE ON FUNCTIONS FROM authenticated;
```

3. Grant execute only to `service_role` (which the SECURITY DEFINER functions run as implicitly — they don't need authenticated to call them directly):
```sql
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth_internal TO service_role;
```

4. The public INVOKER wrappers already call `auth_internal.*` functions. Since INVOKER functions run as the calling user, we need the wrappers themselves to be `SECURITY DEFINER` set to a role that can call `auth_internal`. **However**, the current architecture already has the public wrappers as INVOKER that call `auth_internal` SECURITY DEFINER functions. The DEFINER functions execute as their owner (typically `postgres`), so they can access `auth_internal` regardless of the caller's grants.

   **Key insight**: The `auth_internal` functions are `SECURITY DEFINER` owned by `postgres`. They don't need the *caller* to have EXECUTE on `auth_internal` — the function body runs as the owner. The only reason the grant existed was likely a misunderstanding. The public wrappers call `auth_internal.*` and those inner functions are DEFINER, so they execute as `postgres` regardless.

   **Wait — correction**: Re-read the architecture. Public wrappers are `SECURITY INVOKER`. They call `auth_internal.*` functions. For the INVOKER wrapper to *call* a `auth_internal` function, the calling role (`authenticated`) needs EXECUTE on that function — even if the called function is DEFINER. The DEFINER only affects what happens *inside* the called function, not whether you can call it.

   **Revised approach**: Grant EXECUTE only on the specific `auth_internal` functions that are called by the public wrappers:

```sql
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA auth_internal FROM authenticated;

-- Grant only functions invoked by public INVOKER wrappers:
GRANT EXECUTE ON FUNCTION auth_internal.create_staff_account TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.admin_reset_staff_password TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_staff_member TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.get_staff_members TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_role_permission TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_organization TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_organization TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.manage_create_branch TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_branch TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.search_patients TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.get_patient TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.check_patient_duplicates TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_patient TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_patient TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.archive_patient TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.dev_reset_clinic_installation TO authenticated;
-- Add any other functions called directly by public wrappers
```

5. Verify the exact function signatures (with parameter types) since PostgreSQL grant requires exact signature match. Query:
```sql
SELECT p.proname, pg_get_function_identity_arguments(p.oid)
FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'auth_internal';
```

**Verification**:
- As an authenticated user, attempt `SELECT auth_internal.build_staff_claims('some-uuid')` — should get permission denied.
- All public RPC wrappers (e.g., `SELECT public.create_patient(...)`) should still work.

---

### Fix 3: Add password complexity validation in RPCs

**Review Issue**: 3.2 — No password length/complexity check in `create_staff_account` and `admin_reset_staff_password`.

**Migration**: `20260524100200_fix_password_complexity_validation.sql`

**Detailed Steps**:

1. Create a reusable validation helper:
```sql
CREATE OR REPLACE FUNCTION auth_internal.assert_password_complexity(p_password text)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF p_password IS NULL OR length(p_password) < 8 THEN
    RAISE EXCEPTION 'Password must be at least 8 characters'
      USING ERRCODE = 'check_violation';
  END IF;

  -- At least one letter and one digit
  IF p_password !~ '[A-Za-z]' THEN
    RAISE EXCEPTION 'Password must contain at least one letter'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_password !~ '[0-9]' THEN
    RAISE EXCEPTION 'Password must contain at least one digit'
      USING ERRCODE = 'check_violation';
  END IF;
END;
$$;
```

2. Add a call at the top of `auth_internal.create_staff_account`:
```sql
PERFORM auth_internal.assert_password_complexity(p_password);
```

3. Add the same call at the top of `auth_internal.admin_reset_staff_password`:
```sql
PERFORM auth_internal.assert_password_complexity(p_new_password);
```

4. Redefine both functions with `CREATE OR REPLACE` including the new validation call.

**Verification**:
- Attempt to create a staff account with password `'ab'` → should fail with complexity error.
- Attempt with `'abcdefgh'` (no digit) → should fail.
- Attempt with `'12345678'` (no letter) → should fail.
- Attempt with `'Admin123'` → should succeed.

---

### Fix 4: Add unique/partial index on patient phone for duplicate prevention

**Review Issues**: 1.2 (race condition) + 4.3 (duplicate scan performance)

**Migration**: `20260524100300_fix_patient_phone_index.sql`

**Detailed Steps**:

1. Add a partial unique index for org-scoped phone uniqueness:
```sql
CREATE UNIQUE INDEX patients_org_phone_unique_idx
  ON public.patients (organization_id, phone)
  WHERE is_deleted = false;
```

2. This ensures the race condition in `create_patient` is caught at the DB level — even if two concurrent transactions pass the soft-check, one INSERT will fail with a unique violation.

3. Update `auth_internal.create_patient` to handle the unique violation gracefully:
```sql
BEGIN
  INSERT INTO public.patients (...) VALUES (...);
EXCEPTION
  WHEN unique_violation THEN
    RETURN public.rpc_error(
      'DUPLICATE_PHONE',
      'A patient with this phone number already exists in the organization'
    );
END;
```

4. Also add a non-unique index for the `find_patient_duplicate_candidates` scan:
```sql
-- This replaces the sequential scan in duplicate-finding
CREATE INDEX patients_org_phone_idx
  ON public.patients (organization_id, phone)
  WHERE is_deleted = false;
```

   **Note**: The unique index above already serves this purpose, so the separate non-unique index is redundant. The unique index will be used for both uniqueness enforcement and lookup acceleration.

**Verification**:
- Open two `psql` sessions, BEGIN in both, attempt same phone INSERT in same org → one should fail.
- Run `EXPLAIN ANALYZE` on `find_patient_duplicate_candidates` → should show index scan.

---

### Fix 5: Protect `dev_reset_clinic_installation` from production use

**Review Issues**: 2.5 — No environment guard on destructive reset function.

**Migration**: `20260524100400_fix_dev_reset_environment_guard.sql`

**Detailed Steps**:

1. Redefine `auth_internal.dev_reset_clinic_installation` to check environment:
```sql
CREATE OR REPLACE FUNCTION auth_internal.dev_reset_clinic_installation()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_env text;
BEGIN
  -- Environment gate: only allow in development/local
  v_env := current_setting('app.environment', true);
  IF v_env IS NULL OR v_env NOT IN ('development', 'local', 'test') THEN
    RETURN public.rpc_error(
      'FORBIDDEN',
      'dev_reset_clinic_installation can only run in development/local/test environments'
    );
  END IF;

  -- Existing bootstrap admin check
  PERFORM auth_internal.assert_bootstrap_admin();

  -- ... rest of existing reset logic ...
END;
$$;
```

2. Set the environment variable in local Docker Compose and Supabase config:
   - In `backend/local/docker-compose.yml`, add to the postgres service environment:
     ```yaml
     POSTGRES_INITDB_ARGS: "-c app.environment=development"
     ```
   - Or set via `ALTER DATABASE postgres SET app.environment = 'development';` in a local-only seed.

3. In production deployments, `app.environment` will either not be set (NULL) or set to `'production'`, blocking the reset.

**Verification**:
- In local dev: calling `dev_reset_clinic_installation` as bootstrap admin should succeed.
- Set `app.environment = 'production'` and call → should fail with FORBIDDEN.

---

### Fix 6: Add rollback safety for destructive enum migrations

**Review Issue**: 2.2 — Enum ALTER can fail mid-migration if unexpected values exist.

**Migration**: `20260524100500_fix_enum_migration_safety.sql`

This is a **retrospective safeguard** — the original migration already ran. But we add a pattern for future use and verify current state:

**Detailed Steps**:

1. Add a verification check (idempotent):
```sql
DO $$
BEGIN
  -- Verify no orphaned enum type exists
  IF EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'patient_gender_new'
  ) THEN
    RAISE EXCEPTION 'Orphaned patient_gender_new type detected — manual cleanup required';
  END IF;

  -- Verify current enum values are exactly what we expect
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON e.enumtypid = t.oid
    WHERE t.typname = 'patient_gender'
    AND e.enumlabel = 'male'
  ) THEN
    RAISE EXCEPTION 'patient_gender enum is in unexpected state';
  END IF;
END;
$$;
```

2. Document the rollback pattern for future enum changes in a comment block at the top of the migration:
```sql
/*
  ENUM MIGRATION SAFETY PATTERN:
  Before any ALTER TYPE ... USING cast:
    1. Pre-check: SELECT count(*) FROM table WHERE column::text NOT IN ('allowed','values')
    2. If count > 0, RAISE EXCEPTION with details
    3. Perform the ALTER inside a subtransaction if possible
    4. Verify post-condition
*/
```

3. For the current state, verify data integrity:
```sql
DO $$
DECLARE
  v_bad_count int;
BEGIN
  SELECT count(*) INTO v_bad_count
  FROM public.patients
  WHERE gender::text NOT IN ('male', 'female');

  IF v_bad_count > 0 THEN
    RAISE WARNING '% patients have unexpected gender values', v_bad_count;
  END IF;
END;
$$;
```

---

## Priority 3 — Medium

### Fix 7: Fix indexes for search performance (trigram + functional)

**Review Issues**: 1.3 (dead index condition), 1.4 (unusable name index), 4.2 (LIKE pattern)

**Migration**: `20260524110000_fix_search_indexes.sql`

**Detailed Steps**:

1. Enable the `pg_trgm` extension:
```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

2. Drop the useless indexes:
```sql
-- Dead condition (phone IS NOT NULL is always true now)
DROP INDEX IF EXISTS public.patients_branch_phone_idx;

-- Cannot be used for lower() LIKE '%...%' queries
DROP INDEX IF EXISTS public.patients_branch_full_name_idx;
```

3. Create the trigram GIN index for case-insensitive name search:
```sql
CREATE INDEX patients_org_fullname_trgm_idx
  ON public.patients
  USING gin (lower(full_name) gin_trgm_ops)
  WHERE is_deleted = false;
```

4. Create an org-scoped phone index for phone-prefix searches:
```sql
CREATE INDEX patients_org_phone_prefix_idx
  ON public.patients (organization_id, phone text_pattern_ops)
  WHERE is_deleted = false;
```
   `text_pattern_ops` allows `LIKE 'prefix%'` to use the B-tree index.

5. Keep a branch-scoped phone index for branch-filtered queries:
```sql
CREATE INDEX patients_branch_phone_prefix_idx
  ON public.patients (branch_id, phone text_pattern_ops)
  WHERE is_deleted = false;
```

**Verification**:
```sql
-- Should show Index Scan using patients_org_fullname_trgm_idx
EXPLAIN ANALYZE
SELECT * FROM patients
WHERE is_deleted = false
  AND organization_id = 'some-uuid'
  AND lower(full_name) LIKE '%ahmed%';

-- Should show Index Scan using patients_org_phone_prefix_idx
EXPLAIN ANALYZE
SELECT * FROM patients
WHERE is_deleted = false
  AND organization_id = 'some-uuid'
  AND phone LIKE '0100%';
```

---

### Fix 8: Separate count query from paginated search

**Review Issue**: 4.1 — `count(*) OVER()` forces full materialization.

**Migration**: `20260524110100_fix_search_patients_pagination.sql`

**Detailed Steps**:

1. Redefine `auth_internal.search_patients` to use a separate count query:

```sql
CREATE OR REPLACE FUNCTION auth_internal.search_patients(
  p_organization_id uuid,
  p_branch_id uuid DEFAULT NULL,
  p_name_query text DEFAULT NULL,
  p_phone_query text DEFAULT NULL,
  p_limit int DEFAULT 25,
  p_offset int DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_total_count int;
  v_results jsonb;
  v_escaped_name_query text;
  v_normalized_phone text;
BEGIN
  -- Permission check
  PERFORM auth_internal.assert_permission('patients.view');
  PERFORM auth_internal.assert_org_access(p_organization_id);

  -- Normalize inputs
  v_escaped_name_query := CASE
    WHEN p_name_query IS NOT NULL AND trim(p_name_query) != ''
    THEN lower(trim(p_name_query))
    ELSE NULL
  END;

  v_normalized_phone := CASE
    WHEN p_phone_query IS NOT NULL AND trim(p_phone_query) != ''
    THEN auth_internal.normalize_patient_phone(p_phone_query)
    ELSE NULL
  END;

  -- Count query (separate, avoids OVER() materialization)
  SELECT count(*) INTO v_total_count
  FROM public.patients p
  WHERE p.organization_id = p_organization_id
    AND p.is_deleted = false
    AND (p_branch_id IS NULL OR p.branch_id = p_branch_id)
    AND (v_escaped_name_query IS NULL OR lower(p.full_name) LIKE '%' || v_escaped_name_query || '%')
    AND (v_normalized_phone IS NULL OR p.phone LIKE v_normalized_phone || '%');

  -- Data query (with LIMIT/OFFSET, no window function)
  SELECT COALESCE(jsonb_agg(row_to_json(sub)::jsonb ORDER BY sub.full_name), '[]'::jsonb)
  INTO v_results
  FROM (
    SELECT p.id, p.full_name, p.phone, p.gender::text,
           p.branch_id, p.national_id, p.created_at
    FROM public.patients p
    WHERE p.organization_id = p_organization_id
      AND p.is_deleted = false
      AND (p_branch_id IS NULL OR p.branch_id = p_branch_id)
      AND (v_escaped_name_query IS NULL OR lower(p.full_name) LIKE '%' || v_escaped_name_query || '%')
      AND (v_normalized_phone IS NULL OR p.phone LIKE v_normalized_phone || '%')
    ORDER BY p.full_name ASC
    LIMIT p_limit OFFSET p_offset
  ) sub;

  RETURN public.rpc_success(
    jsonb_build_object(
      'patients', v_results,
      'total_count', v_total_count,
      'limit', p_limit,
      'offset', p_offset
    )
  );
END;
$$;
```

**Trade-off**: Two queries instead of one. For small result sets this is slightly more overhead. For large result sets (1000+), the savings from not materializing all rows for the LIMIT page outweigh the second query cost. The count query can use the same indexes and should be fast with proper indexing from Fix 7.

**Verification**:
- Insert 5000 test patients.
- Run `search_patients` with no filter → compare execution time before/after.
- Verify `total_count` matches `SELECT count(*) FROM patients WHERE ...`.

---

### Fix 9: Add patient transfer and restore RPCs

**Review Issues**: 5.1 (no branch transfer), 5.2 (no restore/unarchive)

**Migration**: `20260524110200_fix_patient_transfer_restore.sql`

**Detailed Steps**:

1. **Transfer patient RPC**:
```sql
CREATE OR REPLACE FUNCTION auth_internal.transfer_patient(
  p_patient_id uuid,
  p_new_branch_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_staff record;
  v_patient record;
  v_branch record;
BEGIN
  -- Permission: reuse patients.edit
  v_staff := auth_internal.get_authenticated_staff();
  PERFORM auth_internal.assert_permission('patients.edit');

  -- Validate patient exists and belongs to caller's org
  SELECT * INTO v_patient
  FROM public.patients
  WHERE id = p_patient_id AND is_deleted = false;

  IF v_patient IS NULL THEN
    RETURN public.rpc_error('NOT_FOUND', 'Patient not found');
  END IF;

  PERFORM auth_internal.assert_org_access(v_patient.organization_id);

  -- Validate target branch exists, is active, and belongs to same org
  SELECT * INTO v_branch
  FROM public.branches
  WHERE id = p_new_branch_id
    AND is_deleted = false
    AND is_active = true
    AND organization_id = v_patient.organization_id;

  IF v_branch IS NULL THEN
    RETURN public.rpc_error('INVALID_BRANCH', 'Target branch not found or not active in the same organization');
  END IF;

  -- Perform transfer
  UPDATE public.patients
  SET branch_id = p_new_branch_id,
      updated_at = now(),
      updated_by = v_staff.user_id
  WHERE id = p_patient_id;

  -- Audit
  INSERT INTO public.audit_log (action, table_name, record_id, actor_id, organization_id, details)
  VALUES ('patient.transfer', 'patients', p_patient_id, v_staff.user_id, v_patient.organization_id,
    jsonb_build_object(
      'from_branch_id', v_patient.branch_id,
      'to_branch_id', p_new_branch_id
    )
  );

  RETURN public.rpc_success(jsonb_build_object('patient_id', p_patient_id, 'new_branch_id', p_new_branch_id));
END;
$$;
```

2. **Restore patient RPC**:
```sql
CREATE OR REPLACE FUNCTION auth_internal.restore_patient(
  p_patient_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_staff record;
  v_patient record;
BEGIN
  -- Permission: patients.delete (same permission as archive)
  v_staff := auth_internal.get_authenticated_staff();
  PERFORM auth_internal.assert_permission('patients.delete');

  -- Find the archived patient
  SELECT * INTO v_patient
  FROM public.patients
  WHERE id = p_patient_id AND is_deleted = true;

  IF v_patient IS NULL THEN
    RETURN public.rpc_error('NOT_FOUND', 'Archived patient not found');
  END IF;

  PERFORM auth_internal.assert_org_access(v_patient.organization_id);

  -- Check for phone conflict with existing active patient
  IF EXISTS (
    SELECT 1 FROM public.patients
    WHERE organization_id = v_patient.organization_id
      AND phone = v_patient.phone
      AND is_deleted = false
      AND id != p_patient_id
  ) THEN
    RETURN public.rpc_error('DUPLICATE_PHONE', 'Another active patient already has this phone number');
  END IF;

  -- Restore
  UPDATE public.patients
  SET is_deleted = false,
      updated_at = now(),
      updated_by = v_staff.user_id
  WHERE id = p_patient_id;

  -- Audit
  INSERT INTO public.audit_log (action, table_name, record_id, actor_id, organization_id, details)
  VALUES ('patient.restore', 'patients', p_patient_id, v_staff.user_id, v_patient.organization_id, '{}'::jsonb);

  RETURN public.rpc_success(jsonb_build_object('patient_id', p_patient_id));
END;
$$;
```

3. **Public INVOKER wrappers**:
```sql
CREATE OR REPLACE FUNCTION public.transfer_patient(p_patient_id uuid, p_new_branch_id uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN RETURN auth_internal.transfer_patient(p_patient_id, p_new_branch_id); END; $$;

CREATE OR REPLACE FUNCTION public.restore_patient(p_patient_id uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN RETURN auth_internal.restore_patient(p_patient_id); END; $$;

GRANT EXECUTE ON FUNCTION public.transfer_patient(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.restore_patient(uuid) TO authenticated;
```

**Verification**:
- Transfer a patient from branch A to branch B → verify `branch_id` updated, audit log written.
- Archive a patient → restore → verify `is_deleted = false` and patient appears in search.
- Attempt restore when phone conflicts → should fail with DUPLICATE_PHONE.

---

### Fix 10: Implement audit log retention strategy

**Review Issue**: 2.6 — Unbounded audit log growth.

**Migration**: `20260524110300_fix_audit_log_retention.sql`

**Detailed Steps**:

1. Add a `created_at` index for efficient range-based queries and deletion:
```sql
CREATE INDEX IF NOT EXISTS audit_log_created_at_idx
  ON public.audit_log (created_at);
```

2. Create a retention cleanup function (configurable retention period):
```sql
CREATE OR REPLACE FUNCTION auth_internal.cleanup_audit_log(
  p_retention_days int DEFAULT 365
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_cutoff timestamptz;
  v_deleted_count int;
BEGIN
  PERFORM auth_internal.assert_bootstrap_admin();

  v_cutoff := now() - (p_retention_days || ' days')::interval;

  DELETE FROM public.audit_log
  WHERE created_at < v_cutoff;

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

  RETURN public.rpc_success(
    jsonb_build_object(
      'deleted_count', v_deleted_count,
      'cutoff_date', v_cutoff
    )
  );
END;
$$;
```

3. Public wrapper:
```sql
CREATE OR REPLACE FUNCTION public.cleanup_audit_log(p_retention_days int DEFAULT 365)
RETURNS jsonb LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN RETURN auth_internal.cleanup_audit_log(p_retention_days); END; $$;

GRANT EXECUTE ON FUNCTION public.cleanup_audit_log(int) TO authenticated;
```

4. **Future enhancement**: For production at scale, consider partitioning:
```sql
-- Future: convert to range-partitioned table
-- ALTER TABLE audit_log RENAME TO audit_log_old;
-- CREATE TABLE audit_log (...) PARTITION BY RANGE (created_at);
-- CREATE TABLE audit_log_2026_q1 PARTITION OF audit_log FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');
-- etc.
```

**Verification**:
- Insert audit entries with old timestamps, call cleanup with 30 days retention, verify old entries deleted.
- Non-bootstrap user cannot call cleanup.

---

### Fix 11: Harden bootstrap credentials

**Review Issue**: 3.3 — Hardcoded `admin` / `admin` with fixed UUID across all installations.

**Migration**: `20260524110400_fix_bootstrap_credential_hardening.sql`

**Detailed Steps**:

1. This cannot retroactively change the seed migration (it already ran). Instead, add a **post-install force-password-change** mechanism:

```sql
-- Add a flag to track if bootstrap password has been changed
ALTER TABLE public.staff_members
  ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false;

-- Mark the bootstrap admin
UPDATE public.staff_members
SET must_change_password = true
WHERE id = (
  SELECT sm.id FROM public.staff_members sm
  WHERE sm.is_bootstrap_admin = true
  AND sm.is_deleted = false
  LIMIT 1
);
```

2. Add a check in `auth_internal.build_staff_claims` to include a `must_change_password` flag in the JWT:
```sql
-- In build_staff_claims, after determining v_staff:
v_must_change := COALESCE(v_staff.must_change_password, false);

-- Include in claims:
'must_change_password', v_must_change
```

3. Optionally, add enforcement at the RPC level — if `must_change_password = true`, block all RPCs except `admin_reset_staff_password` (for self):
```sql
-- In assert_permission or a new guard:
IF v_staff.must_change_password THEN
  RAISE EXCEPTION 'Password change required before performing any action'
    USING ERRCODE = 'insufficient_privilege';
END IF;
```

4. After admin changes their password via `admin_reset_staff_password`, clear the flag:
```sql
UPDATE public.staff_members
SET must_change_password = false
WHERE id = p_staff_member_id;
```

**Alternative (for new installations)**: Modify the seed to read from environment:
```sql
v_password text := COALESCE(
  current_setting('app.bootstrap_password', true),
  gen_random_uuid()::text  -- random if not configured
);
RAISE NOTICE 'Bootstrap admin password: %', v_password;
```

**Verification**:
- Fresh install → admin logs in → JWT contains `must_change_password: true`.
- Frontend blocks navigation until password changed.
- After password change → flag cleared → normal access.

---

### Fix 12: Add rate limiting guidance (Kong configuration)

**Review Issue**: 3.4 — No rate limiting on RPC endpoints.

**Implementation**: This is a **configuration change**, not a SQL migration.

**File**: `backend/local/kong.yml` (or equivalent API gateway config)

**Detailed Steps**:

1. Add rate-limiting plugin to Kong configuration:
```yaml
plugins:
  - name: rate-limiting
    config:
      minute: 60
      hour: 1000
      policy: local
      fault_tolerant: true
      hide_client_headers: false
    route: rpc-routes
```

2. For specific sensitive endpoints, add stricter limits:
```yaml
# Stricter rate limit for auth-related RPCs
- name: rate-limiting
  route: auth-rpcs
  config:
    minute: 10
    hour: 100
    policy: local
```

3. Map routes:
```yaml
routes:
  - name: auth-rpcs
    paths:
      - /rest/v1/rpc/create_staff_account
      - /rest/v1/rpc/admin_reset_staff_password
    methods: [POST]
  - name: rpc-routes
    paths:
      - /rest/v1/rpc/
    methods: [POST]
```

4. **Alternative** (if Kong is not available): Add a simple rate-check in the database using a tracking table:
```sql
CREATE TABLE IF NOT EXISTS auth_internal.rate_limit_log (
  user_id uuid,
  endpoint text,
  called_at timestamptz DEFAULT now()
);

CREATE INDEX rate_limit_log_lookup_idx
  ON auth_internal.rate_limit_log (user_id, endpoint, called_at);
```

**Verification**:
- Call an RPC endpoint 61 times in 1 minute → 61st should return 429.
- Call `create_staff_account` 11 times in 1 minute → 11th should return 429.

---

## Priority 4 — Low

### Fix 13: Update GoTrue version in Docker Compose

**Review Issue**: 1.5 + 7.1 — Version pinned to v2.186.0, migrations assume v2.188+.

**File**: `backend/local/docker-compose.yml`

**Detailed Steps**:

1. Update the image tag:
```yaml
auth:
  image: supabase/gotrue:v2.188.0
```

2. Verify migration compatibility by running `supabase db reset` with the new version.

3. Test the auth flow (`auth_flow_smoke.sh`) with the updated image.

**Verification**:
- `docker compose up auth` starts without errors.
- Login flow works end-to-end.
- Token columns handled correctly (no NULL scan errors).

---

### Fix 14: Create missing `seed.sql` or disable seed config

**Review Issue**: 7.2 — `config.toml` references `./seed.sql` which doesn't exist.

**File**: `backend/supabase/seed.sql`

**Detailed Steps**:

Option A — Create an empty seed file:
```sql
-- Seed file for local development
-- The bootstrap admin is created by migration 20260516100400_auth_rbac_seed.sql
-- Add any additional local dev seed data below this line.
```

Option B — Disable seed in config:

In `backend/supabase/config.toml`:
```toml
[db.seed]
enabled = false
```

**Recommendation**: Go with Option A — an empty seed file with a comment. This allows developers to add local test data in the future.

**Verification**:
- Run `supabase db reset` → should complete without seed-related errors.

---

### Fix 15: Add ability to clear optional patient fields

**Review Issue**: 1.6 — Cannot reset `gender`, `marital_status`, `date_of_birth`, `notes` to NULL.

**Migration**: `20260524120000_fix_patient_clearable_fields.sql`

**Detailed Steps**:

1. Add explicit clear parameters to `update_patient`:
```sql
CREATE OR REPLACE FUNCTION auth_internal.update_patient(
  p_patient_id uuid,
  p_full_name text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_gender text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_marital_status text DEFAULT NULL,
  p_national_id text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_updated_at timestamptz DEFAULT NULL,
  -- New: explicit clear flags
  p_clear_gender boolean DEFAULT false,
  p_clear_date_of_birth boolean DEFAULT false,
  p_clear_marital_status boolean DEFAULT false,
  p_clear_notes boolean DEFAULT false
)
RETURNS jsonb
...
```

2. Modify the update logic for each clearable field:
```sql
-- Gender
v_gender := CASE
  WHEN p_clear_gender THEN NULL
  WHEN p_gender IS NOT NULL AND NULLIF(trim(p_gender), '') IS NOT NULL
    THEN p_gender::public.patient_gender
  ELSE existing_patient.gender
END;

-- Date of birth
v_dob := CASE
  WHEN p_clear_date_of_birth THEN NULL
  WHEN p_date_of_birth IS NOT NULL THEN p_date_of_birth
  ELSE existing_patient.date_of_birth
END;

-- Marital status
v_marital := CASE
  WHEN p_clear_marital_status THEN NULL
  WHEN p_marital_status IS NOT NULL AND NULLIF(trim(p_marital_status), '') IS NOT NULL
    THEN p_marital_status::public.patient_marital_status
  ELSE existing_patient.marital_status
END;

-- Notes
v_notes := CASE
  WHEN p_clear_notes THEN NULL
  WHEN p_notes IS NOT NULL THEN p_notes
  ELSE existing_patient.notes
END;
```

3. Update the public INVOKER wrapper to pass through the new parameters.

**Verification**:
- Set a patient's gender to `'male'`.
- Call `update_patient(p_patient_id := ..., p_clear_gender := true)`.
- Verify `gender` is now NULL.
- Call `update_patient(p_patient_id := ..., p_gender := 'female')` — should set to female.

---

### Fix 16: Fix `update_patient` cannot clear fields — public wrapper

Included in Fix 15 above — the public wrapper `public.update_patient` must also accept and pass through the `p_clear_*` parameters.

---

## Priority 5 — Future Improvements (Document Only)

### Fix 17: Document single-tenant constraint

**Review Issue**: 2.4 — Single-tenant assumption in `build_staff_claims`.

**Action**: Add a comment block in the function and an architecture decision record.

**File**: Add to `specs/architecture-decisions.md` or equivalent:

```markdown
## ADR-001: Single Organization Per Staff Member

**Status**: Accepted  
**Context**: `build_staff_claims` determines org via "first org in DB". Staff members are implicitly bound to one org.  
**Decision**: Multi-org support is explicitly out of scope. If required in the future, the auth layer requires a full rewrite including: `organization_id` on `staff_members`, org-selection at login, per-org JWT claims.  
**Consequences**: All current code assumes 1 org per deployment. Multi-clinic-group scenarios need separate installations.
```

---

### Fix 18: Consider moving `staff_role` enum to a table

**Review Issue**: 5.3 — PostgreSQL enums hard to extend in transactions.

**Migration** (future): `YYYYMMDDHHMMSS_migrate_staff_role_to_table.sql`

**Approach**:
1. Create `public.staff_roles (id text PRIMARY KEY, display_name text, is_active boolean)`.
2. Seed with current enum values.
3. Add FK on `staff_members.role -> staff_roles.id`.
4. Migrate all enum references to text + FK.
5. Drop the enum.

**Note**: This is a significant breaking change — defer until a new role is actually needed.

---

### Fix 19: JWT branch_ids scaling

**Review Issue**: 5.4 — Comma-separated UUIDs in JWT won't scale.

**Future approach**:
- Store only `primary_branch_id` in JWT claims.
- Create a lightweight RPC `get_my_branch_assignments()` that clients call at startup.
- Cache in Flutter app state.

---

### Fix 20: Phone normalization to E.164

**Review Issue**: 5.5 — Digit-only normalization loses country context.

**Future approach**:
- Add `phone_country_code` column (e.g., `+20`, `+1`).
- Store phone in E.164 format: `+201005551234`.
- Update `normalize_patient_phone` to validate format.
- Frontend: phone input with country selector.

---

### Fix 21: Per-organization permission overrides

**Review Issue**: 5.6 — Global permission matrix shared across orgs.

**Future approach**:
- Add nullable `organization_id` to `roles_permissions`.
- Query: org-specific override first, fall back to global (NULL org_id).
- Adds complexity to `assert_permission` — defer until multi-org needed.

---

### Fix 22: Cursor-based pagination

**Review Issue**: 5.7 — OFFSET pagination causes duplicates/skips.

**Future approach**:
- Add parameter `p_cursor text` (last `full_name` + `id` composite).
- Change WHERE to `(full_name, id) > (cursor_name, cursor_id)`.
- Return `next_cursor` in response.
- Keep OFFSET mode as fallback for "jump to page N" UX.

---

### Fix 23: Soft-delete cascade

**Review Issue**: 5.8 — Orphaned records after org soft-delete.

**Future approach**:
- Add trigger on `organizations` UPDATE:
```sql
CREATE TRIGGER cascade_org_soft_delete
AFTER UPDATE OF is_deleted ON public.organizations
FOR EACH ROW
WHEN (NEW.is_deleted = true AND OLD.is_deleted = false)
EXECUTE FUNCTION auth_internal.cascade_soft_delete_org();
```
- Function sets `is_deleted = true` on all branches, patients, staff_assignments in that org.

---

## Priority 6 — Test Gaps

### Fix 24: Add concurrent access tests

**Review Issue**: 6.1

**File**: `backend/tests/patient_management_concurrent.sql`

**Approach**:
- Use `pg_advisory_xact_lock` and two separate sessions.
- Test: Two `create_patient` calls with same phone → one succeeds, one gets unique violation (after Fix 4).
- Cannot easily test within single-transaction pgTAP. Use a shell script that opens two `psql` connections.

---

### Fix 25: Add `dev_reset` safety test

**Review Issue**: 6.4

**File**: Add to `backend/tests/dev_reset_safety.sql`

```sql
-- Test: non-bootstrap user cannot call dev_reset
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"non-bootstrap-user-uuid",...}';
SELECT results_eq(
  $$SELECT (public.dev_reset_clinic_installation()->>'status')$$,
  $$VALUES ('error')$$,
  'Non-bootstrap user cannot reset'
);
```

---

### Fix 26: Add GoTrue ↔ custom claims integration test

**Review Issue**: 6.3

**File**: Extend `backend/tests/auth_flow_smoke.sh`

**Approach**:
- After login, decode the JWT and verify custom claims match expected structure.
- Change a permission, refresh token, verify claims updated.

---

## Priority 7 — Configuration Cleanup

### Fix 27: Document dual config files

**Review Issue**: 7.3

**Action**: Add a README section in `backend/`:

```markdown
## Configuration

- `backend/supabase/config.toml` — Used by `supabase` CLI commands (`supabase start`, `supabase db reset`)
- `backend/local/docker-compose.yml` + `backend/local/config.toml` — Used for raw Docker Compose deployments without Supabase CLI

Choose ONE deployment method. Do not mix.
```

---

## Implementation Order (Recommended Sprint Plan)

| Sprint | Fixes | Effort Estimate |
|--------|-------|-----------------|
| Sprint 1 (Critical) | Fix 1, 2, 3 | 4 hours |
| Sprint 2 (High) | Fix 4, 5, 6 | 3 hours |
| Sprint 3 (Performance) | Fix 7, 8 | 3 hours |
| Sprint 4 (Features) | Fix 9, 15 | 4 hours |
| Sprint 5 (Hardening) | Fix 10, 11, 12 | 4 hours |
| Sprint 6 (Cleanup) | Fix 13, 14, 27 | 1 hour |
| Sprint 7 (Tests) | Fix 24, 25, 26 | 3 hours |
| Backlog | Fix 17–23 | Future sprints |

**Total immediate effort**: ~22 hours across 7 sprints  
**Backlog (future)**: Fix 17–23 tracked as tech debt

---

## Migration File Summary

| Migration File | Fixes Covered |
|----------------|---------------|
| `20260524100000_fix_remove_plaintext_password_from_responses.sql` | Fix 1 |
| `20260524100100_fix_restrict_auth_internal_grants.sql` | Fix 2 |
| `20260524100200_fix_password_complexity_validation.sql` | Fix 3 |
| `20260524100300_fix_patient_phone_index.sql` | Fix 4 |
| `20260524100400_fix_dev_reset_environment_guard.sql` | Fix 5 |
| `20260524100500_fix_enum_migration_safety.sql` | Fix 6 |
| `20260524110000_fix_search_indexes.sql` | Fix 7 |
| `20260524110100_fix_search_patients_pagination.sql` | Fix 8 |
| `20260524110200_fix_patient_transfer_restore.sql` | Fix 9 |
| `20260524110300_fix_audit_log_retention.sql` | Fix 10 |
| `20260524110400_fix_bootstrap_credential_hardening.sql` | Fix 11 |
| `20260524120000_fix_patient_clearable_fields.sql` | Fix 15 |

---

## Notes

- All `CREATE OR REPLACE FUNCTION` calls must include the full function body (PostgreSQL doesn't support partial redefinition).
- Before writing each migration, query the current function signature from the database to ensure parameter types match exactly.
- Run `supabase db reset` after each migration group to verify the full migration chain still applies cleanly.
- Update the corresponding test files to cover the new/changed behavior.

---

# Second Review Cycle — Additional Fixes

**Date**: 2026-05-24 (cycle 2)  
**Source**: `backend/BACKEND_CODE_REVIEW.md` — Sections 9–12

---

## Priority 2 — High (Cycle 2)

### Fix 28: Fix `update_branch` destructive field erasure

**Review Issue**: 9.1 — `update_branch` sets `address`, `phone`, `maps_url` to NULL when omitted.

**Migration**: `20260524130000_fix_update_branch_preserve_fields.sql`

**Detailed Steps**:

1. Redefine `auth_internal.update_branch` with COALESCE-preserved optional fields:

```sql
CREATE OR REPLACE FUNCTION auth_internal.update_branch(
  p_branch_id uuid,
  p_name text,
  p_code text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_maps_url text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_old public.branches%ROWTYPE;
  v_new public.branches%ROWTYPE;
BEGIN
  PERFORM auth_internal.assert_permission('settings.manage_branches');
  v_org_id := public.jwt_organization_id();

  IF NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch name is required.');
  END IF;

  SELECT *
  INTO v_old
  FROM public.branches b
  WHERE b.id = p_branch_id
    AND b.organization_id = v_org_id
    AND b.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('BRANCH_NOT_FOUND', 'Branch was not found in your organization.');
  END IF;

  UPDATE public.branches b
  SET
    name = trim(p_name),
    code = NULLIF(trim(p_code), ''),
    address = COALESCE(NULLIF(trim(p_address), ''), b.address),
    phone = COALESCE(NULLIF(trim(p_phone), ''), b.phone),
    maps_url = COALESCE(NULLIF(trim(p_maps_url), ''), b.maps_url),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE b.id = p_branch_id
  RETURNING * INTO v_new;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(), v_org_id, 'branch.update', 'branches', p_branch_id,
    jsonb_build_object('name', v_old.name, 'code', v_old.code, 'address', v_old.address, 'phone', v_old.phone),
    jsonb_build_object('name', v_new.name, 'code', v_new.code, 'address', v_new.address, 'phone', v_new.phone)
  );

  RETURN public.rpc_success(jsonb_build_object('branch_id', p_branch_id));
EXCEPTION
  WHEN unique_violation THEN
    RETURN public.rpc_error('DUPLICATE_CODE', 'A branch with this code already exists in your organization.');
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage branches.');
    END IF;
    RAISE;
END;
$$;
```

**Note**: Same issue applies to `code` — if you want clearing support, use the sentinel pattern from Fix 15. For now, `code = NULLIF(trim(p_code), '')` preserves existing behavior (code can be explicitly cleared by passing empty string since there's no COALESCE).

**Verification**:
- Call `update_branch(branch_id, 'New Name')` without other params → `address`, `phone`, `maps_url` remain unchanged.
- Call `update_branch(branch_id, 'New Name', p_address := 'New Address')` → only address updates.

---

### Fix 29: Block bootstrap admin password reset by other staff

**Review Issue**: 10.2 — Any owner/administrator can reset the bootstrap admin's password.

**Migration**: `20260524130100_fix_bootstrap_admin_password_protection.sql`

**Detailed Steps**:

1. Redefine `auth_internal.admin_reset_staff_password` to add a bootstrap admin guard:

```sql
-- After finding v_target and before the cross-org check:
IF v_target.is_bootstrap_admin AND v_target.auth_user_id != auth.uid() THEN
  RETURN public.rpc_error(
    'FORBIDDEN',
    'The bootstrap administrator password can only be changed by the bootstrap admin themselves.'
  );
END IF;
```

2. The full function redefinition must include the complete function body (copy current, add the guard).

**Verification**:
- As an administrator, attempt to reset bootstrap admin's password → should fail with FORBIDDEN.
- As the bootstrap admin, reset own password → should succeed.

---

### Fix 30: Fix `set_branch_active` org fallback bypass

**Review Issue**: 10.1 — Null JWT org falls back to branch's org, bypassing org validation.

**Migration**: `20260524130200_fix_set_branch_active_org_guard.sql`

**Detailed Steps**:

1. Redefine `auth_internal.set_branch_active` — remove the fallback block and fail fast:

```sql
-- BEFORE (problematic):
v_org_id := public.jwt_organization_id();
IF v_org_id IS NULL THEN
  SELECT b.organization_id INTO v_org_id
  FROM public.branches b WHERE b.id = p_branch_id AND b.is_deleted = false;
END IF;

-- AFTER (safe):
v_org_id := public.jwt_organization_id();
IF v_org_id IS NULL THEN
  RETURN public.rpc_error('ORG_SETUP_INCOMPLETE', 'Organization context is required to manage branches.');
END IF;
```

**Verification**:
- Set JWT with null org_id → call `set_branch_active` → should fail with ORG_SETUP_INCOMPLETE.
- Normal staff with valid JWT → should work as before.

---

## Priority 3 — Medium (Cycle 2)

### Fix 31: Add last-owner guard to `set_staff_active` and `update_staff_member`

**Review Issue**: 9.4 — No protection against deactivating or demoting the last owner.

**Migration**: `20260524140000_fix_last_owner_guard.sql`

**Detailed Steps**:

1. Create a reusable helper:
```sql
CREATE OR REPLACE FUNCTION auth_internal.assert_not_last_owner(p_staff_member_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_target_role public.staff_role;
  v_other_owners int;
BEGIN
  SELECT sm.role INTO v_target_role
  FROM public.staff_members sm
  WHERE sm.id = p_staff_member_id AND sm.is_deleted = false;

  IF v_target_role = 'owner' THEN
    SELECT count(*) INTO v_other_owners
    FROM public.staff_members sm
    WHERE sm.role = 'owner'
      AND sm.is_active = true
      AND sm.is_deleted = false
      AND sm.id != p_staff_member_id;

    IF v_other_owners < 1 THEN
      RAISE EXCEPTION 'LAST_OWNER';
    END IF;
  END IF;
END;
$$;
```

2. In `set_staff_active`, before the UPDATE:
```sql
IF NOT p_is_active THEN
  BEGIN
    PERFORM auth_internal.assert_not_last_owner(p_staff_member_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'LAST_OWNER' THEN
        RETURN public.rpc_error('LAST_OWNER', 'Cannot deactivate the last active owner.');
      END IF;
      RAISE;
  END;
END IF;
```

3. In `update_staff_member`, when the role is being changed away from owner:
```sql
IF v_old_role = 'owner' AND p_role != 'owner' THEN
  BEGIN
    PERFORM auth_internal.assert_not_last_owner(p_staff_member_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'LAST_OWNER' THEN
        RETURN public.rpc_error('LAST_OWNER', 'Cannot demote the last active owner.');
      END IF;
      RAISE;
  END;
END IF;
```

**Verification**:
- Create org with 1 owner → deactivate → should fail with LAST_OWNER.
- Create 2 owners → deactivate one → should succeed.
- Demote sole owner to receptionist → should fail with LAST_OWNER.

---

### Fix 32: Restrict audit_log DML grants and add explicit deny policies

**Review Issues**: 10.3 + 11.2 — Broad DML grants and missing write-deny policies on audit_log.

**Migration**: `20260524140100_fix_audit_log_write_protection.sql`

**Detailed Steps**:

1. Revoke direct write privileges on `audit_log`:
```sql
REVOKE INSERT, UPDATE, DELETE ON public.audit_log FROM authenticated;
```

2. Add explicit deny policies for defense-in-depth:
```sql
CREATE POLICY audit_log_insert ON public.audit_log
  FOR INSERT TO authenticated WITH CHECK (false);

CREATE POLICY audit_log_update ON public.audit_log
  FOR UPDATE TO authenticated USING (false);

CREATE POLICY audit_log_delete ON public.audit_log
  FOR DELETE TO authenticated USING (false);
```

3. Audit log inserts from SECURITY DEFINER functions still work because they run as the function owner (`postgres`), which bypasses RLS.

**Verification**:
- As authenticated user: `INSERT INTO audit_log (...)` → should fail with policy violation.
- RPCs that write audit entries (e.g., `create_patient`) → should still succeed.

---

### Fix 33: Add `gender` and `marital_status` to `search_patients` response

**Review Issue**: 9.3 — Search results missing fields added in migration 19.

**Migration**: `20260524140200_fix_search_patients_response_fields.sql`

**Detailed Steps**:

1. Redefine `auth_internal.search_patients` with the additional columns in the SELECT and JSON output:

```sql
-- In the filtered CTE, add:
p.gender::text AS gender,
p.marital_status::text AS marital_status

-- In the jsonb_build_object output, add:
'gender', c.gender,
'marital_status', c.marital_status
```

2. The full function body must be rewritten (copy current + add fields).

**Verification**:
- Call `search_patients` → response items should include `gender` and `marital_status` fields.
- Patients without gender/marital_status should have `null` values in the response.

---

### Fix 34: Fix `search_path` on username functions

**Review Issue**: 9.2 — `normalize_username` and `assert_valid_username` missing `SET search_path`.

**Migration**: `20260524140300_fix_username_functions_search_path.sql`

**Detailed Steps**:

```sql
ALTER FUNCTION auth_internal.normalize_username(text) SET search_path = '';
ALTER FUNCTION auth_internal.assert_valid_username(text) SET search_path = '';
```

**Verification**:
- Run Supabase security advisor → no rule 0011 violations for these functions.
- `create_staff_account` with username validation still works.

---

### Fix 35: Add explicit write-deny policies on other write-sensitive tables

**Review Issue**: 10.3 extension — Strengthen the implicit RLS deny pattern.

**Migration**: Included in Fix 32 migration.

**Detailed Steps**:

For `audit_log`, `subscription_cache`, and any future append-only tables, add explicit deny policies. Already covered in Fix 32 for `audit_log`. For `subscription_cache`:

```sql
CREATE POLICY subscription_cache_insert ON public.subscription_cache
  FOR INSERT TO authenticated WITH CHECK (false);
CREATE POLICY subscription_cache_update ON public.subscription_cache
  FOR UPDATE TO authenticated USING (false);
CREATE POLICY subscription_cache_delete ON public.subscription_cache
  FOR DELETE TO authenticated USING (false);
```

---

### Fix 36: Add production guard for demo JWT secrets

**Review Issue**: 10.4 — `.env.example` contains well-known demo tokens.

**Implementation**: Configuration change (not SQL migration).

**Detailed Steps**:

1. Add prominent warnings to `backend/local/.env.example`:
```env
# ╔═══════════════════════════════════════════════════════════════╗
# ║  WARNING: These are PUBLIC demo keys for local dev ONLY.     ║
# ║  NEVER use these values in production. Generate unique keys. ║
# ╚═══════════════════════════════════════════════════════════════╝
```

2. Optionally, add a startup SQL check:
```sql
DO $$
BEGIN
  IF current_setting('app.environment', true) NOT IN ('development', 'local', 'test') THEN
    IF current_setting('app.jwt_secret', true) = 'your-super-secret-jwt-token-with-at-least-32-characters-long' THEN
      RAISE EXCEPTION 'INSECURE_CONFIG: Default JWT secret detected in non-development environment';
    END IF;
  END IF;
END;
$$;
```

---

## Priority 4 — Low (Cycle 2)

### Fix 37: Rename `audit_log.timestamp` to `created_at`

**Review Issue**: 9.5 — Column naming inconsistency.

**Migration**: `20260524150000_fix_audit_log_timestamp_column.sql`

**Detailed Steps**:

```sql
ALTER TABLE public.audit_log RENAME COLUMN "timestamp" TO created_at;

DROP INDEX IF EXISTS audit_log_timestamp_idx;
CREATE INDEX audit_log_created_at_idx ON public.audit_log (created_at DESC);
```

**Impact**: Any code referencing `audit_log.timestamp` must be updated to `created_at`. Since audit_log is only written by RPCs (not queried directly by the client), the impact is limited to internal functions and the Fix 10 cleanup function.

**Verification**:
- All migrations apply cleanly after this change.
- `SELECT created_at FROM audit_log LIMIT 1` returns a timestamp.

---

### Fix 38: Add idempotency check to `set_branch_active`

**Review Issue**: 9.6 — Redundant audit entries when branch state doesn't change.

**Migration**: `20260524150100_fix_set_branch_active_idempotent.sql`

**Detailed Steps**:

1. In `auth_internal.set_branch_active`, after confirming the branch exists, add:
```sql
-- Fetch current state
SELECT b.is_active INTO v_current_active
FROM public.branches b
WHERE b.id = p_branch_id;

-- No-op if already in target state
IF v_current_active = p_is_active THEN
  RETURN public.rpc_success(jsonb_build_object('branch_id', p_branch_id, 'is_active', p_is_active));
END IF;
```

**Verification**:
- Activate an already-active branch → returns success, no audit entry written.
- Deactivate an active branch → audit entry written normally.

---

### Fix 39: Expand `staff_branch_assignments` RLS for admin visibility

**Review Issue**: 11.3 — Admins can't see all branch assignments in their org.

**Migration**: `20260524150200_fix_staff_branch_assignments_admin_rls.sql`

**Detailed Steps**:

```sql
DROP POLICY IF EXISTS staff_branch_assignments_select ON public.staff_branch_assignments;

CREATE POLICY staff_branch_assignments_select ON public.staff_branch_assignments
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND (
      branch_id = ANY (public.jwt_branch_ids())
      OR (
        public.jwt_setup_required()
        AND staff_member_id = public.jwt_staff_member_id()
      )
      OR (
        EXISTS (
          SELECT 1 FROM public.current_staff_member_row() sm
          WHERE sm.role IN ('owner', 'administrator')
        )
        AND EXISTS (
          SELECT 1 FROM public.branches b
          WHERE b.id = staff_branch_assignments.branch_id
            AND b.organization_id = public.jwt_organization_id()
            AND b.is_deleted = false
        )
      )
    )
  );
```

**Verification**:
- Owner at Branch A can see staff assignments at Branch B (same org) → should succeed.
- Receptionist at Branch A cannot see Branch B assignments → should fail.

---

## Updated Implementation Order (Combined Sprints)

| Sprint | Fixes | Effort Estimate |
|--------|-------|-----------------|
| Sprint 1 (Critical) | Fix 1, 2, 3 | 4 hours |
| Sprint 2 (High) | Fix 4, 5, 6, **28, 29, 30** | 5 hours |
| Sprint 3 (Performance) | Fix 7, 8 | 3 hours |
| Sprint 4 (Features) | Fix 9, 15, **33** | 5 hours |
| Sprint 5 (Hardening) | Fix 10, 11, 12, **31, 32, 34, 36** | 5 hours |
| Sprint 6 (Cleanup) | Fix 13, 14, 27, **37, 38, 39** | 2 hours |
| Sprint 7 (Tests) | Fix 24, 25, 26 | 3 hours |
| Backlog | Fix 17–23, **35** | Future sprints |

**Updated total immediate effort**: ~27 hours across 7 sprints  
**New fixes added**: 12 (Fix 28–39)

---

## Cycle 2 Migration File Summary

| Migration File | Fixes Covered |
|----------------|---------------|
| `20260524130000_fix_update_branch_preserve_fields.sql` | Fix 28 |
| `20260524130100_fix_bootstrap_admin_password_protection.sql` | Fix 29 |
| `20260524130200_fix_set_branch_active_org_guard.sql` | Fix 30 |
| `20260524140000_fix_last_owner_guard.sql` | Fix 31 |
| `20260524140100_fix_audit_log_write_protection.sql` | Fix 32, 35 |
| `20260524140200_fix_search_patients_response_fields.sql` | Fix 33 |
| `20260524140300_fix_username_functions_search_path.sql` | Fix 34 |
| `20260524150000_fix_audit_log_timestamp_column.sql` | Fix 37 |
| `20260524150100_fix_set_branch_active_idempotent.sql` | Fix 38 |
| `20260524150200_fix_staff_branch_assignments_admin_rls.sql` | Fix 39 |
