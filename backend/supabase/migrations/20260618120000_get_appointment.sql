-- V1-4: single-appointment read RPC for the appointment detail page.

CREATE OR REPLACE FUNCTION auth_internal.get_appointment(p_appointment_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_created_by_display text;
BEGIN
  PERFORM auth_internal.assert_appointment_access();

  IF p_appointment_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Appointment id is required.');
  END IF;

  SELECT
    a.id,
    a.branch_id,
    a.patient_id,
    p.full_name AS patient_name,
    a.doctor_id,
    sm.full_name AS doctor_name,
    a.start_time,
    a.end_time,
    a.type::text AS type,
    a.status::text AS status,
    a.queue_number,
    a.notes,
    a.cancel_reason,
    a.created_at,
    a.updated_at,
    a.created_by
  INTO v_row
  FROM public.appointments a
  JOIN public.patients p ON p.id = a.patient_id
  LEFT JOIN public.staff_members sm ON sm.id = a.doctor_id
  WHERE a.id = p_appointment_id
    AND a.is_deleted = false
    AND a.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Appointment was not found.');
  END IF;

  SELECT sm.full_name
  INTO v_created_by_display
  FROM public.staff_members sm
  WHERE sm.auth_user_id = v_row.created_by
    AND sm.is_deleted = false
  LIMIT 1;

  RETURN public.rpc_success(
    jsonb_build_object(
      'id', v_row.id,
      'branch_id', v_row.branch_id,
      'patient_id', v_row.patient_id,
      'patient_name', v_row.patient_name,
      'doctor_id', v_row.doctor_id,
      'doctor_name', v_row.doctor_name,
      'start_time', v_row.start_time,
      'end_time', v_row.end_time,
      'type', v_row.type,
      'status', v_row.status,
      'queue_number', v_row.queue_number,
      'notes', v_row.notes,
      'cancel_reason', v_row.cancel_reason,
      'created_at', v_row.created_at,
      'updated_at', v_row.updated_at,
      'created_by_display', v_created_by_display
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view appointments.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_appointment(p_appointment_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_appointment(p_appointment_id);
$$;

GRANT EXECUTE ON FUNCTION auth_internal.get_appointment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_appointment(uuid) TO authenticated;
