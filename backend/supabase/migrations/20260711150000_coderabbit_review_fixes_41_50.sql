-- CodeRabbit review fixes (comments 41, 43, 49, 50).

-- -----------------------------------------------------------------------------
-- dev_reset_clinic_installation: fail closed when app.environment is unset.
-- -----------------------------------------------------------------------------

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

  DELETE FROM auth.users au
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.staff_members sm
    WHERE sm.auth_user_id = au.id
  );
  GET DIAGNOSTICS v_auth_users_deleted = ROW_COUNT;

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

-- -----------------------------------------------------------------------------
-- record_investigation_result: normalize p_result before recorded metadata.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.record_investigation_result(
  p_investigation_line_id uuid,
  p_result text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.visit_investigations%ROWTYPE;
  v_org_id uuid;
  v_recorded_at timestamptz;
  v_normalized_result text;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  SELECT vi.* INTO v_row
  FROM public.visit_investigations vi
  JOIN public.visits v ON v.id = vi.visit_id
  WHERE vi.id = p_investigation_line_id
    AND vi.is_deleted = false
    AND v.is_deleted = false
    AND v.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Investigation was not found.');
  END IF;

  v_normalized_result := CASE WHEN p_result IS NULL THEN NULL ELSE NULLIF(trim(p_result), '') END;

  IF v_normalized_result IS NOT NULL AND length(v_normalized_result) > 10000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Investigation result exceeds maximum length.');
  END IF;

  v_recorded_at := now();

  UPDATE public.visit_investigations vi
  SET
    result = v_normalized_result,
    result_recorded_at = CASE WHEN v_normalized_result IS NULL THEN NULL ELSE v_recorded_at END,
    result_recorded_by = CASE WHEN v_normalized_result IS NULL THEN NULL ELSE auth.uid() END,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE vi.id = p_investigation_line_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(), v_org_id, 'visit.investigation.result_record', 'visit_investigations', p_investigation_line_id,
    jsonb_build_object(
      'investigation_line_id', p_investigation_line_id,
      'result_recorded_at', CASE WHEN v_normalized_result IS NULL THEN NULL ELSE v_recorded_at END
    )
  );

  RETURN public.rpc_success(jsonb_build_object(
    'investigation_line_id', p_investigation_line_id,
    'result_recorded_at', CASE WHEN v_normalized_result IS NULL THEN NULL ELSE v_recorded_at END
  ));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to record investigation results.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- update_visit_vital_sign: use assert_visit_branch_scope like create path.
-- -----------------------------------------------------------------------------

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
  WHERE vvs.id = p_vital_sign_id
    AND vvs.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Vital sign was not found.');
  END IF;

  BEGIN
    PERFORM auth_internal.assert_visit_branch_scope(v_row.visit_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
      END IF;
      RAISE;
  END;

  IF p_name IS NOT NULL AND NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Vital sign name cannot be empty.');
  END IF;

  IF p_value IS NOT NULL AND NULLIF(trim(p_value), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Vital sign value cannot be empty.');
  END IF;

  IF p_name IS NOT NULL AND length(trim(p_name)) > 100 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Vital sign name must be 100 characters or fewer.');
  END IF;

  IF p_value IS NOT NULL AND length(trim(p_value)) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Vital sign value must be 200 characters or fewer.');
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

  UPDATE public.visit_vital_signs vvs
  SET
    name = COALESCE(NULLIF(trim(p_name), ''), vvs.name),
    value = COALESCE(NULLIF(trim(p_value), ''), vvs.value),
    unit = CASE WHEN p_unit IS NULL THEN vvs.unit ELSE NULLIF(trim(p_unit), '') END,
    predefined_vital_sign_id = CASE
      WHEN p_predefined_vital_sign_id IS NOT NULL THEN p_predefined_vital_sign_id
      WHEN p_name IS NOT NULL AND p_predefined_vital_sign_id IS NULL THEN NULL
      ELSE vvs.predefined_vital_sign_id
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

-- -----------------------------------------------------------------------------
-- delete_visit_attachment: soft-delete metadata only after storage row removed.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.delete_visit_attachment(p_attachment_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_attachment public.visit_attachments%ROWTYPE;
  v_org_id uuid;
  v_caller_staff_id uuid;
  v_has_clinical boolean;
  v_has_upload boolean;
  v_storage_deleted int;
BEGIN
  v_caller_staff_id := public.jwt_staff_member_id();
  v_has_clinical := auth_internal.staff_has_visit_clinical_access();
  v_has_upload := auth_internal.staff_has_visit_upload_access();

  IF NOT v_has_clinical AND NOT v_has_upload THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to delete visit attachments.');
  END IF;

  SELECT va.*
  INTO v_attachment
  FROM public.visit_attachments va
  WHERE va.id = p_attachment_id
    AND va.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Attachment was not found.');
  END IF;

  BEGIN
    PERFORM auth_internal.assert_visit_branch_scope(v_attachment.visit_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
      END IF;
      RAISE;
  END;

  IF v_has_clinical THEN
    NULL;
  ELSIF v_has_upload AND v_attachment.uploaded_by = v_caller_staff_id THEN
    NULL;
  ELSE
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to delete this attachment.');
  END IF;

  v_org_id := public.jwt_organization_id();
  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  PERFORM set_config('storage.allow_delete_query', 'true', true);
  DELETE FROM storage.objects o
  WHERE o.bucket_id = 'visit-attachments'
    AND o.name = v_attachment.file_path;

  GET DIAGNOSTICS v_storage_deleted = ROW_COUNT;
  IF v_storage_deleted = 0 THEN
    RETURN public.rpc_error('NOT_FOUND', 'Attachment file was not found in storage.');
  END IF;

  UPDATE public.visit_attachments va
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE va.id = p_attachment_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'visit.attachment.delete',
    'visit_attachments',
    p_attachment_id,
    jsonb_build_object(
      'visit_id', v_attachment.visit_id,
      'attachment_id', p_attachment_id,
      'file_path', v_attachment.file_path
    )
  );

  RETURN public.rpc_success(jsonb_build_object('attachment_id', p_attachment_id));
END;
$$;
