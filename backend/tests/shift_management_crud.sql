-- V1-7 shift management create_shift RPC verification (US1).
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/shift_management_crud.sql

BEGIN;

CREATE TEMP TABLE shift_crud_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.record_shift_crud_result(p_name text, p_passed boolean, p_detail text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO shift_crud_results VALUES (p_name, p_passed, p_detail);
END;
$$;

DO $$
DECLARE
  v_org_id uuid := 'c2800000-0000-4000-8000-0000000000a1';
  v_branch_id uuid := 'd2800000-0000-4000-8000-0000000000a1';
  v_user_owner uuid := 'e2800000-0000-4000-8000-0000000000a1';
  v_user_doctor uuid := 'e2800000-0000-4000-8000-0000000000a2';
  v_user_inactive uuid := 'e2800000-0000-4000-8000-0000000000a3';
  v_user_unassigned uuid := 'e2800000-0000-4000-8000-0000000000a4';
  v_staff_owner uuid := 'f2800000-0000-4000-8000-0000000000a1';
  v_staff_doctor uuid := 'f2800000-0000-4000-8000-0000000000a2';
  v_staff_inactive uuid := 'f2800000-0000-4000-8000-0000000000a3';
  v_staff_unassigned uuid := 'f2800000-0000-4000-8000-0000000000a4';
  v_shift_incomplete uuid;
  v_shift_active uuid;
  v_shift_adjacent uuid;
  v_shift_past uuid;
  v_shift_out_of_range uuid;
  v_org_today date;
  v_future date;
  v_past date;
  v_assignee_count int;
  v_status text;
  v_err text;
  v_overlap_detail text;
  v_audit_count int;
  v_list_result jsonb;
  v_detail_result jsonb;
  v_list_count int;
  v_is_unassigned boolean;
  v_is_read_only boolean;
  v_is_past boolean;
  v_modify_result jsonb;
  v_shift_updated_at timestamptz;
  v_shift_assignment_test uuid;
  v_shift_overlap_target uuid;
  v_shift_cancelled uuid;
  v_add_audit_count int;
  v_remove_audit_count int;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  PERFORM auth_internal.delete_clinic_operational_dependents();
  DELETE FROM public.audit_log;

  DELETE FROM public.staff_branch_assignments
  WHERE staff_member_id IN (v_staff_owner, v_staff_doctor, v_staff_inactive, v_staff_unassigned);
  DELETE FROM public.staff_members
  WHERE id IN (v_staff_owner, v_staff_doctor, v_staff_inactive, v_staff_unassigned);
  DELETE FROM public.branches WHERE id = v_branch_id;
  DELETE FROM public.organizations WHERE id = v_org_id;
  DELETE FROM auth.users
  WHERE id IN (v_user_owner, v_user_doctor, v_user_inactive, v_user_unassigned);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_user_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'crud-shift-owner',
     extensions.crypt('pw-owner', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_doctor, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'crud-shift-doctor',
     extensions.crypt('pw-doc', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_inactive, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'crud-shift-inactive',
     extensions.crypt('pw-inact', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_unassigned, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'crud-shift-unassigned',
     extensions.crypt('pw-unas', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, timezone, created_by, updated_by)
  VALUES (v_org_id, 'CRUD Shift Org', 'UTC', v_user_owner, v_user_owner);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by, working_schedule)
  VALUES (
    v_branch_id,
    v_org_id,
    'CRUD Branch',
    'CRUD',
    v_user_owner,
    v_user_owner,
    jsonb_build_object(
      'days',
      jsonb_build_array(
        jsonb_build_object('day', 'monday', 'is_working_day', true, 'open_time', '08:00', 'close_time', '18:00'),
        jsonb_build_object('day', 'tuesday', 'is_working_day', true, 'open_time', '08:00', 'close_time', '18:00'),
        jsonb_build_object('day', 'wednesday', 'is_working_day', true, 'open_time', '08:00', 'close_time', '18:00'),
        jsonb_build_object('day', 'thursday', 'is_working_day', true, 'open_time', '08:00', 'close_time', '18:00'),
        jsonb_build_object('day', 'friday', 'is_working_day', true, 'open_time', '08:00', 'close_time', '18:00'),
        jsonb_build_object('day', 'saturday', 'is_working_day', false, 'open_time', NULL, 'close_time', NULL),
        jsonb_build_object('day', 'sunday', 'is_working_day', false, 'open_time', NULL, 'close_time', NULL)
      )
    )
  );

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_active, created_by, updated_by)
  VALUES
    (v_staff_owner, v_user_owner, 'Owner CRUD', 'owner', true, v_user_owner, v_user_owner),
    (v_staff_doctor, v_user_doctor, 'Dr CRUD', 'doctor', true, v_user_owner, v_user_owner),
    (v_staff_inactive, v_user_inactive, 'Inactive CRUD', 'receptionist', false, v_user_owner, v_user_owner),
    (v_staff_unassigned, v_user_unassigned, 'Other Branch CRUD', 'receptionist', true, v_user_owner, v_user_owner);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_staff_owner, v_branch_id, true, v_user_owner, v_user_owner),
    (v_staff_doctor, v_branch_id, true, v_user_owner, v_user_owner),
    (v_staff_inactive, v_branch_id, false, v_user_owner, v_user_owner);

  v_org_today := auth_internal.get_org_today(v_org_id);
  v_future := v_org_today + 3;
  v_past := v_org_today - 1;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_owner::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_staff_owner::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  -- Create incomplete shift (zero staff).
  BEGIN
    v_shift_incomplete := public.create_shift(
      v_branch_id,
      v_future,
      time '09:00',
      time '17:00',
      'Coverage block',
      '{}'::uuid[]
    );
  EXCEPTION
    WHEN OTHERS THEN
      v_shift_incomplete := NULL;
      v_err := SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_assignee_count
  FROM public.shift_assignments sa
  WHERE sa.shift_id = v_shift_incomplete;

  PERFORM pg_temp.record_shift_crud_result(
    'create_incomplete_shift_zero_staff',
    v_shift_incomplete IS NOT NULL AND v_assignee_count = 0,
    COALESCE(v_shift_incomplete::text, COALESCE(v_err, '<null>'))
  );

  PERFORM set_config('role', 'authenticated', true);

  -- Create active shift with staff.
  BEGIN
    v_shift_active := public.create_shift(
      v_branch_id,
      v_future + 1,
      time '08:00',
      time '12:00',
      NULL,
      ARRAY[v_staff_doctor]::uuid[]
    );
    v_err := NULL;
  EXCEPTION
    WHEN OTHERS THEN
      v_shift_active := NULL;
      v_err := SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_assignee_count
  FROM public.shift_assignments sa
  WHERE sa.shift_id = v_shift_active;

  PERFORM pg_temp.record_shift_crud_result(
    'create_active_shift_with_staff',
    v_shift_active IS NOT NULL AND v_assignee_count = 1,
    COALESCE(v_shift_active::text, COALESCE(v_err, '<null>'))
  );

  PERFORM set_config('role', 'authenticated', true);

  -- Reject end_time <= start_time.
  BEGIN
    PERFORM public.create_shift(v_branch_id, v_future + 2, time '14:00', time '14:00', NULL, '{}'::uuid[]);
    PERFORM pg_temp.record_shift_crud_result('reject_invalid_time_range_equal', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.record_shift_crud_result(
        'reject_invalid_time_range_equal',
        SQLERRM = 'shift_invalid_time_range',
        SQLERRM
      );
  END;

  BEGIN
    PERFORM public.create_shift(v_branch_id, v_future + 2, time '16:00', time '15:00', NULL, '{}'::uuid[]);
    PERFORM pg_temp.record_shift_crud_result('reject_invalid_time_range_reverse', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.record_shift_crud_result(
        'reject_invalid_time_range_reverse',
        SQLERRM = 'shift_invalid_time_range',
        SQLERRM
      );
  END;

  -- Reject ineligible staff (inactive).
  BEGIN
    PERFORM public.create_shift(
      v_branch_id,
      v_future + 2,
      time '09:00',
      time '17:00',
      NULL,
      ARRAY[v_staff_inactive]::uuid[]
    );
    PERFORM pg_temp.record_shift_crud_result('reject_ineligible_inactive_staff', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.record_shift_crud_result(
        'reject_ineligible_inactive_staff',
        SQLERRM = 'staff_not_eligible',
        SQLERRM
      );
  END;

  -- Reject ineligible staff (not branch-assigned).
  BEGIN
    PERFORM public.create_shift(
      v_branch_id,
      v_future + 2,
      time '09:00',
      time '17:00',
      NULL,
      ARRAY[v_staff_unassigned]::uuid[]
    );
    PERFORM pg_temp.record_shift_crud_result('reject_ineligible_unassigned_staff', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.record_shift_crud_result(
        'reject_ineligible_unassigned_staff',
        SQLERRM = 'staff_not_eligible',
        SQLERRM
      );
  END;

  -- Seed overlapping shift for doctor on v_future + 5.
  PERFORM public.create_shift(
    v_branch_id,
    v_future + 5,
    time '09:00',
    time '17:00',
    NULL,
    ARRAY[v_staff_doctor]::uuid[]
  );

  -- Reject overlap with conflict payload.
  BEGIN
    PERFORM public.create_shift(
      v_branch_id,
      v_future + 5,
      time '16:00',
      time '20:00',
      NULL,
      ARRAY[v_staff_doctor]::uuid[]
    );
    PERFORM pg_temp.record_shift_crud_result('reject_overlap_with_payload', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      v_overlap_detail := SQLERRM;
      PERFORM pg_temp.record_shift_crud_result(
        'reject_overlap_with_payload',
        SQLERRM LIKE 'shift_overlap:%' AND SQLERRM LIKE '%Dr CRUD%',
        v_overlap_detail
      );
  END;

  -- Allow adjacent touching shifts (17:00 start after 09:00-17:00).
  BEGIN
    v_shift_adjacent := public.create_shift(
      v_branch_id,
      v_future + 5,
      time '17:00',
      time '21:00',
      NULL,
      ARRAY[v_staff_doctor]::uuid[]
    );
    v_err := NULL;
  EXCEPTION
    WHEN OTHERS THEN
      v_shift_adjacent := NULL;
      v_err := SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);
  PERFORM pg_temp.record_shift_crud_result(
    'allow_adjacent_touching_shifts',
    v_shift_adjacent IS NOT NULL,
    COALESCE(v_shift_adjacent::text, COALESCE(v_err, '<null>'))
  );

  PERFORM set_config('role', 'authenticated', true);

  -- Reject past shift_date.
  BEGIN
    PERFORM public.create_shift(v_branch_id, v_past, time '09:00', time '17:00', NULL, '{}'::uuid[]);
    PERFORM pg_temp.record_shift_crud_result('reject_past_shift_date', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.record_shift_crud_result(
        'reject_past_shift_date',
        SQLERRM = 'shift_read_only_past_date',
        SQLERRM
      );
  END;

  -- Allow times outside branch working hours (19:00-22:00 while schedule ends 18:00).
  BEGIN
    PERFORM public.create_shift(v_branch_id, v_future + 6, time '19:00', time '22:00', NULL, '{}'::uuid[]);
    PERFORM pg_temp.record_shift_crud_result('allow_outside_branch_working_hours', true, 'created');
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.record_shift_crud_result(
        'allow_outside_branch_working_hours',
        false,
        SQLERRM
      );
  END;

  -- Audit shift.create on last successful create.
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_audit_count
  FROM public.audit_log al
  WHERE al.action = 'shift.create'
    AND al.table_name = 'shifts'
    AND al.organization_id = v_org_id;

  PERFORM pg_temp.record_shift_crud_result(
    'audit_shift_create',
    v_audit_count >= 4,
    'count=' || v_audit_count::text
  );

  -- US3: assignment management on existing shifts.
  PERFORM set_config('role', 'postgres', true);
  SELECT s.updated_at INTO v_shift_updated_at FROM public.shifts s WHERE s.id = v_shift_active;
  DELETE FROM public.audit_log WHERE action IN ('shift.assignment.add', 'shift.assignment.remove');

  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    v_modify_result := public.modify_shift_assignments(
      v_shift_active,
      v_shift_updated_at,
      ARRAY[v_staff_owner]::uuid[],
      '{}'::uuid[]
    );
    v_err := NULL;
  EXCEPTION
    WHEN OTHERS THEN
      v_modify_result := NULL;
      v_err := SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_assignee_count
  FROM public.shift_assignments sa
  WHERE sa.shift_id = v_shift_active;

  PERFORM pg_temp.record_shift_crud_result(
    'assignment_add_eligible_staff',
    v_modify_result IS NOT NULL
      AND (v_modify_result->>'status') = 'active'
      AND (v_modify_result->>'assignee_count')::int = 2
      AND v_assignee_count = 2,
    COALESCE(v_modify_result::text, COALESCE(v_err, '<null>'))
  );

  SELECT s.updated_at INTO v_shift_updated_at FROM public.shifts s WHERE s.id = v_shift_active;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM public.modify_shift_assignments(
      v_shift_active,
      v_shift_updated_at,
      ARRAY[v_staff_doctor]::uuid[],
      '{}'::uuid[]
    );
    PERFORM pg_temp.record_shift_crud_result('assignment_reject_duplicate', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.record_shift_crud_result(
        'assignment_reject_duplicate',
        SQLERRM = 'staff_already_assigned',
        SQLERRM
      );
  END;

  v_shift_overlap_target := public.create_shift(
    v_branch_id,
    v_future + 5,
    time '16:00',
    time '20:00',
    NULL,
    '{}'::uuid[]
  );
  SELECT s.updated_at INTO v_shift_updated_at FROM public.shifts s WHERE s.id = v_shift_overlap_target;

  BEGIN
    PERFORM public.modify_shift_assignments(
      v_shift_overlap_target,
      v_shift_updated_at,
      ARRAY[v_staff_doctor]::uuid[],
      '{}'::uuid[]
    );
    PERFORM pg_temp.record_shift_crud_result('assignment_reject_overlap_on_add', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      v_overlap_detail := SQLERRM;
      PERFORM pg_temp.record_shift_crud_result(
        'assignment_reject_overlap_on_add',
        SQLERRM LIKE 'shift_overlap:%' AND SQLERRM LIKE '%Dr CRUD%',
        v_overlap_detail
      );
  END;

  SELECT s.updated_at INTO v_shift_updated_at FROM public.shifts s WHERE s.id = v_shift_active;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    v_modify_result := public.modify_shift_assignments(
      v_shift_active,
      v_shift_updated_at,
      '{}'::uuid[],
      ARRAY[v_staff_owner]::uuid[]
    );
    v_err := NULL;
  EXCEPTION
    WHEN OTHERS THEN
      v_modify_result := NULL;
      v_err := SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_assignee_count
  FROM public.shift_assignments sa
  WHERE sa.shift_id = v_shift_active;

  PERFORM pg_temp.record_shift_crud_result(
    'assignment_remove_one_of_many',
    v_modify_result IS NOT NULL
      AND (v_modify_result->>'assignee_count')::int = 1
      AND v_assignee_count = 1,
    COALESCE(v_modify_result::text, COALESCE(v_err, '<null>'))
  );

  PERFORM set_config('role', 'authenticated', true);
  v_shift_assignment_test := public.create_shift(
    v_branch_id,
    v_future + 8,
    time '10:00',
    time '14:00',
    NULL,
    ARRAY[v_staff_owner]::uuid[]
  );
  SELECT s.updated_at INTO v_shift_updated_at FROM public.shifts s WHERE s.id = v_shift_assignment_test;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    v_modify_result := public.modify_shift_assignments(
      v_shift_assignment_test,
      v_shift_updated_at,
      '{}'::uuid[],
      ARRAY[v_staff_owner]::uuid[]
    );
    v_err := NULL;
  EXCEPTION
    WHEN OTHERS THEN
      v_modify_result := NULL;
      v_err := SQLERRM;
  END;

  PERFORM pg_temp.record_shift_crud_result(
    'assignment_remove_last_becomes_incomplete',
    v_modify_result IS NOT NULL
      AND (v_modify_result->>'status') = 'incomplete'
      AND (v_modify_result->>'assignee_count')::int = 0,
    COALESCE(v_modify_result::text, COALESCE(v_err, '<null>'))
  );

  v_shift_cancelled := public.create_shift(
    v_branch_id,
    v_future + 9,
    time '09:00',
    time '12:00',
    NULL,
    ARRAY[v_staff_doctor]::uuid[]
  );
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.shifts
  SET deleted_at = now(), updated_by = v_user_owner
  WHERE id = v_shift_cancelled;
  SELECT s.updated_at INTO v_shift_updated_at FROM public.shifts s WHERE s.id = v_shift_cancelled;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM public.modify_shift_assignments(
      v_shift_cancelled,
      v_shift_updated_at,
      ARRAY[v_staff_owner]::uuid[],
      '{}'::uuid[]
    );
    PERFORM pg_temp.record_shift_crud_result('assignment_reject_cancelled_shift', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.record_shift_crud_result(
        'assignment_reject_cancelled_shift',
        SQLERRM = 'shift_cancelled',
        SQLERRM
      );
  END;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.shifts (
    id, organization_id, branch_id, shift_date, start_time, end_time, created_by, updated_by
  )
  VALUES (
    'b2800000-0000-4000-8000-0000000000a1',
    v_org_id,
    v_branch_id,
    v_past,
    time '13:00',
    time '17:00',
    v_user_owner,
    v_user_owner
  )
  RETURNING id INTO v_shift_past;

  INSERT INTO public.shift_assignments (shift_id, staff_member_id, created_by, updated_by)
  VALUES (v_shift_past, v_staff_doctor, v_user_owner, v_user_owner);

  SELECT s.updated_at INTO v_shift_updated_at FROM public.shifts s WHERE s.id = v_shift_past;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM public.modify_shift_assignments(
      v_shift_past,
      v_shift_updated_at,
      ARRAY[v_staff_owner]::uuid[],
      '{}'::uuid[]
    );
    PERFORM pg_temp.record_shift_crud_result('assignment_reject_past_date_shift', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.record_shift_crud_result(
        'assignment_reject_past_date_shift',
        SQLERRM = 'shift_read_only_past_date',
        SQLERRM
      );
  END;

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_add_audit_count
  FROM public.audit_log al
  WHERE al.action = 'shift.assignment.add'
    AND al.organization_id = v_org_id;
  SELECT count(*)::int INTO v_remove_audit_count
  FROM public.audit_log al
  WHERE al.action = 'shift.assignment.remove'
    AND al.organization_id = v_org_id;

  PERFORM pg_temp.record_shift_crud_result(
    'audit_shift_assignment_add',
    v_add_audit_count >= 1,
    'count=' || v_add_audit_count::text
  );
  PERFORM pg_temp.record_shift_crud_result(
    'audit_shift_assignment_remove',
    v_remove_audit_count >= 1,
    'count=' || v_remove_audit_count::text
  );

  -- US4: update date/time/notes on an existing future shift.
  v_shift_assignment_test := public.create_shift(
    v_branch_id,
    v_future + 6,
    time '09:00',
    time '17:00',
    'Before edit',
    ARRAY[v_staff_doctor]::uuid[]
  );
  PERFORM set_config('role', 'postgres', true);
  SELECT s.updated_at INTO v_shift_updated_at FROM public.shifts s WHERE s.id = v_shift_assignment_test;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM public.update_shift(
      v_shift_assignment_test,
      v_shift_updated_at,
      v_future + 7,
      time '10:00',
      time '18:00',
      'After edit'
    );
    v_err := NULL;
  EXCEPTION
    WHEN OTHERS THEN
      v_err := SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);
  SELECT
    s.shift_date = v_future + 7
    AND s.start_time = time '10:00'
    AND s.end_time = time '18:00'
    AND s.notes = 'After edit'
  INTO v_is_unassigned
  FROM public.shifts s
  WHERE s.id = v_shift_assignment_test;

  PERFORM pg_temp.record_shift_crud_result(
    'update_shift_date_time_notes',
    v_err IS NULL AND v_is_unassigned IS TRUE,
    COALESCE(v_err, 'updated=' || COALESCE(v_is_unassigned::text, '<null>'))
  );

  PERFORM set_config('role', 'authenticated', true);

  -- US4: reject update causing overlap (prior values preserved).
  PERFORM public.create_shift(
    v_branch_id,
    v_future + 8,
    time '09:00',
    time '17:00',
    NULL,
    ARRAY[v_staff_doctor]::uuid[]
  );
  v_shift_overlap_target := public.create_shift(
    v_branch_id,
    v_future + 8,
    time '17:00',
    time '20:00',
    NULL,
    ARRAY[v_staff_doctor]::uuid[]
  );
  PERFORM set_config('role', 'postgres', true);
  SELECT s.updated_at INTO v_shift_updated_at FROM public.shifts s WHERE s.id = v_shift_overlap_target;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM public.update_shift(
      v_shift_overlap_target,
      v_shift_updated_at,
      v_future + 8,
      time '16:00',
      time '20:00',
      NULL
    );
    PERFORM pg_temp.record_shift_crud_result('reject_update_overlap', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      v_overlap_detail := SQLERRM;
      PERFORM pg_temp.record_shift_crud_result(
        'reject_update_overlap',
        SQLERRM LIKE 'shift_overlap:%',
        v_overlap_detail
      );
  END;

  PERFORM set_config('role', 'postgres', true);
  SELECT s.start_time = time '17:00' AND s.end_time = time '20:00'
  INTO v_is_unassigned
  FROM public.shifts s
  WHERE s.id = v_shift_overlap_target;

  PERFORM pg_temp.record_shift_crud_result(
    'reject_update_overlap_preserves_prior_values',
    v_is_unassigned IS TRUE,
    'preserved=' || COALESCE(v_is_unassigned::text, '<null>')
  );

  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config('role', 'authenticated', true);

  -- US4: reject update moving shift_date to past.
  v_shift_assignment_test := public.create_shift(
    v_branch_id,
    v_future + 9,
    time '09:00',
    time '12:00',
    NULL,
    '{}'::uuid[]
  );
  PERFORM set_config('role', 'postgres', true);
  SELECT s.updated_at INTO v_shift_updated_at FROM public.shifts s WHERE s.id = v_shift_assignment_test;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM public.update_shift(
      v_shift_assignment_test,
      v_shift_updated_at,
      v_past,
      time '09:00',
      time '12:00',
      NULL
    );
    PERFORM pg_temp.record_shift_crud_result('reject_update_move_to_past', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.record_shift_crud_result(
        'reject_update_move_to_past',
        SQLERRM = 'shift_read_only_past_date',
        SQLERRM
      );
  END;

  -- US4: cancel future shift (soft-delete).
  v_shift_assignment_test := public.create_shift(
    v_branch_id,
    v_future + 11,
    time '13:00',
    time '17:00',
    NULL,
    ARRAY[v_staff_doctor]::uuid[]
  );
  PERFORM set_config('role', 'postgres', true);
  SELECT s.updated_at INTO v_shift_updated_at FROM public.shifts s WHERE s.id = v_shift_assignment_test;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM public.cancel_shift(v_shift_assignment_test, v_shift_updated_at);
    v_err := NULL;
  EXCEPTION
    WHEN OTHERS THEN
      v_err := SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);
  SELECT s.deleted_at IS NOT NULL INTO v_is_unassigned FROM public.shifts s WHERE s.id = v_shift_assignment_test;
  v_list_result := public.list_shifts(v_branch_id, v_future + 11, v_future + 11);
  v_list_count := (
    SELECT count(*)::int
    FROM jsonb_array_elements(v_list_result) elem
    WHERE elem->>'id' = v_shift_assignment_test::text
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM pg_temp.record_shift_crud_result(
    'cancel_future_shift_soft_delete',
    v_err IS NULL AND v_is_unassigned IS TRUE AND v_list_count = 0,
    COALESCE(v_err, 'listed=' || v_list_count::text)
  );

  -- US4: reject edit/cancel on cancelled shift.
  PERFORM set_config('role', 'postgres', true);
  SELECT s.updated_at INTO v_shift_updated_at FROM public.shifts s WHERE s.id = v_shift_assignment_test;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM public.update_shift(
      v_shift_assignment_test,
      v_shift_updated_at,
      v_future + 11,
      time '13:00',
      time '18:00',
      NULL
    );
    PERFORM pg_temp.record_shift_crud_result('reject_update_cancelled_shift', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.record_shift_crud_result(
        'reject_update_cancelled_shift',
        SQLERRM = 'shift_cancelled',
        SQLERRM
      );
  END;

  BEGIN
    PERFORM public.cancel_shift(v_shift_assignment_test, v_shift_updated_at);
    PERFORM pg_temp.record_shift_crud_result('reject_cancel_already_cancelled', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.record_shift_crud_result(
        'reject_cancel_already_cancelled',
        SQLERRM = 'shift_cancelled',
        SQLERRM
      );
  END;

  -- US4: reject edit/cancel on past-date shift.
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.shifts (
    id, organization_id, branch_id, shift_date, start_time, end_time, created_by, updated_by
  )
  VALUES (
    'c2800000-0000-4000-8000-0000000000a1',
    v_org_id,
    v_branch_id,
    v_past,
    time '08:00',
    time '12:00',
    v_user_owner,
    v_user_owner
  )
  RETURNING id INTO v_shift_past;

  SELECT s.updated_at INTO v_shift_updated_at FROM public.shifts s WHERE s.id = v_shift_past;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM public.update_shift(
      v_shift_past,
      v_shift_updated_at,
      v_future,
      time '08:00',
      time '12:00',
      NULL
    );
    PERFORM pg_temp.record_shift_crud_result('reject_update_past_date_shift', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.record_shift_crud_result(
        'reject_update_past_date_shift',
        SQLERRM = 'shift_read_only_past_date',
        SQLERRM
      );
  END;

  BEGIN
    PERFORM public.cancel_shift(v_shift_past, v_shift_updated_at);
    PERFORM pg_temp.record_shift_crud_result('reject_cancel_past_date_shift', false, 'no exception');
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.record_shift_crud_result(
        'reject_cancel_past_date_shift',
        SQLERRM = 'shift_read_only_past_date',
        SQLERRM
      );
  END;

  -- US4: audit shift.update and shift.cancel.
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_audit_count
  FROM public.audit_log al
  WHERE al.action = 'shift.update' AND al.organization_id = v_org_id;
  SELECT count(*)::int INTO v_add_audit_count
  FROM public.audit_log al
  WHERE al.action = 'shift.cancel' AND al.organization_id = v_org_id;

  PERFORM pg_temp.record_shift_crud_result(
    'audit_shift_update',
    v_audit_count >= 1,
    'count=' || v_audit_count::text
  );
  PERFORM pg_temp.record_shift_crud_result(
    'audit_shift_cancel',
    v_add_audit_count >= 1,
    'count=' || v_add_audit_count::text
  );

  PERFORM set_config('role', 'authenticated', true);

  -- US2: list_shifts date-range filtering (only shifts within inclusive bounds).
  v_list_result := public.list_shifts(v_branch_id, v_future, v_future + 1);
  v_list_count := jsonb_array_length(v_list_result);

  PERFORM pg_temp.record_shift_crud_result(
    'list_shifts_date_range_filter',
    v_list_count = 2,
    'count=' || v_list_count::text
  );

  -- US2: incomplete shifts return is_unassigned=true in list payload.
  SELECT (elem->>'is_unassigned')::boolean
  INTO v_is_unassigned
  FROM jsonb_array_elements(v_list_result) elem
  WHERE elem->>'id' = v_shift_incomplete::text;

  PERFORM pg_temp.record_shift_crud_result(
    'list_shifts_incomplete_is_unassigned',
    v_is_unassigned IS TRUE,
    COALESCE(v_is_unassigned::text, '<null>')
  );

  -- US2: cancelled shifts excluded from list_shifts (soft-delete).
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.shifts SET deleted_at = now(), updated_at = now() WHERE id = v_shift_active;

  v_shift_out_of_range := public.create_shift(
    v_branch_id,
    v_future + 10,
    time '10:00',
    time '14:00',
    NULL,
    '{}'::uuid[]
  );

  PERFORM set_config('role', 'authenticated', true);
  v_list_result := public.list_shifts(v_branch_id, v_future, v_future + 30);
  v_list_count := (
    SELECT count(*)::int
    FROM jsonb_array_elements(v_list_result) elem
    WHERE elem->>'id' = v_shift_active::text
  );

  PERFORM pg_temp.record_shift_crud_result(
    'list_shifts_excludes_cancelled',
    v_list_count = 0,
    'cancelled_visible=' || v_list_count::text
  );

  -- US2: get_shift_detail is_read_only for non-manager (doctor without shifts.manage).
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_doctor::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_staff_doctor::text,
      'staff_role', 'doctor',
      'setup_required', false
    )::text,
    true
  );

  v_detail_result := public.get_shift_detail(v_shift_incomplete);
  v_is_read_only := (v_detail_result->'shift'->>'is_read_only')::boolean;

  PERFORM pg_temp.record_shift_crud_result(
    'get_shift_detail_read_only_non_manager',
    v_is_read_only IS TRUE,
    COALESCE(v_is_read_only::text, '<null>')
  );

  -- US2: get_shift_detail is_read_only for past-date shift (manager context).
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_owner::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_staff_owner::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.shifts (
    id, organization_id, branch_id, shift_date, start_time, end_time, created_by, updated_by
  )
  VALUES (
    'a2800000-0000-4000-8000-0000000000a1',
    v_org_id,
    v_branch_id,
    v_past,
    time '09:00',
    time '17:00',
    v_user_owner,
    v_user_owner
  )
  RETURNING id INTO v_shift_past;

  PERFORM set_config('role', 'authenticated', true);
  v_detail_result := public.get_shift_detail(v_shift_past);
  v_is_read_only := (v_detail_result->'shift'->>'is_read_only')::boolean;
  v_is_past := (v_detail_result->'shift'->>'is_past')::boolean;

  PERFORM pg_temp.record_shift_crud_result(
    'get_shift_detail_read_only_past_date',
    v_is_read_only IS TRUE AND v_is_past IS TRUE,
    'read_only=' || COALESCE(v_is_read_only::text, '<null>') || ' past=' || COALESCE(v_is_past::text, '<null>')
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*)::int INTO v_failures
  FROM shift_crud_results
  WHERE NOT passed;

  IF v_failures > 0 THEN
    RAISE EXCEPTION 'shift_management_crud.sql: % failing assertion(s). Run: SELECT * FROM shift_crud_results WHERE NOT passed ORDER BY test_name',
      v_failures;
  END IF;
END;
$$;

SELECT test_name, passed, detail FROM shift_crud_results ORDER BY test_name;

ROLLBACK;
