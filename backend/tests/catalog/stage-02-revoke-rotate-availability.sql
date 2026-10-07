-- Stage 02 catalog SQL: S02-024 … S02-026 (availability RPCs dropped in P5.2).
-- Revoke / rotate / enroll RPC cases (S02-015 … S02-023) and the installation-key
-- handoff case (S02-027) were removed when installation_keys custody was dropped.

BEGIN;

\ir harness.sql

SELECT pg_temp.catalog_common_setup();

INSERT INTO ai_internal.membership (user_id, organization_id, role)
SELECT sm.auth_user_id, org.value, sm.role
FROM public.staff_members sm
JOIN catalog_setup org ON org.key = 'org'
JOIN catalog_setup actor ON actor.key IN ('boot_auth', 'admin_auth', 'doctor_auth')
  AND sm.auth_user_id = actor.value
WHERE sm.is_deleted = false
ON CONFLICT (user_id, organization_id) DO NOTHING;

-- S02-024 — public availability RPCs are absent after P5.2 availability drop
DO $$
DECLARE
  v_set_absent boolean;
  v_get_absent boolean;
  v_ok boolean := false;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();

  v_set_absent := to_regprocedure('public.set_ai_availability(boolean, text)') IS NULL;
  v_get_absent := to_regprocedure('public.get_ai_availability()') IS NULL;

  v_ok := v_set_absent AND v_get_absent;

  v_detail := 'public_set_ai_availability_absent=' || v_set_absent::text
    || ' public_get_ai_availability_absent=' || v_get_absent::text;

  PERFORM pg_temp.record(
    'S02-024 — public availability RPCs are absent after P5.2 availability drop',
    v_ok,
    v_detail
  );
END;
$$;

-- S02-025 — auth_internal availability RPCs are absent after P5.2 availability drop
DO $$
DECLARE
  v_set_absent boolean;
  v_get_absent boolean;
  v_ok boolean := false;
  v_detail text;
BEGIN
  PERFORM pg_temp.reset_postgres();

  v_set_absent := to_regprocedure('auth_internal.set_ai_availability(boolean, text)') IS NULL;
  v_get_absent := to_regprocedure('auth_internal.get_ai_availability()') IS NULL;

  v_ok := v_set_absent AND v_get_absent;

  v_detail := 'auth_internal_set_ai_availability_absent=' || v_set_absent::text
    || ' auth_internal_get_ai_availability_absent=' || v_get_absent::text;

  PERFORM pg_temp.record(
    'S02-025 — auth_internal availability RPCs are absent after P5.2 availability drop',
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
