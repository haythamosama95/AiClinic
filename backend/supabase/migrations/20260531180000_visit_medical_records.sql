-- =============================================================================
-- V1-5: Visit medical records (schema, RLS, storage, RPCs)
-- =============================================================================

DO $$
BEGIN
  CREATE TYPE public.visit_status AS ENUM ('in_progress', 'completed');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
  CREATE TYPE public.visit_attachment_file_type AS ENUM ('pdf', 'docx', 'jpeg', 'png');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

CREATE TABLE IF NOT EXISTS public.visits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.branches (id),
  appointment_id uuid NOT NULL REFERENCES public.appointments (id),
  patient_id uuid NOT NULL REFERENCES public.patients (id),
  doctor_id uuid NOT NULL REFERENCES public.staff_members (id),
  visit_date date NOT NULL,
  status public.visit_status NOT NULL DEFAULT 'in_progress',
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id)
);

CREATE UNIQUE INDEX IF NOT EXISTS visits_appointment_id_active_unique
  ON public.visits (appointment_id)
  WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS visits_patient_visit_date_idx
  ON public.visits (patient_id, visit_date DESC, created_at DESC)
  WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS visits_branch_visit_date_idx
  ON public.visits (branch_id, visit_date DESC)
  WHERE is_deleted = false;

CREATE TABLE IF NOT EXISTS public.soap_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL REFERENCES public.visits (id),
  subjective text,
  objective text,
  assessment text,
  plan text,
  specialty_form_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz DEFAULT now(),
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT soap_notes_visit_id_unique UNIQUE (visit_id)
);

CREATE TABLE IF NOT EXISTS public.treatment_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL REFERENCES public.visits (id),
  patient_id uuid NOT NULL REFERENCES public.patients (id),
  medication_name text NOT NULL,
  dosage text,
  frequency text,
  start_date date,
  end_date date,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT treatment_plans_end_after_start CHECK (
    end_date IS NULL OR start_date IS NULL OR end_date >= start_date
  )
);

CREATE INDEX IF NOT EXISTS treatment_plans_visit_idx
  ON public.treatment_plans (visit_id)
  WHERE is_deleted = false;

CREATE TABLE IF NOT EXISTS public.visit_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL REFERENCES public.visits (id),
  file_path text NOT NULL,
  file_type public.visit_attachment_file_type NOT NULL,
  label text,
  uploaded_by uuid NOT NULL REFERENCES public.staff_members (id),
  size_bytes bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id)
);

CREATE INDEX IF NOT EXISTS visit_attachments_visit_idx
  ON public.visit_attachments (visit_id)
  WHERE is_deleted = false;

SELECT public.apply_standard_audit_triggers('public.visits'::regclass);
SELECT public.apply_standard_audit_triggers('public.soap_notes'::regclass);
SELECT public.apply_standard_audit_triggers('public.treatment_plans'::regclass);
SELECT public.apply_standard_audit_triggers('public.visit_attachments'::regclass);

ALTER TABLE public.visits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.soap_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treatment_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_attachments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS visits_select ON public.visits;
CREATE POLICY visits_select ON public.visits
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND branch_id = ANY (public.jwt_branch_ids())
  );

DROP POLICY IF EXISTS visits_insert ON public.visits;
CREATE POLICY visits_insert ON public.visits
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS visits_update ON public.visits;
CREATE POLICY visits_update ON public.visits
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS visits_delete ON public.visits;
CREATE POLICY visits_delete ON public.visits
  FOR DELETE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS soap_notes_select ON public.soap_notes;
CREATE POLICY soap_notes_select ON public.soap_notes
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND EXISTS (
      SELECT 1
      FROM public.visits v
      WHERE v.id = soap_notes.visit_id
        AND v.is_deleted = false
        AND v.branch_id = ANY (public.jwt_branch_ids())
    )
  );

DROP POLICY IF EXISTS soap_notes_insert ON public.soap_notes;
CREATE POLICY soap_notes_insert ON public.soap_notes
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS soap_notes_update ON public.soap_notes;
CREATE POLICY soap_notes_update ON public.soap_notes
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS soap_notes_delete ON public.soap_notes;
CREATE POLICY soap_notes_delete ON public.soap_notes
  FOR DELETE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS treatment_plans_select ON public.treatment_plans;
CREATE POLICY treatment_plans_select ON public.treatment_plans
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND EXISTS (
      SELECT 1
      FROM public.visits v
      WHERE v.id = treatment_plans.visit_id
        AND v.is_deleted = false
        AND v.branch_id = ANY (public.jwt_branch_ids())
    )
  );

DROP POLICY IF EXISTS treatment_plans_insert ON public.treatment_plans;
CREATE POLICY treatment_plans_insert ON public.treatment_plans
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS treatment_plans_update ON public.treatment_plans;
CREATE POLICY treatment_plans_update ON public.treatment_plans
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS treatment_plans_delete ON public.treatment_plans;
CREATE POLICY treatment_plans_delete ON public.treatment_plans
  FOR DELETE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS visit_attachments_select ON public.visit_attachments;
CREATE POLICY visit_attachments_select ON public.visit_attachments
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND EXISTS (
      SELECT 1
      FROM public.visits v
      WHERE v.id = visit_attachments.visit_id
        AND v.is_deleted = false
        AND v.branch_id = ANY (public.jwt_branch_ids())
    )
  );

DROP POLICY IF EXISTS visit_attachments_insert ON public.visit_attachments;
CREATE POLICY visit_attachments_insert ON public.visit_attachments
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS visit_attachments_update ON public.visit_attachments;
CREATE POLICY visit_attachments_update ON public.visit_attachments
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS visit_attachments_delete ON public.visit_attachments;
CREATE POLICY visit_attachments_delete ON public.visit_attachments
  FOR DELETE
  TO authenticated
  USING (false);

-- -----------------------------------------------------------------------------
-- Permission seed: visits.upload_attachment
-- -----------------------------------------------------------------------------

INSERT INTO public.roles_permissions (role, permission_key, is_granted)
VALUES
  ('owner', 'visits.upload_attachment', true),
  ('administrator', 'visits.upload_attachment', true),
  ('doctor', 'visits.upload_attachment', true),
  ('lab_staff', 'visits.upload_attachment', true)
ON CONFLICT (role, permission_key) DO UPDATE
SET is_granted = EXCLUDED.is_granted,
    is_deleted = false;

-- -----------------------------------------------------------------------------
-- auth_internal helpers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.staff_has_visit_clinical_access()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.current_staff_member_row() sm
    JOIN public.roles_permissions rp ON rp.role = sm.role
    WHERE rp.permission_key IN ('visits.create', 'visits.edit_soap')
      AND rp.is_granted = true
      AND rp.is_deleted = false
  );
$$;

CREATE OR REPLACE FUNCTION auth_internal.staff_has_visit_upload_access()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.current_staff_member_row() sm
    JOIN public.roles_permissions rp ON rp.role = sm.role
    WHERE rp.permission_key IN ('visits.upload_attachment', 'visits.create', 'visits.edit_soap')
      AND rp.is_granted = true
      AND rp.is_deleted = false
  );
$$;

CREATE OR REPLACE FUNCTION auth_internal.assert_visit_branch_scope(p_visit_id uuid)
RETURNS public.visits
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
BEGIN
  SELECT *
  INTO v_visit
  FROM public.visits v
  WHERE v.id = p_visit_id
    AND v.is_deleted = false
    AND v.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND';
  END IF;

  RETURN v_visit;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.resolve_visit_date_from_appointment(
  p_start_time timestamptz,
  p_branch_id uuid
)
RETURNS date
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_tz text;
BEGIN
  SELECT COALESCE(NULLIF(trim(o.timezone), ''), 'UTC')
  INTO v_org_tz
  FROM public.branches b
  JOIN public.organizations o ON o.id = b.organization_id
  WHERE b.id = p_branch_id
    AND b.is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_BRANCH';
  END IF;

  RETURN (p_start_time AT TIME ZONE v_org_tz)::date;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.soap_note_has_content(
  p_subjective text,
  p_objective text,
  p_assessment text,
  p_plan text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT
    length(trim(COALESCE(p_subjective, ''))) > 0
    OR length(trim(COALESCE(p_objective, ''))) > 0
    OR length(trim(COALESCE(p_assessment, ''))) > 0
    OR length(trim(COALESCE(p_plan, ''))) > 0;
$$;

CREATE OR REPLACE FUNCTION auth_internal.validate_visit_attachment_type(p_file_type text)
RETURNS public.visit_attachment_file_type
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_normalized text;
BEGIN
  v_normalized := lower(trim(COALESCE(p_file_type, '')));

  IF v_normalized NOT IN ('pdf', 'docx', 'jpeg', 'png') THEN
    RAISE EXCEPTION 'INVALID_FILE_TYPE';
  END IF;

  RETURN v_normalized::public.visit_attachment_file_type;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.validate_specialty_form_json(
  p_org_id uuid,
  p_form_json jsonb
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_schema jsonb;
  v_required jsonb;
  v_properties jsonb;
  v_key text;
BEGIN
  IF p_form_json IS NULL OR p_form_json = '{}'::jsonb THEN
    RETURN;
  END IF;

  IF jsonb_typeof(p_form_json) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_INPUT';
  END IF;

  SELECT s.value_json
  INTO v_schema
  FROM public.app_settings s
  WHERE s.organization_id = p_org_id
    AND s.branch_id IS NULL
    AND s.key = 'specialty.form_schema_json'
    AND s.is_deleted = false
  LIMIT 1;

  IF v_schema IS NULL OR v_schema = '{}'::jsonb THEN
    RETURN;
  END IF;

  IF COALESCE(v_schema ->> 'type', 'object') <> 'object' THEN
    RETURN;
  END IF;

  v_required := v_schema -> 'required';
  IF v_required IS NOT NULL AND jsonb_typeof(v_required) = 'array' THEN
    FOR v_key IN
      SELECT jsonb_array_elements_text(v_required)
    LOOP
      IF NOT (p_form_json ? v_key) THEN
        RAISE EXCEPTION 'INVALID_INPUT';
      END IF;
    END LOOP;
  END IF;

  v_properties := v_schema -> 'properties';
  IF v_properties IS NOT NULL AND jsonb_typeof(v_properties) = 'object' THEN
    FOR v_key IN
      SELECT jsonb_object_keys(p_form_json)
    LOOP
      IF NOT (v_properties ? v_key) THEN
        RAISE EXCEPTION 'INVALID_INPUT';
      END IF;
    END LOOP;
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.create_visit
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_visit(
  p_appointment_id uuid,
  p_doctor_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_appt public.appointments%ROWTYPE;
  v_patient public.patients%ROWTYPE;
  v_doctor_id uuid;
  v_visit_id uuid;
  v_visit_date date;
  v_advanced_appointment boolean := false;
BEGIN
  v_caller := auth_internal.assert_permission('visits.create');

  SELECT *
  INTO v_appt
  FROM public.appointments a
  WHERE a.id = p_appointment_id
    AND a.is_deleted = false
    AND a.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Appointment was not found.');
  END IF;

  IF v_appt.status NOT IN ('checked_in', 'in_progress') THEN
    RETURN public.rpc_error(
      'APPOINTMENT_NOT_ELIGIBLE',
      'Visits can only be created from checked-in or in-progress appointments.'
    );
  END IF;

  BEGIN
    v_patient := auth_internal.assert_org_patient(v_appt.patient_id, false);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      IF SQLERRM = 'PATIENT_ARCHIVED' THEN
        RETURN public.rpc_error('PATIENT_ARCHIVED', 'This patient is archived.');
      END IF;
      RAISE;
  END;

  IF EXISTS (
    SELECT 1
    FROM public.visits v
    WHERE v.appointment_id = p_appointment_id
      AND v.is_deleted = false
  ) THEN
    RETURN public.rpc_error('VISIT_ALREADY_EXISTS', 'A visit already exists for this appointment.');
  END IF;

  v_doctor_id := v_appt.doctor_id;
  IF v_doctor_id IS NULL THEN
    IF p_doctor_id IS NULL THEN
      RETURN public.rpc_error('DOCTOR_REQUIRED', 'A doctor must be selected for this appointment.');
    END IF;

    BEGIN
      PERFORM auth_internal.assert_appointment_doctor(p_doctor_id, v_appt.branch_id);
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLERRM = 'INVALID_DOCTOR' THEN
          RETURN public.rpc_error('INVALID_DOCTOR', 'Doctor is not valid for this branch.');
        END IF;
        RAISE;
    END;

    v_doctor_id := p_doctor_id;

    UPDATE public.appointments a
    SET
      doctor_id = v_doctor_id,
      updated_at = now(),
      updated_by = auth.uid()
    WHERE a.id = v_appt.id;

    v_appt.doctor_id := v_doctor_id;
  END IF;

  v_visit_date := auth_internal.resolve_visit_date_from_appointment(v_appt.start_time, v_appt.branch_id);

  IF v_appt.status = 'checked_in' THEN
    UPDATE public.appointments a
    SET
      status = 'in_progress',
      updated_at = now(),
      updated_by = auth.uid()
    WHERE a.id = v_appt.id;

    v_advanced_appointment := true;
  END IF;

  INSERT INTO public.visits (
    branch_id,
    appointment_id,
    patient_id,
    doctor_id,
    visit_date,
    status,
    created_by,
    updated_by
  )
  VALUES (
    v_appt.branch_id,
    v_appt.id,
    v_appt.patient_id,
    v_doctor_id,
    v_visit_date,
    'in_progress',
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_visit_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'visit.create',
    'visits',
    v_visit_id,
    jsonb_build_object(
      'visit_id', v_visit_id,
      'appointment_id', v_appt.id,
      'patient_id', v_appt.patient_id,
      'doctor_id', v_doctor_id,
      'visit_date', v_visit_date
    )
  );

  IF v_advanced_appointment THEN
    INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
    VALUES (
      auth.uid(),
      public.jwt_organization_id(),
      'appointment.status_in_progress',
      'appointments',
      v_appt.id,
      jsonb_build_object('old_status', 'checked_in', 'new_status', 'in_progress')
    );
  END IF;

  RETURN public.rpc_success(
    jsonb_build_object(
      'visit_id', v_visit_id,
      'appointment_id', v_appt.id,
      'status', 'in_progress',
      'visit_date', v_visit_date
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to create visits.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.save_soap_note
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.save_soap_note(
  p_visit_id uuid,
  p_expected_updated_at timestamptz,
  p_subjective text DEFAULT NULL,
  p_objective text DEFAULT NULL,
  p_assessment text DEFAULT NULL,
  p_plan text DEFAULT NULL,
  p_specialty_form_json jsonb DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
  v_soap public.soap_notes%ROWTYPE;
  v_org_id uuid;
  v_current_updated_at timestamptz;
  v_new_updated_at timestamptz;
  v_specialty jsonb;
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

  IF length(COALESCE(p_subjective, '')) > 10000
     OR length(COALESCE(p_objective, '')) > 10000
     OR length(COALESCE(p_assessment, '')) > 10000
     OR length(COALESCE(p_plan, '')) > 10000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Each SOAP section must be 10000 characters or fewer.');
  END IF;

  v_specialty := COALESCE(p_specialty_form_json, '{}'::jsonb);

  BEGIN
    PERFORM auth_internal.validate_specialty_form_json(v_org_id, v_specialty);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'INVALID_INPUT' THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Specialty form data is not valid.');
      END IF;
      RAISE;
  END;

  SELECT *
  INTO v_soap
  FROM public.soap_notes sn
  WHERE sn.visit_id = p_visit_id
    AND sn.is_deleted = false;

  IF FOUND THEN
    v_current_updated_at := v_soap.updated_at;
  ELSE
    v_current_updated_at := v_visit.updated_at;
  END IF;

  IF v_current_updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RETURN public.rpc_error('STALE_SOAP', 'This SOAP note was updated elsewhere. Reload and try again.');
  END IF;

  IF FOUND THEN
    UPDATE public.soap_notes sn
    SET
      subjective = p_subjective,
      objective = p_objective,
      assessment = p_assessment,
      plan = p_plan,
      specialty_form_json = v_specialty,
      updated_at = now(),
      updated_by = auth.uid()
    WHERE sn.id = v_soap.id
    RETURNING updated_at INTO v_new_updated_at;
  ELSE
    INSERT INTO public.soap_notes (
      visit_id,
      subjective,
      objective,
      assessment,
      plan,
      specialty_form_json,
      created_by,
      updated_by
    )
    VALUES (
      p_visit_id,
      p_subjective,
      p_objective,
      p_assessment,
      p_plan,
      v_specialty,
      auth.uid(),
      auth.uid()
    )
    RETURNING updated_at INTO v_new_updated_at;
  END IF;

  UPDATE public.visits v
  SET
    updated_at = now(),
    updated_by = auth.uid()
  WHERE v.id = p_visit_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'visit.soap_save',
    'soap_notes',
    p_visit_id,
    jsonb_build_object('visit_id', p_visit_id)
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'visit_id', p_visit_id,
      'updated_at', v_new_updated_at
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to edit SOAP notes.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.complete_visit
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
  v_soap public.soap_notes%ROWTYPE;
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

  SELECT *
  INTO v_appt
  FROM public.appointments a
  WHERE a.id = v_visit.appointment_id
    AND a.is_deleted = false;

  IF NOT FOUND OR v_appt.status <> 'in_progress' THEN
    RETURN public.rpc_error(
      'APPOINTMENT_NOT_IN_PROGRESS',
      'The linked appointment is no longer in progress.'
    );
  END IF;

  SELECT *
  INTO v_soap
  FROM public.soap_notes sn
  WHERE sn.visit_id = p_visit_id
    AND sn.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error(
      'SOAP_REQUIRED_FOR_COMPLETE',
      'At least one SOAP section must contain text before completing the visit.'
    );
  END IF;

  IF p_expected_updated_at IS NOT NULL
     AND v_soap.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RETURN public.rpc_error('STALE_SOAP', 'This SOAP note was updated elsewhere. Reload and try again.');
  END IF;

  IF NOT auth_internal.soap_note_has_content(
    v_soap.subjective,
    v_soap.objective,
    v_soap.assessment,
    v_soap.plan
  ) THEN
    RETURN public.rpc_error(
      'SOAP_REQUIRED_FOR_COMPLETE',
      'At least one SOAP section must contain text before completing the visit.'
    );
  END IF;

  UPDATE public.visits v
  SET
    status = 'completed',
    updated_at = now(),
    updated_by = auth.uid()
  WHERE v.id = p_visit_id;

  UPDATE public.appointments a
  SET
    status = 'completed',
    updated_at = now(),
    updated_by = auth.uid()
  WHERE a.id = v_visit.appointment_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES
    (
      auth.uid(),
      v_org_id,
      'visit.complete',
      'visits',
      p_visit_id,
      jsonb_build_object('visit_id', p_visit_id, 'status', 'completed')
    ),
    (
      auth.uid(),
      v_org_id,
      'appointment.status_completed',
      'appointments',
      v_visit.appointment_id,
      jsonb_build_object('old_status', 'in_progress', 'new_status', 'completed')
    );

  RETURN public.rpc_success(
    jsonb_build_object(
      'visit_id', p_visit_id,
      'visit_status', 'completed',
      'appointment_id', v_visit.appointment_id,
      'appointment_status', 'completed'
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to complete visits.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.create_treatment_plan
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_treatment_plan(
  p_visit_id uuid,
  p_medication_name text,
  p_dosage text DEFAULT NULL,
  p_frequency text DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL,
  p_notes text DEFAULT NULL
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

  IF p_notes IS NOT NULL AND length(trim(p_notes)) > 2000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Notes must be 2000 characters or fewer.');
  END IF;

  IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL AND p_end_date < p_start_date THEN
    RETURN public.rpc_error('INVALID_INPUT', 'End date must be on or after start date.');
  END IF;

  INSERT INTO public.treatment_plans (
    visit_id,
    patient_id,
    medication_name,
    dosage,
    frequency,
    start_date,
    end_date,
    notes,
    created_by,
    updated_by
  )
  VALUES (
    p_visit_id,
    v_visit.patient_id,
    trim(p_medication_name),
    NULLIF(trim(p_dosage), ''),
    NULLIF(trim(p_frequency), ''),
    p_start_date,
    p_end_date,
    NULLIF(trim(p_notes), ''),
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_plan_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'visit.treatment_plan.create',
    'treatment_plans',
    v_plan_id,
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

-- -----------------------------------------------------------------------------
-- auth_internal.update_treatment_plan
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.update_treatment_plan(
  p_treatment_plan_id uuid,
  p_medication_name text DEFAULT NULL,
  p_dosage text DEFAULT NULL,
  p_frequency text DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL,
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

  SELECT tp.*
  INTO v_plan
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

  IF p_notes IS NOT NULL AND length(trim(p_notes)) > 2000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Notes must be 2000 characters or fewer.');
  END IF;

  IF COALESCE(p_start_date, v_plan.start_date) IS NOT NULL
     AND COALESCE(p_end_date, v_plan.end_date) IS NOT NULL
     AND COALESCE(p_end_date, v_plan.end_date) < COALESCE(p_start_date, v_plan.start_date) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'End date must be on or after start date.');
  END IF;

  UPDATE public.treatment_plans tp
  SET
    medication_name = COALESCE(NULLIF(trim(p_medication_name), ''), tp.medication_name),
    dosage = CASE WHEN p_dosage IS NULL THEN tp.dosage ELSE NULLIF(trim(p_dosage), '') END,
    frequency = CASE WHEN p_frequency IS NULL THEN tp.frequency ELSE NULLIF(trim(p_frequency), '') END,
    start_date = COALESCE(p_start_date, tp.start_date),
    end_date = COALESCE(p_end_date, tp.end_date),
    notes = CASE WHEN p_notes IS NULL THEN tp.notes ELSE NULLIF(trim(p_notes), '') END,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE tp.id = p_treatment_plan_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'visit.treatment_plan.update',
    'treatment_plans',
    p_treatment_plan_id,
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
-- auth_internal.archive_treatment_plan
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.archive_treatment_plan(p_treatment_plan_id uuid)
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

  SELECT tp.*
  INTO v_plan
  FROM public.treatment_plans tp
  JOIN public.visits v ON v.id = tp.visit_id
  WHERE tp.id = p_treatment_plan_id
    AND tp.is_deleted = false
    AND v.is_deleted = false
    AND v.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Treatment plan was not found.');
  END IF;

  UPDATE public.treatment_plans tp
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE tp.id = p_treatment_plan_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'visit.treatment_plan.archive',
    'treatment_plans',
    p_treatment_plan_id,
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
-- auth_internal.register_visit_attachment
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.register_visit_attachment(
  p_visit_id uuid,
  p_file_path text,
  p_file_type text,
  p_size_bytes bigint,
  p_label text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
  v_caller public.staff_members%ROWTYPE;
  v_org_id uuid;
  v_file_type public.visit_attachment_file_type;
  v_attachment_id uuid;
  v_expected_prefix text;
BEGIN
  IF NOT auth_internal.staff_has_visit_upload_access() THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to upload visit attachments.');
  END IF;

  SELECT *
  INTO v_caller
  FROM public.current_staff_member_row() sm
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN public.rpc_error('FORBIDDEN', 'Staff context is required.');
  END IF;

  v_org_id := public.jwt_organization_id();
  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
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

  IF NULLIF(trim(p_file_path), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'File path is required.');
  END IF;

  IF p_size_bytes IS NULL OR p_size_bytes <= 0 OR p_size_bytes > 26214400 THEN
    RETURN public.rpc_error('FILE_TOO_LARGE', 'Attachment size must be between 1 byte and 25 MB.');
  END IF;

  IF p_label IS NOT NULL AND length(trim(p_label)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Label must be 200 characters or fewer.');
  END IF;

  BEGIN
    v_file_type := auth_internal.validate_visit_attachment_type(p_file_type);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'INVALID_FILE_TYPE' THEN
        RETURN public.rpc_error('INVALID_FILE_TYPE', 'Attachment type must be pdf, docx, jpeg, or png.');
      END IF;
      RAISE;
  END;

  v_expected_prefix := v_org_id::text || '/' || v_visit.branch_id::text || '/' || p_visit_id::text || '/';
  IF p_file_path NOT LIKE v_expected_prefix || '%' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'File path does not match the visit storage prefix.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM storage.objects o
    WHERE o.bucket_id = 'visit-attachments'
      AND o.name = p_file_path
  ) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Uploaded file was not found in storage.');
  END IF;

  INSERT INTO public.visit_attachments (
    visit_id,
    file_path,
    file_type,
    label,
    uploaded_by,
    size_bytes,
    created_by,
    updated_by
  )
  VALUES (
    p_visit_id,
    p_file_path,
    v_file_type,
    NULLIF(trim(p_label), ''),
    v_caller.id,
    p_size_bytes,
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_attachment_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'visit.attachment.register',
    'visit_attachments',
    v_attachment_id,
    jsonb_build_object(
      'visit_id', p_visit_id,
      'attachment_id', v_attachment_id,
      'file_path', p_file_path,
      'file_type', v_file_type::text
    )
  );

  RETURN public.rpc_success(jsonb_build_object('attachment_id', v_attachment_id));
EXCEPTION
  WHEN OTHERS THEN
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.get_visit_attachment_download
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_visit_attachment_download(p_attachment_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_attachment public.visit_attachments%ROWTYPE;
  v_visit public.visits%ROWTYPE;
  v_caller_staff_id uuid;
  v_has_clinical boolean;
  v_has_upload boolean;
  v_signed_url text;
  v_filename text;
  v_expires_at timestamptz;
BEGIN
  v_caller_staff_id := public.jwt_staff_member_id();
  v_has_clinical := auth_internal.staff_has_visit_clinical_access();
  v_has_upload := auth_internal.staff_has_visit_upload_access();

  SELECT va.*
  INTO v_attachment
  FROM public.visit_attachments va
  WHERE va.id = p_attachment_id
    AND va.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Attachment was not found.');
  END IF;

  BEGIN
    v_visit := auth_internal.assert_visit_branch_scope(v_attachment.visit_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
      END IF;
      RAISE;
  END;

  IF v_has_clinical THEN
    NULL;
  ELSIF v_has_upload AND v_attachment.uploaded_by = v_caller_staff_id THEN
    NULL;
  ELSE
    RETURN public.rpc_error(
      'ATTACHMENT_DOWNLOAD_DENIED',
      'You do not have permission to download this attachment.'
    );
  END IF;

  v_expires_at := now() + interval '1 hour';
  v_filename := regexp_replace(split_part(v_attachment.file_path, '/', 4), '^[0-9a-f-]{36}_', '');

  IF to_regprocedure('storage.create_signed_url(text,text,integer)') IS NOT NULL THEN
    SELECT (storage.create_signed_url('visit-attachments', v_attachment.file_path, 3600)).signed_url
    INTO v_signed_url;
  ELSE
    v_signed_url := v_attachment.file_path;
  END IF;

  RETURN public.rpc_success(
    jsonb_build_object(
      'signed_url', v_signed_url,
      'file_path', v_attachment.file_path,
      'file_type', v_attachment.file_type::text,
      'filename', COALESCE(NULLIF(v_filename, ''), v_attachment.file_path),
      'expires_at', v_expires_at
    )
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.get_visit
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_visit(p_visit_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
  v_soap public.soap_notes%ROWTYPE;
  v_doctor_name text;
  v_has_clinical boolean;
  v_has_patients_view boolean;
  v_payload jsonb;
  v_soap_json jsonb;
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

  SELECT sm.full_name
  INTO v_doctor_name
  FROM public.staff_members sm
  WHERE sm.id = v_visit.doctor_id
    AND sm.is_deleted = false;

  v_payload := jsonb_build_object(
    'id', v_visit.id,
    'branch_id', v_visit.branch_id,
    'appointment_id', v_visit.appointment_id,
    'patient_id', v_visit.patient_id,
    'doctor_id', v_visit.doctor_id,
    'doctor_name', v_doctor_name,
    'visit_date', v_visit.visit_date,
    'status', v_visit.status::text
  );

  IF v_has_clinical THEN
    SELECT *
    INTO v_soap
    FROM public.soap_notes sn
    WHERE sn.visit_id = p_visit_id
      AND sn.is_deleted = false;

    IF FOUND THEN
      v_soap_json := jsonb_build_object(
        'subjective', v_soap.subjective,
        'objective', v_soap.objective,
        'assessment', v_soap.assessment,
        'plan', v_soap.plan,
        'specialty_form_json', COALESCE(v_soap.specialty_form_json, '{}'::jsonb),
        'updated_at', v_soap.updated_at
      );
    ELSE
      v_soap_json := jsonb_build_object(
        'subjective', NULL,
        'objective', NULL,
        'assessment', NULL,
        'plan', NULL,
        'specialty_form_json', '{}'::jsonb,
        'updated_at', v_visit.updated_at
      );
    END IF;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', tp.id,
          'medication_name', tp.medication_name,
          'dosage', tp.dosage,
          'frequency', tp.frequency,
          'start_date', tp.start_date,
          'end_date', tp.end_date,
          'notes', tp.notes
        )
        ORDER BY tp.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_treatment_plans
    FROM public.treatment_plans tp
    WHERE tp.visit_id = p_visit_id
      AND tp.is_deleted = false;

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
    WHERE va.visit_id = p_visit_id
      AND va.is_deleted = false;

    v_payload := v_payload || jsonb_build_object(
      'soap', v_soap_json,
      'treatment_plans', COALESCE(v_treatment_plans, '[]'::jsonb),
      'attachments', COALESCE(v_attachments, '[]'::jsonb)
    );
  END IF;

  RETURN public.rpc_success(v_payload);
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.get_visit_by_appointment
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_visit_by_appointment(p_appointment_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.appointments a
    WHERE a.id = p_appointment_id
      AND a.is_deleted = false
      AND a.branch_id = ANY (public.jwt_branch_ids())
  ) THEN
    RETURN public.rpc_error('NOT_FOUND', 'Appointment was not found.');
  END IF;

  SELECT *
  INTO v_visit
  FROM public.visits v
  WHERE v.appointment_id = p_appointment_id
    AND v.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_success(
      jsonb_build_object(
        'visit_id', NULL,
        'status', NULL
      )
    );
  END IF;

  RETURN public.rpc_success(
    jsonb_build_object(
      'visit_id', v_visit.id,
      'status', v_visit.status::text
    )
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.list_patient_visits
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.list_patient_visits(
  p_patient_id uuid,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_limit int;
  v_offset int;
  v_items jsonb;
  v_total int;
BEGIN
  PERFORM auth_internal.assert_permission('patients.view');
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  BEGIN
    PERFORM auth_internal.assert_org_patient(p_patient_id, false);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      IF SQLERRM = 'PATIENT_ARCHIVED' THEN
        RETURN public.rpc_error('PATIENT_ARCHIVED', 'This patient is archived.');
      END IF;
      RAISE;
  END;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  WITH filtered AS (
    SELECT
      v.id,
      v.visit_date,
      v.status,
      sm.full_name AS doctor_name,
      b.name AS branch_name,
      v.created_at
    FROM public.visits v
    JOIN public.branches b ON b.id = v.branch_id
    JOIN public.staff_members sm ON sm.id = v.doctor_id
    WHERE v.patient_id = p_patient_id
      AND v.is_deleted = false
      AND v.branch_id = ANY (public.jwt_branch_ids())
  ),
  counted AS (
    SELECT
      f.*,
      count(*) OVER ()::int AS total_count
    FROM filtered f
    ORDER BY f.visit_date DESC, f.created_at DESC
    LIMIT v_limit
    OFFSET v_offset
  )
  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'visit_date', c.visit_date,
          'doctor_name', c.doctor_name,
          'status', c.status::text,
          'branch_name', c.branch_name
        )
        ORDER BY c.visit_date DESC, c.created_at DESC
      ),
      '[]'::jsonb
    ),
    COALESCE(max(c.total_count), 0)
  INTO v_items, v_total
  FROM counted c;

  RETURN public.rpc_success(
    jsonb_build_object(
      'items', COALESCE(v_items, '[]'::jsonb),
      'total_count', COALESCE(v_total, 0),
      'limit', v_limit,
      'offset', v_offset
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view patient visits.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.get_specialty_form_schema
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_specialty_form_schema()
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_schema jsonb;
  v_allowed boolean;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

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
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view the specialty form schema.');
  END IF;

  SELECT s.value_json
  INTO v_schema
  FROM public.app_settings s
  WHERE s.organization_id = v_org_id
    AND s.branch_id IS NULL
    AND s.key = 'specialty.form_schema_json'
    AND s.is_deleted = false
  LIMIT 1;

  RETURN public.rpc_success(
    jsonb_build_object(
      'schema_json', COALESCE(v_schema, '{}'::jsonb)
    )
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- Patch: update_appointment_status — block in_progress → completed
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.update_appointment_status(
  p_appointment_id uuid,
  p_new_status text
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_appt public.appointments%ROWTYPE;
  v_new public.appointment_status;
  v_allowed boolean := false;
  v_org_tz text;
  v_appt_day date;
  v_today date;
BEGIN
  SELECT *
  INTO v_appt
  FROM public.appointments a
  WHERE a.id = p_appointment_id
    AND a.is_deleted = false
    AND a.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Appointment was not found.');
  END IF;

  BEGIN
    v_new := lower(trim(p_new_status))::public.appointment_status;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Status is not valid.');
  END;

  IF v_appt.status = 'in_progress' AND v_new = 'completed' THEN
    RETURN public.rpc_error(
      'VISIT_REQUIRED_FOR_COMPLETION',
      'Complete the visit documentation to finish this appointment.'
    );
  END IF;

  v_allowed := CASE v_appt.status
    WHEN 'scheduled' THEN v_new IN ('confirmed', 'cancelled', 'no_show')
    WHEN 'confirmed' THEN v_new IN ('checked_in', 'cancelled', 'no_show')
    WHEN 'checked_in' THEN v_new IN ('in_progress', 'cancelled', 'no_show')
    WHEN 'in_progress' THEN false
    ELSE false
  END;

  IF NOT v_allowed THEN
    RETURN public.rpc_error('INVALID_TRANSITION', 'This status change is not allowed.');
  END IF;

  IF v_new IN ('checked_in', 'in_progress', 'completed', 'no_show') THEN
    SELECT COALESCE(NULLIF(trim(o.timezone), ''), 'UTC')
    INTO v_org_tz
    FROM public.branches b
    JOIN public.organizations o ON o.id = b.organization_id
    WHERE b.id = v_appt.branch_id;

    v_appt_day := (v_appt.start_time AT TIME ZONE v_org_tz)::date;
    v_today := (now() AT TIME ZONE v_org_tz)::date;

    IF v_today < v_appt_day THEN
      RETURN public.rpc_error(
        'INVALID_TRANSITION',
        'This status change is only allowed on or after the appointment day.'
      );
    END IF;
  END IF;

  IF v_new IN ('cancelled', 'no_show') THEN
    PERFORM auth_internal.assert_permission('appointments.cancel');
  ELSE
    PERFORM auth_internal.assert_permission('appointments.create');
  END IF;

  UPDATE public.appointments a
  SET
    status = v_new,
    cancel_reason = a.cancel_reason,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE a.id = v_appt.id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'appointment.status',
    'appointments',
    v_appt.id,
    jsonb_build_object('old_status', v_appt.status::text, 'new_status', v_new::text)
  );

  RETURN public.rpc_success(jsonb_build_object('appointment_id', v_appt.id, 'status', v_new::text));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to update appointment status.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- Patch: dev_reset_clinic_installation — delete visit domain before appointments
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.dev_reset_clinic_installation()
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_env text;
  v_staff public.staff_members%ROWTYPE;
  v_orgs_deleted int;
  v_branches_deleted int;
  v_patients_deleted int;
  v_appointments_deleted int;
  v_visit_attachments_deleted int;
  v_soap_notes_deleted int;
  v_treatment_plans_deleted int;
  v_visits_deleted int;
  v_had_org boolean;
BEGIN
  v_env := current_setting('app.environment', true);
  IF v_env IS NOT NULL AND v_env NOT IN ('development', 'local', 'test') THEN
    RETURN public.rpc_error(
      'FORBIDDEN',
      'dev_reset_clinic_installation can only run in development/local/test environments.'
    );
  END IF;

  v_staff := auth_internal.assert_bootstrap_admin();
  v_had_org := auth_internal.organization_exists();

  DELETE FROM public.visit_attachments WHERE true;
  GET DIAGNOSTICS v_visit_attachments_deleted = ROW_COUNT;

  DELETE FROM public.soap_notes WHERE true;
  GET DIAGNOSTICS v_soap_notes_deleted = ROW_COUNT;

  DELETE FROM public.treatment_plans WHERE true;
  GET DIAGNOSTICS v_treatment_plans_deleted = ROW_COUNT;

  DELETE FROM public.visits WHERE true;
  GET DIAGNOSTICS v_visits_deleted = ROW_COUNT;

  DELETE FROM public.appointments WHERE true;
  GET DIAGNOSTICS v_appointments_deleted = ROW_COUNT;

  DELETE FROM public.staff_branch_assignments WHERE true;
  DELETE FROM public.patients WHERE true;
  GET DIAGNOSTICS v_patients_deleted = ROW_COUNT;

  DELETE FROM public.audit_log WHERE true;
  DELETE FROM public.app_settings WHERE true;
  DELETE FROM public.subscription_cache WHERE true;
  DELETE FROM public.branches WHERE true;
  GET DIAGNOSTICS v_branches_deleted = ROW_COUNT;

  DELETE FROM public.organizations WHERE true;
  GET DIAGNOSTICS v_orgs_deleted = ROW_COUNT;

  IF v_had_org AND auth_internal.organization_exists() THEN
    RETURN public.rpc_error(
      'RESET_INCOMPLETE',
      'Organization data could not be removed. Check database permissions and migrations.'
    );
  END IF;

  INSERT INTO public.audit_log (user_id, action, table_name, new_data_json)
  VALUES (
    auth.uid(),
    'organization.dev_reset',
    'organizations',
    jsonb_build_object(
      'organizations_deleted', v_orgs_deleted,
      'branches_deleted', v_branches_deleted,
      'patients_deleted', v_patients_deleted,
      'appointments_deleted', v_appointments_deleted,
      'visits_deleted', v_visits_deleted,
      'soap_notes_deleted', v_soap_notes_deleted,
      'treatment_plans_deleted', v_treatment_plans_deleted,
      'visit_attachments_deleted', v_visit_attachments_deleted,
      'bootstrap_staff_member_id', v_staff.id,
      'had_organization_before_reset', v_had_org
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'organizations_deleted', v_orgs_deleted,
      'branches_deleted', v_branches_deleted,
      'patients_deleted', v_patients_deleted,
      'appointments_deleted', v_appointments_deleted,
      'visits_deleted', v_visits_deleted,
      'soap_notes_deleted', v_soap_notes_deleted,
      'treatment_plans_deleted', v_treatment_plans_deleted,
      'visit_attachments_deleted', v_visit_attachments_deleted,
      'had_organization_before_reset', v_had_org
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'NOT_BOOTSTRAP_ADMIN' THEN
      RETURN public.rpc_error('NOT_BOOTSTRAP_ADMIN', 'Only the bootstrap administrator may reset clinic installation data.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- Storage bucket: visit-attachments
-- -----------------------------------------------------------------------------

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'visit-attachments',
  'visit-attachments',
  false,
  26214400,
  ARRAY[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'image/jpeg',
    'image/png'
  ]::text[]
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS visit_attachments_storage_insert ON storage.objects;
CREATE POLICY visit_attachments_storage_insert ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'visit-attachments'
    AND (storage.foldername(name))[1] = public.jwt_organization_id()::text
    AND ((storage.foldername(name))[2])::uuid = ANY (public.jwt_branch_ids())
    AND array_length(storage.foldername(name), 1) >= 4
    AND auth_internal.staff_has_visit_upload_access()
    AND EXISTS (
      SELECT 1
      FROM public.visits v
      WHERE v.id = ((storage.foldername(name))[3])::uuid
        AND v.branch_id = ((storage.foldername(name))[2])::uuid
        AND v.is_deleted = false
    )
  );

DROP POLICY IF EXISTS visit_attachments_storage_select ON storage.objects;
CREATE POLICY visit_attachments_storage_select ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'visit-attachments'
    AND (storage.foldername(name))[1] = public.jwt_organization_id()::text
    AND ((storage.foldername(name))[2])::uuid = ANY (public.jwt_branch_ids())
    AND (
      auth_internal.staff_has_visit_clinical_access()
      OR (
        auth_internal.staff_has_visit_upload_access()
        AND EXISTS (
          SELECT 1
          FROM public.visit_attachments va
          WHERE va.file_path = name
            AND va.is_deleted = false
            AND va.uploaded_by = public.jwt_staff_member_id()
        )
      )
    )
  );

-- -----------------------------------------------------------------------------
-- public RPC wrappers (SECURITY INVOKER)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_visit(
  p_appointment_id uuid,
  p_doctor_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.create_visit(p_appointment_id, p_doctor_id);
$$;

CREATE OR REPLACE FUNCTION public.save_soap_note(
  p_visit_id uuid,
  p_expected_updated_at timestamptz,
  p_subjective text DEFAULT NULL,
  p_objective text DEFAULT NULL,
  p_assessment text DEFAULT NULL,
  p_plan text DEFAULT NULL,
  p_specialty_form_json jsonb DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.save_soap_note(
    p_visit_id,
    p_expected_updated_at,
    p_subjective,
    p_objective,
    p_assessment,
    p_plan,
    p_specialty_form_json
  );
$$;

CREATE OR REPLACE FUNCTION public.complete_visit(
  p_visit_id uuid,
  p_expected_updated_at timestamptz DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.complete_visit(p_visit_id, p_expected_updated_at);
$$;

CREATE OR REPLACE FUNCTION public.update_appointment_status(
  p_appointment_id uuid,
  p_new_status text
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_appointment_status(p_appointment_id, p_new_status);
$$;

CREATE OR REPLACE FUNCTION public.create_treatment_plan(
  p_visit_id uuid,
  p_medication_name text,
  p_dosage text DEFAULT NULL,
  p_frequency text DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.create_treatment_plan(
    p_visit_id,
    p_medication_name,
    p_dosage,
    p_frequency,
    p_start_date,
    p_end_date,
    p_notes
  );
$$;

CREATE OR REPLACE FUNCTION public.update_treatment_plan(
  p_treatment_plan_id uuid,
  p_medication_name text DEFAULT NULL,
  p_dosage text DEFAULT NULL,
  p_frequency text DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_treatment_plan(
    p_treatment_plan_id,
    p_medication_name,
    p_dosage,
    p_frequency,
    p_start_date,
    p_end_date,
    p_notes
  );
$$;

CREATE OR REPLACE FUNCTION public.archive_treatment_plan(p_treatment_plan_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.archive_treatment_plan(p_treatment_plan_id);
$$;

CREATE OR REPLACE FUNCTION public.register_visit_attachment(
  p_visit_id uuid,
  p_file_path text,
  p_file_type text,
  p_size_bytes bigint,
  p_label text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.register_visit_attachment(
    p_visit_id,
    p_file_path,
    p_file_type,
    p_size_bytes,
    p_label
  );
$$;

CREATE OR REPLACE FUNCTION public.get_visit_attachment_download(p_attachment_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_visit_attachment_download(p_attachment_id);
$$;

CREATE OR REPLACE FUNCTION public.get_visit(p_visit_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_visit(p_visit_id);
$$;

CREATE OR REPLACE FUNCTION public.get_visit_by_appointment(p_appointment_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_visit_by_appointment(p_appointment_id);
$$;

CREATE OR REPLACE FUNCTION public.list_patient_visits(
  p_patient_id uuid,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.list_patient_visits(p_patient_id, p_limit, p_offset);
$$;

CREATE OR REPLACE FUNCTION public.get_specialty_form_schema()
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_specialty_form_schema();
$$;

-- -----------------------------------------------------------------------------
-- Grants
-- -----------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION auth_internal.staff_has_visit_clinical_access() TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.staff_has_visit_upload_access() TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.assert_visit_branch_scope(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.resolve_visit_date_from_appointment(timestamptz, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.soap_note_has_content(text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.validate_visit_attachment_type(text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.validate_specialty_form_json(uuid, jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION auth_internal.create_visit(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.save_soap_note(uuid, timestamptz, text, text, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.complete_visit(uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_appointment_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_treatment_plan(uuid, text, text, text, date, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_treatment_plan(uuid, text, text, text, date, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.archive_treatment_plan(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.register_visit_attachment(uuid, text, text, bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.get_visit_attachment_download(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.get_visit(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.get_visit_by_appointment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.list_patient_visits(uuid, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.get_specialty_form_schema() TO authenticated;

GRANT EXECUTE ON FUNCTION public.create_visit(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_soap_note(uuid, timestamptz, text, text, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_visit(uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_appointment_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_treatment_plan(uuid, text, text, text, date, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_treatment_plan(uuid, text, text, text, date, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_treatment_plan(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_visit_attachment(uuid, text, text, bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_visit_attachment_download(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_visit(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_visit_by_appointment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_patient_visits(uuid, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_specialty_form_schema() TO authenticated;
