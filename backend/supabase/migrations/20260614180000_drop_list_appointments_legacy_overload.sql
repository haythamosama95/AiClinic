-- Resolve ambiguous overload: 5-arg list_appointments matches both legacy and 6-arg signatures.

DROP FUNCTION IF EXISTS public.list_appointments(uuid, timestamptz, timestamptz, uuid, text[]);
DROP FUNCTION IF EXISTS auth_internal.list_appointments(uuid, timestamptz, timestamptz, uuid, text[]);

GRANT EXECUTE ON FUNCTION auth_internal.list_appointments(
  uuid,
  timestamptz,
  timestamptz,
  uuid,
  text[],
  uuid
) TO authenticated;
