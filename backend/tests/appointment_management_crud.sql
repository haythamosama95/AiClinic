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

-- Same-calendar-day slot in org TZ (UTC in this suite). Avoids greatest(now()+Nh, day+Nh)
-- rolling to tomorrow after ~20:00 UTC, which breaks day-gated status transitions.
CREATE OR REPLACE FUNCTION pg_temp.test_appointment_same_day_slot(p_offset_hours int)
RETURNS timestamptz
LANGUAGE plpgsql
AS $$
DECLARE
  v_tz text := 'UTC';
  v_day_start timestamptz;
BEGIN
  IF p_offset_hours < 1 OR p_offset_hours > 23 THEN
    RAISE EXCEPTION 'test_appointment_same_day_slot: offset must be 1..23, got %', p_offset_hours;
  END IF;
  v_day_start := date_trunc('day', now() AT TIME ZONE v_tz) AT TIME ZONE v_tz;
  RETURN v_day_start + make_interval(hours => p_offset_hours);
END;
$$;

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a1400000-0000-4000-8000-000000000101';
  v_owner_staff uuid := 'b1400000-0000-4000-8000-000000000101';
  v_doctor_user uuid := 'a1400000-0000-4000-8000-000000000102';
  c_doctor_staff_id constant uuid := 'b1400000-0000-4000-8000-000000000102';
  v_lab_user uuid := 'a1400000-0000-4000-8000-000000000103';
  v_lab_staff uuid := 'b1400000-0000-4000-8000-000000000103';
  v_result public.rpc_result;
  v_org_id uuid;
  v_main_branch_id uuid;
  v_patient_id uuid;
  v_patient2_id uuid;
  v_patient3_id uuid;
  v_sd_patient uuid;
  v_appt_planned uuid;
  v_appt_second uuid;
  v_visit_id uuid;
  v_visit_updated_at timestamptz;
  v_doctor2_staff uuid := 'b1400000-0000-4000-8000-000000000104';
  v_doctor2_user uuid := 'a1400000-0000-4000-8000-000000000104';
  v_start timestamptz;
  v_end timestamptz;
  v_items jsonb;
  v_default int;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_today_name text;
  v_i int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.visit_attachments;
  DELETE FROM public.soap_notes;
  DELETE FROM public.treatment_plans;
  DELETE FROM public.visits;
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
  v_main_branch_id := (v_result.data ->> 'branch_id')::uuid;

  -- Keep test timings deterministic: all days open full day unless overridden.
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches b
  SET working_schedule = jsonb_build_object(
    'days',
    jsonb_build_array(
      jsonb_build_object('day', 'monday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'tuesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'wednesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'thursday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'friday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'saturday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'sunday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59')
    )
  )
  WHERE b.id = v_main_branch_id;
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Clinic Owner', 'owner', false, v_bootstrap_user, v_bootstrap_user),
    (c_doctor_staff_id, v_doctor_user, 'Dr Smith', 'doctor', false, v_bootstrap_user, v_bootstrap_user),
    (v_lab_staff, v_lab_user, 'Lab Tech', 'lab_staff', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor2_staff, v_doctor2_user, 'Dr Jones', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  SELECT s.id, v_main_branch_id, true, v_bootstrap_user, v_bootstrap_user
  FROM (VALUES (v_owner_staff), (c_doctor_staff_id), (v_lab_staff), (v_doctor2_staff)) AS s(id);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_main_branch_id::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.create_patient(v_main_branch_id, 'Appt Patient', '201000000141', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.create_patient(v_main_branch_id, 'Appt Patient 2', '201000000144', NULL, NULL, NULL, NULL, false);
  v_patient2_id := (v_result.data ->> 'patient_id')::uuid;

  -- Trivial: settings default fallback 20.
  v_result := public.get_appointment_settings(v_main_branch_id);
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

  v_result := public.get_appointment_settings(v_main_branch_id);
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
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'invalid', now(), 30, NULL, NULL
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
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', NULL, 30, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'planned_requires_start_time',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Planned create outside branch working hours is rejected.
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches b
  SET working_schedule = jsonb_build_object(
    'days',
    jsonb_build_array(
      jsonb_build_object('day', 'monday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
      jsonb_build_object('day', 'tuesday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
      jsonb_build_object('day', 'wednesday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
      jsonb_build_object('day', 'thursday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
      jsonb_build_object('day', 'friday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
      jsonb_build_object('day', 'saturday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
      jsonb_build_object('day', 'sunday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00')
    )
  )
  WHERE b.id = v_main_branch_id;
  PERFORM set_config('role', 'authenticated', true);

  v_start := date_trunc('day', now() + interval '2 days') + interval '2 hours';
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 30, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'planned_outside_working_hours_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Restore full-day schedule for remaining legacy tests.
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches b
  SET working_schedule = jsonb_build_object(
    'days',
    jsonb_build_array(
      jsonb_build_object('day', 'monday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'tuesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'wednesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'thursday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'friday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'saturday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'sunday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59')
    )
  )
  WHERE b.id = v_main_branch_id;
  PERFORM set_config('role', 'authenticated', true);

  -- One patient per same-day slot (patient_has_same_day_appointment counts completed bookings).
  CREATE TEMP TABLE same_day_slot_patients (slot int PRIMARY KEY, patient_id uuid NOT NULL);
  FOR v_i IN 2..12 LOOP
    v_result := public.create_patient(
      v_main_branch_id,
      'Same Day Slot ' || v_i,
      '2010000002' || lpad(v_i::text, 2, '0'),
      NULL,
      NULL,
      NULL,
      NULL,
      false
    );
    INSERT INTO same_day_slot_patients (slot, patient_id)
    VALUES (v_i, (v_result.data ->> 'patient_id')::uuid);
  END LOOP;

  -- Lifecycle tests use an appointment on today's calendar day (org TZ UTC in this suite).
  v_start := pg_temp.test_appointment_same_day_slot(1);
  v_end := v_start + interval '30 minutes';

  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 30, NULL, 'First visit'
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
    v_main_branch_id,
    v_patient_id,
    c_doctor_staff_id,
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
  v_result := public.create_appointment(v_main_branch_id, v_patient2_id, c_doctor_staff_id, 'planned', v_end, 20, NULL, NULL);
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
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, NULL, NULL, NULL
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
    v_main_branch_id, v_patient_id, NULL, 'planned', v_start, 25, NULL, 'Unassigned doctor'
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

  -- Invalid appointment type is rejected.
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'invalid_type', NULL, 15, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'invalid_type_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Status: scheduled -> confirmed -> checked_in -> in_progress -> completed.
  v_result := public.update_appointment_status(v_appt_planned, 'confirmed');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'status_scheduled_to_confirmed',
    v_result.success AND (v_result.data ->> 'status') = 'confirmed',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Future appointment: confirm allowed, check-in blocked until appointment day.
  v_start := date_trunc('hour', now() + interval '20 days');
  v_result := public.create_appointment(
    v_main_branch_id, v_patient2_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_second, 'confirmed');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'status_future_confirm_allowed',
    v_result.success AND (v_result.data ->> 'status') = 'confirmed',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_appointment_status(v_appt_second, 'checked_in');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'status_future_check_in_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_TRANSITION',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.update_appointment_status(v_appt_planned, 'checked_in');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'status_confirmed_to_checked_in',
    v_result.success AND (v_result.data ->> 'status') = 'checked_in',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Invalid skip: scheduled -> checked_in (must confirm first).
  v_start := date_trunc('hour', now() + interval '15 days');
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_second, 'checked_in');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'status_invalid_skip_scheduled_to_checked_in',
    NOT v_result.success AND v_result.error_code = 'INVALID_TRANSITION',
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
    'status_in_progress_to_completed_requires_visit',
    NOT v_result.success AND v_result.error_code = 'VISIT_REQUIRED_FOR_COMPLETION',
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

  -- Transition matrix: scheduled -> in_progress is rejected (skip check-in).
  v_start := date_trunc('hour', now() + interval '16 days');
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_second, 'in_progress');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'status_invalid_skip_scheduled_to_in_progress',
    NOT v_result.success AND v_result.error_code = 'INVALID_TRANSITION',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Reception (bootstrap user) may advance another doctor's appointment on the appointment day.
  v_start := pg_temp.test_appointment_same_day_slot(2);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 2;
  v_result := public.create_appointment(
    v_main_branch_id, v_sd_patient, v_doctor2_staff, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_second, 'confirmed');
  v_result := public.update_appointment_status(v_appt_second, 'checked_in');
  v_result := public.update_appointment_status(v_appt_second, 'in_progress');
  v_result := public.create_visit(v_appt_second, NULL);
  v_visit_id := (v_result.data ->> 'visit_id')::uuid;
  SELECT v.updated_at INTO v_visit_updated_at FROM public.visits v WHERE v.id = v_visit_id;
  v_result := public.save_soap_note(
    v_visit_id,
    v_visit_updated_at,
    'Chief complaint documented.',
    NULL,
    NULL,
    NULL,
    NULL
  );
  v_result := public.complete_visit(v_visit_id, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'status_reception_completes_via_visit_submit',
    v_result.success
      AND (v_result.data ->> 'visit_status') = 'completed'
      AND (v_result.data ->> 'appointment_status') = 'completed',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- checked_in -> completed is rejected (skip in_progress).
  v_start := pg_temp.test_appointment_same_day_slot(3);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 3;
  v_result := public.create_appointment(
    v_main_branch_id, v_sd_patient, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_second, 'confirmed');
  v_result := public.update_appointment_status(v_appt_second, 'checked_in');
  v_result := public.update_appointment_status(v_appt_second, 'completed');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'status_invalid_skip_checked_in_to_completed',
    NOT v_result.success AND v_result.error_code = 'INVALID_TRANSITION',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Reschedule requires scheduled planned — use new appointment.
  v_start := date_trunc('hour', now() + interval '3 days');
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
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
    v_result.success AND (v_result.data ->> 'appointment_id') IS NOT NULL,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Reschedule conflict: another appointment blocks the target slot.
  v_start := date_trunc('hour', now() + interval '6 days');
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 30, NULL, NULL
  );
  v_appt_planned := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.create_appointment(
    v_main_branch_id, v_patient2_id, c_doctor_staff_id, 'planned', v_start + interval '4 hours', 30, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.reschedule_appointment(
    v_appt_second,
    v_start + interval '15 minutes',
    30,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'reschedule_conflict_rejected',
    NOT v_result.success AND v_result.error_code = 'SCHEDULE_CONFLICT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Cannot reschedule after confirmation.
  v_result := public.update_appointment_status(v_appt_second, 'confirmed');
  v_result := public.reschedule_appointment(v_appt_second, v_start + interval '4 hours', 20, NULL);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'reschedule_rejects_after_confirmed',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Cancel scheduled appointment (third).
  v_start := date_trunc('hour', now() + interval '4 days');
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
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
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'rebook_after_cancel_no_conflict',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- No-show from scheduled on the appointment day.
  v_start := pg_temp.test_appointment_same_day_slot(4);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 4;
  v_result := public.create_appointment(
    v_main_branch_id, v_sd_patient, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
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

  -- No-show before the appointment day is rejected.
  v_start := date_trunc('hour', now() + interval '21 days');
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_second, 'no_show');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'no_show_before_appointment_day_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_TRANSITION',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Cancel confirmed appointment (patient did not confirm after phone call).
  v_start := date_trunc('hour', now() + interval '5 days 1 hour');
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_second, 'confirmed');
  v_result := public.cancel_appointment(v_appt_second, 'Patient did not confirm');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'cancel_confirmed_appointment',
    v_result.success AND (v_result.data ->> 'status') = 'cancelled',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Cancel checked-in appointment.
  v_start := pg_temp.test_appointment_same_day_slot(5);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 5;
  v_result := public.create_appointment(
    v_main_branch_id, v_sd_patient, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_second, 'confirmed');
  v_result := public.update_appointment_status(v_appt_second, 'checked_in');
  v_result := public.cancel_appointment(v_appt_second, 'Clinic closed early');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'cancel_checked_in_appointment',
    v_result.success AND (v_result.data ->> 'status') = 'cancelled',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Cannot cancel completed appointment.
  v_start := pg_temp.test_appointment_same_day_slot(6);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 6;
  v_result := public.create_appointment(
    v_main_branch_id, v_sd_patient, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_second, 'confirmed');
  v_result := public.update_appointment_status(v_appt_second, 'checked_in');
  v_result := public.update_appointment_status(v_appt_second, 'in_progress');
  v_result := public.create_visit(v_appt_second, NULL);
  v_visit_id := (v_result.data ->> 'visit_id')::uuid;
  SELECT v.updated_at INTO v_visit_updated_at FROM public.visits v WHERE v.id = v_visit_id;
  v_result := public.save_soap_note(v_visit_id, v_visit_updated_at, 'Done.', NULL, NULL, NULL, NULL);
  v_result := public.complete_visit(v_visit_id, NULL);
  v_result := public.cancel_appointment(v_appt_second, 'Too late');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'cancel_rejects_completed',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- No-show from checked_in.
  v_start := pg_temp.test_appointment_same_day_slot(7);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 7;
  v_result := public.create_appointment(
    v_main_branch_id, v_sd_patient, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_second, 'confirmed');
  v_result := public.update_appointment_status(v_appt_second, 'checked_in');
  v_result := public.update_appointment_status(v_appt_second, 'no_show');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'no_show_from_checked_in',
    v_result.success AND (v_result.data ->> 'status') = 'no_show',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- No-show from confirmed (patient confirmed by phone but did not arrive).
  v_start := pg_temp.test_appointment_same_day_slot(10);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 10;
  v_result := public.create_appointment(
    v_main_branch_id, v_sd_patient, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_second, 'confirmed');
  v_result := public.update_appointment_status(v_appt_second, 'no_show');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'no_show_from_confirmed',
    v_result.success AND (v_result.data ->> 'status') = 'no_show',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Range bounds: end is exclusive (appointment at day_end must not appear in [day_start, day_end) list).
  v_day_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_day_end := v_day_start + interval '2 days';
  v_start := v_day_end;
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 11;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.appointments (
    branch_id,
    patient_id,
    doctor_id,
    start_time,
    end_time,
    type,
    status,
    created_by,
    updated_by
  )
  VALUES (
    v_main_branch_id,
    v_sd_patient,
    c_doctor_staff_id,
    v_start,
    v_start + interval '15 minutes',
    'planned',
    'scheduled',
    v_bootstrap_user,
    v_bootstrap_user
  )
  RETURNING id INTO v_appt_second;
  PERFORM set_config('role', 'authenticated', true);
  v_result := public.rpc_success(jsonb_build_object('appointment_id', v_appt_second));
  v_result := public.list_appointments(v_main_branch_id, v_day_start, v_day_end, NULL, NULL);
  v_items := v_result.data -> 'items';
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'list_appointments_end_exclusive',
    v_result.success
      AND NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_items) AS item
        WHERE (item ->> 'id')::uuid = v_appt_second
      )
      AND v_start >= v_day_end,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);
  -- list_appointments returns items sorted by start_time.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_main_branch_id::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );
  v_day_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_day_end := v_day_start + interval '2 days';
  v_start := pg_temp.test_appointment_same_day_slot(12);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 12;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES (c_doctor_staff_id, v_main_branch_id, true, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT DO NOTHING;
  PERFORM set_config('role', 'authenticated', true);
  v_result := public.create_appointment(
    p_branch_id => v_main_branch_id,
    p_patient_id => v_sd_patient,
    p_doctor_id => c_doctor_staff_id,
    p_type => 'planned',
    p_start_time => v_start,
    p_duration_minutes => 20
  );
  v_result := public.list_appointments(v_main_branch_id, v_day_start, v_day_end, NULL, NULL);
  v_items := v_result.data -> 'items';
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'list_appointments_returns_items',
    v_result.success AND jsonb_typeof(v_items) = 'array' AND jsonb_array_length(v_items) > 0,
    'count=' || COALESCE(jsonb_array_length(v_items)::text, '0')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Doctor filter (qualify doctor id — unqualified doctor_id can clobber PL variables).
  v_result := public.list_appointments(v_main_branch_id, v_day_start, v_day_end, c_doctor_staff_id, NULL);
  v_items := v_result.data -> 'items';
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'list_appointments_doctor_filter',
    v_result.success
      AND COALESCE(
        (
          SELECT bool_and((item ->> 'doctor_id')::uuid = expected.expected_doctor_id)
          FROM jsonb_array_elements(v_items) AS item
          CROSS JOIN (SELECT c_doctor_staff_id AS expected_doctor_id) AS expected
        ),
        true
      ),
    'count=' || COALESCE(jsonb_array_length(v_items)::text, '0')
  );
  -- Archived patient cannot be booked.
  v_result := public.archive_patient(v_patient_id);
  v_start := date_trunc('hour', now() + interval '8 days');
  v_result := public.create_appointment(
    p_branch_id => v_main_branch_id,
    p_patient_id => v_patient_id,
    p_doctor_id => c_doctor_staff_id,
    p_type => 'planned',
    p_start_time => v_start,
    p_duration_minutes => 20
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'create_rejects_archived_patient',
    NOT v_result.success AND v_result.error_code = 'PATIENT_ARCHIVED',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Restore patient for remaining tests (new patient row).
  v_result := public.create_patient(v_main_branch_id, 'Appt Patient Restored', '201000000142', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;

  -- Non-doctor staff id is rejected.
  v_start := date_trunc('hour', now() + interval '9 days');
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, v_lab_staff, 'planned', v_start, 20, NULL, NULL
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
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, NULL, v_end, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'planned_create_with_end_time_override',
    v_result.success
      AND (v_result.data ->> 'end_time')::timestamptz = v_end,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Same time different doctors: conflict because slots are branch-wide.
  v_start := date_trunc('hour', now() + interval '11 days');
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'planned_same_time_doctor_a',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, v_doctor2_staff, 'planned', v_start, 20, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'planned_same_time_different_doctors_conflict',
    NOT v_result.success AND v_result.error_code = 'SCHEDULE_CONFLICT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Two unassigned planned at same time: still conflicts due to slot uniqueness.
  v_start := date_trunc('hour', now() + interval '12 days');
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, NULL, 'planned', v_start, 15, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'two_planned_without_doctor_first',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, NULL, 'planned', v_start, 15, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'two_planned_without_doctor_conflict',
    NOT v_result.success AND v_result.error_code = 'SCHEDULE_CONFLICT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Same-day duplicate patient is rejected.
  v_result := public.create_patient(v_main_branch_id, 'Appt Patient Same Day', '201000000143', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;
  v_start := date_trunc('day', now() + interval '14 days') + interval '9 hours';
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'same_day_first_booking_succeeds',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, v_doctor2_staff, 'planned', v_start + interval '3 hours', 20, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'same_day_second_booking_rejected',
    NOT v_result.success AND v_result.error_code = 'PATIENT_ALREADY_BOOKED_SAME_DAY',
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
      'branch_ids', v_main_branch_id::text,
      'staff_member_id', v_lab_staff::text,
      'staff_role', 'lab_staff',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.get_appointment_settings(v_main_branch_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'lab_staff_denied_settings',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_start := date_trunc('hour', now() + interval '13 days');
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'lab_staff_denied_create_appointment',
    NOT v_result.success AND v_result.error_code = 'FORBIDDEN',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Today's queue: list_appointments returns start_time ASC and excludes other days.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_main_branch_id::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.visit_attachments WHERE visit_id IN (
    SELECT v.id FROM public.visits v WHERE v.branch_id = v_main_branch_id
  );
  DELETE FROM public.soap_notes WHERE visit_id IN (
    SELECT v.id FROM public.visits v WHERE v.branch_id = v_main_branch_id
  );
  DELETE FROM public.treatment_plans WHERE visit_id IN (
    SELECT v.id FROM public.visits v WHERE v.branch_id = v_main_branch_id
  );
  DELETE FROM public.visits WHERE branch_id = v_main_branch_id;
  DELETE FROM public.appointments WHERE branch_id = v_main_branch_id;
  PERFORM set_config('role', 'authenticated', true);

  v_day_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_day_end := v_day_start + interval '1 day';

  v_result := public.create_patient(v_main_branch_id, 'Queue Patient 3', '201000000145', NULL, NULL, NULL, NULL, false);
  v_patient3_id := (v_result.data ->> 'patient_id')::uuid;

  -- Fixed UTC hour offsets avoid now()+Nh rolling past midnight and dropping from today's list.
  v_start := pg_temp.test_appointment_same_day_slot(12);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 12;
  v_result := public.create_appointment(
    v_main_branch_id, v_sd_patient, c_doctor_staff_id, 'planned', v_start, 20, NULL, 'queue-late'
  );
  v_appt_planned := (v_result.data ->> 'appointment_id')::uuid;

  v_start := pg_temp.test_appointment_same_day_slot(10);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 10;
  v_result := public.create_appointment(
    v_main_branch_id, v_sd_patient, c_doctor_staff_id, 'planned', v_start, 20, NULL, 'queue-early'
  );
  v_appt_second := (v_result.data ->> 'appointment_id')::uuid;

  v_start := pg_temp.test_appointment_same_day_slot(11);
  SELECT patient_id INTO v_sd_patient FROM same_day_slot_patients WHERE slot = 11;
  v_result := public.create_appointment(
    v_main_branch_id, v_sd_patient, c_doctor_staff_id, 'planned', v_start, 20, NULL, 'queue-mid'
  );

  v_start := v_day_end + interval '2 hours';
  v_result := public.create_appointment(
    v_main_branch_id, v_patient_id, c_doctor_staff_id, 'planned', v_start, 20, NULL, 'queue-tomorrow'
  );

  v_result := public.list_appointments(v_main_branch_id, v_day_start, v_day_end, NULL, NULL);
  v_items := v_result.data -> 'items';
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results VALUES (
    'list_appointments_today_queue_sort_order',
    v_result.success
      AND jsonb_array_length(v_items) = 3
      AND COALESCE(
        (SELECT bool_and(prev <= cur)
         FROM (
           SELECT
             lag((item ->> 'start_time')::timestamptz) OVER (ORDER BY ord) AS prev,
             (item ->> 'start_time')::timestamptz AS cur
           FROM jsonb_array_elements(v_items) WITH ORDINALITY AS t(item, ord)
         ) ordered
         WHERE prev IS NOT NULL),
        true
      )
      AND (v_items -> 0 ->> 'id')::uuid = v_appt_second
      AND (v_items -> 2 ->> 'id')::uuid = v_appt_planned,
    'count=' || COALESCE(jsonb_array_length(v_items)::text, '0')
  );
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO appointment_crud_results
  SELECT
    'list_appointments_today_excludes_tomorrow',
    NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(v_items) AS item
      WHERE (item ->> 'start_time')::timestamptz >= v_day_end
    ),
    'ok';
  PERFORM set_config('role', 'postgres', true);
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
