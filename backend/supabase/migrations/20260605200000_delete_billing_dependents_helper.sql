-- Shared FK-safe billing teardown for dev_reset parity and backend SQL tests (V1-6).

CREATE OR REPLACE FUNCTION auth_internal.delete_billing_dependents()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF to_regclass('public.payments') IS NOT NULL THEN
    DELETE FROM public.payments;
  END IF;
  IF to_regclass('public.invoice_items') IS NOT NULL THEN
    DELETE FROM public.invoice_items;
  END IF;
  IF to_regclass('public.invoices') IS NOT NULL THEN
    DELETE FROM public.invoices;
  END IF;
  IF to_regclass('public.invoice_number_sequences') IS NOT NULL THEN
    DELETE FROM public.invoice_number_sequences;
  END IF;
  IF to_regclass('public.insurance_providers') IS NOT NULL THEN
    DELETE FROM public.insurance_providers;
  END IF;
  IF to_regclass('public.organization_billing_settings') IS NOT NULL THEN
    DELETE FROM public.organization_billing_settings;
  END IF;
END;
$$;

COMMENT ON FUNCTION auth_internal.delete_billing_dependents() IS
  'Delete billing rows in FK-safe order before visits/branches/organizations. Used by backend SQL tests.';
