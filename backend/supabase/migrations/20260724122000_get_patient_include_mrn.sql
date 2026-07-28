-- Include patient MRN in get_patient detail payload (016 US4).

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
      'mrn', v_patient.mrn,
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
