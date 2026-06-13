-- Add optional patient filter to list_appointments for patient-detail upcoming views.

DROP FUNCTION IF EXISTS public.list_appointments(uuid, timestamptz, timestamptz, uuid, text[]);
DROP FUNCTION IF EXISTS auth_internal.list_appointments(uuid, timestamptz, timestamptz, uuid, text[]);

CREATE OR REPLACE FUNCTION auth_internal.list_appointments(
  p_branch_id uuid,
  p_from timestamptz,
  p_to timestamptz,
  p_doctor_id uuid DEFAULT NULL,
  p_statuses text[] DEFAULT NULL,
  p_patient_id uuid DEFAULT NULL
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
    LEFT JOIN public.staff_members sm ON sm.id = a.doctor_id
    WHERE a.branch_id = p_branch_id
      AND a.is_deleted = false
      AND a.start_time >= p_from
      AND a.start_time < p_to
      AND (p_doctor_id IS NULL OR a.doctor_id = p_doctor_id)
      AND (p_patient_id IS NULL OR a.patient_id = p_patient_id)
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

CREATE OR REPLACE FUNCTION public.list_appointments(
  p_branch_id uuid,
  p_from timestamptz,
  p_to timestamptz,
  p_doctor_id uuid DEFAULT NULL,
  p_statuses text[] DEFAULT NULL,
  p_patient_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.list_appointments(
    p_branch_id,
    p_from,
    p_to,
    p_doctor_id,
    p_statuses,
    p_patient_id
  );
$$;

GRANT EXECUTE ON FUNCTION public.list_appointments(
  uuid,
  timestamptz,
  timestamptz,
  uuid,
  text[],
  uuid
) TO authenticated;
