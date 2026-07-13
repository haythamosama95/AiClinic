-- Allow reverting one step backward in the appointment lifecycle so staff can
-- undo mistaken status advances (confirmed→scheduled, checked_in→confirmed,
-- in_progress→checked_in when no visit exists yet).

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
  v_org_tz text;
  v_appt_day date;
  v_today date;
  v_updated public.appointments%ROWTYPE;
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

  IF v_new IN ('cancelled', 'no_show') THEN
    PERFORM auth_internal.assert_permission('appointments.cancel');
  ELSE
    PERFORM auth_internal.assert_permission('appointments.create');
  END IF;

  IF v_appt.status = 'in_progress' AND v_new = 'completed' THEN
    RETURN public.rpc_error(
      'VISIT_REQUIRED_FOR_COMPLETION',
      'Complete the visit documentation to finish this appointment.'
    );
  END IF;

  IF v_appt.status = 'in_progress' AND v_new = 'checked_in' THEN
    IF EXISTS (
      SELECT 1
      FROM public.visits v
      WHERE v.appointment_id = v_appt.id
        AND v.is_deleted = false
    ) THEN
      RETURN public.rpc_error(
        'VISIT_IN_PROGRESS',
        'Cannot revert while a visit exists for this appointment. Complete or cancel the visit first.'
      );
    END IF;
  END IF;

  v_allowed := CASE v_appt.status
    WHEN 'scheduled' THEN v_new IN ('confirmed', 'cancelled', 'no_show')
    WHEN 'confirmed' THEN v_new IN ('scheduled', 'checked_in', 'cancelled', 'no_show')
    WHEN 'checked_in' THEN v_new IN ('confirmed', 'in_progress', 'cancelled', 'no_show')
    WHEN 'in_progress' THEN v_new IN ('checked_in')
    ELSE false
  END;

  IF NOT v_allowed THEN
    RETURN public.rpc_error('INVALID_TRANSITION', 'This status change is not allowed.');
  END IF;

  IF v_new IN ('checked_in', 'in_progress', 'completed', 'no_show') THEN
    SELECT COALESCE(NULLIF(trim(o.timezone), ''), 'UTC')
    INTO v_org_tz
    FROM public.branches b
    JOIN public.organizations o ON o.id = b.organization_id
    WHERE b.id = v_appt.branch_id;

    v_appt_day := (v_appt.start_time AT TIME ZONE v_org_tz)::date;
    v_today := (now() AT TIME ZONE v_org_tz)::date;

    IF v_today < v_appt_day THEN
      RETURN public.rpc_error(
        'INVALID_TRANSITION',
        'This status change is only allowed on or after the appointment day.'
      );
    END IF;
  END IF;

  IF v_new = 'in_progress'
    AND auth_internal.doctor_has_in_progress_appointment(
      v_appt.branch_id,
      v_appt.doctor_id,
      v_appt.id
    ) THEN
    RETURN public.rpc_error(
      'DOCTOR_ALREADY_IN_PROGRESS',
      'This doctor already has a patient in progress. Complete that visit before starting another.'
    );
  END IF;

  UPDATE public.appointments a
  SET
    status = v_new,
    cancel_reason = a.cancel_reason,
    checked_in_at = CASE
      WHEN v_new = 'checked_in' THEN COALESCE(a.checked_in_at, now())
      WHEN v_new IN ('cancelled', 'no_show') THEN NULL
      WHEN v_new IN ('scheduled', 'confirmed') THEN NULL
      ELSE a.checked_in_at
    END,
    in_progress_at = CASE
      WHEN v_new = 'in_progress' THEN now()
      WHEN v_new IN ('cancelled', 'no_show') THEN NULL
      WHEN v_new IN ('scheduled', 'confirmed', 'checked_in') THEN NULL
      ELSE a.in_progress_at
    END,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE a.id = v_appt.id
  RETURNING * INTO v_updated;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'appointment.status',
    'appointments',
    v_appt.id,
    jsonb_build_object(
      'appointment_id', v_appt.id,
      'branch_id', v_appt.branch_id,
      'patient_id', v_appt.patient_id,
      'doctor_id', v_appt.doctor_id,
      'old_status', v_appt.status::text,
      'new_status', v_new::text
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'appointment_id', v_updated.id,
      'status', v_new::text,
      'updated_at', v_updated.updated_at,
      'checked_in_at', v_updated.checked_in_at,
      'in_progress_at', v_updated.in_progress_at
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to update appointment status.');
    END IF;
    RAISE;
END;
$$;
