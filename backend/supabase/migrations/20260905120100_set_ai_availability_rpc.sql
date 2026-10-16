-- Write path for clinic AI availability flag (closes manual app_settings UPDATE gap).

CREATE OR REPLACE FUNCTION auth_internal.set_ai_availability(
  p_enrolled boolean,
  p_platform_base_url text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_value jsonb;
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();

  IF p_enrolled IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Enrolled flag is required.');
  END IF;

  IF p_enrolled THEN
    IF NULLIF(trim(p_platform_base_url), '') IS NULL THEN
      RETURN public.rpc_error(
        'INVALID_INPUT',
        'Platform base URL is required when enrolled is true.'
      );
    END IF;

    v_value := jsonb_build_object(
      'enrolled', true,
      'platform_base_url', trim(p_platform_base_url)
    );
  ELSE
    v_value := jsonb_build_object(
      'enrolled', false,
      'platform_base_url', NULL
    );
  END IF;

  INSERT INTO ai_internal.app_settings (key, value_json, created_by, updated_by)
  VALUES ('ai.availability', v_value, v_caller.auth_user_id, v_caller.auth_user_id)
  ON CONFLICT (key) DO UPDATE
  SET
    value_json = EXCLUDED.value_json,
    updated_at = clock_timestamp(),
    updated_by = EXCLUDED.updated_by,
    is_deleted = false,
    deleted_at = NULL,
    deleted_by = NULL;

  RETURN public.rpc_success(v_value);
EXCEPTION
  WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may set AI availability.');
    END IF;
    RAISE;
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may set AI availability.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_ai_availability(
  p_enrolled boolean,
  p_platform_base_url text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.set_ai_availability(p_enrolled, p_platform_base_url);
$$;

REVOKE ALL ON FUNCTION auth_internal.set_ai_availability(boolean, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_ai_availability(boolean, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_ai_availability(boolean, text) TO authenticated;
