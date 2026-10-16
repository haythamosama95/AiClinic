-- E3: first ordinary context provider RPC for visit.chief_complaint@v1.

CREATE OR REPLACE FUNCTION auth_internal.get_visit_chief_complaint(p_visit_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
  v_note public.visit_clinical_notes%ROWTYPE;
  v_payload jsonb;
BEGIN
  BEGIN
    v_visit := auth_internal.assert_visit_branch_scope(p_visit_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
      END IF;
      RAISE;
  END;

  IF NOT auth_internal.staff_has_visit_clinical_access() THEN
    RETURN public.rpc_error(
      'FORBIDDEN',
      'You do not have permission to view this visit clinical data.'
    );
  END IF;

  SELECT *
  INTO v_note
  FROM public.visit_clinical_notes vcn
  WHERE vcn.visit_id = p_visit_id
    AND vcn.is_deleted = false;

  v_payload := jsonb_build_object('visit_id', p_visit_id);

  IF FOUND THEN
    IF v_note.complaint IS NOT NULL THEN
      v_payload := v_payload || jsonb_build_object('complaint', v_note.complaint);
    END IF;

    IF v_note.created_at IS NOT NULL THEN
      v_payload := v_payload || jsonb_build_object(
        'recorded_at',
        to_char(v_note.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      );
    END IF;
  END IF;

  RETURN public.rpc_success(v_payload);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_visit_chief_complaint(p_visit_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_visit_chief_complaint(p_visit_id);
$$;

GRANT EXECUTE ON FUNCTION public.get_visit_chief_complaint(uuid) TO authenticated;
