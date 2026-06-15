-- Remove the 240-minute upper bound on appointment duration.

CREATE OR REPLACE FUNCTION auth_internal.assert_appointment_duration_bounds(p_duration_minutes int)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
  IF p_duration_minutes IS NULL OR p_duration_minutes < 5 THEN
    RAISE EXCEPTION 'INVALID_DURATION' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.get_appointment_settings(p_branch_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_default int;
  v_schedule jsonb;
BEGIN
  PERFORM auth_internal.assert_appointment_access();
  PERFORM auth_internal.assert_appointment_branch(p_branch_id);

  SELECT b.working_schedule
  INTO v_schedule
  FROM public.branches b
  WHERE b.id = p_branch_id
    AND b.is_deleted = false;

  v_default := auth_internal.resolve_appointment_default_duration(p_branch_id);

  RETURN public.rpc_success(
    jsonb_build_object(
      'default_duration_minutes', v_default,
      'min_duration_minutes', 5,
      'working_schedule', v_schedule
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM IN ('FORBIDDEN', 'INVALID_BRANCH') THEN
      IF SQLERRM = 'FORBIDDEN' THEN
        RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view appointment settings.');
      END IF;
      RETURN public.rpc_error('INVALID_BRANCH', 'Branch is not valid for this session.');
    END IF;
    RAISE;
END;
$$;
