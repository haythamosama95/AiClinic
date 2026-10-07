-- Stage 02 catalog SQL: S02-024 … S02-026 (availability after installation-key drop).
-- Revoke / rotate / enroll RPC cases (S02-015 … S02-023) and the installation-key
-- handoff case (S02-027) were removed when installation_keys custody was dropped.

BEGIN;

\ir harness.sql

-- Post-drop override: installation_keys is absent after issuer-key custody migration.
CREATE OR REPLACE FUNCTION pg_temp.reset_keystore()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM ai_internal.ai_token_issuance;
  IF to_regclass('ai_internal.installation_keys') IS NOT NULL THEN
    DELETE FROM ai_internal.installation_keys;
  END IF;
  UPDATE ai_internal.app_settings
  SET
    value_json = '{"enrolled": false, "platform_base_url": null}'::jsonb,
    is_deleted = false,
    deleted_at = NULL,
    deleted_by = NULL
  WHERE key = 'ai.availability';
END;
$$;

SELECT pg_temp.catalog_common_setup();

INSERT INTO ai_internal.membership (user_id, organization_id, role)
SELECT sm.auth_user_id, org.value, sm.role
FROM public.staff_members sm
JOIN catalog_setup org ON org.key = 'org'
JOIN catalog_setup actor ON actor.key IN ('boot_auth', 'admin_auth', 'doctor_auth')
  AND sm.auth_user_id = actor.value
WHERE sm.is_deleted = false
ON CONFLICT (user_id, organization_id) DO NOTHING;

-- S02-024 — Availability flag flip after Stage 3 platform enrollment
-- Stage 3 Worker enrollment is simulated: BOOT calls set_ai_availability only.
-- Catalog: get_ai_availability is readable by every authenticated role
-- (doctor, receptionist, administrator). Common setup has ADMIN+DOCTOR only,
-- so ADMIN provisions a receptionist via create_staff_account for that arm.
DO $$
DECLARE
  v_boot_auth uuid;
  v_doctor_auth uuid;
  v_admin_auth uuid;
  v_admin uuid;
  v_org uuid;
  v_branch uuid;
  v_rec_auth uuid;
  v_rec_role public.staff_role;
  v_rec_create public.rpc_result;
  v_created_before uuid;
  v_created_after uuid;
  v_updated_after uuid;
  v_value jsonb;
  v_set public.rpc_result;
  v_get_doctor jsonb;
  v_get_admin jsonb;
  v_get_rec jsonb;
  v_expected jsonb := '{"enrolled": true, "platform_base_url": "http://127.0.0.1:8787"}'::jsonb;
  v_ok boolean := false;
  v_detail text;
  v_set_err text;
  v_set_state text;
  v_get_doctor_err text;
  v_get_doctor_state text;
  v_get_admin_err text;
  v_get_admin_state text;
  v_get_rec_err text;
  v_get_rec_state text;
  v_rec_create_err text;
  v_rec_create_state text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  SELECT value INTO STRICT v_doctor_auth FROM catalog_setup WHERE key = 'doctor_auth';
  SELECT value INTO STRICT v_admin_auth FROM catalog_setup WHERE key = 'admin_auth';
  SELECT value INTO STRICT v_admin FROM catalog_setup WHERE key = 'admin';
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';

  SELECT s.created_by INTO v_created_before
  FROM ai_internal.app_settings s
  WHERE s.key = 'ai.availability';

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  BEGIN
    v_set := public.set_ai_availability(true, 'http://127.0.0.1:8787'::text);
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        v_set_err = MESSAGE_TEXT,
        v_set_state = RETURNED_SQLSTATE;
      v_set := NULL;
  END;

  -- create_staff_account reads jwt_organization_id(); harness JWT is sub+role.
  PERFORM pg_temp.reset_postgres();
  PERFORM pg_temp.set_authenticated_session(v_admin_auth);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_auth::text,
      'role', 'authenticated',
      'organization_id', v_org::text,
      'staff_member_id', v_admin::text
    )::text,
    true
  );
  BEGIN
    v_rec_create := public.create_staff_account(
      's02_reception',
      'Layla#Desk2026!',
      'Layla Reception',
      'receptionist',
      ARRAY[v_branch]::uuid[],
      v_branch,
      NULL
    );
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        v_rec_create_err = MESSAGE_TEXT,
        v_rec_create_state = RETURNED_SQLSTATE;
      v_rec_create := NULL;
  END;

  PERFORM pg_temp.reset_postgres();
  IF v_rec_create.success IS TRUE THEN
    SELECT sm.auth_user_id, sm.role
    INTO STRICT v_rec_auth, v_rec_role
    FROM public.staff_members sm
    WHERE sm.id = (v_rec_create.data ->> 'staff_member_id')::uuid;
  END IF;

  PERFORM pg_temp.reset_postgres();
  PERFORM pg_temp.set_authenticated_session(v_doctor_auth);
  BEGIN
    v_get_doctor := public.get_ai_availability();
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        v_get_doctor_err = MESSAGE_TEXT,
        v_get_doctor_state = RETURNED_SQLSTATE;
      v_get_doctor := NULL;
  END;

  PERFORM pg_temp.reset_postgres();
  PERFORM pg_temp.set_authenticated_session(v_admin_auth);
  BEGIN
    v_get_admin := public.get_ai_availability();
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        v_get_admin_err = MESSAGE_TEXT,
        v_get_admin_state = RETURNED_SQLSTATE;
      v_get_admin := NULL;
  END;

  PERFORM pg_temp.reset_postgres();
  IF v_rec_auth IS NOT NULL THEN
    PERFORM pg_temp.set_authenticated_session(v_rec_auth);
    BEGIN
      v_get_rec := public.get_ai_availability();
    EXCEPTION
      WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
          v_get_rec_err = MESSAGE_TEXT,
          v_get_rec_state = RETURNED_SQLSTATE;
        v_get_rec := NULL;
    END;
  END IF;

  PERFORM pg_temp.reset_postgres();
  SELECT s.value_json, s.created_by, s.updated_by
  INTO STRICT v_value, v_created_after, v_updated_after
  FROM ai_internal.app_settings s
  WHERE s.key = 'ai.availability'
    AND s.is_deleted = false;

  v_ok := (v_set.success IS TRUE)
    AND v_set.error_code IS NULL
    AND v_set.error_message IS NULL
    AND v_set.data IS NOT DISTINCT FROM v_expected
    AND v_get_doctor IS NOT DISTINCT FROM v_expected
    AND v_get_admin IS NOT DISTINCT FROM v_expected
    AND v_get_rec IS NOT DISTINCT FROM v_expected
    AND v_rec_role IS NOT DISTINCT FROM 'receptionist'::public.staff_role
    AND v_value IS NOT DISTINCT FROM v_expected
    AND v_updated_after IS NOT DISTINCT FROM v_boot_auth
    AND v_created_after IS NOT DISTINCT FROM v_boot_auth;

  v_detail := 'set_success=' || COALESCE(v_set.success::text, '<null>')
    || ' set_data=' || COALESCE(v_set.data::text, '<null>')
    || ' get_doctor=' || COALESCE(v_get_doctor::text, '<null>')
    || ' get_admin=' || COALESCE(v_get_admin::text, '<null>')
    || ' get_rec=' || COALESCE(v_get_rec::text, '<null>')
    || ' rec_role=' || COALESCE(v_rec_role::text, '<null>')
    || ' rec_create=' || COALESCE(v_rec_create.error_code, 'ok')
    || ' rec_create_err=' || COALESCE(v_rec_create_state, '<none>')
    || ':' || COALESCE(v_rec_create_err, '')
    || ' updated_by=' || COALESCE(v_updated_after::text, '<null>')
    || ' created_by=' || COALESCE(v_created_after::text, '<null>')
    || ' created_before=' || COALESCE(v_created_before::text, '<null>')
    || ' set_err=' || COALESCE(v_set_state, '<none>')
    || ':' || COALESCE(v_set_err, '')
    || ' get_doctor_err=' || COALESCE(v_get_doctor_state, '<none>')
    || ':' || COALESCE(v_get_doctor_err, '')
    || ' get_admin_err=' || COALESCE(v_get_admin_state, '<none>')
    || ':' || COALESCE(v_get_admin_err, '')
    || ' get_rec_err=' || COALESCE(v_get_rec_state, '<none>')
    || ':' || COALESCE(v_get_rec_err, '');

  PERFORM pg_temp.record(
    'S02-024 — Availability flag flip after Stage 3 platform enrollment',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-025 — Availability falls back to the COALESCE default when the row is missing/soft-deleted
DO $$
DECLARE
  v_admin_auth uuid;
  v_got jsonb;
  v_expected jsonb := '{"enrolled": false, "platform_base_url": null}'::jsonb;
  v_ok boolean := false;
  v_detail text;
  v_call_err text;
  v_call_state text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_admin_auth FROM catalog_setup WHERE key = 'admin_auth';

  -- [SEED] privileged soft-delete (no RPC mutates this row this way)
  UPDATE ai_internal.app_settings
  SET is_deleted = true,
      deleted_at = now()
  WHERE key = 'ai.availability';

  PERFORM pg_temp.set_authenticated_session(v_admin_auth);
  BEGIN
    v_got := public.get_ai_availability();
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        v_call_err = MESSAGE_TEXT,
        v_call_state = RETURNED_SQLSTATE;
      v_got := NULL;
  END;

  PERFORM pg_temp.reset_postgres();
  v_ok := v_got = v_expected AND v_got IS NOT NULL;

  v_detail := 'got=' || COALESCE(v_got::text, '<null>')
    || ' call_err=' || COALESCE(v_call_state, '<none>')
    || ':' || COALESCE(v_call_err, '');

  UPDATE ai_internal.app_settings
  SET is_deleted = false,
      deleted_at = NULL,
      deleted_by = NULL
  WHERE key = 'ai.availability';

  PERFORM pg_temp.record(
    'S02-025 — Availability falls back to the COALESCE default when the row is missing/soft-deleted',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-026 — Administrator holds the ai.visit_summary grant; doctor does not
DO $$
DECLARE
  v_org uuid;
  v_admin_auth uuid;
  v_admin_access boolean;
  v_admin_summary boolean;
  v_doctor_access boolean;
  v_granted_summary_others int;
  v_false_visible int;
  v_ok boolean := false;
  v_detail text;
  v_call_err text;
  v_call_state text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT value INTO STRICT v_admin_auth FROM catalog_setup WHERE key = 'admin_auth';
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';

  -- As ADMIN: harness JWT uses role=authenticated (PostgREST session role).
  -- organization_id is the legacy claim current_org_id() still accepts, so the
  -- per-tenant matrix is the clinic's. staff_role stays for jwt_staff_role().
  PERFORM pg_temp.set_authenticated_session(v_admin_auth);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_auth::text,
      'role', 'authenticated',
      'staff_role', 'administrator',
      'organization_id', v_org::text
    )::text,
    true
  );
  BEGIN
    SELECT EXISTS (
      SELECT 1
      FROM public.roles_permissions rp
      WHERE rp.is_deleted = false
        AND rp.role = 'administrator'::public.staff_role
        AND rp.permission_key = 'ai.access'
        AND rp.is_granted = true
    ) INTO v_admin_access;

    SELECT EXISTS (
      SELECT 1
      FROM public.roles_permissions rp
      WHERE rp.is_deleted = false
        AND rp.role = 'administrator'::public.staff_role
        AND rp.permission_key = 'ai.visit_summary'
        AND rp.is_granted = true
    ) INTO v_admin_summary;

    SELECT EXISTS (
      SELECT 1
      FROM public.roles_permissions rp
      WHERE rp.is_deleted = false
        AND rp.role = 'doctor'::public.staff_role
        AND rp.permission_key = 'ai.access'
        AND rp.is_granted = true
    ) INTO v_doctor_access;

    SELECT count(*)::int INTO v_granted_summary_others
    FROM public.roles_permissions rp
    WHERE rp.permission_key = 'ai.visit_summary'
      AND rp.is_deleted = false
      AND rp.is_granted = true
      AND rp.role IN (
        'doctor'::public.staff_role,
        'receptionist'::public.staff_role,
        'lab_staff'::public.staff_role
      );

    SELECT count(*)::int INTO v_false_visible
    FROM public.roles_permissions rp
    WHERE rp.permission_key LIKE 'ai.%'
      AND rp.is_deleted = false
      AND rp.is_granted = false;
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        v_call_err = MESSAGE_TEXT,
        v_call_state = RETURNED_SQLSTATE;
  END;

  PERFORM pg_temp.reset_postgres();

  v_ok := v_admin_access IS TRUE
    AND v_admin_summary IS TRUE
    AND v_doctor_access IS TRUE
    AND v_granted_summary_others = 0
    AND v_false_visible > 0;

  v_detail := 'admin_access=' || COALESCE(v_admin_access::text, '<null>')
    || ' admin_visit_summary=' || COALESCE(v_admin_summary::text, '<null>')
    || ' doctor_access=' || COALESCE(v_doctor_access::text, '<null>')
    || ' granted_summary_others=' || COALESCE(v_granted_summary_others::text, '<null>')
    || ' false_rows_visible_to_admin=' || COALESCE(v_false_visible::text, '<null>')
    || ' call_err=' || COALESCE(v_call_state, '<none>')
    || ':' || COALESCE(v_call_err, '');

  PERFORM pg_temp.record(
    'S02-026 — Administrator holds the ai.visit_summary grant; doctor does not',
    v_ok,
    v_detail
  );
END;
$$;

SELECT test_name, passed, detail FROM catalog_results ORDER BY test_name;
SELECT pg_temp.fail_if_any();
ROLLBACK;
