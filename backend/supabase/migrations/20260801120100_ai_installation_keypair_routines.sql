-- =============================================================================
-- B1 slice: installation keypair enrollment, rotation, and revocation.
-- =============================================================================

CREATE OR REPLACE FUNCTION auth_internal.enroll_installation_keypair()
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_installation_id uuid;
  v_keypair record;
  v_kid text;
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();

  SELECT ik.installation_id
  INTO v_installation_id
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
  ORDER BY ik.valid_from
  LIMIT 1;

  IF v_installation_id IS NULL THEN
    v_installation_id := gen_random_uuid();
  END IF;

  SELECT kp.public, kp.secret
  INTO v_keypair
  FROM pgsodium.crypto_sign_new_keypair() kp;

  v_kid := gen_random_uuid()::text;

  INSERT INTO ai_internal.installation_keys (
    kid,
    installation_id,
    public_key,
    secret_key,
    algorithm,
    valid_from,
    created_by,
    updated_by
  )
  VALUES (
    v_kid,
    v_installation_id,
    v_keypair.public,
    v_keypair.secret,
    'EdDSA',
    now(),
    v_caller.auth_user_id,
    v_caller.auth_user_id
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'kid', v_kid,
      'installation_id', v_installation_id
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may enroll installation keys.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.rotate_installation_key()
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_installation_id uuid;
  v_keypair record;
  v_kid text;
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();

  SELECT ik.installation_id
  INTO v_installation_id
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
  ORDER BY ik.valid_from
  LIMIT 1;

  IF v_installation_id IS NULL THEN
    RETURN public.rpc_error(
      'INSTALLATION_NOT_ENROLLED',
      'Enroll an installation keypair before rotating.'
    );
  END IF;

  SELECT kp.public, kp.secret
  INTO v_keypair
  FROM pgsodium.crypto_sign_new_keypair() kp;

  v_kid := gen_random_uuid()::text;

  INSERT INTO ai_internal.installation_keys (
    kid,
    installation_id,
    public_key,
    secret_key,
    algorithm,
    valid_from,
    created_by,
    updated_by
  )
  VALUES (
    v_kid,
    v_installation_id,
    v_keypair.public,
    v_keypair.secret,
    'EdDSA',
    now(),
    v_caller.auth_user_id,
    v_caller.auth_user_id
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'kid', v_kid,
      'installation_id', v_installation_id
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may rotate installation keys.');
    END IF;
    RAISE;
END;
$$;

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

  UPDATE ai_internal.installation_keys ik
  SET
    revoked_at = now(),
    updated_at = now(),
    updated_by = v_caller.auth_user_id
  WHERE ik.kid = p_kid;

  RETURN public.rpc_success(
    jsonb_build_object('kid', p_kid, 'revoked_at', now())
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may revoke installation keys.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.enroll_installation_keypair()
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.enroll_installation_keypair();
$$;

CREATE OR REPLACE FUNCTION public.rotate_installation_key()
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.rotate_installation_key();
$$;

CREATE OR REPLACE FUNCTION public.revoke_installation_key(p_kid text)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.revoke_installation_key(p_kid);
$$;

REVOKE EXECUTE ON FUNCTION public.enroll_installation_keypair() FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.rotate_installation_key() FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.revoke_installation_key(text) FROM anon, PUBLIC;

GRANT EXECUTE ON FUNCTION public.enroll_installation_keypair() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rotate_installation_key() TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_installation_key(text) TO authenticated;
