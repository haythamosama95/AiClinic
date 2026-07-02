-- Require at least one non-empty clinical note section before completing a visit.

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
  v_note public.visit_clinical_notes%ROWTYPE;
  v_org_id uuid;
  v_has_content boolean := false;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  BEGIN
    v_visit := auth_internal.assert_visit_branch_scope(p_visit_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
      END IF;
      RAISE;
  END;

  IF v_visit.status <> 'in_progress' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Only in-progress visits can be completed.');
  END IF;

  SELECT * INTO v_appt
  FROM public.appointments a
  WHERE a.id = v_visit.appointment_id AND a.is_deleted = false;

  IF NOT FOUND OR v_appt.status <> 'in_progress' THEN
    RETURN public.rpc_error(
      'APPOINTMENT_NOT_IN_PROGRESS',
      'The linked appointment is no longer in progress.'
    );
  END IF;

  SELECT * INTO v_note
  FROM public.visit_clinical_notes vcn
  WHERE vcn.visit_id = p_visit_id AND vcn.is_deleted = false;

  IF FOUND THEN
    IF p_expected_updated_at IS NOT NULL
       AND v_note.updated_at IS DISTINCT FROM p_expected_updated_at THEN
      RETURN public.rpc_error('STALE_DOCUMENTATION', 'This documentation was updated elsewhere. Reload and try again.');
    END IF;

    v_has_content := auth_internal.clinical_note_has_content(
      v_note.complaint, v_note.history, v_note.examination, v_note.diagnosis, v_note.plan
    );
  END IF;

  IF NOT v_has_content THEN
    RETURN public.rpc_error(
      'DOCUMENTATION_REQUIRED_FOR_COMPLETE',
      'At least one clinical section must contain text before completing the visit.'
    );
  END IF;

  UPDATE public.visits v
  SET status = 'completed', updated_at = now(), updated_by = auth.uid()
  WHERE v.id = p_visit_id;

  UPDATE public.appointments a
  SET status = 'completed', updated_at = now(), updated_by = auth.uid()
  WHERE a.id = v_visit.appointment_id;

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
