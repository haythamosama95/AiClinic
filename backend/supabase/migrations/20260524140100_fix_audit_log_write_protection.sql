-- Fix 32 + 35: Restrict direct DML on audit_log and subscription_cache.
-- SECURITY DEFINER functions (running as postgres) bypass RLS, so RPC audit inserts still work.

-- Revoke direct write privileges from authenticated role
REVOKE INSERT, UPDATE, DELETE ON public.audit_log FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.subscription_cache FROM authenticated;

-- Explicit deny policies for defense-in-depth (RLS must be enabled, which it already is)
CREATE POLICY audit_log_deny_insert ON public.audit_log
  FOR INSERT TO authenticated WITH CHECK (false);

CREATE POLICY audit_log_deny_update ON public.audit_log
  FOR UPDATE TO authenticated USING (false);

CREATE POLICY audit_log_deny_delete ON public.audit_log
  FOR DELETE TO authenticated USING (false);

CREATE POLICY subscription_cache_deny_insert ON public.subscription_cache
  FOR INSERT TO authenticated WITH CHECK (false);

CREATE POLICY subscription_cache_deny_update ON public.subscription_cache
  FOR UPDATE TO authenticated USING (false);

CREATE POLICY subscription_cache_deny_delete ON public.subscription_cache
  FOR DELETE TO authenticated USING (false);
