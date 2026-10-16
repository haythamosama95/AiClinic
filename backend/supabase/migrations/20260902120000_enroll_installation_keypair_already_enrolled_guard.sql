-- Reject enroll when an active installation key already exists; allow re-enroll
-- after all keys are revoked (recovery path).

CREATE OR REPLACE FUNCTION auth_internal.enroll_installation_keypair()
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium, auth_internal
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_installation_id uuid;
  v_keypair record;
  v_kid text;
  v_public_jwk jsonb;
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();

  IF EXISTS (
    SELECT 1
    FROM ai_internal.installation_keys ik
    WHERE ik.is_deleted = false
      AND ik.revoked_at IS NULL
  ) THEN
    RETURN public.rpc_error(
      'ALREADY_ENROLLED',
      'An active installation key already exists. Use rotate_installation_key() to rotate keys.'
    );
  END IF;

  SELECT ik.installation_id
  INTO v_installation_id
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
  ORDER BY ik.valid_from ASC, ik.kid ASC
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
    created_at,
    created_by,
    updated_by
  )
  VALUES (
    v_kid,
    v_installation_id,
    v_keypair.public,
    v_keypair.secret,
    'EdDSA',
    clock_timestamp(),
    clock_timestamp(),
    v_caller.auth_user_id,
    v_caller.auth_user_id
  );

  v_public_jwk := jsonb_build_object(
    'kty', 'OKP',
    'crv', 'Ed25519',
    'x', auth_internal.base64url_encode(v_keypair.public),
    'kid', v_kid
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'kid', v_kid,
      'installation_id', v_installation_id,
      'public_jwk', v_public_jwk
    )
  );
EXCEPTION
  WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may enroll installation keys.');
    END IF;
    RAISE;
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only administrators may enroll installation keys.');
    END IF;
    RAISE;
END;
$$;
