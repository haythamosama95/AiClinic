-- CodeRabbit review fixes (comments 35-36): clear stale catalog ids on free-text rename; fail-closed dev seed guard.

-- -----------------------------------------------------------------------------
-- update_treatment_plan: clear medication_id when name changes without catalog id.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.update_treatment_plan(
  p_treatment_plan_id uuid,
  p_medication_name text DEFAULT NULL,
  p_medication_id uuid DEFAULT NULL,
  p_dosage text DEFAULT NULL,
  p_frequency text DEFAULT NULL,
  p_duration text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan public.treatment_plans%ROWTYPE;
  v_org_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  SELECT tp.* INTO v_plan
  FROM public.treatment_plans tp
  JOIN public.visits v ON v.id = tp.visit_id
  WHERE tp.id = p_treatment_plan_id
    AND tp.is_deleted = false
    AND v.is_deleted = false
    AND v.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Treatment plan was not found.');
  END IF;

  IF p_medication_name IS NOT NULL AND NULLIF(trim(p_medication_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Medication name cannot be empty.');
  END IF;

  IF p_medication_name IS NOT NULL AND length(trim(p_medication_name)) > 500 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Medication name must be 500 characters or fewer.');
  END IF;

  IF p_dosage IS NOT NULL AND NULLIF(trim(p_dosage), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Dosage cannot be empty.');
  END IF;

  IF p_frequency IS NOT NULL AND NULLIF(trim(p_frequency), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Frequency cannot be empty.');
  END IF;

  IF p_duration IS NOT NULL AND NULLIF(trim(p_duration), '') IS NULL THEN
    RETURN public.rpc_error('DURATION_REQUIRED', 'Duration is required.');
  END IF;

  IF p_duration IS NOT NULL AND length(trim(p_duration)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Duration must be 200 characters or fewer.');
  END IF;

  IF p_notes IS NOT NULL AND length(trim(p_notes)) > 2000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Notes must be 2000 characters or fewer.');
  END IF;

  IF p_medication_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.medications m
    WHERE m.id = p_medication_id
      AND m.organization_id = v_org_id
      AND m.is_deleted = false
  ) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Medication catalog item was not found.');
  END IF;

  UPDATE public.treatment_plans tp
  SET
    medication_name = COALESCE(NULLIF(trim(p_medication_name), ''), tp.medication_name),
    medication_id = CASE
      WHEN p_medication_id IS NOT NULL THEN p_medication_id
      WHEN p_medication_name IS NOT NULL AND p_medication_id IS NULL THEN NULL
      ELSE tp.medication_id
    END,
    dosage = CASE WHEN p_dosage IS NULL THEN tp.dosage ELSE trim(p_dosage) END,
    frequency = CASE WHEN p_frequency IS NULL THEN tp.frequency ELSE trim(p_frequency) END,
    duration = CASE WHEN p_duration IS NULL THEN tp.duration ELSE trim(p_duration) END,
    notes = CASE WHEN p_notes IS NULL THEN tp.notes ELSE NULLIF(trim(p_notes), '') END,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE tp.id = p_treatment_plan_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(), v_org_id, 'visit.treatment_plan.update', 'treatment_plans', p_treatment_plan_id,
    jsonb_build_object('treatment_plan_id', p_treatment_plan_id)
  );

  RETURN public.rpc_success(jsonb_build_object('treatment_plan_id', p_treatment_plan_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage treatment plans.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- update_visit_vital_sign: clear predefined_vital_sign_id when name changes without catalog id.
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
      WHEN p_predefined_vital_sign_id IS NOT NULL THEN p_predefined_vital_sign_id
      WHEN p_name IS NOT NULL AND p_predefined_vital_sign_id IS NULL THEN NULL
      ELSE vvs.predefined_vital_sign_id
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
-- update_visit_investigation: clear investigation_id when name changes without catalog id.
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
      WHEN p_name IS NOT NULL AND p_investigation_id IS NULL THEN NULL
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

-- -----------------------------------------------------------------------------
-- Fail closed on dev_seed_investigations_catalog unless environment is explicit.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.dev_seed_investigations_catalog(p_names text[])
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_env text;
  v_org_id uuid;
  v_inserted int;
BEGIN
  v_env := current_setting('app.environment', true);
  IF v_env IS NULL OR v_env NOT IN ('development', 'local', 'test') THEN
    RETURN public.rpc_error(
      'FORBIDDEN',
      'dev_seed_investigations_catalog can only run in development/local/test environments.'
    );
  END IF;

  PERFORM auth_internal.assert_bootstrap_admin();
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  IF p_names IS NULL OR cardinality(p_names) = 0 THEN
    RETURN public.rpc_success(jsonb_build_object('inserted', 0, 'requested', 0));
  END IF;

  INSERT INTO public.investigations (organization_id, name, created_by, updated_by)
  SELECT v_org_id, seeds.v_name, auth.uid(), auth.uid()
  FROM (
    SELECT DISTINCT ON (lower(trim(n))) trim(n) AS v_name
    FROM unnest(p_names) AS n
    WHERE trim(n) <> '' AND length(trim(n)) <= 200
  ) AS seeds
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.investigations i
    WHERE i.organization_id = v_org_id
      AND i.is_deleted = false
      AND lower(trim(i.name)) = lower(seeds.v_name)
  );

  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  RETURN public.rpc_success(
    jsonb_build_object(
      'inserted', v_inserted,
      'requested', cardinality(p_names)
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'NOT_BOOTSTRAP_ADMIN' THEN
      RETURN public.rpc_error('NOT_BOOTSTRAP_ADMIN', 'Only the bootstrap administrator may seed investigations.');
    END IF;
    RAISE;
END;
$$;
