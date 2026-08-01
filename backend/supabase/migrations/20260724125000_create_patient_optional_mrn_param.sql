-- Optional explicit MRN on create_patient (dev seed / imports). Server still validates format + uniqueness.

DROP FUNCTION IF EXISTS public.create_patient(uuid, text, text, date, text, text, text, boolean);
DROP FUNCTION IF EXISTS auth_internal.create_patient(uuid, text, text, date, text, text, text, boolean);

CREATE OR REPLACE FUNCTION auth_internal.create_patient(
  p_active_branch_id uuid,
  p_full_name text,
  p_phone text,
  p_date_of_birth date DEFAULT NULL,
  p_gender text DEFAULT NULL,
  p_marital_status text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_acknowledge_duplicate boolean DEFAULT false,
  p_mrn text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_org_id uuid;
  v_branch_org_id uuid;
  v_normalized_phone text;
  v_candidates jsonb;
  v_patient_id uuid;
  v_mrn text;
  v_mrn_numeric bigint;
  v_gender public.patient_gender;
  v_marital_status public.patient_marital_status;
BEGIN
  v_caller := auth_internal.assert_permission('patients.create');
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  IF NULLIF(trim(p_full_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Full name is required.');
  END IF;

  v_normalized_phone := auth_internal.normalize_patient_phone(p_phone);
  IF v_normalized_phone IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Mobile number is required.');
  END IF;

  IF length(v_normalized_phone) < 8 OR length(v_normalized_phone) > 15 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Mobile number must contain 8 to 15 digits.');
  END IF;

  IF p_notes IS NOT NULL AND length(trim(p_notes)) > 4000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Notes must be 4000 characters or fewer.');
  END IF;

  IF p_date_of_birth IS NOT NULL AND p_date_of_birth > current_date THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Date of birth cannot be in the future.');
  END IF;

  IF p_active_branch_id IS NULL OR NOT (p_active_branch_id = ANY (public.jwt_branch_ids())) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Active branch is not in your assigned branches.');
  END IF;

  SELECT b.organization_id
  INTO v_branch_org_id
  FROM public.branches b
  WHERE b.id = p_active_branch_id
    AND b.is_deleted = false
    AND b.is_active = true;

  IF NOT FOUND OR v_branch_org_id <> v_org_id THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Active branch is not valid for this organization.');
  END IF;

  IF p_gender IS NOT NULL AND NULLIF(trim(p_gender), '') IS NOT NULL THEN
    BEGIN
      v_gender := trim(p_gender)::public.patient_gender;
    EXCEPTION
      WHEN invalid_text_representation THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Gender must be male or female.');
    END;
  END IF;

  IF p_marital_status IS NOT NULL AND NULLIF(trim(p_marital_status), '') IS NOT NULL THEN
    BEGIN
      v_marital_status := trim(p_marital_status)::public.patient_marital_status;
    EXCEPTION
      WHEN invalid_text_representation THEN
        RETURN public.rpc_error(
          'INVALID_INPUT',
          'Marital status must be single, married, divorced, or widowed.'
        );
    END;
  END IF;

  v_candidates := auth_internal.find_patient_duplicate_candidates(
    v_org_id,
    p_full_name,
    p_phone,
    p_date_of_birth,
    NULL
  );

  IF jsonb_array_length(v_candidates) > 0 AND NOT COALESCE(p_acknowledge_duplicate, false) THEN
    RETURN (
      false,
      jsonb_build_object('candidates', v_candidates),
      'DUPLICATE_WARNING',
      'Similar patients found — review before saving.'
    )::public.rpc_result;
  END IF;

  IF NULLIF(trim(COALESCE(p_mrn, '')), '') IS NOT NULL THEN
    v_mrn := upper(trim(p_mrn));
    IF v_mrn !~ '^MRN-\d{6,}$' THEN
      RETURN public.rpc_error('INVALID_INPUT', 'MRN must be in format MRN-NNNNNN.');
    END IF;

    IF EXISTS (SELECT 1 FROM public.patients p WHERE p.mrn = v_mrn) THEN
      RETURN public.rpc_error(
        'MRN_EXISTS',
        'Another patient already uses this MRN.',
        jsonb_build_object('conflicting_mrn', v_mrn)
      );
    END IF;
  ELSE
    v_mrn := auth_internal.assign_patient_mrn();
  END IF;

  BEGIN
    INSERT INTO public.patients (
      branch_id,
      organization_id,
      full_name,
      phone,
      date_of_birth,
      gender,
      marital_status,
      notes,
      mrn,
      created_by,
      updated_by
    )
    VALUES (
      p_active_branch_id,
      v_org_id,
      trim(p_full_name),
      v_normalized_phone,
      p_date_of_birth,
      v_gender,
      v_marital_status,
      NULLIF(trim(COALESCE(p_notes, '')), ''),
      v_mrn,
      auth.uid(),
      auth.uid()
    )
    RETURNING id INTO v_patient_id;
  EXCEPTION
    WHEN unique_violation THEN
      RETURN public.rpc_error(
        'DUPLICATE_PHONE',
        'A patient with this phone number already exists in the organization.'
      );
  END;

  IF NULLIF(trim(COALESCE(p_mrn, '')), '') IS NOT NULL THEN
    v_mrn_numeric := substring(v_mrn from 'MRN-(\d+)$')::bigint;
    PERFORM setval(
      'public.patient_mrn_seq',
      GREATEST((SELECT last_value FROM public.patient_mrn_seq), v_mrn_numeric),
      true
    );
  END IF;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'patient.create',
    'patients',
    v_patient_id,
    jsonb_build_object(
      'full_name', trim(p_full_name),
      'branch_id', p_active_branch_id,
      'phone', v_normalized_phone,
      'mrn', v_mrn
    )
  );

  RETURN public.rpc_success(jsonb_build_object('patient_id', v_patient_id, 'mrn', v_mrn));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to register patients.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_patient(
  p_active_branch_id uuid,
  p_full_name text,
  p_phone text,
  p_date_of_birth date DEFAULT NULL,
  p_gender text DEFAULT NULL,
  p_marital_status text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_acknowledge_duplicate boolean DEFAULT false,
  p_mrn text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.create_patient(
    p_active_branch_id,
    p_full_name,
    p_phone,
    p_date_of_birth,
    p_gender,
    p_marital_status,
    p_notes,
    p_acknowledge_duplicate,
    p_mrn
  );
$$;

REVOKE ALL ON FUNCTION auth_internal.create_patient(uuid, text, text, date, text, text, text, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth_internal.create_patient(uuid, text, text, date, text, text, text, boolean, text) TO authenticated;

REVOKE ALL ON FUNCTION public.create_patient(uuid, text, text, date, text, text, text, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_patient(uuid, text, text, date, text, text, text, boolean, text) TO authenticated;
