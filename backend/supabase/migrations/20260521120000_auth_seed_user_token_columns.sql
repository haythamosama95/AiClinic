-- Fix GoTrue scan errors for SQL-seeded auth.users (NULL token columns → empty string).
-- GoTrue v2.188+ cannot scan NULL into string for confirmation_token and related fields.
-- See: auth logs "converting NULL to string is unsupported" on password grant.
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

-- GoTrue hook calls get_custom_claims(jsonb) only; the uuid overload makes the call ambiguous.
ALTER FUNCTION public.get_custom_claims (uuid)
RENAME TO get_staff_claims_for_user;

REVOKE ALL ON FUNCTION public.get_staff_claims_for_user (uuid)
FROM
  PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_staff_claims_for_user (uuid) TO service_role;