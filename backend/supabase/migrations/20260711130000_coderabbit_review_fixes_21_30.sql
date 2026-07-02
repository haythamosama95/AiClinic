-- CodeRabbit review fixes (comments 24-25): complete_visit TOCTOU guard, update length validation.

-- -----------------------------------------------------------------------------
-- complete_visit: guard concurrent status changes with in_progress WHERE + row counts.
-- -----------------------------------------------------------------------------

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
  v_rows_updated int;
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

-- -----------------------------------------------------------------------------
-- update_visit_vital_sign: length validation before UPDATE.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.update_visit_vital_sign(
  p_vital_sign_id uuid,
  p_name text DEFAULT NULL,
  p_value text DEFAULT NULL,
  p_unit text DEFAULT NULL,
  p_predefined_vital_sign_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.visit_vital_signs%ROWTYPE;
  v_org_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  SELECT vvs.* INTO v_row
  FROM public.visit_vital_signs vvs
  JOIN public.visits v ON v.id = vvs.visit_id
  WHERE vvs.id = p_vital_sign_id
    AND vvs.is_deleted = false
    AND v.is_deleted = false
    AND v.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Vital sign was not found.');
  END IF;

  IF p_name IS NOT NULL AND NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Vital sign name cannot be empty.');
  END IF;

  IF p_value IS NOT NULL AND NULLIF(trim(p_value), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Vital sign value cannot be empty.');
  END IF;

  IF p_name IS NOT NULL AND length(trim(p_name)) > 100 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Vital sign name must be 100 characters or fewer.');
  END IF;

  IF p_value IS NOT NULL AND length(trim(p_value)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Vital sign value must be 200 characters or fewer.');
  END IF;

  IF p_unit IS NOT NULL AND length(trim(p_unit)) > 50 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Unit must be 50 characters or fewer.');
  END IF;

  IF p_predefined_vital_sign_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.predefined_vital_signs pvs
    WHERE pvs.id = p_predefined_vital_sign_id
      AND pvs.organization_id = v_org_id
      AND pvs.is_deleted = false
  ) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Predefined vital sign was not found.');
  END IF;

  UPDATE public.visit_vital_signs vvs
  SET
    name = COALESCE(NULLIF(trim(p_name), ''), vvs.name),
    value = COALESCE(NULLIF(trim(p_value), ''), vvs.value),
    unit = CASE WHEN p_unit IS NULL THEN vvs.unit ELSE NULLIF(trim(p_unit), '') END,
    predefined_vital_sign_id = CASE
      WHEN p_predefined_vital_sign_id IS NULL THEN vvs.predefined_vital_sign_id
      ELSE p_predefined_vital_sign_id
    END,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE vvs.id = p_vital_sign_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'visit.vital_sign.update', 'visit_vital_signs', p_vital_sign_id,
    jsonb_build_object('vital_sign_id', p_vital_sign_id));

  RETURN public.rpc_success(jsonb_build_object('vital_sign_id', p_vital_sign_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage vital signs.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- update_visit_investigation: length validation before UPDATE.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.update_visit_investigation(
  p_investigation_line_id uuid,
  p_name text DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_investigation_id uuid DEFAULT NULL,
  p_clear_investigation_id boolean DEFAULT false
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.visit_investigations%ROWTYPE;
  v_org_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  SELECT vi.* INTO v_row
  FROM public.visit_investigations vi
  JOIN public.visits v ON v.id = vi.visit_id
  WHERE vi.id = p_investigation_line_id
    AND vi.is_deleted = false
    AND v.is_deleted = false
    AND v.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Investigation line was not found.');
  END IF;

  IF p_name IS NOT NULL AND NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Investigation name cannot be empty.');
  END IF;

  IF p_name IS NOT NULL AND length(trim(p_name)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Investigation name must be 200 characters or fewer.');
  END IF;

  IF p_note IS NOT NULL AND length(trim(p_note)) > 2000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Note must be 2000 characters or fewer.');
  END IF;

  IF p_investigation_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.investigations i
    WHERE i.id = p_investigation_id
      AND i.organization_id = v_org_id
      AND i.is_deleted = false
  ) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Investigation catalog item was not found.');
  END IF;

  UPDATE public.visit_investigations vi
  SET
    name = COALESCE(NULLIF(trim(p_name), ''), vi.name),
    note = CASE WHEN p_note IS NULL THEN vi.note ELSE NULLIF(trim(p_note), '') END,
    investigation_id = CASE
      WHEN p_clear_investigation_id THEN NULL
      WHEN p_investigation_id IS NOT NULL THEN p_investigation_id
      ELSE vi.investigation_id
    END,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE vi.id = p_investigation_line_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'visit.investigation.update', 'visit_investigations', p_investigation_line_id,
    jsonb_build_object(
      'name', p_name,
      'note', p_note,
      'investigation_id', p_investigation_id,
      'clear_investigation_id', p_clear_investigation_id
    )
  );

  RETURN public.rpc_success(jsonb_build_object('investigation_line_id', p_investigation_line_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage investigations.');
    END IF;
    RAISE;
END;
$$;
