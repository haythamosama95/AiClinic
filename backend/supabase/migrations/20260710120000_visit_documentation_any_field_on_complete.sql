-- Require at least one visit documentation field (not only clinical note text) before completing.

CREATE OR REPLACE FUNCTION auth_internal.visit_has_documentation(p_visit_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT
    EXISTS (
      SELECT 1
      FROM public.visit_clinical_notes vcn
      WHERE vcn.visit_id = p_visit_id
        AND vcn.is_deleted = false
        AND auth_internal.clinical_note_has_content(
          vcn.complaint, vcn.history, vcn.examination, vcn.diagnosis, vcn.plan
        )
    )
    OR EXISTS (
      SELECT 1
      FROM public.visit_vital_signs vvs
      WHERE vvs.visit_id = p_visit_id
        AND vvs.is_deleted = false
    )
    OR EXISTS (
      SELECT 1
      FROM public.visit_investigations vi
      WHERE vi.visit_id = p_visit_id
        AND vi.is_deleted = false
    )
    OR EXISTS (
      SELECT 1
      FROM public.treatment_plans tp
      WHERE tp.visit_id = p_visit_id
        AND tp.is_deleted = false
    )
    OR EXISTS (
      SELECT 1
      FROM public.visit_attachments va
      WHERE va.visit_id = p_visit_id
        AND va.is_deleted = false
    );
$$;

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
  END IF;

  IF NOT auth_internal.visit_has_documentation(p_visit_id) THEN
    RETURN public.rpc_error(
      'DOCUMENTATION_REQUIRED_FOR_COMPLETE',
      'Enter at least one documentation field before submitting this visit.'
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

GRANT EXECUTE ON FUNCTION auth_internal.visit_has_documentation(uuid) TO authenticated;
