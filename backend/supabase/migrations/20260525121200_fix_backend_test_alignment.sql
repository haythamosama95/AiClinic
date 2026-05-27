-- Align RPC behavior with backend verification suite after security/integrity fixes.

-- dev_reset: delete patients before branches (FK) and keep environment gate from 20260525120500.
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

  DELETE FROM public.staff_branch_assignments WHERE true;
  DELETE FROM public.patients WHERE true;
  GET DIAGNOSTICS v_patients_deleted = ROW_COUNT;

  DELETE FROM public.audit_log WHERE organization_id IS NOT NULL;
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
      'bootstrap_staff_member_id', v_staff.id,
      'had_organization_before_reset', v_had_org
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'organizations_deleted', v_orgs_deleted,
      'branches_deleted', v_branches_deleted,
      'patients_deleted', v_patients_deleted,
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

-- Branch management: require non-empty code on create.
CREATE OR REPLACE FUNCTION auth_internal.manage_create_branch(
  p_name text,
  p_code text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_maps_url text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_branch_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('settings.manage_branches');
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL OR public.jwt_setup_required() THEN
    RETURN public.rpc_error('ORG_SETUP_INCOMPLETE', 'Complete clinic setup before creating branches.');
  END IF;

  IF NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch name is required.');
  END IF;

  IF NULLIF(trim(p_code), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch code is required.');
  END IF;

  INSERT INTO public.branches (
    organization_id,
    name,
    code,
    address,
    phone,
    maps_url,
    created_by,
    updated_by
  )
  VALUES (
    v_org_id,
    trim(p_name),
    NULLIF(trim(p_code), ''),
    NULLIF(trim(p_address), ''),
    NULLIF(trim(p_phone), ''),
    NULLIF(trim(p_maps_url), ''),
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_branch_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'branch.create',
    'branches',
    v_branch_id,
    jsonb_build_object(
      'organization_id', v_org_id,
      'name', trim(p_name),
      'code', NULLIF(trim(p_code), '')
    )
  );

  RETURN public.rpc_success(jsonb_build_object('branch_id', v_branch_id));
EXCEPTION
  WHEN unique_violation THEN
    RETURN public.rpc_error('DUPLICATE_CODE', 'A branch with this code already exists in your organization.');
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage branches.');
    END IF;
    RAISE;
END;
$$;

-- Staff lifecycle: block self-deactivation.
CREATE OR REPLACE FUNCTION auth_internal.set_staff_active(p_staff_member_id uuid, p_is_active boolean)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_action text;
BEGIN
  PERFORM auth_internal.assert_permission('settings.manage_staff');
  v_org_id := public.jwt_organization_id();

  IF NOT p_is_active AND p_staff_member_id = public.jwt_staff_member_id() THEN
    RETURN public.rpc_error('CANNOT_DEACTIVATE_SELF', 'You cannot deactivate your own account.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.staff_members sm
    JOIN public.staff_branch_assignments sba ON sba.staff_member_id = sm.id AND sba.is_deleted = false
    JOIN public.branches b ON b.id = sba.branch_id AND b.is_deleted = false
    WHERE sm.id = p_staff_member_id
      AND sm.is_deleted = false
      AND b.organization_id = v_org_id
  ) THEN
    RETURN public.rpc_error('STAFF_NOT_FOUND', 'Staff member was not found in your organization.');
  END IF;

  UPDATE public.staff_members sm
  SET
    is_active = p_is_active,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE sm.id = p_staff_member_id;

  v_action := CASE WHEN p_is_active THEN 'staff.reactivate' ELSE 'staff.deactivate' END;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    v_action,
    'staff_members',
    p_staff_member_id,
    jsonb_build_object('is_active', p_is_active)
  );

  RETURN public.rpc_success(jsonb_build_object('staff_member_id', p_staff_member_id, 'is_active', p_is_active));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage staff.');
    END IF;
    RAISE;
END;
$$;

-- Patient update: preserve omitted optional fields (regression from partial 20260523140100 overlay).
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
