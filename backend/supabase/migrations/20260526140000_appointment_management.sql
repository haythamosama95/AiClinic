-- =============================================================================
-- V1-4: Appointment management (schema, RLS, RPCs)
-- =============================================================================

DO $$
BEGIN
  CREATE TYPE public.appointment_type AS ENUM ('planned', 'walk_in');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
  CREATE TYPE public.appointment_status AS ENUM (
    'scheduled',
    'checked_in',
    'in_progress',
    'completed',
    'cancelled',
    'no_show'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

CREATE TABLE IF NOT EXISTS public.appointments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.branches (id),
  patient_id uuid NOT NULL REFERENCES public.patients (id),
  doctor_id uuid NOT NULL REFERENCES public.staff_members (id),
  start_time timestamptz NOT NULL,
  end_time timestamptz NOT NULL,
  type public.appointment_type NOT NULL,
  status public.appointment_status NOT NULL,
  queue_number int,
  notes text,
  cancel_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT appointments_end_after_start CHECK (end_time > start_time)
);

CREATE INDEX IF NOT EXISTS appointments_branch_doctor_start_idx
  ON public.appointments (branch_id, doctor_id, start_time)
  WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS appointments_branch_status_start_idx
  ON public.appointments (branch_id, status, start_time)
  WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS appointments_branch_start_idx
  ON public.appointments (branch_id, start_time)
  WHERE is_deleted = false;

SELECT public.apply_standard_audit_triggers('public.appointments'::regclass);

ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS appointments_select ON public.appointments;
CREATE POLICY appointments_select ON public.appointments
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND branch_id = ANY (public.jwt_branch_ids())
  );

DROP POLICY IF EXISTS appointments_insert ON public.appointments;
CREATE POLICY appointments_insert ON public.appointments
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS appointments_update ON public.appointments;
CREATE POLICY appointments_update ON public.appointments
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS appointments_delete ON public.appointments;
CREATE POLICY appointments_delete ON public.appointments
  FOR DELETE
  TO authenticated
  USING (false);

-- -----------------------------------------------------------------------------
-- auth_internal.assert_appointment_access (view: create OR cancel)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_appointment_access()
RETURNS public.staff_members
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
BEGIN
  SELECT *
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.auth_user_id = auth.uid()
    AND sm.is_deleted = false
    AND sm.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  IF v_staff.is_bootstrap_admin AND NOT auth_internal.organization_exists() THEN
    RETURN v_staff;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.roles_permissions rp
    WHERE rp.role = v_staff.role
      AND rp.permission_key IN ('appointments.create', 'appointments.cancel')
      AND rp.is_granted = true
      AND rp.is_deleted = false
  ) THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN v_staff;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.resolve_appointment_default_duration
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.resolve_appointment_default_duration(p_branch_id uuid)
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_value jsonb;
  v_minutes int;
BEGIN
  SELECT b.organization_id
  INTO v_org_id
  FROM public.branches b
  WHERE b.id = p_branch_id
    AND b.is_deleted = false;

  IF NOT FOUND THEN
    RETURN 20;
  END IF;

  SELECT s.value_json
  INTO v_value
  FROM public.app_settings s
  WHERE s.organization_id = v_org_id
    AND s.branch_id = p_branch_id
    AND s.key = 'appointment.default_duration_minutes'
    AND s.is_deleted = false
  LIMIT 1;

  IF v_value IS NULL THEN
    SELECT s.value_json
    INTO v_value
    FROM public.app_settings s
    WHERE s.organization_id = v_org_id
      AND s.branch_id IS NULL
      AND s.key = 'appointment.default_duration_minutes'
      AND s.is_deleted = false
    LIMIT 1;
  END IF;

  IF v_value IS NULL THEN
    RETURN 20;
  END IF;

  BEGIN
    v_minutes := (v_value #>> '{}')::int;
  EXCEPTION
    WHEN OTHERS THEN
      v_minutes := (v_value ->> 'minutes')::int;
  END;

  IF v_minutes IS NULL OR v_minutes < 5 OR v_minutes > 240 THEN
    RETURN 20;
  END IF;

  RETURN v_minutes;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.assert_appointment_duration_bounds
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_appointment_duration_bounds(p_duration_minutes int)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
  IF p_duration_minutes IS NULL OR p_duration_minutes < 5 OR p_duration_minutes > 240 THEN
    RAISE EXCEPTION 'INVALID_DURATION' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.assert_appointment_branch
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_appointment_branch(p_branch_id uuid)
RETURNS public.branches
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_branch public.branches%ROWTYPE;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  IF p_branch_id IS NULL OR NOT (p_branch_id = ANY (public.jwt_branch_ids())) THEN
    RAISE EXCEPTION 'INVALID_BRANCH';
  END IF;

  SELECT *
  INTO v_branch
  FROM public.branches b
  WHERE b.id = p_branch_id
    AND b.organization_id = v_org_id
    AND b.is_deleted = false
    AND b.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_BRANCH';
  END IF;

  RETURN v_branch;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.assert_appointment_doctor
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_appointment_doctor(
  p_doctor_id uuid,
  p_branch_id uuid
)
RETURNS public.staff_members
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_doctor public.staff_members%ROWTYPE;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  SELECT *
  INTO v_doctor
  FROM public.staff_members sm
  WHERE sm.id = p_doctor_id
    AND sm.is_deleted = false
    AND sm.is_active = true
    AND sm.role = 'doctor';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_DOCTOR';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.staff_branch_assignments sba
    WHERE sba.staff_member_id = p_doctor_id
      AND sba.branch_id = p_branch_id
      AND sba.is_deleted = false
  ) THEN
    RAISE EXCEPTION 'INVALID_DOCTOR';
  END IF;

  RETURN v_doctor;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.appointment_has_overlap
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.appointment_has_overlap(
  p_branch_id uuid,
  p_doctor_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_exclude_appointment_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.appointments a
    WHERE a.branch_id = p_branch_id
      AND a.doctor_id = p_doctor_id
      AND a.is_deleted = false
      AND a.status NOT IN ('cancelled', 'no_show')
      AND (p_exclude_appointment_id IS NULL OR a.id <> p_exclude_appointment_id)
      AND a.start_time < p_end_time
      AND a.end_time > p_start_time
  );
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.find_walk_in_slot
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.find_walk_in_slot(
  p_branch_id uuid,
  p_doctor_id uuid,
  p_duration_minutes int
)
RETURNS TABLE (slot_start timestamptz, slot_end timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_tz text;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_cursor timestamptz;
  v_appt record;
BEGIN
  SELECT COALESCE(NULLIF(trim(o.timezone), ''), 'UTC')
  INTO v_org_tz
  FROM public.branches b
  JOIN public.organizations o ON o.id = b.organization_id
  WHERE b.id = p_branch_id;

  v_day_start := (date_trunc('day', now() AT TIME ZONE v_org_tz) AT TIME ZONE v_org_tz);
  v_day_end := v_day_start + interval '1 day';
  v_cursor := greatest(now(), v_day_start);

  FOR v_appt IN
    SELECT a.start_time, a.end_time
    FROM public.appointments a
    WHERE a.branch_id = p_branch_id
      AND a.doctor_id = p_doctor_id
      AND a.is_deleted = false
      AND a.status NOT IN ('cancelled', 'no_show')
      AND a.start_time >= v_day_start
      AND a.start_time < v_day_end
    ORDER BY a.start_time
  LOOP
    IF v_cursor + make_interval(mins => p_duration_minutes) <= v_appt.start_time
       AND NOT auth_internal.appointment_has_overlap(
         p_branch_id, p_doctor_id, v_cursor, v_cursor + make_interval(mins => p_duration_minutes), NULL
       ) THEN
      slot_start := v_cursor;
      slot_end := v_cursor + make_interval(mins => p_duration_minutes);
      RETURN NEXT;
      RETURN;
    END IF;

    IF v_appt.end_time > v_cursor THEN
      v_cursor := v_appt.end_time;
    END IF;
  END LOOP;

  IF v_cursor + make_interval(mins => p_duration_minutes) <= v_day_end
     AND NOT auth_internal.appointment_has_overlap(
       p_branch_id, p_doctor_id, v_cursor, v_cursor + make_interval(mins => p_duration_minutes), NULL
     ) THEN
    slot_start := v_cursor;
    slot_end := v_cursor + make_interval(mins => p_duration_minutes);
    RETURN NEXT;
  END IF;

  RETURN;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.resolve_appointment_times
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.resolve_appointment_times(
  p_start_time timestamptz,
  p_duration_minutes int,
  p_end_time timestamptz DEFAULT NULL
)
RETURNS TABLE (resolved_start timestamptz, resolved_end timestamptz, resolved_duration int)
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_duration int;
  v_end timestamptz;
BEGIN
  IF p_start_time IS NULL THEN
    RAISE EXCEPTION 'INVALID_INPUT';
  END IF;

  v_duration := p_duration_minutes;
  PERFORM auth_internal.assert_appointment_duration_bounds(v_duration);

  IF p_end_time IS NOT NULL THEN
    IF p_end_time <= p_start_time THEN
      RAISE EXCEPTION 'INVALID_INPUT';
    END IF;
    v_duration := (round(extract(epoch FROM (p_end_time - p_start_time)) / 60))::int;
    PERFORM auth_internal.assert_appointment_duration_bounds(v_duration);
    v_end := p_end_time;
  ELSE
    v_end := p_start_time + make_interval(mins => v_duration);
  END IF;

  resolved_start := p_start_time;
  resolved_end := v_end;
  resolved_duration := v_duration;
  RETURN NEXT;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.get_appointment_settings
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_appointment_settings(p_branch_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_default int;
BEGIN
  PERFORM auth_internal.assert_appointment_access();
  PERFORM auth_internal.assert_appointment_branch(p_branch_id);

  v_default := auth_internal.resolve_appointment_default_duration(p_branch_id);

  RETURN public.rpc_success(
    jsonb_build_object(
      'default_duration_minutes', v_default,
      'min_duration_minutes', 5,
      'max_duration_minutes', 240
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM IN ('FORBIDDEN', 'INVALID_BRANCH') THEN
      IF SQLERRM = 'FORBIDDEN' THEN
        RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view appointment settings.');
      END IF;
      RETURN public.rpc_error('INVALID_INPUT', 'Branch is not valid for this session.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.set_appointment_default_duration
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.set_appointment_default_duration(
  p_branch_id uuid,
  p_duration_minutes int
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_setting_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('settings.manage_branches');
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  BEGIN
    PERFORM auth_internal.assert_appointment_duration_bounds(p_duration_minutes);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Duration must be between 5 and 240 minutes.');
  END;

  IF p_branch_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.branches b
      WHERE b.id = p_branch_id
        AND b.organization_id = v_org_id
        AND b.is_deleted = false
    ) THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Branch is not valid for this organization.');
    END IF;
  END IF;

  SELECT s.id
  INTO v_setting_id
  FROM public.app_settings s
  WHERE s.organization_id = v_org_id
    AND s.branch_id IS NOT DISTINCT FROM p_branch_id
    AND s.key = 'appointment.default_duration_minutes'
    AND s.is_deleted = false
  LIMIT 1;

  IF v_setting_id IS NULL THEN
    INSERT INTO public.app_settings (organization_id, branch_id, key, value_json, created_by, updated_by)
    VALUES (v_org_id, p_branch_id, 'appointment.default_duration_minutes', to_jsonb(p_duration_minutes), auth.uid(), auth.uid());
  ELSE
    UPDATE public.app_settings s
    SET
      value_json = to_jsonb(p_duration_minutes),
      updated_at = now(),
      updated_by = auth.uid()
    WHERE s.id = v_setting_id;
  END IF;

  RETURN public.rpc_success(jsonb_build_object('default_duration_minutes', p_duration_minutes));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to change appointment settings.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.create_appointment
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_appointment(
  p_branch_id uuid,
  p_patient_id uuid,
  p_doctor_id uuid,
  p_type text,
  p_start_time timestamptz DEFAULT NULL,
  p_duration_minutes int DEFAULT NULL,
  p_end_time timestamptz DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_patient public.patients%ROWTYPE;
  v_type public.appointment_type;
  v_status public.appointment_status;
  v_duration int;
  v_start timestamptz;
  v_end timestamptz;
  v_slot record;
  v_appointment_id uuid;
BEGIN
  v_caller := auth_internal.assert_permission('appointments.create');
  PERFORM auth_internal.assert_appointment_branch(p_branch_id);
  PERFORM auth_internal.assert_appointment_doctor(p_doctor_id, p_branch_id);

  BEGIN
    v_patient := auth_internal.assert_org_patient(p_patient_id, false);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      IF SQLERRM = 'PATIENT_ARCHIVED' THEN
        RETURN public.rpc_error('PATIENT_ARCHIVED', 'This patient is archived.');
      END IF;
      RAISE;
  END;

  IF p_notes IS NOT NULL AND length(trim(p_notes)) > 2000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Notes must be 2000 characters or fewer.');
  END IF;

  BEGIN
    v_type := lower(trim(p_type))::public.appointment_type;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Type must be planned or walk_in.');
  END;

  v_duration := COALESCE(p_duration_minutes, auth_internal.resolve_appointment_default_duration(p_branch_id));

  BEGIN
    PERFORM auth_internal.assert_appointment_duration_bounds(v_duration);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Duration must be between 5 and 240 minutes.');
  END;

  IF v_type = 'planned' THEN
    IF p_start_time IS NULL THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Start time is required for planned appointments.');
    END IF;

    SELECT rt.resolved_start, rt.resolved_end
    INTO v_start, v_end
    FROM auth_internal.resolve_appointment_times(p_start_time, v_duration, p_end_time) rt;

    IF auth_internal.appointment_has_overlap(p_branch_id, p_doctor_id, v_start, v_end, NULL) THEN
      RETURN public.rpc_error('SCHEDULE_CONFLICT', 'This time slot overlaps another appointment for the doctor.');
    END IF;

    v_status := 'scheduled';
  ELSE
    SELECT s.slot_start, s.slot_end
    INTO v_start, v_end
    FROM auth_internal.find_walk_in_slot(p_branch_id, p_doctor_id, v_duration) s
    LIMIT 1;

    IF v_start IS NULL THEN
      RETURN public.rpc_error('NO_SLOT_AVAILABLE', 'No walk-in slot is available today for this doctor and duration.');
    END IF;

    v_status := 'checked_in';
  END IF;

  INSERT INTO public.appointments (
    branch_id,
    patient_id,
    doctor_id,
    start_time,
    end_time,
    type,
    status,
    queue_number,
    notes,
    created_by,
    updated_by
  )
  VALUES (
    p_branch_id,
    p_patient_id,
    p_doctor_id,
    v_start,
    v_end,
    v_type,
    v_status,
    NULL,
    NULLIF(trim(COALESCE(p_notes, '')), ''),
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_appointment_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'appointment.create',
    'appointments',
    v_appointment_id,
    jsonb_build_object(
      'branch_id', p_branch_id,
      'patient_id', p_patient_id,
      'doctor_id', p_doctor_id,
      'type', v_type::text,
      'status', v_status::text,
      'start_time', v_start,
      'end_time', v_end
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'appointment_id', v_appointment_id,
      'start_time', v_start,
      'end_time', v_end,
      'status', v_status::text,
      'type', v_type::text
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to create appointments.');
    END IF;
    IF SQLERRM = 'INVALID_DOCTOR' THEN
      RETURN public.rpc_error('INVALID_DOCTOR', 'Doctor is not valid for this branch.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.reschedule_appointment
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.reschedule_appointment(
  p_appointment_id uuid,
  p_start_time timestamptz,
  p_duration_minutes int DEFAULT NULL,
  p_end_time timestamptz DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_appt public.appointments%ROWTYPE;
  v_duration int;
  v_start timestamptz;
  v_end timestamptz;
BEGIN
  PERFORM auth_internal.assert_permission('appointments.create');

  SELECT *
  INTO v_appt
  FROM public.appointments a
  WHERE a.id = p_appointment_id
    AND a.is_deleted = false
    AND a.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Appointment was not found.');
  END IF;

  IF v_appt.status <> 'scheduled' OR v_appt.type <> 'planned' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Only scheduled planned appointments can be rescheduled.');
  END IF;

  IF p_start_time IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Start time is required.');
  END IF;

  v_duration := COALESCE(p_duration_minutes, auth_internal.resolve_appointment_default_duration(v_appt.branch_id));

  BEGIN
    PERFORM auth_internal.assert_appointment_duration_bounds(v_duration);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Duration must be between 5 and 240 minutes.');
  END;

  SELECT rt.resolved_start, rt.resolved_end
  INTO v_start, v_end
  FROM auth_internal.resolve_appointment_times(p_start_time, v_duration, p_end_time) rt;

  IF auth_internal.appointment_has_overlap(v_appt.branch_id, v_appt.doctor_id, v_start, v_end, v_appt.id) THEN
    RETURN public.rpc_error('SCHEDULE_CONFLICT', 'This time slot overlaps another appointment for the doctor.');
  END IF;

  UPDATE public.appointments a
  SET
    start_time = v_start,
    end_time = v_end,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE a.id = v_appt.id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'appointment.reschedule',
    'appointments',
    v_appt.id,
    jsonb_build_object('start_time', v_start, 'end_time', v_end)
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'appointment_id', v_appt.id,
      'start_time', v_start,
      'end_time', v_end
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to reschedule appointments.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.cancel_appointment
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.cancel_appointment(
  p_appointment_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_appt public.appointments%ROWTYPE;
BEGIN
  PERFORM auth_internal.assert_permission('appointments.cancel');

  SELECT *
  INTO v_appt
  FROM public.appointments a
  WHERE a.id = p_appointment_id
    AND a.is_deleted = false
    AND a.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Appointment was not found.');
  END IF;

  IF v_appt.status NOT IN ('scheduled', 'checked_in') THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Only scheduled or checked-in appointments can be cancelled.');
  END IF;

  IF p_reason IS NOT NULL AND length(trim(p_reason)) > 2000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Cancel reason must be 2000 characters or fewer.');
  END IF;

  UPDATE public.appointments a
  SET
    status = 'cancelled',
    cancel_reason = NULLIF(trim(COALESCE(p_reason, '')), ''),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE a.id = v_appt.id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'appointment.cancel',
    'appointments',
    v_appt.id,
    jsonb_build_object('status', 'cancelled', 'cancel_reason', NULLIF(trim(COALESCE(p_reason, '')), ''))
  );

  RETURN public.rpc_success(jsonb_build_object('appointment_id', v_appt.id, 'status', 'cancelled'));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to cancel appointments.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.update_appointment_status
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.update_appointment_status(
  p_appointment_id uuid,
  p_new_status text
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_appt public.appointments%ROWTYPE;
  v_new public.appointment_status;
  v_allowed boolean := false;
BEGIN
  SELECT *
  INTO v_appt
  FROM public.appointments a
  WHERE a.id = p_appointment_id
    AND a.is_deleted = false
    AND a.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Appointment was not found.');
  END IF;

  BEGIN
    v_new := lower(trim(p_new_status))::public.appointment_status;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Status is not valid.');
  END;

  v_allowed := CASE v_appt.status
    WHEN 'scheduled' THEN v_new IN ('checked_in', 'cancelled', 'no_show')
    WHEN 'checked_in' THEN v_new IN ('in_progress', 'cancelled', 'no_show')
    WHEN 'in_progress' THEN v_new = 'completed'
    ELSE false
  END;

  IF NOT v_allowed THEN
    RETURN public.rpc_error('INVALID_TRANSITION', 'This status change is not allowed.');
  END IF;

  IF v_new IN ('cancelled', 'no_show') THEN
    PERFORM auth_internal.assert_permission('appointments.cancel');
  ELSE
    PERFORM auth_internal.assert_permission('appointments.create');
  END IF;

  UPDATE public.appointments a
  SET
    status = v_new,
    cancel_reason = a.cancel_reason,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE a.id = v_appt.id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'appointment.status',
    'appointments',
    v_appt.id,
    jsonb_build_object('old_status', v_appt.status::text, 'new_status', v_new::text)
  );

  RETURN public.rpc_success(jsonb_build_object('appointment_id', v_appt.id, 'status', v_new::text));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to update appointment status.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.list_appointments
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.list_appointments(
  p_branch_id uuid,
  p_from timestamptz,
  p_to timestamptz,
  p_doctor_id uuid DEFAULT NULL,
  p_statuses text[] DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_items jsonb;
BEGIN
  PERFORM auth_internal.assert_appointment_access();
  PERFORM auth_internal.assert_appointment_branch(p_branch_id);

  IF p_from IS NULL OR p_to IS NULL OR p_to <= p_from THEN
    RETURN public.rpc_error('INVALID_INPUT', 'A valid time range is required.');
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', sub.id,
        'patient_id', sub.patient_id,
        'patient_name', sub.patient_name,
        'doctor_id', sub.doctor_id,
        'doctor_name', sub.doctor_name,
        'start_time', sub.start_time,
        'end_time', sub.end_time,
        'type', sub.type,
        'status', sub.status
      )
      ORDER BY sub.start_time
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM (
    SELECT
      a.id,
      a.patient_id,
      p.full_name AS patient_name,
      a.doctor_id,
      sm.full_name AS doctor_name,
      a.start_time,
      a.end_time,
      a.type::text AS type,
      a.status::text AS status
    FROM public.appointments a
    JOIN public.patients p ON p.id = a.patient_id
    JOIN public.staff_members sm ON sm.id = a.doctor_id
    WHERE a.branch_id = p_branch_id
      AND a.is_deleted = false
      AND a.start_time >= p_from
      AND a.start_time < p_to
      AND (p_doctor_id IS NULL OR a.doctor_id = p_doctor_id)
      AND (
        p_statuses IS NULL
        OR cardinality(p_statuses) = 0
        OR a.status::text = ANY (p_statuses)
      )
    ORDER BY a.start_time
  ) sub;

  RETURN public.rpc_success(jsonb_build_object('items', v_items));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM IN ('FORBIDDEN', 'INVALID_BRANCH') THEN
      IF SQLERRM = 'FORBIDDEN' THEN
        RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to list appointments.');
      END IF;
      RETURN public.rpc_error('INVALID_INPUT', 'Branch is not valid for this session.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- public RPC wrappers (SECURITY INVOKER)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_appointment_settings(p_branch_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_appointment_settings(p_branch_id);
$$;

CREATE OR REPLACE FUNCTION public.set_appointment_default_duration(
  p_duration_minutes int,
  p_branch_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.set_appointment_default_duration(p_branch_id, p_duration_minutes);
$$;

CREATE OR REPLACE FUNCTION public.create_appointment(
  p_branch_id uuid,
  p_patient_id uuid,
  p_doctor_id uuid,
  p_type text,
  p_start_time timestamptz DEFAULT NULL,
  p_duration_minutes int DEFAULT NULL,
  p_end_time timestamptz DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.create_appointment(
    p_branch_id,
    p_patient_id,
    p_doctor_id,
    p_type,
    p_start_time,
    p_duration_minutes,
    p_end_time,
    p_notes
  );
$$;

CREATE OR REPLACE FUNCTION public.reschedule_appointment(
  p_appointment_id uuid,
  p_start_time timestamptz,
  p_duration_minutes int DEFAULT NULL,
  p_end_time timestamptz DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.reschedule_appointment(
    p_appointment_id,
    p_start_time,
    p_duration_minutes,
    p_end_time
  );
$$;

CREATE OR REPLACE FUNCTION public.cancel_appointment(p_appointment_id uuid, p_reason text DEFAULT NULL)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.cancel_appointment(p_appointment_id, p_reason);
$$;

CREATE OR REPLACE FUNCTION public.update_appointment_status(p_appointment_id uuid, p_new_status text)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_appointment_status(p_appointment_id, p_new_status);
$$;

CREATE OR REPLACE FUNCTION public.list_appointments(
  p_branch_id uuid,
  p_from timestamptz,
  p_to timestamptz,
  p_doctor_id uuid DEFAULT NULL,
  p_statuses text[] DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.list_appointments(p_branch_id, p_from, p_to, p_doctor_id, p_statuses);
$$;

GRANT EXECUTE ON FUNCTION public.get_appointment_settings(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_appointment_default_duration(int, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_appointment(uuid, uuid, uuid, text, timestamptz, int, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reschedule_appointment(uuid, timestamptz, int, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_appointment(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_appointment_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_appointments(uuid, timestamptz, timestamptz, uuid, text[]) TO authenticated;
