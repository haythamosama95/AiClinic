-- Backfill predefined vital signs (and other org catalog defaults) for orgs that missed seeding.
-- bootstrap_finish_setup never called seed_organization_catalog_defaults; only bootstrap_create_organization did.

-- Backfill every active organization (idempotent per catalog row).
SELECT auth_internal.seed_organization_catalog_defaults(o.id)
FROM public.organizations o
WHERE o.is_deleted = false;

-- Ensure any future organization insert receives catalog defaults regardless of creation path.
CREATE OR REPLACE FUNCTION auth_internal.trg_seed_organization_catalog_defaults()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM auth_internal.seed_organization_catalog_defaults(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS seed_organization_catalog_defaults ON public.organizations;
CREATE TRIGGER seed_organization_catalog_defaults
  AFTER INSERT ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_seed_organization_catalog_defaults();
