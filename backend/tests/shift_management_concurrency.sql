-- V1-7 shift management US4 concurrent update_shift stale rejection.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/shift_management_concurrency.sql

BEGIN;

CREATE TEMP TABLE shift_concurrency_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.record_shift_concurrency_result(p_name text, p_passed boolean, p_detail text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO shift_concurrency_results VALUES (p_name, p_passed, p_detail);
END;
$$;

DO $$
DECLARE
  v_org_id uuid := 'c3800000-0000-4000-8000-0000000000a1';
  v_branch_id uuid := 'd3800000-0000-4000-8000-0000000000a1';
  v_user_owner uuid := 'e3800000-0000-4000-8000-0000000000a1';
  v_user_doctor uuid := 'e3800000-0000-4000-8000-0000000000a2';
  v_staff_owner uuid := 'f3800000-0000-4000-8000-0000000000a1';
  v_staff_doctor uuid := 'f3800000-0000-4000-8000-0000000000a2';
  v_shift_id uuid;
  v_updated_at timestamptz;
  v_stale_updated_at timestamptz;
  v_future date;
  v_err text;
  v_preserved boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  PERFORM auth_internal.delete_clinic_operational_dependents();
  DELETE FROM public.audit_log;

  DELETE FROM public.staff_branch_assignments
  WHERE staff_member_id IN (v_staff_owner, v_staff_doctor);
  DELETE FROM public.staff_members WHERE id IN (v_staff_owner, v_staff_doctor);
  DELETE FROM public.branches WHERE id = v_branch_id;
  DELETE FROM public.organizations WHERE id = v_org_id;
  DELETE FROM auth.users WHERE id IN (v_user_owner, v_user_doctor);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (
      v_user_owner,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'conc-shift-owner',
      extensions.crypt('pw-owner', extensions.gen_salt('bf')),
      now(),
      now(),
      now()
    ),
    (
      v_user_doctor,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'conc-shift-doctor',
      extensions.crypt('pw-doc', extensions.gen_salt('bf')),
      now(),
      now(),
      now()
    )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, timezone, created_by, updated_by)
  VALUES (v_org_id, 'Concurrency Shift Org', 'UTC', v_user_owner, v_user_owner);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES (v_branch_id, v_org_id, 'Concurrency Branch', 'CONC', v_user_owner, v_user_owner);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_active, created_by, updated_by)
  VALUES
    (v_staff_owner, v_user_owner, 'Owner Conc', 'administrator', true, v_user_owner, v_user_owner),
    (v_staff_doctor, v_user_doctor, 'Dr Conc', 'doctor', true, v_user_owner, v_user_owner);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_staff_owner, v_branch_id, true, v_user_owner, v_user_owner),
    (v_staff_doctor, v_branch_id, true, v_user_owner, v_user_owner);

  v_future := auth_internal.get_org_today(v_org_id) + 4;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_owner::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_staff_owner::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_shift_id := public.create_shift(
    v_branch_id,
    v_future,
    time '09:00',
    time '17:00',
    'Concurrency target',
    ARRAY[v_staff_doctor]::uuid[]
  );

  PERFORM set_config('role', 'postgres', true);
  SELECT s.updated_at INTO v_updated_at FROM public.shifts s WHERE s.id = v_shift_id;
  v_stale_updated_at := v_updated_at - interval '1 second';
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM public.update_shift(
      v_shift_id,
      v_stale_updated_at,
      v_future,
      time '09:00',
      time '18:00',
      'Should fail stale'
    );
    PERFORM pg_temp.record_shift_concurrency_result('update_shift_rejects_stale_expected_updated_at', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      v_err := SQLERRM;
      PERFORM pg_temp.record_shift_concurrency_result(
        'update_shift_rejects_stale_expected_updated_at',
        SQLERRM = 'stale_shift',
        v_err
      );
  END;

  PERFORM set_config('role', 'postgres', true);
  SELECT s.end_time = time '17:00' AND s.notes = 'Concurrency target'
  INTO v_preserved
  FROM public.shifts s
  WHERE s.id = v_shift_id;

  PERFORM pg_temp.record_shift_concurrency_result(
    'update_shift_stale_leaves_prior_values',
    v_preserved IS TRUE,
    'unchanged=' || COALESCE(v_preserved::text, '<null>')
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*)::int INTO v_failures
  FROM shift_concurrency_results
  WHERE NOT passed;

  IF v_failures > 0 THEN
    RAISE EXCEPTION 'shift_management_concurrency.sql: % failing assertion(s). Run: SELECT * FROM shift_concurrency_results WHERE NOT passed ORDER BY test_name',
      v_failures;
  END IF;
END;
$$;

SELECT test_name, passed, detail FROM shift_concurrency_results ORDER BY test_name;

ROLLBACK;
