-- Fix 9: Add patient transfer and restore RPCs.
-- transfer_patient: Move a patient to a different branch within the same org.
-- restore_patient: Unarchive a soft-deleted patient.

-- =============================================================================
-- auth_internal.transfer_patient
-- =============================================================================

CREATE OR REPLACE FUNCTION auth_internal.transfer_patient(
  p_patient_id uuid,
  p_new_branch_id uuid
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_patient public.patients%ROWTYPE;
  v_branch public.branches%ROWTYPE;
  v_old_branch_id uuid;
BEGIN
  v_staff := auth_internal.assert_permission('patients.edit');
  
  IF p_patient_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Patient ID is required.');
  END IF;

  IF p_new_branch_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Target branch ID is required.');
  END IF;

  BEGIN
    v_patient := auth_internal.assert_org_patient(p_patient_id, false);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      IF SQLERRM = 'PATIENT_ARCHIVED' THEN
        RETURN public.rpc_error('PATIENT_ARCHIVED', 'Cannot transfer an archived patient.');
      END IF;
      IF SQLERRM = 'FORBIDDEN' THEN
        RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to access this patient.');
      END IF;
      RAISE;
  END;

  IF v_patient.branch_id = p_new_branch_id THEN
    RETURN public.rpc_success(
      jsonb_build_object('patient_id', p_patient_id, 'new_branch_id', p_new_branch_id)
    );
  END IF;

  SELECT *
  INTO v_branch
  FROM public.branches b
  WHERE b.id = p_new_branch_id
    AND b.is_deleted = false
    AND b.is_active = true
    AND b.organization_id = v_patient.organization_id;

  IF NOT FOUND THEN
    RETURN public.rpc_error(
      'INVALID_BRANCH',
      'Target branch not found or not active in the same organization.'
    );
  END IF;

  v_old_branch_id := v_patient.branch_id;

  UPDATE public.patients p
  SET
    branch_id = p_new_branch_id,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE p.id = p_patient_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_patient.organization_id,
    'patient.transfer',
    'patients',
    p_patient_id,
    jsonb_build_object('branch_id', v_old_branch_id),
    jsonb_build_object('branch_id', p_new_branch_id)
  );

  RETURN public.rpc_success(
    jsonb_build_object('patient_id', p_patient_id, 'new_branch_id', p_new_branch_id)
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to transfer patients.');
    END IF;
    RAISE;
END;
$$;

-- =============================================================================
-- auth_internal.restore_patient
-- =============================================================================

CREATE OR REPLACE FUNCTION auth_internal.restore_patient(p_patient_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_patient public.patients%ROWTYPE;
BEGIN
  v_staff := auth_internal.assert_permission('patients.delete');

  IF p_patient_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Patient ID is required.');
  END IF;

  BEGIN
    v_patient := auth_internal.assert_org_patient(p_patient_id, true);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      IF SQLERRM = 'FORBIDDEN' THEN
        RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to access this patient.');
      END IF;
      RAISE;
  END;

  IF NOT v_patient.is_deleted THEN
    RETURN public.rpc_error('INVALID_STATE', 'Patient is not archived.');
  END IF;

  BEGIN
    UPDATE public.patients p
    SET
      is_deleted = false,
      deleted_at = NULL,
      deleted_by = NULL,
      updated_at = now(),
      updated_by = auth.uid()
    WHERE p.id = p_patient_id;
  EXCEPTION
    WHEN unique_violation THEN
      RETURN public.rpc_error(
        'DUPLICATE_PHONE',
        'Another active patient already has this phone number. Update the phone before restoring.'
      );
  END;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_patient.organization_id,
    'patient.restore',
    'patients',
    p_patient_id,
    jsonb_build_object('full_name', v_patient.full_name, 'branch_id', v_patient.branch_id)
  );

  RETURN public.rpc_success(jsonb_build_object('patient_id', p_patient_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to restore patients.');
    END IF;
    RAISE;
END;
$$;

-- =============================================================================
-- Public INVOKER wrappers
-- =============================================================================

CREATE OR REPLACE FUNCTION public.transfer_patient(p_patient_id uuid, p_new_branch_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.transfer_patient(p_patient_id, p_new_branch_id);
$$;

CREATE OR REPLACE FUNCTION public.restore_patient(p_patient_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.restore_patient(p_patient_id);
$$;

-- Grants for public wrappers
GRANT EXECUTE ON FUNCTION public.transfer_patient(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.restore_patient(uuid) TO authenticated;

-- Grants for auth_internal (needed because public INVOKER wrappers call these)
GRANT EXECUTE ON FUNCTION auth_internal.transfer_patient(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.restore_patient(uuid) TO authenticated;
