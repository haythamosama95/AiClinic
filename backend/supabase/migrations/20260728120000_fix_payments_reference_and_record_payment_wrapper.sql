-- payments.reference is defined in billing.sql but may be absent when the table
-- already existed before that migration (CREATE TABLE IF NOT EXISTS).
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS reference text;

-- Public wrapper: note-only API delegating to auth_internal with NULL reference.
CREATE OR REPLACE FUNCTION public.record_payment(
  p_invoice_id uuid,
  p_method public.payment_method,
  p_amount numeric,
  p_note text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.record_payment(p_invoice_id, p_method, p_amount, NULL, p_note);
$$;

GRANT EXECUTE ON FUNCTION public.record_payment(uuid, public.payment_method, numeric, text) TO authenticated;
