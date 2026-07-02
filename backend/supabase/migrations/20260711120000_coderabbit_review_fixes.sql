-- CodeRabbit review fixes: restrict catalog seed RPC, idempotent catalog creates, clear investigation link.

-- -----------------------------------------------------------------------------
-- Restrict seed_organization_catalog_defaults to internal callers only.
-- -----------------------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION auth_internal.seed_organization_catalog_defaults(uuid) FROM PUBLIC, authenticated, anon;

CREATE OR REPLACE FUNCTION auth_internal.seed_organization_catalog_defaults(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_organization_id IS NULL THEN
    RETURN;
  END IF;

  -- Block cross-tenant invocation when an authenticated session is present.
  IF auth.uid() IS NOT NULL
    AND p_organization_id IS DISTINCT FROM public.jwt_organization_id() THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.organizations o
    WHERE o.id = p_organization_id AND o.is_deleted = false
  ) THEN
    RETURN;
  END IF;

  INSERT INTO public.predefined_vital_signs (organization_id, name, default_unit)
  SELECT p_organization_id, seed.name, seed.default_unit
  FROM (
    VALUES
      ('Blood Pressure', 'mmHg'),
      ('Heart Rate', 'bpm'),
      ('Temperature', '°C'),
      ('Respiratory Rate', '/min'),
      ('Oxygen Saturation', '%'),
      ('Weight', 'kg'),
      ('Height', 'cm')
  ) AS seed(name, default_unit)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.predefined_vital_signs pvs
    WHERE pvs.organization_id = p_organization_id
      AND pvs.is_deleted = false
      AND lower(trim(pvs.name)) = lower(trim(seed.name))
  );

  INSERT INTO public.medications (organization_id, name)
  SELECT p_organization_id, seed.name
  FROM (
    VALUES
      ('Amoxicillin'), ('Ibuprofen'), ('Paracetamol'), ('Omeprazole'), ('Metformin'),
      ('Atorvastatin'), ('Amlodipine'), ('Salbutamol'), ('Cetirizine'), ('Azithromycin')
  ) AS seed(name)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.medications m
    WHERE m.organization_id = p_organization_id
      AND m.is_deleted = false
      AND lower(trim(m.name)) = lower(trim(seed.name))
  );

  INSERT INTO public.investigations (organization_id, name)
  SELECT p_organization_id, seed.name
  FROM (
    VALUES
      ('Complete Blood Count'), ('Lipid Panel'), ('Chest X-Ray'), ('Urinalysis'),
      ('Fasting Blood Glucose'), ('Liver Function Test'), ('Thyroid Panel'),
      ('ECG'), ('Abdominal Ultrasound'), ('HbA1c')
  ) AS seed(name)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.investigations i
    WHERE i.organization_id = p_organization_id
      AND i.is_deleted = false
      AND lower(trim(i.name)) = lower(trim(seed.name))
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- Idempotent catalog create RPCs under concurrent requests.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_catalog_medication(p_name text)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_name text;
  v_existing public.medications%ROWTYPE;
  v_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();
  v_name := trim(COALESCE(p_name, ''));

  IF v_name = '' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Medication name is required.');
  END IF;

  IF length(v_name) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Medication name must be 200 characters or fewer.');
  END IF;

  SELECT * INTO v_existing
  FROM public.medications m
  WHERE m.organization_id = v_org_id
    AND m.is_deleted = false
    AND lower(trim(m.name)) = lower(v_name)
  LIMIT 1;

  IF FOUND THEN
    RETURN public.rpc_success(jsonb_build_object('id', v_existing.id, 'name', v_existing.name, 'created', false));
  END IF;

  INSERT INTO public.medications (organization_id, name, created_by, updated_by)
  VALUES (v_org_id, v_name, auth.uid(), auth.uid())
  RETURNING id INTO v_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'catalog.medication.create', 'medications', v_id, jsonb_build_object('name', v_name));

  RETURN public.rpc_success(jsonb_build_object('id', v_id, 'name', v_name, 'created', true));
EXCEPTION
  WHEN unique_violation THEN
    SELECT * INTO v_existing
    FROM public.medications m
    WHERE m.organization_id = v_org_id
      AND m.is_deleted = false
      AND lower(trim(m.name)) = lower(v_name)
    LIMIT 1;

    IF FOUND THEN
      RETURN public.rpc_success(jsonb_build_object('id', v_existing.id, 'name', v_existing.name, 'created', false));
    END IF;
    RAISE;
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to create catalog medications.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.create_catalog_investigation(p_name text)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_name text;
  v_existing public.investigations%ROWTYPE;
  v_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();
  v_name := trim(COALESCE(p_name, ''));

  IF v_name = '' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Investigation name is required.');
  END IF;

  IF length(v_name) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Investigation name must be 200 characters or fewer.');
  END IF;

  SELECT * INTO v_existing
  FROM public.investigations i
  WHERE i.organization_id = v_org_id
    AND i.is_deleted = false
    AND lower(trim(i.name)) = lower(v_name)
  LIMIT 1;

  IF FOUND THEN
    RETURN public.rpc_success(jsonb_build_object('id', v_existing.id, 'name', v_existing.name, 'created', false));
  END IF;

  INSERT INTO public.investigations (organization_id, name, created_by, updated_by)
  VALUES (v_org_id, v_name, auth.uid(), auth.uid())
  RETURNING id INTO v_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'catalog.investigation.create', 'investigations', v_id, jsonb_build_object('name', v_name));

  RETURN public.rpc_success(jsonb_build_object('id', v_id, 'name', v_name, 'created', true));
EXCEPTION
  WHEN unique_violation THEN
    SELECT * INTO v_existing
    FROM public.investigations i
    WHERE i.organization_id = v_org_id
      AND i.is_deleted = false
      AND lower(trim(i.name)) = lower(v_name)
    LIMIT 1;

    IF FOUND THEN
      RETURN public.rpc_success(jsonb_build_object('id', v_existing.id, 'name', v_existing.name, 'created', false));
    END IF;
    RAISE;
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to create catalog investigations.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.create_predefined_vital_sign(
  p_name text,
  p_default_unit text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_name text;
  v_unit text;
  v_existing public.predefined_vital_signs%ROWTYPE;
  v_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();
  v_name := trim(COALESCE(p_name, ''));
  v_unit := NULLIF(trim(COALESCE(p_default_unit, '')), '');

  IF v_name = '' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Vital sign name is required.');
  END IF;

  IF length(v_name) > 100 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Vital sign name must be 100 characters or fewer.');
  END IF;

  IF v_unit IS NOT NULL AND length(v_unit) > 50 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Default unit must be 50 characters or fewer.');
  END IF;

  SELECT * INTO v_existing
  FROM public.predefined_vital_signs pvs
  WHERE pvs.organization_id = v_org_id
    AND pvs.is_deleted = false
    AND lower(trim(pvs.name)) = lower(v_name)
  LIMIT 1;

  IF FOUND THEN
    RETURN public.rpc_success(jsonb_build_object(
      'id', v_existing.id, 'name', v_existing.name, 'default_unit', v_existing.default_unit, 'created', false
    ));
  END IF;

  INSERT INTO public.predefined_vital_signs (organization_id, name, default_unit, created_by, updated_by)
  VALUES (v_org_id, v_name, v_unit, auth.uid(), auth.uid())
  RETURNING id INTO v_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'catalog.vital_sign.create', 'predefined_vital_signs', v_id, jsonb_build_object('name', v_name));

  RETURN public.rpc_success(jsonb_build_object('id', v_id, 'name', v_name, 'default_unit', v_unit, 'created', true));
EXCEPTION
  WHEN unique_violation THEN
    SELECT * INTO v_existing
    FROM public.predefined_vital_signs pvs
    WHERE pvs.organization_id = v_org_id
      AND pvs.is_deleted = false
      AND lower(trim(pvs.name)) = lower(v_name)
    LIMIT 1;

    IF FOUND THEN
      RETURN public.rpc_success(jsonb_build_object(
        'id', v_existing.id, 'name', v_existing.name, 'default_unit', v_existing.default_unit, 'created', false
      ));
    END IF;
    RAISE;
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to create predefined vital signs.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- Allow clearing investigation catalog link on update.
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

DROP FUNCTION IF EXISTS public.update_visit_investigation(uuid, text, text, uuid);

CREATE OR REPLACE FUNCTION public.update_visit_investigation(
  p_investigation_line_id uuid,
  p_name text DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_investigation_id uuid DEFAULT NULL,
  p_clear_investigation_id boolean DEFAULT false
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_visit_investigation(
    p_investigation_line_id, p_name, p_note, p_investigation_id, p_clear_investigation_id
  );
$$;

GRANT EXECUTE ON FUNCTION auth_internal.update_visit_investigation(uuid, text, text, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_visit_investigation(uuid, text, text, uuid, boolean) TO authenticated;

-- -----------------------------------------------------------------------------
-- Atomic optimistic concurrency + correct audit record_id for documentation save.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.save_visit_documentation(
  p_visit_id uuid,
  p_expected_updated_at timestamptz,
  p_complaint text DEFAULT NULL,
  p_history text DEFAULT NULL,
  p_examination text DEFAULT NULL,
  p_diagnosis text DEFAULT NULL,
  p_plan text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
  v_note public.visit_clinical_notes%ROWTYPE;
  v_org_id uuid;
  v_note_id uuid;
  v_new_updated_at timestamptz;
  v_rows_updated int;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  IF p_expected_updated_at IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
  END IF;

  BEGIN
    v_visit := auth_internal.assert_visit_branch_scope(p_visit_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
      END IF;
      RAISE;
  END;

  IF length(COALESCE(p_complaint, '')) > 10000
     OR length(COALESCE(p_history, '')) > 10000
     OR length(COALESCE(p_examination, '')) > 10000
     OR length(COALESCE(p_diagnosis, '')) > 10000
     OR length(COALESCE(p_plan, '')) > 10000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Each clinical section must be 10000 characters or fewer.');
  END IF;

  PERFORM 1
  FROM public.visits v
  WHERE v.id = p_visit_id
  FOR UPDATE;

  SELECT *
  INTO v_note
  FROM public.visit_clinical_notes vcn
  WHERE vcn.visit_id = p_visit_id
    AND vcn.is_deleted = false;

  IF FOUND THEN
    UPDATE public.visit_clinical_notes vcn
    SET
      complaint = p_complaint,
      history = p_history,
      examination = p_examination,
      diagnosis = p_diagnosis,
      plan = p_plan,
      updated_at = now(),
      updated_by = auth.uid()
    WHERE vcn.id = v_note.id
      AND vcn.updated_at = p_expected_updated_at
    RETURNING vcn.id, vcn.updated_at INTO v_note_id, v_new_updated_at;

    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
    IF v_rows_updated = 0 THEN
      RETURN public.rpc_error('STALE_DOCUMENTATION', 'This documentation was updated elsewhere. Reload and try again.');
    END IF;
  ELSE
    SELECT updated_at
    INTO v_new_updated_at
    FROM public.visits v
    WHERE v.id = p_visit_id;

    IF v_new_updated_at IS DISTINCT FROM p_expected_updated_at THEN
      RETURN public.rpc_error('STALE_DOCUMENTATION', 'This documentation was updated elsewhere. Reload and try again.');
    END IF;

    INSERT INTO public.visit_clinical_notes (
      visit_id, complaint, history, examination, diagnosis, plan, created_by, updated_by
    )
    VALUES (
      p_visit_id, p_complaint, p_history, p_examination, p_diagnosis, p_plan, auth.uid(), auth.uid()
    )
    RETURNING id, updated_at INTO v_note_id, v_new_updated_at;
  END IF;

  UPDATE public.visits v
  SET updated_at = now(), updated_by = auth.uid()
  WHERE v.id = p_visit_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(), v_org_id, 'visit.documentation_save', 'visit_clinical_notes', v_note_id,
    jsonb_build_object('visit_id', p_visit_id)
  );

  RETURN public.rpc_success(jsonb_build_object('visit_id', p_visit_id, 'updated_at', v_new_updated_at));
EXCEPTION
  WHEN unique_violation THEN
    RETURN public.rpc_error('STALE_DOCUMENTATION', 'This documentation was updated elsewhere. Reload and try again.');
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to edit visit documentation.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- Backfill legacy soap_notes into visit_clinical_notes when table still exists.
-- -----------------------------------------------------------------------------

DO $$
BEGIN
  IF to_regclass('public.soap_notes') IS NOT NULL THEN
    INSERT INTO public.visit_clinical_notes (
      visit_id,
      complaint,
      examination,
      diagnosis,
      plan,
      created_at,
      created_by,
      updated_at,
      updated_by
    )
    SELECT
      sn.visit_id,
      sn.subjective,
      sn.objective,
      sn.assessment,
      sn.plan,
      sn.created_at,
      sn.created_by,
      sn.updated_at,
      sn.updated_by
    FROM public.soap_notes sn
    WHERE sn.is_deleted = false
      AND NOT EXISTS (
        SELECT 1
        FROM public.visit_clinical_notes vcn
        WHERE vcn.visit_id = sn.visit_id
          AND vcn.is_deleted = false
      );

    DROP TABLE public.soap_notes;
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- Fail closed on dev_seed_medications_catalog unless environment is explicit.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.dev_seed_medications_catalog(p_names text[])
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
      'dev_seed_medications_catalog can only run in development/local/test environments.'
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

  INSERT INTO public.medications (organization_id, name, created_by, updated_by)
  SELECT v_org_id, seeds.v_name, auth.uid(), auth.uid()
  FROM (
    SELECT DISTINCT ON (lower(trim(n))) trim(n) AS v_name
    FROM unnest(p_names) AS n
    WHERE trim(n) <> '' AND length(trim(n)) <= 200
  ) AS seeds
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.medications m
    WHERE m.organization_id = v_org_id
      AND m.is_deleted = false
      AND lower(trim(m.name)) = lower(seeds.v_name)
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
      RETURN public.rpc_error('NOT_BOOTSTRAP_ADMIN', 'Only the bootstrap administrator may seed medications.');
    END IF;
    RAISE;
END;
$$;
