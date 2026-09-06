-- Fresh-revoke success payload must return the stored revoked_at (re-SELECT
-- after UPDATE), matching the idempotent already-revoked branch.

CREATE OR REPLACE FUNCTION auth_internal.revoke_installation_key(p_kid text)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_row ai_internal.installation_keys%ROWTYPE;
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();

  IF NULLIF(trim(p_kid), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Key id is required.');
  END IF;

  SELECT *
  INTO v_row
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = p_kid
    AND ik.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('KEY_NOT_FOUND', 'Installation key was not found.');
  END IF;

  IF v_row.revoked_at IS NOT NULL THEN
    RETURN public.rpc_success(
      jsonb_build_object('kid', v_row.kid, 'revoked_at', v_row.revoked_at)
    );
  END IF;

  IF (
    SELECT count(*)
    FROM ai_internal.installation_keys ik
    WHERE ik.is_deleted = false
      AND ik.revoked_at IS NULL
  ) = 1 THEN
    RETURN public.rpc_error(
      'CANNOT_REVOKE_LAST_ACTIVE_KEY',
      'Cannot revoke the last active installation key. Rotate a replacement key first.'
    );
  END IF;

  UPDATE ai_internal.installation_keys ik
  SET
    revoked_at = clock_timestamp(),
    updated_at = clock_timestamp(),
    updated_by = v_caller.auth_user_id
  WHERE ik.kid = p_kid;

  SELECT *
  INTO STRICT v_row
  FROM ai_internal.installation_keys ik
  WHERE ik.kid = p_kid
    AND ik.is_deleted = false;

  RETURN public.rpc_success(
    jsonb_build_object('kid', v_row.kid, 'revoked_at', v_row.revoked_at)
  );
EXCEPTION
  WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may revoke installation keys.');
    END IF;
    RAISE;
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may revoke installation keys.');
    END IF;
    RAISE;
END;
$$;
