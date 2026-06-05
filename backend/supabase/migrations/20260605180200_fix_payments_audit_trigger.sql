-- Fix payments audit trigger (append-only table has no updated_by column).

CREATE OR REPLACE FUNCTION public.set_payment_created_by()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.created_by := COALESCE(NEW.created_by, auth.uid());
  NEW.created_at := COALESCE(NEW.created_at, now());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payments_set_audit_user ON public.payments;
DROP TRIGGER IF EXISTS trg_payments_set_created_by ON public.payments;
CREATE TRIGGER trg_payments_set_created_by
  BEFORE INSERT ON public.payments
  FOR EACH ROW
  EXECUTE FUNCTION public.set_payment_created_by();
