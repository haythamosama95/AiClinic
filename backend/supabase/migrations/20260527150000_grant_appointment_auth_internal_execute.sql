-- Grant EXECUTE on appointment auth_internal functions called by public INVOKER wrappers.
-- Required after 20260525120200_fix_restrict_auth_internal_grants.sql (whitelist-only grants).

GRANT EXECUTE ON FUNCTION auth_internal.get_appointment_settings(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.set_appointment_default_duration(uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_appointment(
  uuid, uuid, uuid, text, timestamptz, int, timestamptz, text
) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.reschedule_appointment(uuid, timestamptz, int, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.cancel_appointment(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_appointment_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.list_appointments(uuid, timestamptz, timestamptz, uuid, text[]) TO authenticated;
