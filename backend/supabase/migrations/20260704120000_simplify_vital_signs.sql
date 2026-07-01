-- Simplify vital signs: drop measured_at, remove Pain Score catalog seed and data.

-- get_patient_safety_context: last vitals no longer expose measured_at
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
          'unit', vvs.unit
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

-- get_visit: vital signs payload without measured_at
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
      'plan_details', v_plan_details,
      'pending_investigations', COALESCE(v_pending_investigations, '[]'::jsonb)
    );
  END IF;

  RETURN public.rpc_success(v_payload);
END;
$$;

-- Vital sign RPCs: revert to 013 shape (no measured_at parameter)
DROP FUNCTION IF EXISTS public.create_visit_vital_sign(uuid, text, text, text, uuid, timestamptz);
DROP FUNCTION IF EXISTS public.update_visit_vital_sign(uuid, text, text, text, uuid, timestamptz);
DROP FUNCTION IF EXISTS auth_internal.create_visit_vital_sign(uuid, text, text, text, uuid, timestamptz);
DROP FUNCTION IF EXISTS auth_internal.update_visit_vital_sign(uuid, text, text, text, uuid, timestamptz);

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

CREATE OR REPLACE FUNCTION public.create_visit_vital_sign(
  p_visit_id uuid,
  p_name text,
  p_value text,
  p_unit text DEFAULT NULL,
  p_predefined_vital_sign_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.create_visit_vital_sign(p_visit_id, p_name, p_value, p_unit, p_predefined_vital_sign_id); $$;

CREATE OR REPLACE FUNCTION public.update_visit_vital_sign(
  p_vital_sign_id uuid,
  p_name text DEFAULT NULL,
  p_value text DEFAULT NULL,
  p_unit text DEFAULT NULL,
  p_predefined_vital_sign_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql SECURITY INVOKER SET search_path = public, auth_internal
AS $$ SELECT auth_internal.update_visit_vital_sign(p_vital_sign_id, p_name, p_value, p_unit, p_predefined_vital_sign_id); $$;

GRANT EXECUTE ON FUNCTION auth_internal.create_visit_vital_sign(uuid, text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_visit_vital_sign(uuid, text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_visit_vital_sign(uuid, text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_visit_vital_sign(uuid, text, text, text, uuid) TO authenticated;

ALTER TABLE public.visit_vital_signs DROP COLUMN IF EXISTS measured_at;

-- Retire Pain Score from catalog and visit lines
UPDATE public.visit_vital_signs
SET is_deleted = true, deleted_at = now()
WHERE is_deleted = false AND lower(trim(name)) = lower('Pain Score');

UPDATE public.predefined_vital_signs
SET is_deleted = true, deleted_at = now()
WHERE is_deleted = false AND lower(trim(name)) = lower('Pain Score');

-- Org catalog seed: no Pain Score
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
