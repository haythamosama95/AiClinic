-- =============================================================================
-- P5.1: Issuer key custody, versioned issue RPCs, and installation key removal.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T007: ai_internal.issuer_key and auth_internal.insert_issuer_kid
-- -----------------------------------------------------------------------------

CREATE TABLE ai_internal.issuer_key (
  kid text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  public_key text NOT NULL,
  secret_ref uuid NOT NULL,
  status text NOT NULL,
  not_before timestamptz NOT NULL,
  not_after timestamptz NOT NULL,
  CONSTRAINT issuer_key_status_check CHECK (status IN ('signing', 'next', 'retired'))
);

CREATE UNIQUE INDEX issuer_key_one_signing_idx
  ON ai_internal.issuer_key ((true))
  WHERE status = 'signing';

CREATE UNIQUE INDEX issuer_key_one_next_idx
  ON ai_internal.issuer_key ((true))
  WHERE status = 'next';

ALTER TABLE ai_internal.issuer_key ENABLE ROW LEVEL SECURITY;

CREATE POLICY issuer_key_deny_all ON ai_internal.issuer_key
  FOR ALL
  USING (false);

CREATE OR REPLACE FUNCTION auth_internal.insert_issuer_kid()
RETURNS TABLE (
  kid text,
  public_key text,
  status text,
  not_before timestamptz,
  not_after timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium, vault, auth_internal
AS $$
DECLARE
  v_existing_next ai_internal.issuer_key%ROWTYPE;
  v_has_signing boolean;
  v_keypair record;
  v_kid text;
  v_secret_ref uuid;
  v_public_key text;
  v_status text;
  v_not_before timestamptz;
  v_not_after timestamptz;
BEGIN
  SELECT ik.*
  INTO v_existing_next
  FROM ai_internal.issuer_key ik
  WHERE ik.status = 'next'
  LIMIT 1;

  IF FOUND THEN
    RETURN QUERY
    SELECT
      v_existing_next.kid,
      v_existing_next.public_key,
      v_existing_next.status,
      v_existing_next.not_before,
      v_existing_next.not_after;
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM ai_internal.issuer_key ik
    WHERE ik.status = 'signing'
  )
  INTO v_has_signing;

  SELECT kp.public, kp.secret
  INTO v_keypair
  FROM pgsodium.crypto_sign_new_keypair() kp;

  v_kid := gen_random_uuid()::text;
  v_public_key := auth_internal.base64url_encode(v_keypair.public);
  v_secret_ref := vault.create_secret(
    encode(v_keypair.secret, 'base64'),
    'issuer-key-' || v_kid,
    'Ed25519 issuer private key'
  );
  v_not_before := clock_timestamp();
  v_not_after := v_not_before + interval '13 months';
  v_status := CASE WHEN v_has_signing THEN 'next' ELSE 'signing' END;

  INSERT INTO ai_internal.issuer_key (
    kid,
    public_key,
    secret_ref,
    status,
    not_before,
    not_after
  )
  VALUES (
    v_kid,
    v_public_key,
    v_secret_ref,
    v_status,
    v_not_before,
    v_not_after
  );

  RETURN QUERY
  SELECT v_kid, v_public_key, v_status, v_not_before, v_not_after;
END;
$$;

REVOKE ALL ON FUNCTION auth_internal.insert_issuer_kid() FROM PUBLIC, anon, authenticated, service_role;

SELECT auth_internal.insert_issuer_kid();

-- -----------------------------------------------------------------------------
-- T008: Drop installation keys and enroll / rotate / revoke RPCs
-- -----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS installation_keys_single_installation
  ON ai_internal.installation_keys;

DROP FUNCTION IF EXISTS public.enroll_installation_keypair();
DROP FUNCTION IF EXISTS public.rotate_installation_key();
DROP FUNCTION IF EXISTS public.revoke_installation_key(text);
DROP FUNCTION IF EXISTS auth_internal.enroll_installation_keypair();
DROP FUNCTION IF EXISTS auth_internal.rotate_installation_key();
DROP FUNCTION IF EXISTS auth_internal.revoke_installation_key(text);
DROP FUNCTION IF EXISTS public.issue_ai_token(text[]);
DROP FUNCTION IF EXISTS auth_internal.issue_ai_token(text[]);

DROP FUNCTION IF EXISTS ai_internal.enforce_single_installation();

DROP TABLE IF EXISTS ai_internal.installation_keys;

ALTER TABLE ai_internal.ai_token_issuance
  DROP COLUMN IF EXISTS installation_id;

-- -----------------------------------------------------------------------------
-- T009: App settings for issuer id, base URLs, and contract versions
-- -----------------------------------------------------------------------------

INSERT INTO ai_internal.app_settings (key, value_json)
VALUES
  ('ai.issuer_id', '"issuer-test"'::jsonb),
  ('ai.platform_base_url', '"http://127.0.0.1:8787"'::jsonb),
  ('ai.abo_base_url', '"http://127.0.0.1:8788"'::jsonb),
  (
    'ai.contract_versions',
    '{
      "aboClinic": {"current": 1, "minimum": 0},
      "aboConsole": {"current": 1, "minimum": 0},
      "backendRpc": {"current": 1, "minimum": 0},
      "platformClinic": {"current": 1, "minimum": 0},
      "platformFeed": {"current": 1, "minimum": 0},
      "vendorEntrypoint": {"current": 1, "minimum": 0},
      "platformDo": {"current": 1, "minimum": 0},
      "paymobReturn": {"current": 1, "minimum": 0},
      "paymobAdapter": {"current": 1, "minimum": 0}
    }'::jsonb
  )
ON CONFLICT (key) DO UPDATE
SET value_json = EXCLUDED.value_json,
    updated_at = now();

-- -----------------------------------------------------------------------------
-- T010: Per-audience issuance rows on ai_token_issuance
-- -----------------------------------------------------------------------------

ALTER TABLE ai_internal.ai_token_issuance
  ADD COLUMN IF NOT EXISTS aud text;

UPDATE ai_internal.ai_token_issuance
SET aud = 'ai-platform'
WHERE aud IS NULL;

ALTER TABLE ai_internal.ai_token_issuance
  ALTER COLUMN aud SET NOT NULL;

CREATE INDEX IF NOT EXISTS ai_token_issuance_actor_aud_iat_idx
  ON ai_internal.ai_token_issuance (actor_staff_id, aud, iat DESC)
  WHERE is_deleted = false;

-- -----------------------------------------------------------------------------
-- T011: rpc_result contract_version and helper RPC updates
-- -----------------------------------------------------------------------------

ALTER TYPE public.rpc_result ADD ATTRIBUTE contract_version integer;

DROP FUNCTION IF EXISTS public.rpc_success(jsonb);
DROP FUNCTION IF EXISTS public.rpc_error(text, text);

CREATE OR REPLACE FUNCTION public.rpc_success(
  p_data jsonb DEFAULT '{}'::jsonb,
  p_contract_version integer DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT (true, p_data, NULL::text, NULL::text, p_contract_version)::public.rpc_result;
$$;

CREATE OR REPLACE FUNCTION public.rpc_error(
  p_code text,
  p_message text,
  p_contract_version integer DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT (false, NULL::jsonb, p_code, p_message, p_contract_version)::public.rpc_result;
$$;

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
      'Similar patients found — review before saving.',
      NULL::integer
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
        'Another patient already uses this MRN.'
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

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'patient.create',
    'patients',
    v_patient_id,
    jsonb_build_object('patient_id', v_patient_id, 'mrn', v_mrn)
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

CREATE OR REPLACE FUNCTION auth_internal.invoke_acceptance_domain_rpc(
  p_domain_function text,
  p_target_args jsonb
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_oid oid;
  v_argnames text[];
  v_argtypes oidvector;
  v_nargs int;
  v_parts text[] := ARRAY[]::text[];
  v_i int;
  v_sql text;
  v_success boolean;
  v_data jsonb;
  v_error_code text;
  v_error_message text;
BEGIN
  IF p_domain_function IS NULL OR length(trim(p_domain_function)) = 0 THEN
    RETURN public.rpc_error('INTERNAL_ERROR', 'Domain function is not configured.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM ai_internal.acceptance_targets t
    WHERE t.domain_function = p_domain_function
  ) THEN
    RETURN public.rpc_error('INTERNAL_ERROR', 'Domain function is not configured.');
  END IF;

  SELECT p.oid, p.proargnames, p.proargtypes
  INTO v_oid, v_argnames, v_argtypes
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = p_domain_function
    AND p.prokind = 'f'
    AND pg_get_function_result(p.oid) = 'rpc_result'
  ORDER BY p.oid
  LIMIT 1;

  IF v_oid IS NULL THEN
    RETURN public.rpc_error('INTERNAL_ERROR', 'Domain function is not configured.');
  END IF;

  v_nargs := coalesce(array_length(v_argnames, 1), 0);
  IF v_nargs = 0 THEN
    RETURN public.rpc_error('INTERNAL_ERROR', 'Domain function is not configured.');
  END IF;

  FOR v_i IN 1 .. v_nargs LOOP
    v_parts := v_parts || format(
      '($1->>%L)::%s',
      v_argnames[v_i],
      format_type(v_argtypes[v_i - 1], NULL)
    );
  END LOOP;

  v_sql := format(
    'SELECT r.success, r.data, r.error_code, r.error_message FROM public.%I(%s) AS r',
    p_domain_function,
    array_to_string(v_parts, ', ')
  );
  EXECUTE v_sql
    USING coalesce(p_target_args, '{}'::jsonb)
    INTO v_success, v_data, v_error_code, v_error_message;

  RETURN (v_success, v_data, v_error_code, v_error_message, NULL::integer)::public.rpc_result;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.reassign_patient_mrn(
  p_patient_id uuid,
  p_new_mrn text
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_patient public.patients%ROWTYPE;
  v_old_mrn text;
  v_new_mrn text;
  v_conflict uuid;
BEGIN
  PERFORM auth_internal.assert_permission('patients.reassign_mrn');
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
        RETURN public.rpc_error('PATIENT_ARCHIVED', 'This patient is archived and its MRN cannot be reassigned.');
      END IF;
      RAISE;
  END;

  v_old_mrn := v_patient.mrn;
  v_new_mrn := upper(trim(p_new_mrn));

  IF NULLIF(v_new_mrn, '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'MRN must be in format MRN-NNNNNN.');
  END IF;

  IF v_new_mrn !~ '^MRN-\d{6,}$' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'MRN must be in format MRN-NNNNNN.');
  END IF;

  IF v_new_mrn = v_old_mrn THEN
    RETURN public.rpc_error('INVALID_INPUT', 'MRN is already set to this value.');
  END IF;

  SELECT p.id
  INTO v_conflict
  FROM public.patients p
  WHERE p.mrn = v_new_mrn
    AND p.id <> p_patient_id
  LIMIT 1;

  IF v_conflict IS NOT NULL THEN
    RETURN (
      false,
      jsonb_build_object('conflicting_mrn', v_new_mrn),
      'MRN_EXISTS',
      'Another patient already uses this MRN.',
      NULL::integer
    )::public.rpc_result;
  END IF;

  UPDATE public.patients
  SET
    mrn = v_new_mrn,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE id = p_patient_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'patient.mrn_reassign',
    'patients',
    p_patient_id,
    jsonb_build_object('mrn', v_old_mrn),
    jsonb_build_object('mrn', v_new_mrn)
  );

  RETURN public.rpc_success(jsonb_build_object('patient_id', p_patient_id, 'mrn', v_new_mrn));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to reassign MRNs.');
    END IF;
    RAISE;
END;
$$;

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

  IF p_clear_date_of_birth THEN
    v_apply_date_of_birth := true;
  ELSIF p_date_of_birth IS NOT NULL THEN
    v_apply_date_of_birth := true;
  END IF;

  IF p_clear_notes THEN
    v_apply_notes := true;
  ELSIF p_notes IS NOT NULL THEN
    v_apply_notes := true;
  END IF;

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
      'Similar patients found — review before saving.',
      NULL::integer
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
    to_jsonb(v_old),
    to_jsonb(v_new)
  );

  RETURN public.rpc_success(jsonb_build_object('patient_id', p_patient_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to edit patients.');
    END IF;
    RAISE;
END;
$$;

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
      'Similar patients found — review before saving.',
      NULL::integer
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
    to_jsonb(v_old),
    to_jsonb(v_new)
  );

  RETURN public.rpc_success(jsonb_build_object('patient_id', p_patient_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to edit patients.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- T012: Versioned issue_ai_token with issuer-key signing
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.issue_ai_token(p_contract_version integer)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium, vault, auth_internal
AS $$
DECLARE
  v_uid uuid;
  v_org uuid;
  v_staff public.staff_members%ROWTYPE;
  v_branch_id uuid;
  v_signing_key ai_internal.issuer_key%ROWTYPE;
  v_secret_key bytea;
  v_scopes jsonb;
  v_jti uuid;
  v_iat bigint;
  v_exp bigint;
  v_header_text text;
  v_payload_text text;
  v_header_b64 text;
  v_payload_b64 text;
  v_signing_input text;
  v_signature bytea;
  v_token text;
BEGIN
  v_uid := auth_internal.assert_valid_ai_session();

  v_org := public.current_org_id();
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  SELECT sm.*
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.auth_user_id = v_uid
    AND sm.is_deleted = false
    AND sm.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'STAFF_NOT_FOUND';
  END IF;

  SELECT b.id
  INTO v_branch_id
  FROM public.staff_branch_assignments sba
  JOIN public.branches b ON b.id = sba.branch_id
  WHERE sba.staff_member_id = v_staff.id
    AND sba.is_deleted = false
    AND b.is_deleted = false
    AND b.is_active = true
    AND b.organization_id = v_org
  ORDER BY sba.is_primary DESC, b.name
  LIMIT 1;

  IF v_branch_id IS NULL THEN
    RAISE EXCEPTION 'BRANCH_NOT_FOUND';
  END IF;

  SELECT ik.*
  INTO v_signing_key
  FROM ai_internal.issuer_key ik
  WHERE ik.status = 'signing'
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ISSUER_KEY_NOT_CONFIGURED';
  END IF;

  SELECT decode(ds.decrypted_secret, 'base64')
  INTO v_secret_key
  FROM vault.decrypted_secrets ds
  WHERE ds.id = v_signing_key.secret_ref;

  IF v_secret_key IS NULL THEN
    RAISE EXCEPTION 'ISSUER_KEY_NOT_CONFIGURED';
  END IF;

  SELECT coalesce(
    jsonb_agg(rp.permission_key ORDER BY rp.permission_key),
    '[]'::jsonb
  )
  INTO v_scopes
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org
    AND rp.role = public.current_membership_role()
    AND rp.permission_key LIKE 'ai.%'
    AND rp.is_granted = true
    AND rp.is_deleted = false;

  IF jsonb_array_length(v_scopes) < 1 THEN
    RAISE EXCEPTION 'AI_ACCESS_DENIED';
  END IF;

  v_jti := gen_random_uuid();
  v_iat := extract(epoch FROM now())::bigint;
  v_exp := v_iat + 600;

  v_header_text := jsonb_build_object(
    'alg', 'EdDSA',
    'kid', v_signing_key.kid,
    'typ', 'JWT'
  )::text;

  v_payload_text := jsonb_build_object(
    'iss', auth_internal.ai_app_setting_text('ai.issuer_id', 'issuer-test'),
    'aud', 'ai-platform',
    'sub', v_staff.id::text,
    'org', v_org::text,
    'branch', v_branch_id::text,
    'role', public.current_membership_role()::text,
    'scopes', v_scopes,
    'jti', v_jti::text,
    'iat', v_iat,
    'exp', v_exp,
    'ver', '2'
  )::text;

  v_header_b64 := auth_internal.base64url_encode(convert_to(v_header_text, 'utf8'));
  v_payload_b64 := auth_internal.base64url_encode(convert_to(v_payload_text, 'utf8'));
  v_signing_input := v_header_b64 || '.' || v_payload_b64;

  v_signature := pgsodium.crypto_sign_detached(
    convert_to(v_signing_input, 'utf8'),
    v_secret_key
  );

  v_token := v_signing_input || '.' || auth_internal.base64url_encode(v_signature);

  INSERT INTO ai_internal.ai_token_issuance (
    jti,
    actor_staff_id,
    organization_id,
    aud,
    iat,
    created_by,
    updated_by
  )
  VALUES (
    v_jti,
    v_staff.id,
    v_org,
    'ai-platform',
    to_timestamp(v_iat),
    v_uid,
    v_uid
  );

  RETURN v_token;
END;
$$;

CREATE OR REPLACE FUNCTION public.issue_ai_token(p_contract_version integer DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
BEGIN
  IF p_contract_version IS NULL OR p_contract_version NOT IN (0, 1) THEN
    RAISE EXCEPTION 'CONTRACT_VERSION_UNSUPPORTED'
      USING DETAIL = '{"accepted_versions":[0,1]}';
  END IF;

  RETURN auth_internal.issue_ai_token(p_contract_version);
END;
$$;

REVOKE EXECUTE ON FUNCTION auth_internal.issue_ai_token(integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.issue_ai_token(integer) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.issue_ai_token(integer) TO authenticated;
