-- =============================================================================
-- Visits Page Redesign (013): clinical notes, catalogs, vital signs, investigations
-- Spec: specs/013-visits/plan.md
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Organization-scoped catalog tables
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.medications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT medications_name_length CHECK (length(name) <= 200)
);

CREATE UNIQUE INDEX IF NOT EXISTS medications_org_name_unique
  ON public.medications (organization_id, lower(trim(name)))
  WHERE is_deleted = false;

CREATE TABLE IF NOT EXISTS public.investigations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT investigations_name_length CHECK (length(name) <= 200)
);

CREATE UNIQUE INDEX IF NOT EXISTS investigations_org_name_unique
  ON public.investigations (organization_id, lower(trim(name)))
  WHERE is_deleted = false;

CREATE TABLE IF NOT EXISTS public.predefined_vital_signs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
  name text NOT NULL,
  default_unit text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT predefined_vital_signs_name_length CHECK (length(name) <= 100),
  CONSTRAINT predefined_vital_signs_unit_length CHECK (default_unit IS NULL OR length(default_unit) <= 50)
);

CREATE UNIQUE INDEX IF NOT EXISTS predefined_vital_signs_org_name_unique
  ON public.predefined_vital_signs (organization_id, lower(trim(name)))
  WHERE is_deleted = false;

-- -----------------------------------------------------------------------------
-- visit_clinical_notes (replaces soap_notes)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.visit_clinical_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL REFERENCES public.visits (id),
  complaint text,
  history text,
  examination text,
  diagnosis text,
  plan text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz DEFAULT now(),
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT visit_clinical_notes_visit_id_unique UNIQUE (visit_id),
  CONSTRAINT visit_clinical_notes_complaint_length CHECK (length(coalesce(complaint, '')) <= 10000),
  CONSTRAINT visit_clinical_notes_history_length CHECK (length(coalesce(history, '')) <= 10000),
  CONSTRAINT visit_clinical_notes_examination_length CHECK (length(coalesce(examination, '')) <= 10000),
  CONSTRAINT visit_clinical_notes_diagnosis_length CHECK (length(coalesce(diagnosis, '')) <= 10000),
  CONSTRAINT visit_clinical_notes_plan_length CHECK (length(coalesce(plan, '')) <= 10000)
);

-- -----------------------------------------------------------------------------
-- Visit child records
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.visit_vital_signs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL REFERENCES public.visits (id),
  predefined_vital_sign_id uuid REFERENCES public.predefined_vital_signs (id),
  name text NOT NULL,
  value text NOT NULL,
  unit text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT visit_vital_signs_name_length CHECK (length(name) <= 100),
  CONSTRAINT visit_vital_signs_value_length CHECK (length(value) <= 200),
  CONSTRAINT visit_vital_signs_unit_length CHECK (unit IS NULL OR length(unit) <= 50)
);

CREATE INDEX IF NOT EXISTS visit_vital_signs_visit_idx
  ON public.visit_vital_signs (visit_id)
  WHERE is_deleted = false;

CREATE TABLE IF NOT EXISTS public.visit_investigations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL REFERENCES public.visits (id),
  investigation_id uuid REFERENCES public.investigations (id),
  name text NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT visit_investigations_name_length CHECK (length(name) <= 200),
  CONSTRAINT visit_investigations_note_length CHECK (note IS NULL OR length(note) <= 2000)
);

CREATE INDEX IF NOT EXISTS visit_investigations_visit_idx
  ON public.visit_investigations (visit_id)
  WHERE is_deleted = false;

-- -----------------------------------------------------------------------------
-- treatment_plans: medication_id, duration-only
-- -----------------------------------------------------------------------------

ALTER TABLE public.treatment_plans
  ADD COLUMN IF NOT EXISTS medication_id uuid REFERENCES public.medications (id);

UPDATE public.treatment_plans tp
SET duration = coalesce(
  nullif(trim(tp.duration), ''),
  (tp.end_date - tp.start_date)::text || ' days'
)
WHERE tp.is_deleted = false
  AND nullif(trim(coalesce(tp.duration, '')), '') IS NULL
  AND tp.start_date IS NOT NULL
  AND tp.end_date IS NOT NULL;

ALTER TABLE public.treatment_plans
  DROP CONSTRAINT IF EXISTS treatment_plans_end_after_start;

ALTER TABLE public.treatment_plans
  DROP COLUMN IF EXISTS start_date,
  DROP COLUMN IF EXISTS end_date;

-- -----------------------------------------------------------------------------
-- Drop legacy soap_notes
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS public.soap_notes;

-- -----------------------------------------------------------------------------
-- Audit triggers and RLS
-- -----------------------------------------------------------------------------

SELECT public.apply_standard_audit_triggers('public.medications'::regclass);
SELECT public.apply_standard_audit_triggers('public.investigations'::regclass);
SELECT public.apply_standard_audit_triggers('public.predefined_vital_signs'::regclass);
SELECT public.apply_standard_audit_triggers('public.visit_clinical_notes'::regclass);
SELECT public.apply_standard_audit_triggers('public.visit_vital_signs'::regclass);
SELECT public.apply_standard_audit_triggers('public.visit_investigations'::regclass);

ALTER TABLE public.medications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investigations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.predefined_vital_signs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_clinical_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_vital_signs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_investigations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS medications_select ON public.medications;
CREATE POLICY medications_select ON public.medications
  FOR SELECT TO authenticated
  USING (is_deleted = false AND organization_id = public.jwt_organization_id());

DROP POLICY IF EXISTS medications_insert ON public.medications;
CREATE POLICY medications_insert ON public.medications FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS medications_update ON public.medications;
CREATE POLICY medications_update ON public.medications FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS medications_delete ON public.medications;
CREATE POLICY medications_delete ON public.medications FOR DELETE TO authenticated USING (false);

DROP POLICY IF EXISTS investigations_select ON public.investigations;
CREATE POLICY investigations_select ON public.investigations
  FOR SELECT TO authenticated
  USING (is_deleted = false AND organization_id = public.jwt_organization_id());

DROP POLICY IF EXISTS investigations_insert ON public.investigations;
CREATE POLICY investigations_insert ON public.investigations FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS investigations_update ON public.investigations;
CREATE POLICY investigations_update ON public.investigations FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS investigations_delete ON public.investigations;
CREATE POLICY investigations_delete ON public.investigations FOR DELETE TO authenticated USING (false);

DROP POLICY IF EXISTS predefined_vital_signs_select ON public.predefined_vital_signs;
CREATE POLICY predefined_vital_signs_select ON public.predefined_vital_signs
  FOR SELECT TO authenticated
  USING (is_deleted = false AND organization_id = public.jwt_organization_id());

DROP POLICY IF EXISTS predefined_vital_signs_insert ON public.predefined_vital_signs;
CREATE POLICY predefined_vital_signs_insert ON public.predefined_vital_signs FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS predefined_vital_signs_update ON public.predefined_vital_signs;
CREATE POLICY predefined_vital_signs_update ON public.predefined_vital_signs FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS predefined_vital_signs_delete ON public.predefined_vital_signs;
CREATE POLICY predefined_vital_signs_delete ON public.predefined_vital_signs FOR DELETE TO authenticated USING (false);

DROP POLICY IF EXISTS visit_clinical_notes_select ON public.visit_clinical_notes;
CREATE POLICY visit_clinical_notes_select ON public.visit_clinical_notes
  FOR SELECT TO authenticated
  USING (
    is_deleted = false
    AND EXISTS (
      SELECT 1 FROM public.visits v
      WHERE v.id = visit_clinical_notes.visit_id
        AND v.is_deleted = false
        AND v.branch_id = ANY (public.jwt_branch_ids())
    )
  );

DROP POLICY IF EXISTS visit_clinical_notes_insert ON public.visit_clinical_notes;
CREATE POLICY visit_clinical_notes_insert ON public.visit_clinical_notes FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS visit_clinical_notes_update ON public.visit_clinical_notes;
CREATE POLICY visit_clinical_notes_update ON public.visit_clinical_notes FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS visit_clinical_notes_delete ON public.visit_clinical_notes;
CREATE POLICY visit_clinical_notes_delete ON public.visit_clinical_notes FOR DELETE TO authenticated USING (false);

DROP POLICY IF EXISTS visit_vital_signs_select ON public.visit_vital_signs;
CREATE POLICY visit_vital_signs_select ON public.visit_vital_signs
  FOR SELECT TO authenticated
  USING (
    is_deleted = false
    AND EXISTS (
      SELECT 1 FROM public.visits v
      WHERE v.id = visit_vital_signs.visit_id
        AND v.is_deleted = false
        AND v.branch_id = ANY (public.jwt_branch_ids())
    )
  );

DROP POLICY IF EXISTS visit_vital_signs_insert ON public.visit_vital_signs;
CREATE POLICY visit_vital_signs_insert ON public.visit_vital_signs FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS visit_vital_signs_update ON public.visit_vital_signs;
CREATE POLICY visit_vital_signs_update ON public.visit_vital_signs FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS visit_vital_signs_delete ON public.visit_vital_signs;
CREATE POLICY visit_vital_signs_delete ON public.visit_vital_signs FOR DELETE TO authenticated USING (false);

DROP POLICY IF EXISTS visit_investigations_select ON public.visit_investigations;
CREATE POLICY visit_investigations_select ON public.visit_investigations
  FOR SELECT TO authenticated
  USING (
    is_deleted = false
    AND EXISTS (
      SELECT 1 FROM public.visits v
      WHERE v.id = visit_investigations.visit_id
        AND v.is_deleted = false
        AND v.branch_id = ANY (public.jwt_branch_ids())
    )
  );

DROP POLICY IF EXISTS visit_investigations_insert ON public.visit_investigations;
CREATE POLICY visit_investigations_insert ON public.visit_investigations FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS visit_investigations_update ON public.visit_investigations;
CREATE POLICY visit_investigations_update ON public.visit_investigations FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS visit_investigations_delete ON public.visit_investigations;
CREATE POLICY visit_investigations_delete ON public.visit_investigations FOR DELETE TO authenticated USING (false);

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.clinical_note_has_content(
  p_complaint text,
  p_history text,
  p_examination text,
  p_diagnosis text,
  p_plan text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT
    length(trim(COALESCE(p_complaint, ''))) > 0
    OR length(trim(COALESCE(p_history, ''))) > 0
    OR length(trim(COALESCE(p_examination, ''))) > 0
    OR length(trim(COALESCE(p_diagnosis, ''))) > 0
    OR length(trim(COALESCE(p_plan, ''))) > 0;
$$;

CREATE OR REPLACE FUNCTION auth_internal.assert_catalog_read_access()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT auth_internal.staff_has_visit_clinical_access() THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.save_visit_documentation
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
  v_current_updated_at timestamptz;
  v_new_updated_at timestamptz;
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

  SELECT *
  INTO v_note
  FROM public.visit_clinical_notes vcn
  WHERE vcn.visit_id = p_visit_id
    AND vcn.is_deleted = false;

  IF FOUND THEN
    v_current_updated_at := v_note.updated_at;
  ELSE
    v_current_updated_at := v_visit.updated_at;
  END IF;

  IF v_current_updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RETURN public.rpc_error('STALE_DOCUMENTATION', 'This documentation was updated elsewhere. Reload and try again.');
  END IF;

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
    RETURNING updated_at INTO v_new_updated_at;
  ELSE
    INSERT INTO public.visit_clinical_notes (
      visit_id, complaint, history, examination, diagnosis, plan, created_by, updated_by
    )
    VALUES (
      p_visit_id, p_complaint, p_history, p_examination, p_diagnosis, p_plan, auth.uid(), auth.uid()
    )
    RETURNING updated_at INTO v_new_updated_at;
  END IF;

  UPDATE public.visits v
  SET updated_at = now(), updated_by = auth.uid()
  WHERE v.id = p_visit_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(), v_org_id, 'visit.documentation_save', 'visit_clinical_notes', p_visit_id,
    jsonb_build_object('visit_id', p_visit_id)
  );

  RETURN public.rpc_success(jsonb_build_object('visit_id', p_visit_id, 'updated_at', v_new_updated_at));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to edit visit documentation.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.complete_visit (clinical note required)
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

-- -----------------------------------------------------------------------------
-- auth_internal.create_treatment_plan / update_treatment_plan (duration-only)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_treatment_plan(
  p_visit_id uuid,
  p_medication_name text,
  p_dosage text,
  p_frequency text,
  p_duration text,
  p_notes text DEFAULT NULL,
  p_medication_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
  v_plan_id uuid;
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

  IF NULLIF(trim(p_medication_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Medication name is required.');
  END IF;

  IF length(trim(p_medication_name)) > 500 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Medication name must be 500 characters or fewer.');
  END IF;

  IF NULLIF(trim(p_dosage), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Dosage is required.');
  END IF;

  IF NULLIF(trim(p_frequency), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Frequency is required.');
  END IF;

  IF NULLIF(trim(p_duration), '') IS NULL THEN
    RETURN public.rpc_error('DURATION_REQUIRED', 'Duration is required.');
  END IF;

  IF length(trim(p_duration)) > 200 THEN
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

  INSERT INTO public.treatment_plans (
    visit_id, patient_id, medication_name, medication_id, dosage, frequency, duration, notes, created_by, updated_by
  )
  VALUES (
    p_visit_id, v_visit.patient_id, trim(p_medication_name), p_medication_id,
    trim(p_dosage), trim(p_frequency), trim(p_duration), NULLIF(trim(p_notes), ''),
    auth.uid(), auth.uid()
  )
  RETURNING id INTO v_plan_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(), v_org_id, 'visit.treatment_plan.create', 'treatment_plans', v_plan_id,
    jsonb_build_object('visit_id', p_visit_id, 'treatment_plan_id', v_plan_id)
  );

  RETURN public.rpc_success(jsonb_build_object('treatment_plan_id', v_plan_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage treatment plans.');
    END IF;
    RAISE;
END;
$$;

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
    medication_id = CASE WHEN p_medication_id IS NULL THEN tp.medication_id ELSE p_medication_id END,
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
-- Catalog search and create RPCs
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.search_medications(
  p_query text DEFAULT '',
  p_limit int DEFAULT 20
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_limit int;
  v_query text;
  v_items jsonb;
BEGIN
  PERFORM auth_internal.assert_catalog_read_access();
  v_org_id := public.jwt_organization_id();
  v_limit := GREATEST(1, LEAST(COALESCE(p_limit, 20), 50));
  v_query := trim(COALESCE(p_query, ''));

  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', sub.id, 'name', sub.name) ORDER BY sub.name), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT m.id, m.name
    FROM public.medications m
    WHERE m.organization_id = v_org_id
      AND m.is_deleted = false
      AND (v_query = '' OR m.name ILIKE '%' || v_query || '%')
    ORDER BY m.name ASC
    LIMIT v_limit
  ) sub;

  RETURN public.rpc_success(jsonb_build_object('items', COALESCE(v_items, '[]'::jsonb)));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to search medications.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.search_investigations(
  p_query text DEFAULT '',
  p_limit int DEFAULT 20
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_limit int;
  v_query text;
  v_items jsonb;
BEGIN
  PERFORM auth_internal.assert_catalog_read_access();
  v_org_id := public.jwt_organization_id();
  v_limit := GREATEST(1, LEAST(COALESCE(p_limit, 20), 50));
  v_query := trim(COALESCE(p_query, ''));

  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', sub.id, 'name', sub.name) ORDER BY sub.name), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT i.id, i.name
    FROM public.investigations i
    WHERE i.organization_id = v_org_id
      AND i.is_deleted = false
      AND (v_query = '' OR i.name ILIKE '%' || v_query || '%')
    ORDER BY i.name ASC
    LIMIT v_limit
  ) sub;

  RETURN public.rpc_success(jsonb_build_object('items', COALESCE(v_items, '[]'::jsonb)));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to search investigations.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.list_predefined_vital_signs()
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_items jsonb;
BEGIN
  PERFORM auth_internal.assert_catalog_read_access();
  v_org_id := public.jwt_organization_id();

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object('id', pvs.id, 'name', pvs.name, 'default_unit', pvs.default_unit)
      ORDER BY pvs.name
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM public.predefined_vital_signs pvs
  WHERE pvs.organization_id = v_org_id AND pvs.is_deleted = false;

  RETURN public.rpc_success(jsonb_build_object('items', COALESCE(v_items, '[]'::jsonb)));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to list vital signs.');
    END IF;
    RAISE;
END;
$$;

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
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to create predefined vital signs.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- Vital sign CRUD RPCs
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_visit_vital_sign(
  p_visit_id uuid,
  p_name text,
  p_value text,
  p_unit text DEFAULT NULL,
  p_predefined_vital_sign_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
  v_org_id uuid;
  v_id uuid;
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

  IF NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Vital sign name is required.');
  END IF;

  IF NULLIF(trim(p_value), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Vital sign value is required.');
  END IF;

  IF length(trim(p_name)) > 100 OR length(trim(p_value)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Vital sign name or value exceeds maximum length.');
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

  INSERT INTO public.visit_vital_signs (
    visit_id, predefined_vital_sign_id, name, value, unit, created_by, updated_by
  )
  VALUES (
    p_visit_id, p_predefined_vital_sign_id, trim(p_name), trim(p_value),
    NULLIF(trim(p_unit), ''), auth.uid(), auth.uid()
  )
  RETURNING id INTO v_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'visit.vital_sign.create', 'visit_vital_signs', v_id,
    jsonb_build_object('visit_id', p_visit_id, 'vital_sign_id', v_id));

  RETURN public.rpc_success(jsonb_build_object('vital_sign_id', v_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage vital signs.');
    END IF;
    RAISE;
END;
$$;

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

CREATE OR REPLACE FUNCTION auth_internal.archive_visit_vital_sign(p_vital_sign_id uuid)
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

  UPDATE public.visit_vital_signs vvs
  SET is_deleted = true, deleted_at = now(), deleted_by = auth.uid(), updated_at = now(), updated_by = auth.uid()
  WHERE vvs.id = p_vital_sign_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'visit.vital_sign.archive', 'visit_vital_signs', p_vital_sign_id,
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
-- Investigation CRUD RPCs
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_visit_investigation(
  p_visit_id uuid,
  p_name text,
  p_note text DEFAULT NULL,
  p_investigation_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
  v_org_id uuid;
  v_id uuid;
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

  IF NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Investigation name is required.');
  END IF;

  IF length(trim(p_name)) > 200 THEN
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

  INSERT INTO public.visit_investigations (
    visit_id, investigation_id, name, note, created_by, updated_by
  )
  VALUES (
    p_visit_id, p_investigation_id, trim(p_name), NULLIF(trim(p_note), ''), auth.uid(), auth.uid()
  )
  RETURNING id INTO v_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'visit.investigation.create', 'visit_investigations', v_id,
    jsonb_build_object('visit_id', p_visit_id, 'investigation_line_id', v_id));

  RETURN public.rpc_success(jsonb_build_object('investigation_line_id', v_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage investigations.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.update_visit_investigation(
  p_investigation_line_id uuid,
  p_name text DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_investigation_id uuid DEFAULT NULL
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
    investigation_id = CASE WHEN p_investigation_id IS NULL THEN vi.investigation_id ELSE p_investigation_id END,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE vi.id = p_investigation_line_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'visit.investigation.update', 'visit_investigations', p_investigation_line_id,
    jsonb_build_object('investigation_line_id', p_investigation_line_id));

  RETURN public.rpc_success(jsonb_build_object('investigation_line_id', p_investigation_line_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage investigations.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.archive_visit_investigation(p_investigation_line_id uuid)
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

  UPDATE public.visit_investigations vi
  SET is_deleted = true, deleted_at = now(), deleted_by = auth.uid(), updated_at = now(), updated_by = auth.uid()
  WHERE vi.id = p_investigation_line_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'visit.investigation.archive', 'visit_investigations', p_investigation_line_id,
    jsonb_build_object('investigation_line_id', p_investigation_line_id));

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
-- auth_internal.get_visit (documentation, vital signs, investigations)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_visit(p_visit_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
  v_note public.visit_clinical_notes%ROWTYPE;
  v_doctor_name text;
  v_has_clinical boolean;
  v_has_patients_view boolean;
  v_payload jsonb;
  v_documentation jsonb;
  v_vital_signs jsonb;
  v_investigations jsonb;
  v_treatment_plans jsonb;
  v_attachments jsonb;
BEGIN
  BEGIN
    v_visit := auth_internal.assert_visit_branch_scope(p_visit_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
      END IF;
      RAISE;
  END;

  v_has_clinical := auth_internal.staff_has_visit_clinical_access();
  v_has_patients_view := EXISTS (
    SELECT 1
    FROM public.current_staff_member_row() sm
    JOIN public.roles_permissions rp ON rp.role = sm.role
    WHERE rp.permission_key = 'patients.view'
      AND rp.is_granted = true
      AND rp.is_deleted = false
  );

  IF NOT v_has_clinical AND NOT v_has_patients_view THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view this visit.');
  END IF;

  SELECT sm.full_name INTO v_doctor_name
  FROM public.staff_members sm
  WHERE sm.id = v_visit.doctor_id AND sm.is_deleted = false;

  v_payload := jsonb_build_object(
    'id', v_visit.id,
    'branch_id', v_visit.branch_id,
    'appointment_id', v_visit.appointment_id,
    'patient_id', v_visit.patient_id,
    'doctor_id', v_visit.doctor_id,
    'doctor_name', v_doctor_name,
    'visit_date', v_visit.visit_date,
    'status', v_visit.status::text,
    'updated_at', v_visit.updated_at
  );

  IF v_has_clinical THEN
    SELECT * INTO v_note
    FROM public.visit_clinical_notes vcn
    WHERE vcn.visit_id = p_visit_id AND vcn.is_deleted = false;

    IF FOUND THEN
      v_documentation := jsonb_build_object(
        'complaint', v_note.complaint,
        'history', v_note.history,
        'examination', v_note.examination,
        'diagnosis', v_note.diagnosis,
        'plan', v_note.plan,
        'updated_at', v_note.updated_at
      );
    ELSE
      v_documentation := jsonb_build_object(
        'complaint', '',
        'history', '',
        'examination', '',
        'diagnosis', '',
        'plan', '',
        'updated_at', v_visit.updated_at
      );
    END IF;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', vvs.id,
          'name', vvs.name,
          'value', vvs.value,
          'unit', vvs.unit,
          'predefined_vital_sign_id', vvs.predefined_vital_sign_id
        )
        ORDER BY vvs.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_vital_signs
    FROM public.visit_vital_signs vvs
    WHERE vvs.visit_id = p_visit_id AND vvs.is_deleted = false;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', vi.id,
          'name', vi.name,
          'note', vi.note,
          'investigation_id', vi.investigation_id
        )
        ORDER BY vi.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_investigations
    FROM public.visit_investigations vi
    WHERE vi.visit_id = p_visit_id AND vi.is_deleted = false;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', tp.id,
          'medication_name', tp.medication_name,
          'medication_id', tp.medication_id,
          'dosage', tp.dosage,
          'frequency', tp.frequency,
          'duration', tp.duration,
          'notes', tp.notes
        )
        ORDER BY tp.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_treatment_plans
    FROM public.treatment_plans tp
    WHERE tp.visit_id = p_visit_id AND tp.is_deleted = false;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', va.id,
          'file_type', va.file_type::text,
          'label', va.label,
          'uploaded_by', va.uploaded_by,
          'uploaded_by_name', uploader.full_name,
          'size_bytes', va.size_bytes,
          'created_at', va.created_at,
          'can_download',
            auth_internal.staff_has_visit_clinical_access()
            OR (
              auth_internal.staff_has_visit_upload_access()
              AND va.uploaded_by = public.jwt_staff_member_id()
            )
        )
        ORDER BY va.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_attachments
    FROM public.visit_attachments va
    LEFT JOIN public.staff_members uploader ON uploader.id = va.uploaded_by
    WHERE va.visit_id = p_visit_id AND va.is_deleted = false;

    v_payload := v_payload || jsonb_build_object(
      'documentation', v_documentation,
      'vital_signs', COALESCE(v_vital_signs, '[]'::jsonb),
      'investigations', COALESCE(v_investigations, '[]'::jsonb),
      'treatment_plans', COALESCE(v_treatment_plans, '[]'::jsonb),
      'attachments', COALESCE(v_attachments, '[]'::jsonb)
    );
  END IF;

  RETURN public.rpc_success(v_payload);
END;
$$;

-- -----------------------------------------------------------------------------
-- Public RPC wrappers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.save_visit_documentation(
  p_visit_id uuid,
  p_complaint text DEFAULT NULL,
  p_history text DEFAULT NULL,
  p_examination text DEFAULT NULL,
  p_diagnosis text DEFAULT NULL,
  p_plan text DEFAULT NULL,
  p_expected_updated_at timestamptz DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.save_visit_documentation(
    p_visit_id, p_expected_updated_at, p_complaint, p_history, p_examination, p_diagnosis, p_plan
  );
$$;

CREATE OR REPLACE FUNCTION public.search_medications(p_query text DEFAULT '', p_limit int DEFAULT 20)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.search_medications(p_query, p_limit); $$;

CREATE OR REPLACE FUNCTION public.search_investigations(p_query text DEFAULT '', p_limit int DEFAULT 20)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.search_investigations(p_query, p_limit); $$;

CREATE OR REPLACE FUNCTION public.list_predefined_vital_signs()
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.list_predefined_vital_signs(); $$;

CREATE OR REPLACE FUNCTION public.create_catalog_medication(p_name text)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.create_catalog_medication(p_name); $$;

CREATE OR REPLACE FUNCTION public.create_catalog_investigation(p_name text)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.create_catalog_investigation(p_name); $$;

CREATE OR REPLACE FUNCTION public.create_predefined_vital_sign(p_name text, p_default_unit text DEFAULT NULL)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.create_predefined_vital_sign(p_name, p_default_unit); $$;

CREATE OR REPLACE FUNCTION public.create_visit_vital_sign(
  p_visit_id uuid, p_name text, p_value text, p_unit text DEFAULT NULL, p_predefined_vital_sign_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.create_visit_vital_sign(p_visit_id, p_name, p_value, p_unit, p_predefined_vital_sign_id); $$;

CREATE OR REPLACE FUNCTION public.update_visit_vital_sign(
  p_vital_sign_id uuid, p_name text DEFAULT NULL, p_value text DEFAULT NULL,
  p_unit text DEFAULT NULL, p_predefined_vital_sign_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.update_visit_vital_sign(p_vital_sign_id, p_name, p_value, p_unit, p_predefined_vital_sign_id); $$;

CREATE OR REPLACE FUNCTION public.archive_visit_vital_sign(p_vital_sign_id uuid)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.archive_visit_vital_sign(p_vital_sign_id); $$;

CREATE OR REPLACE FUNCTION public.create_visit_investigation(
  p_visit_id uuid, p_name text, p_note text DEFAULT NULL, p_investigation_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.create_visit_investigation(p_visit_id, p_name, p_note, p_investigation_id); $$;

CREATE OR REPLACE FUNCTION public.update_visit_investigation(
  p_investigation_line_id uuid, p_name text DEFAULT NULL, p_note text DEFAULT NULL, p_investigation_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.update_visit_investigation(p_investigation_line_id, p_name, p_note, p_investigation_id); $$;

CREATE OR REPLACE FUNCTION public.archive_visit_investigation(p_investigation_line_id uuid)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.archive_visit_investigation(p_investigation_line_id); $$;

DROP FUNCTION IF EXISTS public.create_treatment_plan(uuid, text, text, text, date, date, text);
DROP FUNCTION IF EXISTS public.create_treatment_plan(uuid, text, text, text, date, date, text, text);
DROP FUNCTION IF EXISTS public.update_treatment_plan(uuid, text, text, text, date, date, text);
DROP FUNCTION IF EXISTS public.update_treatment_plan(uuid, text, text, text, date, date, text, text);

CREATE OR REPLACE FUNCTION public.create_treatment_plan(
  p_visit_id uuid,
  p_medication_name text,
  p_dosage text,
  p_frequency text,
  p_duration text,
  p_notes text DEFAULT NULL,
  p_medication_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.create_treatment_plan(
    p_visit_id, p_medication_name, p_dosage, p_frequency, p_duration, p_notes, p_medication_id
  );
$$;

CREATE OR REPLACE FUNCTION public.update_treatment_plan(
  p_treatment_plan_id uuid,
  p_medication_name text DEFAULT NULL,
  p_medication_id uuid DEFAULT NULL,
  p_dosage text DEFAULT NULL,
  p_frequency text DEFAULT NULL,
  p_duration text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_treatment_plan(
    p_treatment_plan_id, p_medication_name, p_medication_id, p_dosage, p_frequency, p_duration, p_notes
  );
$$;

DROP FUNCTION IF EXISTS public.save_soap_note(uuid, timestamptz, text, text, text, text, jsonb);
DROP FUNCTION IF EXISTS auth_internal.save_soap_note(uuid, timestamptz, text, text, text, text, jsonb);
DROP FUNCTION IF EXISTS public.get_specialty_form_schema();

-- -----------------------------------------------------------------------------
-- Grants
-- -----------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION auth_internal.clinical_note_has_content(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.assert_catalog_read_access() TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.save_visit_documentation(uuid, timestamptz, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.search_medications(text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.search_investigations(text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.list_predefined_vital_signs() TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_catalog_medication(text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_catalog_investigation(text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_predefined_vital_sign(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_visit_vital_sign(uuid, text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_visit_vital_sign(uuid, text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.archive_visit_vital_sign(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_visit_investigation(uuid, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_visit_investigation(uuid, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.archive_visit_investigation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_treatment_plan(uuid, text, text, text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_treatment_plan(uuid, text, uuid, text, text, text, text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_visit_documentation(uuid, text, text, text, text, text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_medications(text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_investigations(text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_predefined_vital_signs() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_catalog_medication(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_catalog_investigation(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_predefined_vital_sign(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_visit_vital_sign(uuid, text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_visit_vital_sign(uuid, text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_visit_vital_sign(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_visit_investigation(uuid, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_visit_investigation(uuid, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_visit_investigation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_treatment_plan(uuid, text, text, text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_treatment_plan(uuid, text, uuid, text, text, text, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- Dev seed data (idempotent per organization)
-- -----------------------------------------------------------------------------

INSERT INTO public.predefined_vital_signs (organization_id, name, default_unit)
SELECT o.id, seed.name, seed.default_unit
FROM public.organizations o
CROSS JOIN (
  VALUES
    ('Blood Pressure', 'mmHg'),
    ('Heart Rate', 'bpm'),
    ('Temperature', '°C'),
    ('Respiratory Rate', '/min'),
    ('Oxygen Saturation', '%'),
    ('Weight', 'kg'),
    ('Height', 'cm')
) AS seed(name, default_unit)
WHERE o.is_deleted = false
  AND NOT EXISTS (
    SELECT 1 FROM public.predefined_vital_signs pvs
    WHERE pvs.organization_id = o.id AND pvs.is_deleted = false
  );

INSERT INTO public.medications (organization_id, name)
SELECT o.id, seed.name
FROM public.organizations o
CROSS JOIN (
  VALUES
    ('Amoxicillin'), ('Ibuprofen'), ('Paracetamol'), ('Omeprazole'), ('Metformin'),
    ('Atorvastatin'), ('Amlodipine'), ('Salbutamol'), ('Cetirizine'), ('Azithromycin')
) AS seed(name)
WHERE o.is_deleted = false
  AND NOT EXISTS (
    SELECT 1 FROM public.medications m
    WHERE m.organization_id = o.id AND m.is_deleted = false
  );

INSERT INTO public.investigations (organization_id, name)
SELECT o.id, seed.name
FROM public.organizations o
CROSS JOIN (
  VALUES
    ('Complete Blood Count'), ('Lipid Panel'), ('Chest X-Ray'), ('Urinalysis'),
    ('Fasting Blood Glucose'), ('Liver Function Test'), ('Thyroid Panel'),
    ('ECG'), ('Abdominal Ultrasound'), ('HbA1c')
) AS seed(name)
WHERE o.is_deleted = false
  AND NOT EXISTS (
    SELECT 1 FROM public.investigations i
    WHERE i.organization_id = o.id AND i.is_deleted = false
  );

-- -----------------------------------------------------------------------------
-- Test fixture teardown: include new visit documentation tables
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.delete_clinic_operational_dependents()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM auth_internal.delete_billing_dependents();

  IF to_regclass('public.visit_attachments') IS NOT NULL THEN
    DELETE FROM public.visit_attachments;
  END IF;
  IF to_regclass('public.visit_vital_signs') IS NOT NULL THEN
    DELETE FROM public.visit_vital_signs;
  END IF;
  IF to_regclass('public.visit_investigations') IS NOT NULL THEN
    DELETE FROM public.visit_investigations;
  END IF;
  IF to_regclass('public.visit_clinical_notes') IS NOT NULL THEN
    DELETE FROM public.visit_clinical_notes;
  END IF;
  IF to_regclass('public.treatment_plans') IS NOT NULL THEN
    DELETE FROM public.treatment_plans;
  END IF;
  IF to_regclass('public.visits') IS NOT NULL THEN
    DELETE FROM public.visits;
  END IF;

  IF to_regclass('public.appointments') IS NOT NULL THEN
    DELETE FROM public.appointments;
  END IF;

  DELETE FROM public.patients;
END;
$$;
