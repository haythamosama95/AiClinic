-- V1-3 cross-organization denial for patient reads and RPCs.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/patient_management_rls.sql

BEGIN;

CREATE TEMP TABLE patient_rls_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_org_a uuid := 'c2000000-0000-4000-8000-0000000000a1';
  v_org_b uuid := 'c2000000-0000-4000-8000-0000000000b2';
  v_branch_a uuid := 'd2000000-0000-4000-8000-0000000000a1';
  v_branch_b uuid := 'd2000000-0000-4000-8000-0000000000b2';
  v_user_a uuid := 'e2000000-0000-4000-8000-0000000000a1';
  v_user_b uuid := 'e2000000-0000-4000-8000-0000000000b2';
  v_staff_a uuid := 'f2000000-0000-4000-8000-0000000000a1';
  v_staff_b uuid := 'f2000000-0000-4000-8000-0000000000b2';
  v_patient_a uuid := 'a2000000-0000-4000-8000-0000000000a1';
  v_patient_b uuid := 'a2000000-0000-4000-8000-0000000000b2';
  v_result public.rpc_result;
  v_visible_count int;
  v_dml_failed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  PERFORM auth_internal.delete_clinic_operational_dependents();
  DELETE FROM public.staff_branch_assignments
  WHERE staff_member_id IN (v_staff_a, v_staff_b);
  DELETE FROM public.staff_members
  WHERE id IN (v_staff_a, v_staff_b);
  DELETE FROM public.branches WHERE id IN (v_branch_a, v_branch_b);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM auth.users WHERE id IN (v_user_a, v_user_b);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_user_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-pat-a',
     extensions.crypt('pw-a', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-pat-b',
     extensions.crypt('pw-b', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'RLS Patient Org A', v_user_a, v_user_a),
    (v_org_b, 'RLS Patient Org B', v_user_b, v_user_b);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_a, 'Branch A', 'PA', v_user_a, v_user_a),
    (v_branch_b, v_org_b, 'Branch B', 'PB', v_user_b, v_user_b);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_staff_a, v_user_a, 'Owner A', 'owner', v_user_a, v_user_a),
    (v_staff_b, v_user_b, 'Owner B', 'owner', v_user_b, v_user_b);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_staff_a, v_branch_a, true, v_user_a, v_user_a),
    (v_staff_b, v_branch_b, true, v_user_b, v_user_b);

  INSERT INTO public.patients (
    id, branch_id, organization_id, full_name, phone, created_by, updated_by
  )
  VALUES
    (v_patient_a, v_branch_a, v_org_a, 'Org A Patient', '201111111111', v_user_a, v_user_a),
    (v_patient_b, v_branch_b, v_org_b, 'Org B Patient', '201234567890', v_user_b, v_user_b);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_a::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_a::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  -- Direct SELECT under RLS must not expose org B patient.
  SELECT count(*)::int
  INTO v_visible_count
  FROM public.patients p
  WHERE p.id = v_patient_b;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_rls_results VALUES (
    'cross_org_direct_select_hidden',
    v_visible_count = 0,
    'count=' || v_visible_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_patient(v_patient_b);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_rls_results VALUES (
    'cross_org_get_patient_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_patient(
    v_patient_b,
    'Hijacked',
    now(),
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    false
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_rls_results VALUES (
    'cross_org_update_patient_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.archive_patient(v_patient_b);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_rls_results VALUES (
    'cross_org_archive_patient_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.search_patients(NULL, 'organization', NULL, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_rls_results VALUES (
    'search_patients_org_scope_excludes_other_org',
    v_result.success
      AND NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(COALESCE(v_result.data -> 'items', '[]'::jsonb)) item
        WHERE (item ->> 'id')::uuid = v_patient_b
      ),
    COALESCE(v_result.error_code, 'items=' || jsonb_array_length(COALESCE(v_result.data -> 'items', '[]'::jsonb))::text)
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Direct INSERT blocked by RLS.
  v_dml_failed := false;
  BEGIN
    INSERT INTO public.patients (
      id, branch_id, organization_id, full_name, created_by, updated_by
    )
    VALUES (
      'a2000000-0000-4000-8000-000000000099',
      v_branch_a,
      v_org_a,
      'Direct Insert Attempt',
      v_user_a,
      v_user_a
    );
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    v_dml_failed := true;
  END;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_rls_results VALUES (
    'direct_insert_denied',
    v_dml_failed,
    CASE WHEN v_dml_failed THEN 'insert blocked' ELSE 'insert succeeded unexpectedly' END
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Direct UPDATE blocked by RLS (no rows match policy; name must remain unchanged).
  UPDATE public.patients
  SET full_name = 'Direct Update Attempt'
  WHERE id = v_patient_a;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_rls_results VALUES (
    'direct_update_denied',
    (SELECT full_name FROM public.patients p WHERE p.id = v_patient_a) = 'Org A Patient',
    'name=' || (SELECT full_name FROM public.patients p WHERE p.id = v_patient_a)
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Direct DELETE blocked by RLS (row must still exist).
  DELETE FROM public.patients WHERE id = v_patient_a;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_rls_results VALUES (
    'direct_delete_denied',
    EXISTS (SELECT 1 FROM public.patients p WHERE p.id = v_patient_a),
    'exists=' || EXISTS (SELECT 1 FROM public.patients p WHERE p.id = v_patient_a)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Tampered organization_id in JWT must not expose org A patient.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_a::text,
      'role', 'authenticated',
      'organization_id', v_org_b::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_a::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.get_patient(v_patient_a);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_rls_results VALUES (
    'tampered_org_jwt_get_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.search_patients(NULL, 'organization', NULL, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_rls_results VALUES (
    'tampered_org_jwt_search_empty',
    v_result.success
      AND NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(COALESCE(v_result.data -> 'items', '[]'::jsonb)) item
        WHERE (item ->> 'id')::uuid = v_patient_a
      ),
    'items=' || jsonb_array_length(COALESCE(v_result.data -> 'items', '[]'::jsonb))::text
  );
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  SELECT count(*)::int
  INTO v_failed
  FROM patient_rls_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM patient_rls_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'patient_management_rls: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
