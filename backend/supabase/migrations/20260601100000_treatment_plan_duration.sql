-- Treatment plan duration text (replaces start/end date in UI) and richer get_visit payload.

ALTER TABLE public.treatment_plans
  ADD COLUMN IF NOT EXISTS duration text;

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
  p_notes text DEFAULT NULL,
  p_duration text DEFAULT NULL
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

  IF p_duration IS NOT NULL AND length(trim(p_duration)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Duration must be 200 characters or fewer.');
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
    duration,
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
    NULLIF(trim(p_duration), ''),
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
  p_notes text DEFAULT NULL,
  p_duration text DEFAULT NULL
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

  IF p_duration IS NOT NULL AND length(trim(p_duration)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Duration must be 200 characters or fewer.');
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
    duration = CASE WHEN p_duration IS NULL THEN tp.duration ELSE NULLIF(trim(p_duration), '') END,
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

-- Patch get_visit treatment plan payload (preserve existing permission and attachment logic).
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
          'visit_id', tp.visit_id,
          'patient_id', tp.patient_id,
          'medication_name', tp.medication_name,
          'dosage', tp.dosage,
          'frequency', tp.frequency,
          'duration', tp.duration,
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

DROP FUNCTION IF EXISTS public.create_treatment_plan(uuid, text, text, text, date, date, text);

CREATE OR REPLACE FUNCTION public.create_treatment_plan(
  p_visit_id uuid,
  p_medication_name text,
  p_dosage text DEFAULT NULL,
  p_frequency text DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_duration text DEFAULT NULL
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
    p_notes,
    p_duration
  );
$$;

DROP FUNCTION IF EXISTS public.update_treatment_plan(uuid, text, text, text, date, date, text);

CREATE OR REPLACE FUNCTION public.update_treatment_plan(
  p_treatment_plan_id uuid,
  p_medication_name text DEFAULT NULL,
  p_dosage text DEFAULT NULL,
  p_frequency text DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_duration text DEFAULT NULL
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
    p_notes,
    p_duration
  );
$$;

GRANT EXECUTE ON FUNCTION public.create_treatment_plan(uuid, text, text, text, date, date, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_treatment_plan(uuid, text, text, text, date, date, text, text) TO authenticated;
