-- =============================================================================
-- Visit Encounter Workspace (014): US6 patient safety + US7 diagnosis/plan outputs
-- Spec: specs/014-visit-encounter-workspace/plan.md
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Organization-scoped diagnosis catalog
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.diagnosis_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
  code text,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT diagnosis_codes_name_length CHECK (length(name) <= 200),
  CONSTRAINT diagnosis_codes_code_length CHECK (code IS NULL OR length(code) <= 20)
);

CREATE UNIQUE INDEX IF NOT EXISTS diagnosis_codes_org_name_unique
  ON public.diagnosis_codes (organization_id, lower(trim(name)))
  WHERE is_deleted = false;

-- -----------------------------------------------------------------------------
-- Patient-level safety tables
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.patient_allergies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES public.patients (id),
  substance text NOT NULL,
  reaction text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT patient_allergies_substance_length CHECK (length(substance) <= 200),
  CONSTRAINT patient_allergies_reaction_length CHECK (reaction IS NULL OR length(reaction) <= 500)
);

CREATE INDEX IF NOT EXISTS patient_allergies_patient_idx
  ON public.patient_allergies (patient_id)
  WHERE is_deleted = false;

CREATE TABLE IF NOT EXISTS public.patient_medications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES public.patients (id),
  medication_id uuid REFERENCES public.medications (id),
  name text NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT patient_medications_name_length CHECK (length(name) <= 200),
  CONSTRAINT patient_medications_note_length CHECK (note IS NULL OR length(note) <= 500)
);

CREATE INDEX IF NOT EXISTS patient_medications_patient_idx
  ON public.patient_medications (patient_id)
  WHERE is_deleted = false;

CREATE TABLE IF NOT EXISTS public.patient_chronic_conditions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES public.patients (id),
  diagnosis_code_id uuid REFERENCES public.diagnosis_codes (id),
  name text NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT patient_chronic_conditions_name_length CHECK (length(name) <= 200),
  CONSTRAINT patient_chronic_conditions_note_length CHECK (note IS NULL OR length(note) <= 500)
);

CREATE INDEX IF NOT EXISTS patient_chronic_conditions_patient_idx
  ON public.patient_chronic_conditions (patient_id)
  WHERE is_deleted = false;

-- -----------------------------------------------------------------------------
-- Visit-level structured records
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.visit_diagnosis_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL REFERENCES public.visits (id),
  diagnosis_code_id uuid REFERENCES public.diagnosis_codes (id),
  code text,
  label text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT visit_diagnosis_codes_code_length CHECK (code IS NULL OR length(code) <= 20),
  CONSTRAINT visit_diagnosis_codes_label_length CHECK (length(label) <= 200)
);

CREATE INDEX IF NOT EXISTS visit_diagnosis_codes_visit_idx
  ON public.visit_diagnosis_codes (visit_id)
  WHERE is_deleted = false;

CREATE TABLE IF NOT EXISTS public.visit_plan_details (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL REFERENCES public.visits (id),
  follow_up_interval text,
  follow_up_date date,
  patient_instructions text,
  referral text,
  certificate_start_date date,
  certificate_end_date date,
  certificate_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz DEFAULT now(),
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT visit_plan_details_visit_id_unique UNIQUE (visit_id),
  CONSTRAINT visit_plan_details_follow_up_interval_length CHECK (follow_up_interval IS NULL OR length(follow_up_interval) <= 100),
  CONSTRAINT visit_plan_details_patient_instructions_length CHECK (patient_instructions IS NULL OR length(patient_instructions) <= 10000),
  CONSTRAINT visit_plan_details_referral_length CHECK (referral IS NULL OR length(referral) <= 2000),
  CONSTRAINT visit_plan_details_certificate_reason_length CHECK (certificate_reason IS NULL OR length(certificate_reason) <= 2000)
);

-- -----------------------------------------------------------------------------
-- Audit triggers and RLS
-- -----------------------------------------------------------------------------

SELECT public.apply_standard_audit_triggers('public.diagnosis_codes'::regclass);
SELECT public.apply_standard_audit_triggers('public.patient_allergies'::regclass);
SELECT public.apply_standard_audit_triggers('public.patient_medications'::regclass);
SELECT public.apply_standard_audit_triggers('public.patient_chronic_conditions'::regclass);
SELECT public.apply_standard_audit_triggers('public.visit_diagnosis_codes'::regclass);
SELECT public.apply_standard_audit_triggers('public.visit_plan_details'::regclass);

ALTER TABLE public.diagnosis_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_allergies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_medications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_chronic_conditions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_diagnosis_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_plan_details ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS diagnosis_codes_select ON public.diagnosis_codes;
CREATE POLICY diagnosis_codes_select ON public.diagnosis_codes
  FOR SELECT TO authenticated
  USING (is_deleted = false AND organization_id = public.jwt_organization_id());

DROP POLICY IF EXISTS diagnosis_codes_insert ON public.diagnosis_codes;
CREATE POLICY diagnosis_codes_insert ON public.diagnosis_codes FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS diagnosis_codes_update ON public.diagnosis_codes;
CREATE POLICY diagnosis_codes_update ON public.diagnosis_codes FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS diagnosis_codes_delete ON public.diagnosis_codes;
CREATE POLICY diagnosis_codes_delete ON public.diagnosis_codes FOR DELETE TO authenticated USING (false);

DROP POLICY IF EXISTS patient_allergies_select ON public.patient_allergies;
CREATE POLICY patient_allergies_select ON public.patient_allergies
  FOR SELECT TO authenticated
  USING (
    is_deleted = false
    AND EXISTS (
      SELECT 1 FROM public.patients p
      WHERE p.id = patient_allergies.patient_id
        AND p.is_deleted = false
        AND p.organization_id = public.jwt_organization_id()
        AND auth_internal.staff_can_access_branch(p.branch_id)
    )
  );

DROP POLICY IF EXISTS patient_allergies_insert ON public.patient_allergies;
CREATE POLICY patient_allergies_insert ON public.patient_allergies FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS patient_allergies_update ON public.patient_allergies;
CREATE POLICY patient_allergies_update ON public.patient_allergies FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS patient_allergies_delete ON public.patient_allergies;
CREATE POLICY patient_allergies_delete ON public.patient_allergies FOR DELETE TO authenticated USING (false);

DROP POLICY IF EXISTS patient_medications_select ON public.patient_medications;
CREATE POLICY patient_medications_select ON public.patient_medications
  FOR SELECT TO authenticated
  USING (
    is_deleted = false
    AND EXISTS (
      SELECT 1 FROM public.patients p
      WHERE p.id = patient_medications.patient_id
        AND p.is_deleted = false
        AND p.organization_id = public.jwt_organization_id()
        AND auth_internal.staff_can_access_branch(p.branch_id)
    )
  );

DROP POLICY IF EXISTS patient_medications_insert ON public.patient_medications;
CREATE POLICY patient_medications_insert ON public.patient_medications FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS patient_medications_update ON public.patient_medications;
CREATE POLICY patient_medications_update ON public.patient_medications FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS patient_medications_delete ON public.patient_medications;
CREATE POLICY patient_medications_delete ON public.patient_medications FOR DELETE TO authenticated USING (false);

DROP POLICY IF EXISTS patient_chronic_conditions_select ON public.patient_chronic_conditions;
CREATE POLICY patient_chronic_conditions_select ON public.patient_chronic_conditions
  FOR SELECT TO authenticated
  USING (
    is_deleted = false
    AND EXISTS (
      SELECT 1 FROM public.patients p
      WHERE p.id = patient_chronic_conditions.patient_id
        AND p.is_deleted = false
        AND p.organization_id = public.jwt_organization_id()
        AND auth_internal.staff_can_access_branch(p.branch_id)
    )
  );

DROP POLICY IF EXISTS patient_chronic_conditions_insert ON public.patient_chronic_conditions;
CREATE POLICY patient_chronic_conditions_insert ON public.patient_chronic_conditions FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS patient_chronic_conditions_update ON public.patient_chronic_conditions;
CREATE POLICY patient_chronic_conditions_update ON public.patient_chronic_conditions FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS patient_chronic_conditions_delete ON public.patient_chronic_conditions;
CREATE POLICY patient_chronic_conditions_delete ON public.patient_chronic_conditions FOR DELETE TO authenticated USING (false);

DROP POLICY IF EXISTS visit_diagnosis_codes_select ON public.visit_diagnosis_codes;
CREATE POLICY visit_diagnosis_codes_select ON public.visit_diagnosis_codes
  FOR SELECT TO authenticated
  USING (
    is_deleted = false
    AND EXISTS (
      SELECT 1 FROM public.visits v
      WHERE v.id = visit_diagnosis_codes.visit_id
        AND v.is_deleted = false
        AND auth_internal.staff_can_access_branch(v.branch_id)
    )
  );

DROP POLICY IF EXISTS visit_diagnosis_codes_insert ON public.visit_diagnosis_codes;
CREATE POLICY visit_diagnosis_codes_insert ON public.visit_diagnosis_codes FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS visit_diagnosis_codes_update ON public.visit_diagnosis_codes;
CREATE POLICY visit_diagnosis_codes_update ON public.visit_diagnosis_codes FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS visit_diagnosis_codes_delete ON public.visit_diagnosis_codes;
CREATE POLICY visit_diagnosis_codes_delete ON public.visit_diagnosis_codes FOR DELETE TO authenticated USING (false);

DROP POLICY IF EXISTS visit_plan_details_select ON public.visit_plan_details;
CREATE POLICY visit_plan_details_select ON public.visit_plan_details
  FOR SELECT TO authenticated
  USING (
    is_deleted = false
    AND EXISTS (
      SELECT 1 FROM public.visits v
      WHERE v.id = visit_plan_details.visit_id
        AND v.is_deleted = false
        AND auth_internal.staff_can_access_branch(v.branch_id)
    )
  );

DROP POLICY IF EXISTS visit_plan_details_insert ON public.visit_plan_details;
CREATE POLICY visit_plan_details_insert ON public.visit_plan_details FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS visit_plan_details_update ON public.visit_plan_details;
CREATE POLICY visit_plan_details_update ON public.visit_plan_details FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS visit_plan_details_delete ON public.visit_plan_details;
CREATE POLICY visit_plan_details_delete ON public.visit_plan_details FOR DELETE TO authenticated USING (false);

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_patient_branch_scope(p_patient_id uuid)
RETURNS public.patients
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_patient public.patients%ROWTYPE;
BEGIN
  SELECT *
  INTO v_patient
  FROM public.patients p
  WHERE p.id = p_patient_id
    AND p.is_deleted = false
    AND p.organization_id = public.jwt_organization_id()
    AND auth_internal.staff_can_access_branch(p.branch_id);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND';
  END IF;

  RETURN v_patient;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.get_patient_safety_context
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_patient_safety_context(p_patient_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed boolean;
  v_allergies jsonb;
  v_medications jsonb;
  v_conditions jsonb;
  v_last_visit_id uuid;
  v_last_visit_date date;
  v_last_vitals jsonb;
BEGIN
  v_allowed := auth_internal.staff_has_visit_clinical_access()
    OR EXISTS (
      SELECT 1
      FROM public.current_staff_member_row() sm
      JOIN public.roles_permissions rp ON rp.role = sm.role
      WHERE rp.permission_key = 'patients.view'
        AND rp.is_granted = true
        AND rp.is_deleted = false
    );

  IF NOT v_allowed THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view patient safety context.');
  END IF;

  BEGIN
    PERFORM auth_internal.assert_patient_branch_scope(p_patient_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      RAISE;
  END;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object('id', pa.id, 'substance', pa.substance, 'reaction', pa.reaction)
      ORDER BY pa.created_at ASC
    ),
    '[]'::jsonb
  )
  INTO v_allergies
  FROM public.patient_allergies pa
  WHERE pa.patient_id = p_patient_id AND pa.is_deleted = false;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', pm.id,
        'name', pm.name,
        'medication_id', pm.medication_id,
        'note', pm.note
      )
      ORDER BY pm.created_at ASC
    ),
    '[]'::jsonb
  )
  INTO v_medications
  FROM public.patient_medications pm
  WHERE pm.patient_id = p_patient_id AND pm.is_deleted = false;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', pcc.id,
        'name', pcc.name,
        'diagnosis_code_id', pcc.diagnosis_code_id,
        'note', pcc.note
      )
      ORDER BY pcc.created_at ASC
    ),
    '[]'::jsonb
  )
  INTO v_conditions
  FROM public.patient_chronic_conditions pcc
  WHERE pcc.patient_id = p_patient_id AND pcc.is_deleted = false;

  SELECT v.id, v.visit_date
  INTO v_last_visit_id, v_last_visit_date
  FROM public.visits v
  WHERE v.patient_id = p_patient_id
    AND v.is_deleted = false
    AND auth_internal.staff_can_access_branch(v.branch_id)
    AND EXISTS (
      SELECT 1 FROM public.visit_vital_signs vvs
      WHERE vvs.visit_id = v.id AND vvs.is_deleted = false
    )
  ORDER BY v.visit_date DESC, v.created_at DESC
  LIMIT 1;

  IF FOUND THEN
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'name', vvs.name,
          'value', vvs.value,
          'unit', vvs.unit,
          'measured_at', vvs.measured_at
        )
        ORDER BY vvs.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_last_vitals
    FROM public.visit_vital_signs vvs
    WHERE vvs.visit_id = v_last_visit_id AND vvs.is_deleted = false;

    v_last_vitals := jsonb_build_object(
      'visit_id', v_last_visit_id,
      'visit_date', v_last_visit_date,
      'items', COALESCE(v_last_vitals, '[]'::jsonb)
    );
  ELSE
    v_last_vitals := jsonb_build_object(
      'visit_id', NULL,
      'visit_date', NULL,
      'items', '[]'::jsonb
    );
  END IF;

  RETURN public.rpc_success(jsonb_build_object(
    'allergies', COALESCE(v_allergies, '[]'::jsonb),
    'current_medications', COALESCE(v_medications, '[]'::jsonb),
    'chronic_conditions', COALESCE(v_conditions, '[]'::jsonb),
    'last_vitals', v_last_vitals
  ));
END;
$$;

-- -----------------------------------------------------------------------------
-- Patient allergy CRUD
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_patient_allergy(
  p_patient_id uuid,
  p_substance text,
  p_reaction text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  BEGIN
    PERFORM auth_internal.assert_patient_branch_scope(p_patient_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      RAISE;
  END;

  IF NULLIF(trim(p_substance), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Substance is required.');
  END IF;

  IF length(trim(p_substance)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Substance must be 200 characters or fewer.');
  END IF;

  IF p_reaction IS NOT NULL AND length(trim(p_reaction)) > 500 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Reaction must be 500 characters or fewer.');
  END IF;

  INSERT INTO public.patient_allergies (patient_id, substance, reaction, created_by, updated_by)
  VALUES (p_patient_id, trim(p_substance), NULLIF(trim(p_reaction), ''), auth.uid(), auth.uid())
  RETURNING id INTO v_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'patient.allergy.create', 'patient_allergies', v_id,
    jsonb_build_object('patient_id', p_patient_id, 'allergy_id', v_id));

  RETURN public.rpc_success(jsonb_build_object('id', v_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage patient allergies.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.update_patient_allergy(
  p_allergy_id uuid,
  p_substance text DEFAULT NULL,
  p_reaction text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.patient_allergies%ROWTYPE;
  v_org_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  SELECT pa.* INTO v_row
  FROM public.patient_allergies pa
  JOIN public.patients p ON p.id = pa.patient_id
  WHERE pa.id = p_allergy_id
    AND pa.is_deleted = false
    AND p.is_deleted = false
    AND p.organization_id = v_org_id
    AND auth_internal.staff_can_access_branch(p.branch_id);

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Allergy record was not found.');
  END IF;

  IF p_substance IS NOT NULL AND NULLIF(trim(p_substance), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Substance cannot be empty.');
  END IF;

  IF p_substance IS NOT NULL AND length(trim(p_substance)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Substance must be 200 characters or fewer.');
  END IF;

  IF p_reaction IS NOT NULL AND length(trim(p_reaction)) > 500 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Reaction must be 500 characters or fewer.');
  END IF;

  UPDATE public.patient_allergies pa
  SET
    substance = COALESCE(NULLIF(trim(p_substance), ''), pa.substance),
    reaction = CASE WHEN p_reaction IS NULL THEN pa.reaction ELSE NULLIF(trim(p_reaction), '') END,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE pa.id = p_allergy_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'patient.allergy.update', 'patient_allergies', p_allergy_id,
    jsonb_build_object('allergy_id', p_allergy_id));

  RETURN public.rpc_success(jsonb_build_object('id', p_allergy_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage patient allergies.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.archive_patient_allergy(p_allergy_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.patient_allergies%ROWTYPE;
  v_org_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  SELECT pa.* INTO v_row
  FROM public.patient_allergies pa
  JOIN public.patients p ON p.id = pa.patient_id
  WHERE pa.id = p_allergy_id
    AND pa.is_deleted = false
    AND p.is_deleted = false
    AND p.organization_id = v_org_id
    AND auth_internal.staff_can_access_branch(p.branch_id);

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Allergy record was not found.');
  END IF;

  UPDATE public.patient_allergies pa
  SET is_deleted = true, deleted_at = now(), deleted_by = auth.uid(), updated_at = now(), updated_by = auth.uid()
  WHERE pa.id = p_allergy_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'patient.allergy.archive', 'patient_allergies', p_allergy_id,
    jsonb_build_object('allergy_id', p_allergy_id));

  RETURN public.rpc_success(jsonb_build_object('id', p_allergy_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage patient allergies.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- Patient medication CRUD
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_patient_medication(
  p_patient_id uuid,
  p_name text,
  p_medication_id uuid DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  BEGIN
    PERFORM auth_internal.assert_patient_branch_scope(p_patient_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      RAISE;
  END;

  IF NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Medication name is required.');
  END IF;

  IF length(trim(p_name)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Medication name must be 200 characters or fewer.');
  END IF;

  IF p_note IS NOT NULL AND length(trim(p_note)) > 500 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Note must be 500 characters or fewer.');
  END IF;

  IF p_medication_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.medications m
    WHERE m.id = p_medication_id
      AND m.organization_id = v_org_id
      AND m.is_deleted = false
  ) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Medication catalog item was not found.');
  END IF;

  INSERT INTO public.patient_medications (patient_id, medication_id, name, note, created_by, updated_by)
  VALUES (p_patient_id, p_medication_id, trim(p_name), NULLIF(trim(p_note), ''), auth.uid(), auth.uid())
  RETURNING id INTO v_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'patient.medication.create', 'patient_medications', v_id,
    jsonb_build_object('patient_id', p_patient_id, 'medication_record_id', v_id));

  RETURN public.rpc_success(jsonb_build_object('id', v_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage patient medications.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.update_patient_medication(
  p_medication_record_id uuid,
  p_name text DEFAULT NULL,
  p_medication_id uuid DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.patient_medications%ROWTYPE;
  v_org_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  SELECT pm.* INTO v_row
  FROM public.patient_medications pm
  JOIN public.patients p ON p.id = pm.patient_id
  WHERE pm.id = p_medication_record_id
    AND pm.is_deleted = false
    AND p.is_deleted = false
    AND p.organization_id = v_org_id
    AND auth_internal.staff_can_access_branch(p.branch_id);

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Medication record was not found.');
  END IF;

  IF p_name IS NOT NULL AND NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Medication name cannot be empty.');
  END IF;

  IF p_name IS NOT NULL AND length(trim(p_name)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Medication name must be 200 characters or fewer.');
  END IF;

  IF p_note IS NOT NULL AND length(trim(p_note)) > 500 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Note must be 500 characters or fewer.');
  END IF;

  IF p_medication_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.medications m
    WHERE m.id = p_medication_id
      AND m.organization_id = v_org_id
      AND m.is_deleted = false
  ) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Medication catalog item was not found.');
  END IF;

  UPDATE public.patient_medications pm
  SET
    name = COALESCE(NULLIF(trim(p_name), ''), pm.name),
    medication_id = CASE WHEN p_medication_id IS NULL THEN pm.medication_id ELSE p_medication_id END,
    note = CASE WHEN p_note IS NULL THEN pm.note ELSE NULLIF(trim(p_note), '') END,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE pm.id = p_medication_record_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'patient.medication.update', 'patient_medications', p_medication_record_id,
    jsonb_build_object('medication_record_id', p_medication_record_id));

  RETURN public.rpc_success(jsonb_build_object('id', p_medication_record_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage patient medications.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.archive_patient_medication(p_medication_record_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.patient_medications%ROWTYPE;
  v_org_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  SELECT pm.* INTO v_row
  FROM public.patient_medications pm
  JOIN public.patients p ON p.id = pm.patient_id
  WHERE pm.id = p_medication_record_id
    AND pm.is_deleted = false
    AND p.is_deleted = false
    AND p.organization_id = v_org_id
    AND auth_internal.staff_can_access_branch(p.branch_id);

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Medication record was not found.');
  END IF;

  UPDATE public.patient_medications pm
  SET is_deleted = true, deleted_at = now(), deleted_by = auth.uid(), updated_at = now(), updated_by = auth.uid()
  WHERE pm.id = p_medication_record_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'patient.medication.archive', 'patient_medications', p_medication_record_id,
    jsonb_build_object('medication_record_id', p_medication_record_id));

  RETURN public.rpc_success(jsonb_build_object('id', p_medication_record_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage patient medications.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- Patient chronic condition CRUD
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_patient_chronic_condition(
  p_patient_id uuid,
  p_name text,
  p_diagnosis_code_id uuid DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  BEGIN
    PERFORM auth_internal.assert_patient_branch_scope(p_patient_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      RAISE;
  END;

  IF NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Condition name is required.');
  END IF;

  IF length(trim(p_name)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Condition name must be 200 characters or fewer.');
  END IF;

  IF p_note IS NOT NULL AND length(trim(p_note)) > 500 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Note must be 500 characters or fewer.');
  END IF;

  IF p_diagnosis_code_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.diagnosis_codes dc
    WHERE dc.id = p_diagnosis_code_id
      AND dc.organization_id = v_org_id
      AND dc.is_deleted = false
  ) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Diagnosis catalog item was not found.');
  END IF;

  INSERT INTO public.patient_chronic_conditions (patient_id, diagnosis_code_id, name, note, created_by, updated_by)
  VALUES (p_patient_id, p_diagnosis_code_id, trim(p_name), NULLIF(trim(p_note), ''), auth.uid(), auth.uid())
  RETURNING id INTO v_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'patient.chronic_condition.create', 'patient_chronic_conditions', v_id,
    jsonb_build_object('patient_id', p_patient_id, 'condition_id', v_id));

  RETURN public.rpc_success(jsonb_build_object('id', v_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage chronic conditions.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.update_patient_chronic_condition(
  p_condition_id uuid,
  p_name text DEFAULT NULL,
  p_diagnosis_code_id uuid DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.patient_chronic_conditions%ROWTYPE;
  v_org_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  SELECT pcc.* INTO v_row
  FROM public.patient_chronic_conditions pcc
  JOIN public.patients p ON p.id = pcc.patient_id
  WHERE pcc.id = p_condition_id
    AND pcc.is_deleted = false
    AND p.is_deleted = false
    AND p.organization_id = v_org_id
    AND auth_internal.staff_can_access_branch(p.branch_id);

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Chronic condition record was not found.');
  END IF;

  IF p_name IS NOT NULL AND NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Condition name cannot be empty.');
  END IF;

  IF p_name IS NOT NULL AND length(trim(p_name)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Condition name must be 200 characters or fewer.');
  END IF;

  IF p_note IS NOT NULL AND length(trim(p_note)) > 500 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Note must be 500 characters or fewer.');
  END IF;

  IF p_diagnosis_code_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.diagnosis_codes dc
    WHERE dc.id = p_diagnosis_code_id
      AND dc.organization_id = v_org_id
      AND dc.is_deleted = false
  ) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Diagnosis catalog item was not found.');
  END IF;

  UPDATE public.patient_chronic_conditions pcc
  SET
    name = COALESCE(NULLIF(trim(p_name), ''), pcc.name),
    diagnosis_code_id = CASE WHEN p_diagnosis_code_id IS NULL THEN pcc.diagnosis_code_id ELSE p_diagnosis_code_id END,
    note = CASE WHEN p_note IS NULL THEN pcc.note ELSE NULLIF(trim(p_note), '') END,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE pcc.id = p_condition_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'patient.chronic_condition.update', 'patient_chronic_conditions', p_condition_id,
    jsonb_build_object('condition_id', p_condition_id));

  RETURN public.rpc_success(jsonb_build_object('id', p_condition_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage chronic conditions.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.archive_patient_chronic_condition(p_condition_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.patient_chronic_conditions%ROWTYPE;
  v_org_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  SELECT pcc.* INTO v_row
  FROM public.patient_chronic_conditions pcc
  JOIN public.patients p ON p.id = pcc.patient_id
  WHERE pcc.id = p_condition_id
    AND pcc.is_deleted = false
    AND p.is_deleted = false
    AND p.organization_id = v_org_id
    AND auth_internal.staff_can_access_branch(p.branch_id);

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Chronic condition record was not found.');
  END IF;

  UPDATE public.patient_chronic_conditions pcc
  SET is_deleted = true, deleted_at = now(), deleted_by = auth.uid(), updated_at = now(), updated_by = auth.uid()
  WHERE pcc.id = p_condition_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'patient.chronic_condition.archive', 'patient_chronic_conditions', p_condition_id,
    jsonb_build_object('condition_id', p_condition_id));

  RETURN public.rpc_success(jsonb_build_object('id', p_condition_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage chronic conditions.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- Diagnosis catalog RPCs
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.search_diagnosis_codes(
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

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object('id', sub.id, 'code', sub.code, 'name', sub.name)
      ORDER BY sub.name
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM (
    SELECT dc.id, dc.code, dc.name
    FROM public.diagnosis_codes dc
    WHERE dc.organization_id = v_org_id
      AND dc.is_deleted = false
      AND (
        v_query = ''
        OR dc.name ILIKE '%' || v_query || '%'
        OR dc.code ILIKE '%' || v_query || '%'
      )
    ORDER BY dc.name ASC
    LIMIT v_limit
  ) sub;

  RETURN public.rpc_success(jsonb_build_object('items', COALESCE(v_items, '[]'::jsonb)));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to search diagnosis codes.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.create_catalog_diagnosis_code(
  p_name text,
  p_code text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_name text;
  v_code text;
  v_existing public.diagnosis_codes%ROWTYPE;
  v_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();
  v_name := trim(COALESCE(p_name, ''));
  v_code := NULLIF(trim(COALESCE(p_code, '')), '');

  IF v_name = '' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Diagnosis name is required.');
  END IF;

  IF length(v_name) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Diagnosis name must be 200 characters or fewer.');
  END IF;

  IF v_code IS NOT NULL AND length(v_code) > 20 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Diagnosis code must be 20 characters or fewer.');
  END IF;

  SELECT * INTO v_existing
  FROM public.diagnosis_codes dc
  WHERE dc.organization_id = v_org_id
    AND dc.is_deleted = false
    AND lower(trim(dc.name)) = lower(v_name)
  LIMIT 1;

  IF FOUND THEN
    RETURN public.rpc_success(jsonb_build_object(
      'id', v_existing.id,
      'code', v_existing.code,
      'name', v_existing.name,
      'created', false
    ));
  END IF;

  INSERT INTO public.diagnosis_codes (organization_id, code, name, created_by, updated_by)
  VALUES (v_org_id, v_code, v_name, auth.uid(), auth.uid())
  RETURNING id INTO v_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'catalog.diagnosis_code.create', 'diagnosis_codes', v_id,
    jsonb_build_object('name', v_name, 'code', v_code));

  RETURN public.rpc_success(jsonb_build_object(
    'id', v_id,
    'code', v_code,
    'name', v_name,
    'created', true
  ));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to create catalog diagnosis codes.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- Visit diagnosis code RPCs
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_visit_diagnosis_code(
  p_visit_id uuid,
  p_label text,
  p_code text DEFAULT NULL,
  p_diagnosis_code_id uuid DEFAULT NULL
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
  v_code text;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();
  v_code := NULLIF(trim(COALESCE(p_code, '')), '');

  BEGIN
    v_visit := auth_internal.assert_visit_branch_scope(p_visit_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
      END IF;
      RAISE;
  END;

  IF NULLIF(trim(p_label), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Diagnosis label is required.');
  END IF;

  IF length(trim(p_label)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Diagnosis label must be 200 characters or fewer.');
  END IF;

  IF v_code IS NOT NULL AND length(v_code) > 20 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Diagnosis code must be 20 characters or fewer.');
  END IF;

  IF p_diagnosis_code_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.diagnosis_codes dc
    WHERE dc.id = p_diagnosis_code_id
      AND dc.organization_id = v_org_id
      AND dc.is_deleted = false
  ) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Diagnosis catalog item was not found.');
  END IF;

  INSERT INTO public.visit_diagnosis_codes (
    visit_id, diagnosis_code_id, code, label, created_by, updated_by
  )
  VALUES (
    p_visit_id, p_diagnosis_code_id, v_code, trim(p_label), auth.uid(), auth.uid()
  )
  RETURNING id INTO v_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'visit.diagnosis_code.create', 'visit_diagnosis_codes', v_id,
    jsonb_build_object('visit_id', p_visit_id, 'visit_diagnosis_code_id', v_id));

  RETURN public.rpc_success(jsonb_build_object('visit_diagnosis_code_id', v_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage visit diagnosis codes.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.archive_visit_diagnosis_code(p_visit_diagnosis_code_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.visit_diagnosis_codes%ROWTYPE;
  v_org_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  SELECT vdc.* INTO v_row
  FROM public.visit_diagnosis_codes vdc
  JOIN public.visits v ON v.id = vdc.visit_id
  WHERE vdc.id = p_visit_diagnosis_code_id
    AND vdc.is_deleted = false
    AND v.is_deleted = false
    AND auth_internal.staff_can_access_branch(v.branch_id);

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Visit diagnosis code was not found.');
  END IF;

  UPDATE public.visit_diagnosis_codes vdc
  SET is_deleted = true, deleted_at = now(), deleted_by = auth.uid(), updated_at = now(), updated_by = auth.uid()
  WHERE vdc.id = p_visit_diagnosis_code_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'visit.diagnosis_code.archive', 'visit_diagnosis_codes', p_visit_diagnosis_code_id,
    jsonb_build_object('visit_diagnosis_code_id', p_visit_diagnosis_code_id));

  RETURN public.rpc_success(jsonb_build_object('id', p_visit_diagnosis_code_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage visit diagnosis codes.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.save_visit_plan_details
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.save_visit_plan_details(
  p_visit_id uuid,
  p_expected_updated_at timestamptz,
  p_follow_up_interval text DEFAULT NULL,
  p_follow_up_date date DEFAULT NULL,
  p_patient_instructions text DEFAULT NULL,
  p_referral text DEFAULT NULL,
  p_certificate_start_date date DEFAULT NULL,
  p_certificate_end_date date DEFAULT NULL,
  p_certificate_reason text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
  v_plan public.visit_plan_details%ROWTYPE;
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

  IF length(COALESCE(p_follow_up_interval, '')) > 100
     OR length(COALESCE(p_patient_instructions, '')) > 10000
     OR length(COALESCE(p_referral, '')) > 2000
     OR length(COALESCE(p_certificate_reason, '')) > 2000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'One or more plan detail fields exceed maximum length.');
  END IF;

  IF p_certificate_start_date IS NOT NULL
     AND p_certificate_end_date IS NOT NULL
     AND p_certificate_end_date < p_certificate_start_date THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Certificate end date must be on or after the start date.');
  END IF;

  SELECT *
  INTO v_plan
  FROM public.visit_plan_details vpd
  WHERE vpd.visit_id = p_visit_id
    AND vpd.is_deleted = false;

  IF FOUND THEN
    v_current_updated_at := v_plan.updated_at;
  ELSE
    v_current_updated_at := v_visit.updated_at;
  END IF;

  IF v_current_updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RETURN public.rpc_error('STALE_PLAN_DETAILS', 'These plan details were updated elsewhere. Reload and try again.');
  END IF;

  IF FOUND THEN
    UPDATE public.visit_plan_details vpd
    SET
      follow_up_interval = NULLIF(trim(p_follow_up_interval), ''),
      follow_up_date = p_follow_up_date,
      patient_instructions = NULLIF(trim(p_patient_instructions), ''),
      referral = NULLIF(trim(p_referral), ''),
      certificate_start_date = p_certificate_start_date,
      certificate_end_date = p_certificate_end_date,
      certificate_reason = NULLIF(trim(p_certificate_reason), ''),
      updated_at = now(),
      updated_by = auth.uid()
    WHERE vpd.id = v_plan.id
    RETURNING updated_at INTO v_new_updated_at;
  ELSE
    INSERT INTO public.visit_plan_details (
      visit_id,
      follow_up_interval,
      follow_up_date,
      patient_instructions,
      referral,
      certificate_start_date,
      certificate_end_date,
      certificate_reason,
      created_by,
      updated_by
    )
    VALUES (
      p_visit_id,
      NULLIF(trim(p_follow_up_interval), ''),
      p_follow_up_date,
      NULLIF(trim(p_patient_instructions), ''),
      NULLIF(trim(p_referral), ''),
      p_certificate_start_date,
      p_certificate_end_date,
      NULLIF(trim(p_certificate_reason), ''),
      auth.uid(),
      auth.uid()
    )
    RETURNING updated_at INTO v_new_updated_at;
  END IF;

  UPDATE public.visits v
  SET updated_at = now(), updated_by = auth.uid()
  WHERE v.id = p_visit_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(), v_org_id, 'visit.plan_details_save', 'visit_plan_details', p_visit_id,
    jsonb_build_object('visit_id', p_visit_id)
  );

  RETURN public.rpc_success(jsonb_build_object('visit_id', p_visit_id, 'updated_at', v_new_updated_at));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to save visit plan details.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- US8: Objective enrichments (measured_at, investigation results, Pain Score)
-- -----------------------------------------------------------------------------

ALTER TABLE public.visit_vital_signs
  ADD COLUMN IF NOT EXISTS measured_at timestamptz;

ALTER TABLE public.visit_investigations
  ADD COLUMN IF NOT EXISTS result text,
  ADD COLUMN IF NOT EXISTS result_recorded_at timestamptz,
  ADD COLUMN IF NOT EXISTS result_recorded_by uuid REFERENCES auth.users (id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'visit_investigations_result_length'
      AND conrelid = 'public.visit_investigations'::regclass
  ) THEN
    ALTER TABLE public.visit_investigations
      ADD CONSTRAINT visit_investigations_result_length
      CHECK (result IS NULL OR length(result) <= 10000);
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS auth_internal.create_visit_vital_sign(uuid, text, text, text, uuid);
DROP FUNCTION IF EXISTS auth_internal.update_visit_vital_sign(uuid, text, text, text, uuid);

CREATE OR REPLACE FUNCTION auth_internal.create_visit_vital_sign(
  p_visit_id uuid,
  p_name text,
  p_value text,
  p_unit text DEFAULT NULL,
  p_predefined_vital_sign_id uuid DEFAULT NULL,
  p_measured_at timestamptz DEFAULT NULL
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
    visit_id, predefined_vital_sign_id, name, value, unit, measured_at, created_by, updated_by
  )
  VALUES (
    p_visit_id, p_predefined_vital_sign_id, trim(p_name), trim(p_value),
    NULLIF(trim(p_unit), ''), p_measured_at, auth.uid(), auth.uid()
  )
  RETURNING id INTO v_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'visit.vital_sign.create', 'visit_vital_signs', v_id,
    jsonb_build_object('visit_id', p_visit_id, 'vital_sign_id', v_id, 'measured_at', p_measured_at));

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
  p_predefined_vital_sign_id uuid DEFAULT NULL,
  p_measured_at timestamptz DEFAULT NULL
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
    measured_at = CASE WHEN p_measured_at IS NULL THEN vvs.measured_at ELSE p_measured_at END,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE vvs.id = p_vital_sign_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (auth.uid(), v_org_id, 'visit.vital_sign.update', 'visit_vital_signs', p_vital_sign_id,
    jsonb_build_object('vital_sign_id', p_vital_sign_id, 'measured_at', p_measured_at));

  RETURN public.rpc_success(jsonb_build_object('vital_sign_id', p_vital_sign_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage vital signs.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.record_investigation_result(
  p_investigation_line_id uuid,
  p_result text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.visit_investigations%ROWTYPE;
  v_org_id uuid;
  v_recorded_at timestamptz;
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
    RETURN public.rpc_error('NOT_FOUND', 'Investigation was not found.');
  END IF;

  IF p_result IS NOT NULL AND length(trim(p_result)) > 10000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Investigation result exceeds maximum length.');
  END IF;

  v_recorded_at := now();

  UPDATE public.visit_investigations vi
  SET
    result = CASE WHEN p_result IS NULL THEN NULL ELSE NULLIF(trim(p_result), '') END,
    result_recorded_at = CASE WHEN p_result IS NULL THEN NULL ELSE v_recorded_at END,
    result_recorded_by = CASE WHEN p_result IS NULL THEN NULL ELSE auth.uid() END,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE vi.id = p_investigation_line_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(), v_org_id, 'visit.investigation.result_record', 'visit_investigations', p_investigation_line_id,
    jsonb_build_object('investigation_line_id', p_investigation_line_id, 'result_recorded_at', v_recorded_at)
  );

  RETURN public.rpc_success(jsonb_build_object(
    'investigation_line_id', p_investigation_line_id,
    'result_recorded_at', CASE WHEN p_result IS NULL THEN NULL ELSE v_recorded_at END
  ));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to record investigation results.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.get_visit (add diagnosis_codes + plan_details + US8 enrichments)
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
  v_plan public.visit_plan_details%ROWTYPE;
  v_doctor_name text;
  v_has_clinical boolean;
  v_has_patients_view boolean;
  v_payload jsonb;
  v_documentation jsonb;
  v_vital_signs jsonb;
  v_investigations jsonb;
  v_treatment_plans jsonb;
  v_attachments jsonb;
  v_diagnosis_codes jsonb;
  v_plan_details jsonb;
  v_pending_investigations jsonb;
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
          'predefined_vital_sign_id', vvs.predefined_vital_sign_id,
          'measured_at', vvs.measured_at
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
          'investigation_id', vi.investigation_id,
          'result', vi.result,
          'result_recorded_at', vi.result_recorded_at
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
          'id', vi.id,
          'name', vi.name,
          'note', vi.note,
          'investigation_id', vi.investigation_id,
          'ordered_visit_id', v_prior.id,
          'ordered_visit_date', v_prior.visit_date,
          'result', vi.result,
          'result_recorded_at', vi.result_recorded_at
        )
        ORDER BY v_prior.visit_date DESC, vi.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_pending_investigations
    FROM public.visit_investigations vi
    JOIN public.visits v_prior ON v_prior.id = vi.visit_id
    WHERE v_prior.patient_id = v_visit.patient_id
      AND v_prior.id <> p_visit_id
      AND v_prior.is_deleted = false
      AND vi.is_deleted = false
      AND vi.result IS NULL
      AND auth_internal.staff_can_access_branch(v_prior.branch_id);

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

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', vdc.id,
          'code', vdc.code,
          'label', vdc.label,
          'diagnosis_code_id', vdc.diagnosis_code_id
        )
        ORDER BY vdc.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_diagnosis_codes
    FROM public.visit_diagnosis_codes vdc
    WHERE vdc.visit_id = p_visit_id AND vdc.is_deleted = false;

    SELECT * INTO v_plan
    FROM public.visit_plan_details vpd
    WHERE vpd.visit_id = p_visit_id AND vpd.is_deleted = false;

    IF FOUND THEN
      v_plan_details := jsonb_build_object(
        'follow_up_interval', v_plan.follow_up_interval,
        'follow_up_date', v_plan.follow_up_date,
        'patient_instructions', v_plan.patient_instructions,
        'referral', v_plan.referral,
        'certificate_start_date', v_plan.certificate_start_date,
        'certificate_end_date', v_plan.certificate_end_date,
        'certificate_reason', v_plan.certificate_reason,
        'updated_at', v_plan.updated_at
      );
    ELSE
      v_plan_details := NULL;
    END IF;

    v_payload := v_payload || jsonb_build_object(
      'documentation', v_documentation,
      'vital_signs', COALESCE(v_vital_signs, '[]'::jsonb),
      'investigations', COALESCE(v_investigations, '[]'::jsonb),
      'treatment_plans', COALESCE(v_treatment_plans, '[]'::jsonb),
      'attachments', COALESCE(v_attachments, '[]'::jsonb),
      'diagnosis_codes', COALESCE(v_diagnosis_codes, '[]'::jsonb),
      'plan_details', v_plan_details,
      'pending_investigations', COALESCE(v_pending_investigations, '[]'::jsonb)
    );
  END IF;

  RETURN public.rpc_success(v_payload);
END;
$$;

-- -----------------------------------------------------------------------------
-- Public RPC wrappers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_patient_safety_context(p_patient_id uuid)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.get_patient_safety_context(p_patient_id); $$;

CREATE OR REPLACE FUNCTION public.create_patient_allergy(
  p_patient_id uuid, p_substance text, p_reaction text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.create_patient_allergy(p_patient_id, p_substance, p_reaction); $$;

CREATE OR REPLACE FUNCTION public.update_patient_allergy(
  p_allergy_id uuid, p_substance text DEFAULT NULL, p_reaction text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.update_patient_allergy(p_allergy_id, p_substance, p_reaction); $$;

CREATE OR REPLACE FUNCTION public.archive_patient_allergy(p_allergy_id uuid)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.archive_patient_allergy(p_allergy_id); $$;

CREATE OR REPLACE FUNCTION public.create_patient_medication(
  p_patient_id uuid, p_name text, p_medication_id uuid DEFAULT NULL, p_note text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.create_patient_medication(p_patient_id, p_name, p_medication_id, p_note); $$;

CREATE OR REPLACE FUNCTION public.update_patient_medication(
  p_medication_record_id uuid, p_name text DEFAULT NULL, p_medication_id uuid DEFAULT NULL, p_note text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.update_patient_medication(p_medication_record_id, p_name, p_medication_id, p_note); $$;

CREATE OR REPLACE FUNCTION public.archive_patient_medication(p_medication_record_id uuid)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.archive_patient_medication(p_medication_record_id); $$;

CREATE OR REPLACE FUNCTION public.create_patient_chronic_condition(
  p_patient_id uuid, p_name text, p_diagnosis_code_id uuid DEFAULT NULL, p_note text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.create_patient_chronic_condition(p_patient_id, p_name, p_diagnosis_code_id, p_note); $$;

CREATE OR REPLACE FUNCTION public.update_patient_chronic_condition(
  p_condition_id uuid, p_name text DEFAULT NULL, p_diagnosis_code_id uuid DEFAULT NULL, p_note text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.update_patient_chronic_condition(p_condition_id, p_name, p_diagnosis_code_id, p_note); $$;

CREATE OR REPLACE FUNCTION public.archive_patient_chronic_condition(p_condition_id uuid)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.archive_patient_chronic_condition(p_condition_id); $$;

CREATE OR REPLACE FUNCTION public.search_diagnosis_codes(p_query text DEFAULT '', p_limit int DEFAULT 20)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.search_diagnosis_codes(p_query, p_limit); $$;

CREATE OR REPLACE FUNCTION public.create_catalog_diagnosis_code(p_name text, p_code text DEFAULT NULL)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.create_catalog_diagnosis_code(p_name, p_code); $$;

CREATE OR REPLACE FUNCTION public.create_visit_diagnosis_code(
  p_visit_id uuid, p_label text, p_code text DEFAULT NULL, p_diagnosis_code_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.create_visit_diagnosis_code(p_visit_id, p_label, p_code, p_diagnosis_code_id); $$;

CREATE OR REPLACE FUNCTION public.archive_visit_diagnosis_code(p_visit_diagnosis_code_id uuid)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.archive_visit_diagnosis_code(p_visit_diagnosis_code_id); $$;

CREATE OR REPLACE FUNCTION public.save_visit_plan_details(
  p_visit_id uuid,
  p_follow_up_interval text DEFAULT NULL,
  p_follow_up_date date DEFAULT NULL,
  p_patient_instructions text DEFAULT NULL,
  p_referral text DEFAULT NULL,
  p_certificate_start_date date DEFAULT NULL,
  p_certificate_end_date date DEFAULT NULL,
  p_certificate_reason text DEFAULT NULL,
  p_expected_updated_at timestamptz DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.save_visit_plan_details(
    p_visit_id,
    p_expected_updated_at,
    p_follow_up_interval,
    p_follow_up_date,
    p_patient_instructions,
    p_referral,
    p_certificate_start_date,
    p_certificate_end_date,
    p_certificate_reason
  );
$$;

DROP FUNCTION IF EXISTS public.create_visit_vital_sign(uuid, text, text, text, uuid);
DROP FUNCTION IF EXISTS public.update_visit_vital_sign(uuid, text, text, text, uuid);

CREATE OR REPLACE FUNCTION public.create_visit_vital_sign(
  p_visit_id uuid,
  p_name text,
  p_value text,
  p_unit text DEFAULT NULL,
  p_predefined_vital_sign_id uuid DEFAULT NULL,
  p_measured_at timestamptz DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.create_visit_vital_sign(p_visit_id, p_name, p_value, p_unit, p_predefined_vital_sign_id, p_measured_at); $$;

CREATE OR REPLACE FUNCTION public.update_visit_vital_sign(
  p_vital_sign_id uuid,
  p_name text DEFAULT NULL,
  p_value text DEFAULT NULL,
  p_unit text DEFAULT NULL,
  p_predefined_vital_sign_id uuid DEFAULT NULL,
  p_measured_at timestamptz DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.update_visit_vital_sign(p_vital_sign_id, p_name, p_value, p_unit, p_predefined_vital_sign_id, p_measured_at); $$;

CREATE OR REPLACE FUNCTION public.record_investigation_result(
  p_investigation_line_id uuid,
  p_result text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.record_investigation_result(p_investigation_line_id, p_result); $$;

-- -----------------------------------------------------------------------------
-- Grants
-- -----------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION auth_internal.assert_patient_branch_scope(uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION auth_internal.get_patient_safety_context(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_patient_allergy(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_patient_allergy(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.archive_patient_allergy(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_patient_medication(uuid, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_patient_medication(uuid, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.archive_patient_medication(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_patient_chronic_condition(uuid, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_patient_chronic_condition(uuid, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.archive_patient_chronic_condition(uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION auth_internal.search_diagnosis_codes(text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_catalog_diagnosis_code(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_visit_diagnosis_code(uuid, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.archive_visit_diagnosis_code(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.save_visit_plan_details(uuid, timestamptz, text, date, text, text, date, date, text) TO authenticated;

GRANT EXECUTE ON FUNCTION auth_internal.create_visit_vital_sign(uuid, text, text, text, uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_visit_vital_sign(uuid, text, text, text, uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.record_investigation_result(uuid, text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_patient_safety_context(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_allergy(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_patient_allergy(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_patient_allergy(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_medication(uuid, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_patient_medication(uuid, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_patient_medication(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_chronic_condition(uuid, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_patient_chronic_condition(uuid, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_patient_chronic_condition(uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.search_diagnosis_codes(text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_catalog_diagnosis_code(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_visit_diagnosis_code(uuid, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_visit_diagnosis_code(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_visit_plan_details(uuid, text, date, text, text, date, date, text, timestamptz) TO authenticated;

GRANT EXECUTE ON FUNCTION public.create_visit_vital_sign(uuid, text, text, text, uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_visit_vital_sign(uuid, text, text, text, uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_investigation_result(uuid, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- Diagnosis code seeds (idempotent per organization)
-- -----------------------------------------------------------------------------

INSERT INTO public.diagnosis_codes (organization_id, code, name)
SELECT o.id, seed.code, seed.name
FROM public.organizations o
CROSS JOIN (
  VALUES
    ('I10', 'Essential hypertension'),
    ('E11', 'Type 2 diabetes mellitus'),
    ('J06.9', 'Acute upper respiratory infection'),
    ('K21', 'Gastro-oesophageal reflux disease'),
    ('G43', 'Migraine'),
    ('J45', 'Asthma'),
    ('M79.3', 'Myalgia'),
    ('N39.0', 'Urinary tract infection'),
    ('R10.4', 'Abdominal pain'),
    ('F41.1', 'Generalized anxiety disorder'),
    ('E78.5', 'Hyperlipidaemia')
) AS seed(code, name)
WHERE o.is_deleted = false
  AND NOT EXISTS (
    SELECT 1 FROM public.diagnosis_codes dc
    WHERE dc.organization_id = o.id AND dc.is_deleted = false
  );

-- Pain Score predefined vital sign (idempotent per organization)
INSERT INTO public.predefined_vital_signs (organization_id, name, default_unit)
SELECT o.id, 'Pain Score', NULL
FROM public.organizations o
WHERE o.is_deleted = false
  AND NOT EXISTS (
    SELECT 1 FROM public.predefined_vital_signs pvs
    WHERE pvs.organization_id = o.id
      AND pvs.is_deleted = false
      AND lower(trim(pvs.name)) = lower('Pain Score')
  );

-- Extend org catalog seed helper for new organizations
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
      ('Height', 'cm'),
      ('Pain Score', NULL)
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

  IF NOT EXISTS (
    SELECT 1 FROM public.diagnosis_codes dc
    WHERE dc.organization_id = p_organization_id AND dc.is_deleted = false
  ) THEN
    INSERT INTO public.diagnosis_codes (organization_id, code, name)
    SELECT p_organization_id, seed.code, seed.name
    FROM (
      VALUES
        ('I10', 'Essential hypertension'),
        ('E11', 'Type 2 diabetes mellitus'),
        ('J06.9', 'Acute upper respiratory infection'),
        ('K21', 'Gastro-oesophageal reflux disease'),
        ('G43', 'Migraine'),
        ('J45', 'Asthma'),
        ('M79.3', 'Myalgia'),
        ('N39.0', 'Urinary tract infection'),
        ('R10.4', 'Abdominal pain'),
        ('F41.1', 'Generalized anxiety disorder'),
        ('E78.5', 'Hyperlipidaemia')
    ) AS seed(code, name);
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- Test fixture teardown: include new encounter workspace tables
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
  IF to_regclass('public.visit_plan_details') IS NOT NULL THEN
    DELETE FROM public.visit_plan_details;
  END IF;
  IF to_regclass('public.visit_diagnosis_codes') IS NOT NULL THEN
    DELETE FROM public.visit_diagnosis_codes;
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

  IF to_regclass('public.patient_allergies') IS NOT NULL THEN
    DELETE FROM public.patient_allergies;
  END IF;
  IF to_regclass('public.patient_medications') IS NOT NULL THEN
    DELETE FROM public.patient_medications;
  END IF;
  IF to_regclass('public.patient_chronic_conditions') IS NOT NULL THEN
    DELETE FROM public.patient_chronic_conditions;
  END IF;

  DELETE FROM public.patients;
END;
$$;
