-- Seed file for local development
-- The bootstrap admin is created by migration 20260516100400_auth_rbac_seed.sql
-- Add any additional local dev seed data below this line.

-- Local-only: expose app.environment to PostgREST sessions so dev_reset and similar
-- tooling work via RPC. Production databases never run this seed file.
CREATE OR REPLACE FUNCTION public.local_dev_pre_request()
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path = public
AS $fn$
  SELECT set_config('app.environment', 'development', true);
$fn$;

REVOKE ALL ON FUNCTION public.local_dev_pre_request() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.local_dev_pre_request() TO authenticator, anon, authenticated, service_role;

DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    EXECUTE format(
      'ALTER ROLE authenticator SET pgrst.db_pre_request TO %L',
      'public.local_dev_pre_request'
    );
    PERFORM pg_notify('pgrst', 'reload config');
  END IF;
END
$do$;
