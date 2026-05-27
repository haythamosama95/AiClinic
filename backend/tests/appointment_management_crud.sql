-- V1-4 appointment management RPC verification.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/appointment_management_crud.sql
--
-- Limitation: this script runs as the psql superuser (postgres). That bypasses
-- EXECUTE checks on auth_internal that PostgREST enforces for role authenticated.
-- Grant regressions are covered by appointment_management_grants.sql and Flutter
-- boundary tests under test/boundary/appointments/.

BEGIN;

CREATE TEMP TABLE appointment_crud_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1400000-0000-4000-8000-000000000101';
  v_owner_staff uuid := 'b1400000-0000-4000-8000-000000000101';
  v_doctor_user uuid := 'a1400000-0000-4000-8000-000000000102';
  v_doctor_staff uuid := 'b1400000-0000-4000-8000-000000000102';
  v_lab_user uuid := 'a1400000-0000-4000-8000-000000000103';
  v_lab_staff uuid := 'b1400000-0000-4000-8000-000000000103';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_patient_id uuid;
  v_appt_planned uuid;
  v_appt_walkin uuid;
  v_appt_second uuid;
  v_doctor2_staff uuid := 'b1400000-0000-4000-8000-000000000104';
  v_doctor2_user uuid := 'a1400000-0000-4000-8000-000000000104';
  v_start timestamptz;
  v_end timestamptz;
  v_items jsonb;
  v_default int;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_i int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.appointments;
  DELETE FROM public.patients;
  DELETE FROM public.app_settings WHERE key = 'appointment.default_duration_minutes';
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.staff_members WHERE id NOT IN (v_bootstrap_staff);
  DELETE FROM public.audit_log;
  DELETE FROM public.branches;
  DELETE FROM public.organizations;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_doctor_user, v_lab_user, v_doctor2_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v14-owner',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v14-doctor',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_lab_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v14-lab',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor2_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'v14-doctor2',
     extensions.crypt('test-password', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('V14 Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MAIN', NULL);
  v_branch_main := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Clinic Owner', 'owner', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Dr Smith', 'doctor', false, v_bootstrap_user, v_bootstrap_user),
    (v_lab_staff, v_lab_user, 'Lab Tech', 'lab_staff', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor2_staff, v_doctor2_user, 'Dr Jones', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  SELECT s.id, v_branch_main, true, v_bootstrap_user, v_bootstrap_user
  FROM (VALUES (v_owner_staff), (v_doctor_staff), (v_lab_staff), (v_doctor2_staff)) AS s(id);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.create_patient(v_branch_main, 'Appt Patient', '201000000141', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;

  -- Trivial: settings default fallback 20.
  v_result := public.get_appointment_settings(v_branch_main);
  v_default := (v_result.data ->> 'default_duration_minutes')::int;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'settings_default_fallback_20',
    v_result.success AND v_default = 20,
    'default=' || COALESCE(v_default::text, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Settings: set org-wide default duration.
  v_result := public.set_appointment_default_duration(30, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'set_default_duration_org_wide',
    v_result.success AND (v_result.data ->> 'default_duration_minutes')::int = 30,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_appointment_settings(v_branch_main);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'settings_reflects_org_default',
    v_result.success AND (v_result.data ->> 'default_duration_minutes')::int = 30,
    COALESCE((v_result.data ->> 'default_duration_minutes'), '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Stupid: invalid duration on set.
  v_result := public.set_appointment_default_duration(3, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'set_duration_rejects_too_short',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.set_appointment_default_duration(241, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'set_duration_rejects_too_long',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Stupid: invalid type on create.
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'invalid', now(), 30, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'create_rejects_invalid_type',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Planned create without start time.
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', NULL, 30, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'planned_requires_start_time',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_start := date_trunc('hour', now() + interval '2 days');
  v_end := v_start + interval '30 minutes';

  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', v_start, 30, NULL, 'First visit'
  );
  v_appt_planned := (v_result.data ->> 'appointment_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'planned_create_success',
    v_result.success
      AND (v_result.data ->> 'status') = 'scheduled'
      AND (v_result.data ->> 'type') = 'planned',
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Conflict: overlapping planned slot.
  v_result := public.create_appointment(
    v_branch_main,
    v_patient_id,
    v_doctor_staff,
    'planned',
    v_start + interval '15 minutes',
    30,
    NULL,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'planned_conflict_rejected',
    NOT v_result.success AND v_result.error_code = 'SCHEDULE_CONFLICT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- US1: adjacent non-overlapping slot succeeds (ends where next starts).
  v_result := public.create_appointment(
    v_branch_main,
    v_patient_id,
    v_doctor_staff,
    'planned',
    v_end,
    20,
    NULL,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'planned_adjacent_slot_succeeds',
    v_result.success AND (v_result.data ->> 'status') = 'scheduled',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- US1: planned create without explicit duration uses settings default (30).
  v_start := date_trunc('hour', now() + interval '6 days');
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', v_start, NULL, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'planned_create_uses_settings_default_duration',
    v_result.success
      AND (v_result.data ->> 'end_time')::timestamptz = v_start + interval '30 minutes',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Planned create without assigned doctor (optional doctor).
  v_start := date_trunc('hour', now() + interval '7 days');
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, NULL, 'planned', v_start, 25, NULL, 'Unassigned doctor'
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'planned_create_without_doctor',
    v_result.success
      AND (v_result.data ->> 'status') = 'scheduled'
      AND (v_result.data ->> 'type') = 'planned',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Walk-in requires a doctor.
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, NULL, 'walk_in', NULL, 15, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'walk_in_requires_doctor',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_message, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Walk-in auto slot.
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'walk_in', NULL, 15, NULL, NULL
  );
  v_appt_walkin := (v_result.data ->> 'appointment_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'walk_in_create_checked_in',
    v_result.success
      AND (v_result.data ->> 'status') = 'checked_in'
      AND (v_result.data ->> 'type') = 'walk_in'
      AND (v_result.data ->> 'start_time') IS NOT NULL,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Status: scheduled -> checked_in -> in_progress -> completed.
  v_result := public.update_appointment_status(v_appt_planned, 'checked_in');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'status_scheduled_to_checked_in',
    v_result.success AND (v_result.data ->> 'status') = 'checked_in',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_appointment_status(v_appt_planned, 'in_progress');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'status_checked_in_to_in_progress',
    v_result.success AND (v_result.data ->> 'status') = 'in_progress',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_appointment_status(v_appt_planned, 'completed');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'status_in_progress_to_completed',
    v_result.success AND (v_result.data ->> 'status') = 'completed',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Invalid skip: completed -> checked_in.
  v_result := public.update_appointment_status(v_appt_planned, 'checked_in');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'status_invalid_transition_from_completed',
    NOT v_result.success AND v_result.error_code = 'INVALID_TRANSITION',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Reschedule requires scheduled planned — use new appointment.
  v_start := date_trunc('hour', now() + interval '3 days');
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;

  v_result := public.reschedule_appointment(
    v_appt_second,
    v_start + interval '2 hours',
    25,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'reschedule_scheduled_planned',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Cannot reschedule after check-in.
  v_result := public.update_appointment_status(v_appt_second, 'checked_in');
  v_result := public.reschedule_appointment(v_appt_second, v_start + interval '4 hours', 20, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'reschedule_rejects_after_check_in',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Cancel scheduled appointment (third).
  v_start := date_trunc('hour', now() + interval '4 days');
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;

  v_result := public.cancel_appointment(v_appt_second, 'Patient called');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'cancel_scheduled_appointment',
    v_result.success AND (v_result.data ->> 'status') = 'cancelled',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Cancelled slot can be rebooked (no conflict).
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'rebook_after_cancel_no_conflict',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- No-show from scheduled.
  v_start := date_trunc('hour', now() + interval '5 days');
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_second, 'no_show');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'no_show_from_scheduled',
    v_result.success AND (v_result.data ->> 'status') = 'no_show',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- list_appointments returns items sorted by start_time.
  v_day_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_day_end := v_day_start + interval '2 days';
  v_result := public.list_appointments(v_branch_main, v_day_start, v_day_end, NULL, NULL);
  v_items := v_result.data -> 'items';
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'list_appointments_returns_items',
    v_result.success AND jsonb_typeof(v_items) = 'array' AND jsonb_array_length(v_items) > 0,
    'count=' || COALESCE(jsonb_array_length(v_items)::text, '0')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Doctor filter.
  v_result := public.list_appointments(v_branch_main, v_day_start, v_day_end, v_doctor_staff, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'list_appointments_doctor_filter',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- NO_SLOT_AVAILABLE: pack doctor day with 15-min slots in UTC today.
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.appointments WHERE doctor_id = v_doctor_staff;
  v_day_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_day_end := v_day_start + interval '1 day';
  v_start := v_day_start;
  FOR v_i IN 1..96 LOOP
    INSERT INTO public.appointments (
      branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
    )
    VALUES (
      v_branch_main,
      v_patient_id,
      v_doctor_staff,
      v_start,
      v_start + interval '15 minutes',
      'planned',
      'scheduled',
      v_owner_user,
      v_owner_user
    );
    v_start := v_start + interval '15 minutes';
  END LOOP;
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'walk_in', NULL, 15, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'walk_in_no_slot_available',
    NOT v_result.success AND v_result.error_code = 'NO_SLOT_AVAILABLE',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Archived patient cannot be booked.
  v_result := public.archive_patient(v_patient_id);
  v_start := date_trunc('hour', now() + interval '8 days');
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'create_rejects_archived_patient',
    NOT v_result.success AND v_result.error_code = 'PATIENT_ARCHIVED',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Restore patient for remaining tests (new patient row).
  v_result := public.create_patient(v_branch_main, 'Appt Patient Restored', '201000000142', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;

  -- Non-doctor staff id is rejected.
  v_start := date_trunc('hour', now() + interval '9 days');
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_lab_staff, 'planned', v_start, 20, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'create_rejects_invalid_doctor',
    NOT v_result.success AND v_result.error_code = 'INVALID_DOCTOR',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- End time override implies duration.
  v_start := date_trunc('hour', now() + interval '10 days');
  v_end := v_start + interval '45 minutes';
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', v_start, NULL, v_end, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'planned_create_with_end_time_override',
    v_result.success
      AND (v_result.data ->> 'end_time')::timestamptz = v_end,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Same time different doctors: no conflict.
  v_start := date_trunc('hour', now() + interval '11 days');
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'planned_same_time_doctor_a',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor2_staff, 'planned', v_start, 20, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'planned_same_time_different_doctors_allowed',
    v_result.success AND (v_result.data ->> 'status') = 'scheduled',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Two unassigned planned at same time: no doctor overlap check.
  v_start := date_trunc('hour', now() + interval '12 days');
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, NULL, 'planned', v_start, 15, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'two_planned_without_doctor_first',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_appointment(
    v_branch_main, v_patient_id, NULL, 'planned', v_start, 15, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'two_planned_without_doctor_no_overlap',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Lab staff without appointment permission cannot get settings.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_lab_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_lab_staff::text,
      'staff_role', 'lab_staff',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.get_appointment_settings(v_branch_main);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'lab_staff_denied_settings',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_start := date_trunc('hour', now() + interval '13 days');
  v_result := public.create_appointment(
    v_branch_main, v_patient_id, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'lab_staff_denied_create_appointment',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
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
  FROM appointment_crud_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM appointment_crud_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'appointment_management_crud: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
