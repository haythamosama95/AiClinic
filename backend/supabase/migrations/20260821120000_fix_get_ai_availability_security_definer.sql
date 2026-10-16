-- public.get_ai_availability must run as SECURITY DEFINER so authenticated callers
-- can invoke auth_internal.get_ai_availability (EXECUTE revoked from authenticated).

CREATE OR REPLACE FUNCTION public.get_ai_availability()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_ai_availability();
$$;

REVOKE ALL ON FUNCTION public.get_ai_availability() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ai_availability() TO authenticated;
