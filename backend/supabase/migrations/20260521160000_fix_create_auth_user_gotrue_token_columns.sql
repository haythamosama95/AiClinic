-- Staff accounts created via create_staff_account left GoTrue token columns NULL.
-- GoTrue v2.188+ fails password grant with "Database error querying schema"
-- (see migration 20260521120000_auth_seed_user_token_columns.sql).
-- Match bootstrap seed: empty strings for confirmation/recovery/email-change tokens.

CREATE OR REPLACE FUNCTION auth_internal.create_auth_user(p_email text, p_password text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid := gen_random_uuid();
BEGIN
  IF EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE lower(u.email) = lower(trim(p_email))
  ) THEN
    RAISE EXCEPTION 'EMAIL_EXISTS';
  END IF;

  INSERT INTO auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    confirmation_token,
    recovery_token,
    email_change,
    email_change_token_new,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    lower(trim(p_email)),
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    '',
    '',
    '',
    '',
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    '{}'::jsonb,
    now(),
    now()
  );

  INSERT INTO auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  )
  VALUES (
    gen_random_uuid(),
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', lower(trim(p_email))),
    'email',
    lower(trim(p_email)),
    now(),
    now(),
    now()
  );

  RETURN v_user_id;
END;
$$;

-- Repair users already provisioned before this migration.
UPDATE auth.users
SET
  confirmation_token = COALESCE(confirmation_token, ''),
  recovery_token = COALESCE(recovery_token, ''),
  email_change = COALESCE(email_change, ''),
  email_change_token_new = COALESCE(email_change_token_new, '')
WHERE
  confirmation_token IS NULL
  OR recovery_token IS NULL
  OR email_change IS NULL
  OR email_change_token_new IS NULL;
