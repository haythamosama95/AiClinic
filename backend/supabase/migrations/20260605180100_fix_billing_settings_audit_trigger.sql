-- Fix organization_billing_settings audit trigger (no created_by column on table).

CREATE OR REPLACE FUNCTION public.set_billing_settings_audit_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.updated_by := COALESCE(NEW.updated_by, auth.uid());
    NEW.updated_at := COALESCE(NEW.updated_at, now());
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.updated_by := auth.uid();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_organization_billing_settings_set_audit_user ON public.organization_billing_settings;
CREATE TRIGGER trg_organization_billing_settings_set_audit_user
  BEFORE INSERT OR UPDATE ON public.organization_billing_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.set_billing_settings_audit_user();
