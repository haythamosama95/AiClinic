-- =============================================================================
-- V1-3: Patient registration field updates
-- - Remove national_id
-- - Require phone (mobile)
-- - Restrict gender to male/female
-- - Add marital_status
-- =============================================================================

DO $$
BEGIN
  CREATE TYPE public.patient_marital_status AS ENUM (
    'single',
    'married',
    'divorced',
    'widowed'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS marital_status public.patient_marital_status;

UPDATE public.patients
SET gender = NULL
WHERE gender::text IN ('other', 'unknown');

UPDATE public.patients
SET phone = '00000000' || replace(id::text, '-', '')
WHERE phone IS NULL
  AND is_deleted = false;

DROP INDEX IF EXISTS public.patients_org_national_id_unique;

ALTER TABLE public.patients
  DROP COLUMN IF EXISTS national_id;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'patients'
      AND column_name = 'phone'
      AND is_nullable = 'YES'
  ) THEN
    ALTER TABLE public.patients
      ALTER COLUMN phone SET NOT NULL;
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    WHERE t.typname = 'patient_gender'
      AND e.enumlabel IN ('other', 'unknown')
  ) THEN
    CREATE TYPE public.patient_gender_new AS ENUM ('male', 'female');

    ALTER TABLE public.patients
      ALTER COLUMN gender TYPE public.patient_gender_new
      USING gender::text::public.patient_gender_new;

    DROP TYPE public.patient_gender;

    ALTER TYPE public.patient_gender_new RENAME TO patient_gender;
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS auth_internal.normalize_patient_national_id(text);

-- Parameter lists change (national_id removed, marital_status added). DROP required;
-- CREATE OR REPLACE cannot rename or reorder parameters (SQLSTATE 42P13).
DROP FUNCTION IF EXISTS public.check_patient_duplicates(text, text, date, text, uuid);
DROP FUNCTION IF EXISTS public.create_patient(uuid, text, text, date, text, text, text, boolean);
DROP FUNCTION IF EXISTS public.update_patient(uuid, text, timestamptz, text, date, text, text, text, boolean);

DROP FUNCTION IF EXISTS auth_internal.check_patient_duplicates(text, text, date, text, uuid);
DROP FUNCTION IF EXISTS auth_internal.create_patient(uuid, text, text, date, text, text, text, boolean);
DROP FUNCTION IF EXISTS auth_internal.update_patient(uuid, text, timestamptz, text, date, text, text, text, boolean);
DROP FUNCTION IF EXISTS auth_internal.find_patient_duplicate_candidates(uuid, text, text, date, text, uuid);

-- -----------------------------------------------------------------------------
-- auth_internal.find_patient_duplicate_candidates
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.find_patient_duplicate_candidates(
  p_org_id uuid,
  p_full_name text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_exclude_patient_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_normalized_phone text;
  v_normalized_name text;
  v_candidates jsonb;
BEGIN
  v_normalized_phone := auth_internal.normalize_patient_phone(p_phone);
  v_normalized_name := NULLIF(lower(trim(COALESCE(p_full_name, ''))), '');

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', sub.id,
        'full_name', sub.full_name,
        'phone', sub.phone,
        'date_of_birth', sub.date_of_birth,
        'branch_name', sub.branch_name
      )
      ORDER BY sub.full_name
    ),
    '[]'::jsonb
  )
  INTO v_candidates
  FROM (
    SELECT DISTINCT ON (p.id)
      p.id,
      p.full_name,
      p.phone,
      p.date_of_birth,
      b.name AS branch_name
    FROM public.patients p
    JOIN public.branches b ON b.id = p.branch_id
    WHERE p.organization_id = p_org_id
      AND p.is_deleted = false
      AND (p_exclude_patient_id IS NULL OR p.id <> p_exclude_patient_id)
      AND (
        (
          v_normalized_phone IS NOT NULL
          AND p.phone IS NOT NULL
          AND NOT (p.phone LIKE '00000000%' AND length(p.phone) > 8)
          AND p.phone = v_normalized_phone
        )
        OR (
          v_normalized_name IS NOT NULL
          AND p.date_of_birth IS NOT NULL
          AND p_date_of_birth IS NOT NULL
          AND lower(trim(p.full_name)) = v_normalized_name
          AND p.date_of_birth = p_date_of_birth
        )
      )
    ORDER BY p.id, p.full_name
  ) sub;

  RETURN v_candidates;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.get_patient (marital_status in payload)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_patient(p_patient_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_patient public.patients%ROWTYPE;
  v_branch_name text;
  v_created_by_display text;
BEGIN
  PERFORM auth_internal.assert_permission('patients.view');

  BEGIN
    v_patient := auth_internal.assert_org_patient(p_patient_id, false);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      IF SQLERRM = 'PATIENT_ARCHIVED' THEN
        RETURN public.rpc_error('PATIENT_ARCHIVED', 'This patient is archived.');
      END IF;
      IF SQLERRM = 'FORBIDDEN' THEN
        RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view this patient.');
      END IF;
      RAISE;
  END;

  SELECT b.name
  INTO v_branch_name
  FROM public.branches b
  WHERE b.id = v_patient.branch_id;

  SELECT sm.full_name
  INTO v_created_by_display
  FROM public.staff_members sm
  WHERE sm.auth_user_id = v_patient.created_by
    AND sm.is_deleted = false
  LIMIT 1;

  RETURN public.rpc_success(
    jsonb_build_object(
      'id', v_patient.id,
      'full_name', v_patient.full_name,
      'phone', v_patient.phone,
      'date_of_birth', v_patient.date_of_birth,
      'gender', v_patient.gender::text,
      'marital_status', v_patient.marital_status::text,
      'notes', v_patient.notes,
      'branch_id', v_patient.branch_id,
      'branch_name', v_branch_name,
      'created_at', v_patient.created_at,
      'updated_at', v_patient.updated_at,
      'created_by_display', v_created_by_display
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view patients.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.check_patient_duplicates
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.check_patient_duplicates(
  p_full_name text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_exclude_patient_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_candidates jsonb;
BEGIN
  IF NOT (
    EXISTS (
      SELECT 1
      FROM public.current_staff_member_row() sm
      JOIN public.roles_permissions rp ON rp.role = sm.role
      WHERE rp.permission_key IN ('patients.create', 'patients.edit')
        AND rp.is_granted = true
        AND rp.is_deleted = false
    )
  ) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to check patient duplicates.');
  END IF;

  v_org_id := public.jwt_organization_id();
  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  IF p_exclude_patient_id IS NOT NULL THEN
    PERFORM auth_internal.assert_org_patient(p_exclude_patient_id, false);
  END IF;

  v_candidates := auth_internal.find_patient_duplicate_candidates(
    v_org_id,
    p_full_name,
    p_phone,
    p_date_of_birth,
    p_exclude_patient_id
  );

  RETURN public.rpc_success(jsonb_build_object('candidates', v_candidates));
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
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.create_patient
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_patient(
  p_active_branch_id uuid,
  p_full_name text,
  p_phone text,
  p_date_of_birth date DEFAULT NULL,
  p_gender text DEFAULT NULL,
  p_marital_status text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_acknowledge_duplicate boolean DEFAULT false
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

  INSERT INTO public.patients (
    branch_id,
    organization_id,
    full_name,
    phone,
    date_of_birth,
    gender,
    marital_status,
    notes,
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
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_patient_id;

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
      'phone', v_normalized_phone
    )
  );

  RETURN public.rpc_success(jsonb_build_object('patient_id', v_patient_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to register patients.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.update_patient
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.update_patient(
  p_patient_id uuid,
  p_full_name text,
  p_expected_updated_at timestamptz,
  p_phone text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_gender text DEFAULT NULL,
  p_marital_status text DEFAULT NULL,
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
  v_candidates jsonb;
  v_gender public.patient_gender;
  v_marital_status public.patient_marital_status;
  v_apply_gender boolean := false;
  v_apply_marital_status boolean := false;
  v_apply_phone boolean := false;
  v_apply_date_of_birth boolean := false;
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

  IF p_date_of_birth IS NOT NULL THEN
    v_apply_date_of_birth := true;
  END IF;

  IF p_notes IS NOT NULL THEN
    v_apply_notes := true;
  END IF;

  IF p_gender IS NOT NULL AND NULLIF(trim(p_gender), '') IS NOT NULL THEN
    BEGIN
      v_gender := trim(p_gender)::public.patient_gender;
      v_apply_gender := true;
    EXCEPTION
      WHEN invalid_text_representation THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Gender must be male or female.');
    END;
  END IF;

  IF p_marital_status IS NOT NULL AND NULLIF(trim(p_marital_status), '') IS NOT NULL THEN
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

  v_candidates := auth_internal.find_patient_duplicate_candidates(
    v_org_id,
    p_full_name,
    COALESCE(p_phone, v_patient.phone),
    p_date_of_birth,
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
    date_of_birth = CASE WHEN v_apply_date_of_birth THEN p_date_of_birth ELSE p.date_of_birth END,
    gender = CASE WHEN v_apply_gender THEN v_gender ELSE p.gender END,
    marital_status = CASE WHEN v_apply_marital_status THEN v_marital_status ELSE p.marital_status END,
    notes = CASE WHEN v_apply_notes THEN NULLIF(trim(COALESCE(p_notes, '')), '') ELSE p.notes END,
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

-- -----------------------------------------------------------------------------
-- public RPC wrappers (new signatures)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.check_patient_duplicates(
  p_full_name text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_exclude_patient_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.check_patient_duplicates(
    p_full_name,
    p_phone,
    p_date_of_birth,
    p_exclude_patient_id
  );
$$;

CREATE OR REPLACE FUNCTION public.create_patient(
  p_active_branch_id uuid,
  p_full_name text,
  p_phone text,
  p_date_of_birth date DEFAULT NULL,
  p_gender text DEFAULT NULL,
  p_marital_status text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_acknowledge_duplicate boolean DEFAULT false
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
    p_acknowledge_duplicate
  );
$$;

CREATE OR REPLACE FUNCTION public.update_patient(
  p_patient_id uuid,
  p_full_name text,
  p_expected_updated_at timestamptz,
  p_phone text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_gender text DEFAULT NULL,
  p_marital_status text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_acknowledge_duplicate boolean DEFAULT false
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
    p_acknowledge_duplicate
  );
$$;

REVOKE ALL ON FUNCTION public.check_patient_duplicates(text, text, date, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_patient(uuid, text, text, date, text, text, text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_patient(uuid, text, timestamptz, text, date, text, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.check_patient_duplicates(text, text, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient(uuid, text, text, date, text, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_patient(uuid, text, timestamptz, text, date, text, text, text, boolean) TO authenticated;
