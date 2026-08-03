-- Admin-only MRN reassignment RPC with duplicate validation and audit.

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
      'Another patient already uses this MRN.'
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

CREATE OR REPLACE FUNCTION public.reassign_patient_mrn(
  p_patient_id uuid,
  p_new_mrn text
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.reassign_patient_mrn(p_patient_id, p_new_mrn);
$$;

GRANT EXECUTE ON FUNCTION public.reassign_patient_mrn(uuid, text) TO authenticated;
