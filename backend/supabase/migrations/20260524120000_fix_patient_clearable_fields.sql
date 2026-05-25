-- Fix 15: Add ability to clear optional patient fields (gender, date_of_birth,
-- marital_status, notes) by passing explicit p_clear_* boolean flags.
-- Previously, passing NULL for these fields preserved the existing value but
-- there was no way to intentionally set them back to NULL.

-- The function signature changes (new parameters added), so we must DROP old
-- versions and CREATE new ones for both auth_internal and public wrappers.

DROP FUNCTION IF EXISTS public.update_patient(uuid, text, timestamptz, text, date, text, text, text, boolean);
DROP FUNCTION IF EXISTS auth_internal.update_patient(uuid, text, timestamptz, text, date, text, text, text, boolean);

-- =============================================================================
-- auth_internal.update_patient (with clearable fields)
-- =============================================================================

CREATE OR REPLACE FUNCTION auth_internal.update_patient(
  p_patient_id uuid,
  p_full_name text,
  p_expected_updated_at timestamptz,
  p_phone text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_gender text DEFAULT NULL,
  p_marital_status text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_acknowledge_duplicate boolean DEFAULT false,
  p_clear_gender boolean DEFAULT false,
  p_clear_date_of_birth boolean DEFAULT false,
  p_clear_marital_status boolean DEFAULT false,
  p_clear_notes boolean DEFAULT false
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
  v_candidates jsonb;
  v_gender public.patient_gender;
  v_marital_status public.patient_marital_status;
  v_apply_phone boolean := false;
  v_apply_date_of_birth boolean := false;
  v_apply_gender boolean := false;
  v_apply_marital_status boolean := false;
  v_apply_notes boolean := false;
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

  -- Phone handling
  IF p_phone IS NOT NULL THEN
    v_normalized_phone := auth_internal.normalize_patient_phone(p_phone);
    IF v_normalized_phone IS NULL THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Mobile number is required.');
    END IF;
    IF length(v_normalized_phone) < 8 OR length(v_normalized_phone) > 15 THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Mobile number must contain 8 to 15 digits.');
    END IF;
    v_apply_phone := true;
  END IF;

  -- Date of birth: clear takes priority over value
  IF p_clear_date_of_birth THEN
    v_apply_date_of_birth := true;
  ELSIF p_date_of_birth IS NOT NULL THEN
    v_apply_date_of_birth := true;
  END IF;

  -- Notes: clear takes priority over value
  IF p_clear_notes THEN
    v_apply_notes := true;
  ELSIF p_notes IS NOT NULL THEN
    v_apply_notes := true;
  END IF;

  -- Gender: clear takes priority over value
  IF p_clear_gender THEN
    v_apply_gender := true;
    v_gender := NULL;
  ELSIF p_gender IS NOT NULL AND NULLIF(trim(p_gender), '') IS NOT NULL THEN
    BEGIN
      v_gender := trim(p_gender)::public.patient_gender;
      v_apply_gender := true;
    EXCEPTION
      WHEN invalid_text_representation THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Gender must be male or female.');
    END;
  END IF;

  -- Marital status: clear takes priority over value
  IF p_clear_marital_status THEN
    v_apply_marital_status := true;
    v_marital_status := NULL;
  ELSIF p_marital_status IS NOT NULL AND NULLIF(trim(p_marital_status), '') IS NOT NULL THEN
    BEGIN
      v_marital_status := trim(p_marital_status)::public.patient_marital_status;
      v_apply_marital_status := true;
    EXCEPTION
      WHEN invalid_text_representation THEN
        RETURN public.rpc_error(
          'INVALID_INPUT',
          'Marital status must be single, married, divorced, or widowed.'
        );
    END;
  END IF;

  -- Duplicate check
  v_candidates := auth_internal.find_patient_duplicate_candidates(
    v_org_id,
    p_full_name,
    COALESCE(p_phone, v_patient.phone),
    CASE WHEN p_clear_date_of_birth THEN NULL ELSE COALESCE(p_date_of_birth, v_patient.date_of_birth) END,
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
    phone = CASE WHEN v_apply_phone THEN v_normalized_phone ELSE p.phone END,
    date_of_birth = CASE
      WHEN p_clear_date_of_birth THEN NULL
      WHEN v_apply_date_of_birth THEN p_date_of_birth
      ELSE p.date_of_birth
    END,
    gender = CASE
      WHEN p_clear_gender THEN NULL
      WHEN v_apply_gender THEN v_gender
      ELSE p.gender
    END,
    marital_status = CASE
      WHEN p_clear_marital_status THEN NULL
      WHEN v_apply_marital_status THEN v_marital_status
      ELSE p.marital_status
    END,
    notes = CASE
      WHEN p_clear_notes THEN NULL
      WHEN v_apply_notes THEN NULLIF(trim(COALESCE(p_notes, '')), '')
      ELSE p.notes
    END,
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
      'marital_status', v_old.marital_status::text,
      'notes', v_old.notes
    ),
    jsonb_build_object(
      'full_name', v_new.full_name,
      'phone', v_new.phone,
      'date_of_birth', v_new.date_of_birth,
      'gender', v_new.gender::text,
      'marital_status', v_new.marital_status::text,
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

-- =============================================================================
-- Public INVOKER wrapper (new signature with clear flags)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.update_patient(
  p_patient_id uuid,
  p_full_name text,
  p_expected_updated_at timestamptz,
  p_phone text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_gender text DEFAULT NULL,
  p_marital_status text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_acknowledge_duplicate boolean DEFAULT false,
  p_clear_gender boolean DEFAULT false,
  p_clear_date_of_birth boolean DEFAULT false,
  p_clear_marital_status boolean DEFAULT false,
  p_clear_notes boolean DEFAULT false
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_patient(
    p_patient_id,
    p_full_name,
    p_expected_updated_at,
    p_phone,
    p_date_of_birth,
    p_gender,
    p_marital_status,
    p_notes,
    p_acknowledge_duplicate,
    p_clear_gender,
    p_clear_date_of_birth,
    p_clear_marital_status,
    p_clear_notes
  );
$$;

REVOKE ALL ON FUNCTION public.update_patient(uuid, text, timestamptz, text, date, text, text, text, boolean, boolean, boolean, boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_patient(uuid, text, timestamptz, text, date, text, text, text, boolean, boolean, boolean, boolean, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_patient(uuid, text, timestamptz, text, date, text, text, text, boolean, boolean, boolean, boolean, boolean) TO authenticated;
