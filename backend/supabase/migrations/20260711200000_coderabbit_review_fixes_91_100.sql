-- CodeRabbit review fixes (comment 99).
-- complete_visit: compare p_expected_updated_at against latest timestamp across all documentation sources.

CREATE OR REPLACE FUNCTION auth_internal.complete_visit(
  p_visit_id uuid,
  p_expected_updated_at timestamptz DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
  v_appt public.appointments%ROWTYPE;
  v_org_id uuid;
  v_rows_updated int;
  v_latest_doc_updated_at timestamptz;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  SELECT v.*
  INTO v_visit
  FROM public.visits v
  WHERE v.id = p_visit_id
    AND v.is_deleted = false
    AND auth_internal.staff_can_access_branch(v.branch_id)
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
  END IF;

  SELECT a.*
  INTO v_appt
  FROM public.appointments a
  WHERE a.id = v_visit.appointment_id
    AND a.is_deleted = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
  END IF;

  IF v_visit.status <> 'in_progress' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Only in-progress visits can be completed.');
  END IF;

  IF v_appt.status <> 'in_progress' THEN
    RETURN public.rpc_error(
      'APPOINTMENT_NOT_IN_PROGRESS',
      'The linked appointment is no longer in progress.'
    );
  END IF;

  IF p_expected_updated_at IS NOT NULL THEN
    SELECT GREATEST(
      COALESCE(
        (SELECT vcn.updated_at
         FROM public.visit_clinical_notes vcn
         WHERE vcn.visit_id = p_visit_id AND vcn.is_deleted = false),
        '-infinity'::timestamptz
      ),
      COALESCE(
        (SELECT MAX(vvs.updated_at)
         FROM public.visit_vital_signs vvs
         WHERE vvs.visit_id = p_visit_id AND vvs.is_deleted = false),
        '-infinity'::timestamptz
      ),
      COALESCE(
        (SELECT MAX(vi.updated_at)
         FROM public.visit_investigations vi
         WHERE vi.visit_id = p_visit_id AND vi.is_deleted = false),
        '-infinity'::timestamptz
      ),
      COALESCE(
        (SELECT MAX(tp.updated_at)
         FROM public.treatment_plans tp
         WHERE tp.visit_id = p_visit_id AND tp.is_deleted = false),
        '-infinity'::timestamptz
      ),
      COALESCE(
        (SELECT MAX(va.updated_at)
         FROM public.visit_attachments va
         WHERE va.visit_id = p_visit_id AND va.is_deleted = false),
        '-infinity'::timestamptz
      )
    )
    INTO v_latest_doc_updated_at;

    IF v_latest_doc_updated_at <> '-infinity'::timestamptz
       AND v_latest_doc_updated_at IS DISTINCT FROM p_expected_updated_at THEN
      RETURN public.rpc_error('STALE_DOCUMENTATION', 'This documentation was updated elsewhere. Reload and try again.');
    END IF;
  END IF;

  IF NOT auth_internal.visit_has_documentation(p_visit_id) THEN
    RETURN public.rpc_error(
      'DOCUMENTATION_REQUIRED_FOR_COMPLETE',
      'Enter at least one documentation field before submitting this visit.'
    );
  END IF;

  UPDATE public.visits v
  SET status = 'completed', updated_at = now(), updated_by = auth.uid()
  WHERE v.id = p_visit_id
    AND v.status = 'in_progress'
    AND v.is_deleted = false;

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
  IF v_rows_updated = 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Only in-progress visits can be completed.');
  END IF;

  UPDATE public.appointments a
  SET status = 'completed', updated_at = now(), updated_by = auth.uid()
  WHERE a.id = v_visit.appointment_id
    AND a.status = 'in_progress'
    AND a.is_deleted = false;

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
  IF v_rows_updated = 0 THEN
    RETURN public.rpc_error(
      'APPOINTMENT_NOT_IN_PROGRESS',
      'The linked appointment is no longer in progress.'
    );
  END IF;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES
    (auth.uid(), v_org_id, 'visit.complete', 'visits', p_visit_id,
     jsonb_build_object('visit_id', p_visit_id, 'status', 'completed')),
    (auth.uid(), v_org_id, 'appointment.status_completed', 'appointments', v_visit.appointment_id,
     jsonb_build_object('old_status', 'in_progress', 'new_status', 'completed'));

  RETURN public.rpc_success(jsonb_build_object(
    'visit_id', p_visit_id,
    'visit_status', 'completed',
    'appointment_id', v_visit.appointment_id,
    'appointment_status', 'completed'
  ));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to complete visits.');
    END IF;
    RAISE;
END;
$$;
