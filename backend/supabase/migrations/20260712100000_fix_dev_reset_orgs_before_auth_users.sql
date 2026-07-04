-- Dev reset must delete organizations/branches before auth.users
-- (organizations.created_by and branches.created_by FK to auth.users).
-- Service catalog tables must be cleared before branches/organizations.

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

-- Test fixture helper must clear service catalog before branches/organizations.
CREATE OR REPLACE FUNCTION auth_internal.delete_clinic_test_fixtures(
  p_preserve_staff_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM auth_internal.delete_clinic_operational_dependents();

  DELETE FROM public.staff_branch_assignments;

  IF COALESCE(array_length(p_preserve_staff_ids, 1), 0) > 0 THEN
    DELETE FROM public.staff_members
    WHERE id <> ALL (p_preserve_staff_ids);
  ELSE
    DELETE FROM public.staff_members;
  END IF;

  DELETE FROM public.audit_log;
  DELETE FROM public.app_settings;
  DELETE FROM public.subscription_cache;

  IF to_regclass('public.service_branches') IS NOT NULL THEN
    DELETE FROM public.service_branches;
  END IF;
  IF to_regclass('public.services') IS NOT NULL THEN
    DELETE FROM public.services;
  END IF;

  DELETE FROM public.branches;
  DELETE FROM public.organizations;
END;
$$;
