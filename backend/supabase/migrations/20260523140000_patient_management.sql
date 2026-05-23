-- =============================================================================
-- V1-3: Patient management (schema, RLS, RPCs)
-- =============================================================================

CREATE TYPE public.patient_gender AS ENUM (
  'male',
  'female',
  'other',
  'unknown'
);

CREATE TABLE public.patients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.branches (id),
  organization_id uuid NOT NULL REFERENCES public.organizations (id),
  full_name text NOT NULL,
  phone text,
  date_of_birth date,
  gender public.patient_gender,
  national_id text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id)
);

CREATE INDEX patients_branch_full_name_idx ON public.patients (branch_id, full_name)
  WHERE is_deleted = false;

CREATE INDEX patients_branch_phone_idx ON public.patients (branch_id, phone)
  WHERE is_deleted = false AND phone IS NOT NULL;

CREATE UNIQUE INDEX patients_org_national_id_unique
  ON public.patients (organization_id, lower(trim(national_id)))
  WHERE national_id IS NOT NULL
    AND trim(national_id) <> ''
    AND is_deleted = false;

CREATE INDEX patients_organization_id_idx ON public.patients (organization_id)
  WHERE is_deleted = false;

SELECT public.apply_standard_audit_triggers('public.patients'::regclass);

ALTER TABLE public.patients ENABLE ROW LEVEL SECURITY;

CREATE POLICY patients_select ON public.patients
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND organization_id = public.jwt_organization_id()
  );

CREATE POLICY patients_insert ON public.patients
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

CREATE POLICY patients_update ON public.patients
  FOR UPDATE
  TO authenticated
  USING (false);

CREATE POLICY patients_delete ON public.patients
  FOR DELETE
  TO authenticated
  USING (false);

-- -----------------------------------------------------------------------------
-- auth_internal.normalize_patient_phone
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.normalize_patient_phone(p_phone text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT NULLIF(regexp_replace(COALESCE(p_phone, ''), '[^0-9]', '', 'g'), '');
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.normalize_patient_national_id
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.normalize_patient_national_id(p_national_id text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT NULLIF(lower(trim(COALESCE(p_national_id, ''))), '');
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.find_patient_duplicate_candidates
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.find_patient_duplicate_candidates(
  p_org_id uuid,
  p_full_name text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_national_id text DEFAULT NULL,
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
  v_normalized_national_id text;
  v_normalized_name text;
  v_candidates jsonb;
BEGIN
  v_normalized_phone := auth_internal.normalize_patient_phone(p_phone);
  v_normalized_national_id := auth_internal.normalize_patient_national_id(p_national_id);
  v_normalized_name := NULLIF(lower(trim(COALESCE(p_full_name, ''))), '');

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', sub.id,
        'full_name', sub.full_name,
        'phone', sub.phone,
        'national_id', sub.national_id,
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
      p.national_id,
      p.date_of_birth,
      b.name AS branch_name
    FROM public.patients p
    JOIN public.branches b ON b.id = p.branch_id
    WHERE p.organization_id = p_org_id
      AND p.is_deleted = false
      AND (p_exclude_patient_id IS NULL OR p.id <> p_exclude_patient_id)
      AND (
        (
          v_normalized_national_id IS NOT NULL
          AND auth_internal.normalize_patient_national_id(p.national_id) = v_normalized_national_id
        )
        OR (
          v_normalized_phone IS NOT NULL
          AND p.phone IS NOT NULL
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
-- auth_internal.assert_org_patient
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_org_patient(
  p_patient_id uuid,
  p_allow_archived boolean DEFAULT false
)
RETURNS public.patients
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_patient public.patients%ROWTYPE;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  SELECT *
  INTO v_patient
  FROM public.patients p
  WHERE p.id = p_patient_id
    AND p.organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND';
  END IF;

  IF v_patient.is_deleted AND NOT p_allow_archived THEN
    RAISE EXCEPTION 'PATIENT_ARCHIVED';
  END IF;

  RETURN v_patient;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.search_patients
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.search_patients(
  p_query text DEFAULT NULL,
  p_scope text DEFAULT 'branch',
  p_branch_id uuid DEFAULT NULL,
  p_limit int DEFAULT 25,
  p_offset int DEFAULT 0
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_query text;
  v_scope text;
  v_is_phone boolean := false;
  v_phone_prefix text;
  v_name_query text;
  v_escaped_name_query text;
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

  v_scope := lower(trim(COALESCE(p_scope, '')));
  IF v_scope NOT IN ('branch', 'organization') THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Scope must be branch or organization.');
  END IF;

  IF v_scope = 'branch' THEN
    IF p_branch_id IS NULL THEN
      RETURN public.rpc_error('BRANCH_REQUIRED', 'Branch id is required for branch scope.');
    END IF;

    IF NOT (p_branch_id = ANY (public.jwt_branch_ids())) THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Branch is not in your assigned branches.');
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.branches b
      WHERE b.id = p_branch_id
        AND b.organization_id = v_org_id
        AND b.is_deleted = false
        AND b.is_active = true
    ) THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Branch is not active for this organization.');
    END IF;
  END IF;

  v_query := NULLIF(trim(COALESCE(p_query, '')), '');
  IF v_query IS NOT NULL THEN
    IF v_query ~ '^[0-9]+$' THEN
      IF length(v_query) < 2 THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Phone search requires at least 2 digits.');
      END IF;
      v_is_phone := true;
      v_phone_prefix := v_query;
    ELSE
      IF length(v_query) < 3 THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Name search requires at least 3 characters.');
      END IF;
      v_name_query := lower(v_query);
      v_escaped_name_query := replace(replace(replace(v_name_query, '\', '\\'), '%', '\%'), '_', '\_');
    END IF;
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  WITH filtered AS (
    SELECT
      p.id,
      p.full_name,
      p.phone,
      p.date_of_birth,
      p.branch_id,
      b.name AS branch_name
    FROM public.patients p
    JOIN public.branches b ON b.id = p.branch_id
    WHERE p.is_deleted = false
      AND p.organization_id = v_org_id
      AND (
        v_scope = 'organization'
        OR p.branch_id = p_branch_id
      )
      AND (
        v_query IS NULL
        OR (
          v_is_phone
          AND p.phone IS NOT NULL
          AND p.phone LIKE v_phone_prefix || '%'
        )
        OR (
          NOT v_is_phone
          AND lower(p.full_name) LIKE '%' || v_escaped_name_query || '%' ESCAPE '\'
        )
      )
  ),
  counted AS (
    SELECT
      f.*,
      count(*) OVER ()::int AS total_count
    FROM filtered f
    ORDER BY f.full_name ASC
    LIMIT v_limit
    OFFSET v_offset
  )
  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'full_name', c.full_name,
          'phone', c.phone,
          'date_of_birth', c.date_of_birth,
          'branch_id', c.branch_id,
          'branch_name', c.branch_name
        )
        ORDER BY c.full_name
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
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view patients.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.get_patient
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
      'national_id', v_patient.national_id,
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
  p_national_id text DEFAULT NULL,
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
    p_national_id,
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
  v_caller public.staff_members%ROWTYPE;
  v_org_id uuid;
  v_branch_org_id uuid;
  v_normalized_phone text;
  v_normalized_national_id text;
  v_candidates jsonb;
  v_patient_id uuid;
  v_gender public.patient_gender;
BEGIN
  v_caller := auth_internal.assert_permission('patients.create');
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  IF NULLIF(trim(p_full_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Full name is required.');
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
      AND auth_internal.normalize_patient_national_id(p.national_id) = v_normalized_national_id
  ) THEN
    RETURN public.rpc_error('NATIONAL_ID_EXISTS', 'This national ID is already registered.');
  END IF;

  IF p_gender IS NOT NULL AND NULLIF(trim(p_gender), '') IS NOT NULL THEN
    BEGIN
      v_gender := trim(p_gender)::public.patient_gender;
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
    national_id,
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
    NULLIF(trim(COALESCE(p_national_id, '')), ''),
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

-- -----------------------------------------------------------------------------
-- auth_internal.archive_patient
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.archive_patient(p_patient_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_patient public.patients%ROWTYPE;
BEGIN
  PERFORM auth_internal.assert_permission('patients.delete');
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  BEGIN
    v_patient := auth_internal.assert_org_patient(p_patient_id, false);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      IF SQLERRM = 'PATIENT_ARCHIVED' THEN
        RETURN public.rpc_error('PATIENT_ARCHIVED', 'This patient is already archived.');
      END IF;
      RAISE;
  END;

  UPDATE public.patients p
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE p.id = p_patient_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'patient.archive',
    'patients',
    p_patient_id,
    jsonb_build_object('full_name', v_patient.full_name, 'branch_id', v_patient.branch_id)
  );

  RETURN public.rpc_success(jsonb_build_object('patient_id', p_patient_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to archive patients.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- public RPC wrappers (SECURITY INVOKER)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.search_patients(
  p_query text DEFAULT NULL,
  p_scope text DEFAULT 'branch',
  p_branch_id uuid DEFAULT NULL,
  p_limit int DEFAULT 25,
  p_offset int DEFAULT 0
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.search_patients(p_query, p_scope, p_branch_id, p_limit, p_offset);
$$;

CREATE OR REPLACE FUNCTION public.get_patient(p_patient_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_patient(p_patient_id);
$$;

CREATE OR REPLACE FUNCTION public.check_patient_duplicates(
  p_full_name text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_national_id text DEFAULT NULL,
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
    p_national_id,
    p_exclude_patient_id
  );
$$;

CREATE OR REPLACE FUNCTION public.create_patient(
  p_active_branch_id uuid,
  p_full_name text,
  p_phone text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_gender text DEFAULT NULL,
  p_national_id text DEFAULT NULL,
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
    p_national_id,
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
  p_national_id text DEFAULT NULL,
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
    p_national_id,
    p_notes,
    p_acknowledge_duplicate
  );
$$;

CREATE OR REPLACE FUNCTION public.archive_patient(p_patient_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.archive_patient(p_patient_id);
$$;

GRANT EXECUTE ON FUNCTION public.search_patients(text, text, uuid, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_patient(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_patient_duplicates(text, text, date, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient(uuid, text, text, date, text, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_patient(uuid, text, timestamptz, text, date, text, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_patient(uuid) TO authenticated;
