-- Preserve existing gender when update_patient omits p_gender (V1-3 fix).

CREATE OR REPLACE FUNCTION auth_internal.update_patient(
  p_patient_id uuid,
  p_full_name text,
  p_expected_updated_at timestamptz,
  p_phone text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_gender text DEFAULT NULL,
  p_national_id text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_acknowledge_duplicate boolean DEFAULT false
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_patient public.patients%ROWTYPE;
  v_old public.patients%ROWTYPE;
  v_new public.patients%ROWTYPE;
  v_normalized_phone text;
  v_normalized_national_id text;
  v_candidates jsonb;
  v_gender public.patient_gender;
  v_apply_gender boolean := false;
BEGIN
  PERFORM auth_internal.assert_permission('patients.edit');
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  IF NULLIF(trim(p_full_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Full name is required.');
  END IF;

  IF p_expected_updated_at IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
  END IF;

  IF p_notes IS NOT NULL AND length(trim(p_notes)) > 4000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Notes must be 4000 characters or fewer.');
  END IF;

  IF p_date_of_birth IS NOT NULL AND p_date_of_birth > current_date THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Date of birth cannot be in the future.');
  END IF;

  BEGIN
    v_patient := auth_internal.assert_org_patient(p_patient_id, false);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      IF SQLERRM = 'PATIENT_ARCHIVED' THEN
        RETURN public.rpc_error('PATIENT_ARCHIVED', 'This patient is archived and cannot be edited.');
      END IF;
      RAISE;
  END;

  v_old := v_patient;

  IF v_patient.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RETURN public.rpc_error('STALE_PATIENT', 'This record was updated elsewhere. Reload and try again.');
  END IF;

  v_normalized_phone := auth_internal.normalize_patient_phone(p_phone);
  IF v_normalized_phone IS NOT NULL AND (length(v_normalized_phone) < 8 OR length(v_normalized_phone) > 15) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Phone must contain 8 to 15 digits when provided.');
  END IF;

  v_normalized_national_id := auth_internal.normalize_patient_national_id(p_national_id);
  IF v_normalized_national_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.patients p
    WHERE p.organization_id = v_org_id
      AND p.is_deleted = false
      AND p.id <> p_patient_id
      AND auth_internal.normalize_patient_national_id(p.national_id) = v_normalized_national_id
  ) THEN
    RETURN public.rpc_error('NATIONAL_ID_EXISTS', 'This national ID is already registered.');
  END IF;

  IF p_gender IS NOT NULL AND NULLIF(trim(p_gender), '') IS NOT NULL THEN
    BEGIN
      v_gender := trim(p_gender)::public.patient_gender;
      v_apply_gender := true;
    EXCEPTION
      WHEN invalid_text_representation THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Gender must be male, female, other, or unknown.');
    END;
  END IF;

  v_candidates := auth_internal.find_patient_duplicate_candidates(
    v_org_id,
    p_full_name,
    p_phone,
    p_date_of_birth,
    p_national_id,
    p_patient_id
  );

  IF jsonb_array_length(v_candidates) > 0 AND NOT COALESCE(p_acknowledge_duplicate, false) THEN
    RETURN (
      false,
      jsonb_build_object('candidates', v_candidates),
      'DUPLICATE_WARNING',
      'Similar patients found — review before saving.'
    )::public.rpc_result;
  END IF;

  UPDATE public.patients p
  SET
    full_name = trim(p_full_name),
    phone = v_normalized_phone,
    date_of_birth = p_date_of_birth,
    gender = CASE WHEN v_apply_gender THEN v_gender ELSE p.gender END,
    national_id = NULLIF(trim(COALESCE(p_national_id, '')), ''),
    notes = NULLIF(trim(COALESCE(p_notes, '')), ''),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE p.id = p_patient_id
  RETURNING * INTO v_new;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'patient.update',
    'patients',
    p_patient_id,
    jsonb_build_object(
      'full_name', v_old.full_name,
      'phone', v_old.phone,
      'date_of_birth', v_old.date_of_birth,
      'gender', v_old.gender::text,
      'national_id', v_old.national_id,
      'notes', v_old.notes
    ),
    jsonb_build_object(
      'full_name', v_new.full_name,
      'phone', v_new.phone,
      'date_of_birth', v_new.date_of_birth,
      'gender', v_new.gender::text,
      'national_id', v_new.national_id,
      'notes', v_new.notes
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'patient_id', p_patient_id,
      'updated_at', v_new.updated_at
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to edit patients.');
    END IF;
    RAISE;
END;
$$;
