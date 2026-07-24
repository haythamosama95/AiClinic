-- Patient MRN: global sequence, unique index, generator helper, create_patient extension.

-- -----------------------------------------------------------------------------
-- Part A: schema — sequence, column, backfill, NOT NULL, unique index
-- -----------------------------------------------------------------------------

CREATE SEQUENCE public.patient_mrn_seq
  AS bigint
  START WITH 1
  INCREMENT BY 1
  NO MINVALUE
  NO MAXVALUE
  NO CYCLE;

ALTER TABLE public.patients ADD COLUMN mrn text;

UPDATE public.patients
   SET mrn = format('MRN-%s', lpad(nextval('public.patient_mrn_seq')::text, 6, '0'))
 WHERE mrn IS NULL;

ALTER TABLE public.patients ALTER COLUMN mrn SET NOT NULL;

CREATE UNIQUE INDEX patients_mrn_unique ON public.patients (mrn);

-- -----------------------------------------------------------------------------
-- Part B: internal MRN generator (auth_internal only)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assign_patient_mrn()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN format('MRN-%s', lpad(nextval('public.patient_mrn_seq')::text, 6, '0'));
END;
$$;

REVOKE ALL ON FUNCTION auth_internal.assign_patient_mrn() FROM PUBLIC, authenticated, anon;

-- -----------------------------------------------------------------------------
-- Part C: extend create_patient — assign MRN, return in payload + audit
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
  v_mrn text;
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

  v_mrn := auth_internal.assign_patient_mrn();

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

-- Reset MRN sequence after patient teardown (dev reset + test fixtures).
CREATE OR REPLACE FUNCTION auth_internal.delete_clinic_operational_dependents()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM auth_internal.delete_billing_dependents();

  IF to_regclass('public.visit_attachments') IS NOT NULL THEN
    DELETE FROM public.visit_attachments;
  END IF;
  IF to_regclass('public.visit_vital_signs') IS NOT NULL THEN
    DELETE FROM public.visit_vital_signs;
  END IF;
  IF to_regclass('public.visit_investigations') IS NOT NULL THEN
    DELETE FROM public.visit_investigations;
  END IF;
  IF to_regclass('public.visit_clinical_notes') IS NOT NULL THEN
    DELETE FROM public.visit_clinical_notes;
  END IF;
  IF to_regclass('public.treatment_plans') IS NOT NULL THEN
    DELETE FROM public.treatment_plans;
  END IF;
  IF to_regclass('public.visits') IS NOT NULL THEN
    DELETE FROM public.visits;
  END IF;

  IF to_regclass('public.shift_assignments') IS NOT NULL THEN
    DELETE FROM public.shift_assignments;
  END IF;
  IF to_regclass('public.shifts') IS NOT NULL THEN
    DELETE FROM public.shifts;
  END IF;

  IF to_regclass('public.appointments') IS NOT NULL THEN
    DELETE FROM public.appointments;
  END IF;

  IF to_regclass('public.patient_allergies') IS NOT NULL THEN
    DELETE FROM public.patient_allergies;
  END IF;
  IF to_regclass('public.patient_medications') IS NOT NULL THEN
    DELETE FROM public.patient_medications;
  END IF;
  IF to_regclass('public.patient_chronic_conditions') IS NOT NULL THEN
    DELETE FROM public.patient_chronic_conditions;
  END IF;

  DELETE FROM public.patients;

  IF to_regclass('public.patient_mrn_seq') IS NOT NULL THEN
    PERFORM setval('public.patient_mrn_seq', 1, false);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.dev_reset_clinic_installation()
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_env text;
  v_staff public.staff_members%ROWTYPE;
  v_orgs_deleted int;
  v_branches_deleted int;
  v_patients_deleted int;
  v_appointments_deleted int;
  v_staff_deleted int;
  v_auth_users_deleted int;
  v_had_org boolean;
BEGIN
  v_env := current_setting('app.environment', true);
  IF v_env IS NULL OR v_env NOT IN ('development', 'local', 'test') THEN
    RETURN public.rpc_error(
      'FORBIDDEN',
      'dev_reset_clinic_installation can only run in development/local/test environments.'
    );
  END IF;

  v_staff := auth_internal.assert_bootstrap_admin();
  v_had_org := auth_internal.organization_exists();

  IF to_regclass('public.payments') IS NOT NULL THEN
    DELETE FROM public.payments WHERE true;
  END IF;
  IF to_regclass('public.invoice_items') IS NOT NULL THEN
    DELETE FROM public.invoice_items WHERE true;
  END IF;
  IF to_regclass('public.invoices') IS NOT NULL THEN
    DELETE FROM public.invoices WHERE true;
  END IF;
  IF to_regclass('public.invoice_number_sequences') IS NOT NULL THEN
    DELETE FROM public.invoice_number_sequences WHERE true;
  END IF;
  IF to_regclass('public.insurance_providers') IS NOT NULL THEN
    DELETE FROM public.insurance_providers WHERE true;
  END IF;
  IF to_regclass('public.organization_billing_settings') IS NOT NULL THEN
    DELETE FROM public.organization_billing_settings WHERE true;
  END IF;

  IF to_regclass('public.visit_attachments') IS NOT NULL THEN
    DELETE FROM public.visit_attachments WHERE true;
  END IF;
  IF to_regclass('public.visit_investigations') IS NOT NULL THEN
    DELETE FROM public.visit_investigations WHERE true;
  END IF;
  IF to_regclass('public.visit_vital_signs') IS NOT NULL THEN
    DELETE FROM public.visit_vital_signs WHERE true;
  END IF;
  IF to_regclass('public.visit_clinical_notes') IS NOT NULL THEN
    DELETE FROM public.visit_clinical_notes WHERE true;
  END IF;
  IF to_regclass('public.soap_notes') IS NOT NULL THEN
    DELETE FROM public.soap_notes WHERE true;
  END IF;
  IF to_regclass('public.treatment_plans') IS NOT NULL THEN
    DELETE FROM public.treatment_plans WHERE true;
  END IF;
  IF to_regclass('public.visits') IS NOT NULL THEN
    DELETE FROM public.visits WHERE true;
  END IF;

  IF to_regclass('public.shift_assignments') IS NOT NULL THEN
    DELETE FROM public.shift_assignments WHERE true;
  END IF;
  IF to_regclass('public.shifts') IS NOT NULL THEN
    DELETE FROM public.shifts WHERE true;
  END IF;

  DELETE FROM public.appointments WHERE true;
  GET DIAGNOSTICS v_appointments_deleted = ROW_COUNT;

  DELETE FROM public.staff_branch_assignments WHERE true;

  IF to_regclass('public.patient_allergies') IS NOT NULL THEN
    DELETE FROM public.patient_allergies WHERE true;
  END IF;
  IF to_regclass('public.patient_medications') IS NOT NULL THEN
    DELETE FROM public.patient_medications WHERE true;
  END IF;
  IF to_regclass('public.patient_chronic_conditions') IS NOT NULL THEN
    DELETE FROM public.patient_chronic_conditions WHERE true;
  END IF;

  DELETE FROM public.patients WHERE true;
  GET DIAGNOSTICS v_patients_deleted = ROW_COUNT;

  IF to_regclass('public.patient_mrn_seq') IS NOT NULL THEN
    PERFORM setval('public.patient_mrn_seq', 1, false);
  END IF;

  DELETE FROM public.staff_members
  WHERE NOT is_bootstrap_admin;
  GET DIAGNOSTICS v_staff_deleted = ROW_COUNT;

  DELETE FROM public.audit_log WHERE true;

  DELETE FROM public.app_settings WHERE true;
  DELETE FROM public.subscription_cache WHERE true;

  IF to_regclass('public.service_branches') IS NOT NULL THEN
    DELETE FROM public.service_branches WHERE true;
  END IF;
  IF to_regclass('public.services') IS NOT NULL THEN
    DELETE FROM public.services WHERE true;
  END IF;

  DELETE FROM public.branches WHERE true;
  GET DIAGNOSTICS v_branches_deleted = ROW_COUNT;

  DELETE FROM public.organizations WHERE true;
  GET DIAGNOSTICS v_orgs_deleted = ROW_COUNT;

  DELETE FROM auth.users au
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.staff_members sm
    WHERE sm.auth_user_id = au.id
  );
  GET DIAGNOSTICS v_auth_users_deleted = ROW_COUNT;

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
      'staff_deleted', v_staff_deleted,
      'auth_users_deleted', v_auth_users_deleted,
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
      'staff_deleted', v_staff_deleted,
      'auth_users_deleted', v_auth_users_deleted,
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
