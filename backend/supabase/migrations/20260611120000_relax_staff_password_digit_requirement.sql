-- Drop the "at least one digit" staff password rule; keep minimum length and letter checks.

CREATE OR REPLACE FUNCTION auth_internal.assert_password_complexity(p_password text)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF p_password IS NULL OR length(p_password) < 8 THEN
    RAISE EXCEPTION 'Password must be at least 8 characters'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_password !~ '[A-Za-z]' THEN
    RAISE EXCEPTION 'Password must contain at least one letter'
      USING ERRCODE = 'check_violation';
  END IF;
END;
$$;
