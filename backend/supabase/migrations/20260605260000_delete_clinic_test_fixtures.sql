-- FK-safe clinic data teardown for backend SQL tests and dev_reset parity (V1-6).

CREATE OR REPLACE FUNCTION auth_internal.delete_clinic_operational_dependents()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM auth_internal.delete_billing_dependents();

  IF to_regclass('public.visit_attachments') IS NOT NULL THEN
    DELETE FROM public.visit_attachments;
  END IF;
  IF to_regclass('public.soap_notes') IS NOT NULL THEN
    DELETE FROM public.soap_notes;
  END IF;
  IF to_regclass('public.treatment_plans') IS NOT NULL THEN
    DELETE FROM public.treatment_plans;
  END IF;
  IF to_regclass('public.visits') IS NOT NULL THEN
    DELETE FROM public.visits;
  END IF;

  IF to_regclass('public.appointments') IS NOT NULL THEN
    DELETE FROM public.appointments;
  END IF;

  DELETE FROM public.patients;
END;
$$;

COMMENT ON FUNCTION auth_internal.delete_clinic_operational_dependents() IS
  'Delete billing, visit, appointment, and patient rows in FK-safe order. Used by backend SQL tests.';

CREATE OR REPLACE FUNCTION auth_internal.delete_clinic_test_fixtures(
  p_preserve_staff_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM auth_internal.delete_clinic_operational_dependents();

  DELETE FROM public.staff_branch_assignments;

  IF COALESCE(array_length(p_preserve_staff_ids, 1), 0) > 0 THEN
    DELETE FROM public.staff_members
    WHERE id <> ALL (p_preserve_staff_ids);
  ELSE
    DELETE FROM public.staff_members;
  END IF;

  DELETE FROM public.audit_log;
  DELETE FROM public.app_settings;
  DELETE FROM public.subscription_cache;
  DELETE FROM public.branches;
  DELETE FROM public.organizations;
END;
$$;

COMMENT ON FUNCTION auth_internal.delete_clinic_test_fixtures(uuid[]) IS
  'FK-safe org/clinic teardown for backend SQL tests; optionally preserves bootstrap or fixture staff rows.';

GRANT EXECUTE ON FUNCTION auth_internal.delete_clinic_operational_dependents() TO postgres;
GRANT EXECUTE ON FUNCTION auth_internal.delete_clinic_test_fixtures(uuid[]) TO postgres;
