-- =============================================================================
-- Service Catalog (015): schema, RLS, audit triggers, permission seed
-- =============================================================================

DO $$
BEGIN
  CREATE TYPE public.service_global_status AS ENUM ('active', 'inactive');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
  CREATE TYPE public.service_branch_status AS ENUM ('active', 'inactive');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
  CREATE TYPE public.service_copy_mode AS ENUM ('replace', 'merge');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

-- -----------------------------------------------------------------------------
-- services (org-scoped catalog root)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id),
  name text NOT NULL,
  default_price numeric(14, 2) NOT NULL,
  global_status public.service_global_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT services_name_length CHECK (char_length(btrim(name)) BETWEEN 1 AND 200),
  CONSTRAINT services_default_price_non_negative CHECK (default_price >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS services_org_name_unique
  ON public.services (organization_id, lower(btrim(name)))
  WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS services_org_status_idx
  ON public.services (organization_id, global_status)
  WHERE is_deleted = false;

-- -----------------------------------------------------------------------------
-- service_branches (per-branch assignment + configuration)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.service_branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id uuid NOT NULL REFERENCES public.services (id),
  branch_id uuid NOT NULL REFERENCES public.branches (id),
  status public.service_branch_status NOT NULL DEFAULT 'active',
  price_override numeric(14, 2),
  promotion_price numeric(14, 2),
  promotion_start_date date,
  promotion_end_date date,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT service_branches_price_override_non_negative CHECK (
    price_override IS NULL OR price_override >= 0
  ),
  CONSTRAINT service_branches_promotion_price_non_negative CHECK (
    promotion_price IS NULL OR promotion_price >= 0
  ),
  CONSTRAINT service_branches_promotion_all_or_nothing CHECK (
    (
      promotion_price IS NULL
      AND promotion_start_date IS NULL
      AND promotion_end_date IS NULL
    )
    OR (
      promotion_price IS NOT NULL
      AND promotion_start_date IS NOT NULL
      AND promotion_end_date IS NOT NULL
      AND promotion_start_date <= promotion_end_date
    )
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS service_branches_service_branch_unique
  ON public.service_branches (service_id, branch_id)
  WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS service_branches_branch_status_idx
  ON public.service_branches (branch_id, status)
  WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS service_branches_service_idx
  ON public.service_branches (service_id)
  WHERE is_deleted = false;

-- -----------------------------------------------------------------------------
-- Audit triggers
-- -----------------------------------------------------------------------------

SELECT public.apply_standard_audit_triggers('public.services'::regclass);
SELECT public.apply_standard_audit_triggers('public.service_branches'::regclass);

-- -----------------------------------------------------------------------------
-- Permission-aware RLS helpers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.staff_has_services_read_access()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.current_staff_member_row() sm
    JOIN public.roles_permissions rp ON rp.role = sm.role
    WHERE rp.permission_key IN ('services.view', 'services.manage', 'invoices.create')
      AND rp.is_granted = true
      AND rp.is_deleted = false
  );
$$;

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------

ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_branches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS services_select ON public.services;
CREATE POLICY services_select ON public.services
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND organization_id = public.jwt_organization_id()
    AND auth_internal.staff_has_services_read_access()
  );

DROP POLICY IF EXISTS services_insert ON public.services;
CREATE POLICY services_insert ON public.services
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS services_update ON public.services;
CREATE POLICY services_update ON public.services
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS services_delete ON public.services;
CREATE POLICY services_delete ON public.services
  FOR DELETE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS service_branches_select ON public.service_branches;
CREATE POLICY service_branches_select ON public.service_branches
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND branch_id = ANY (public.jwt_branch_ids())
    AND auth_internal.staff_has_services_read_access()
    AND EXISTS (
      SELECT 1
      FROM public.services s
      WHERE s.id = service_branches.service_id
        AND s.is_deleted = false
        AND s.organization_id = public.jwt_organization_id()
    )
  );

DROP POLICY IF EXISTS service_branches_insert ON public.service_branches;
CREATE POLICY service_branches_insert ON public.service_branches
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS service_branches_update ON public.service_branches;
CREATE POLICY service_branches_update ON public.service_branches
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS service_branches_delete ON public.service_branches;
CREATE POLICY service_branches_delete ON public.service_branches
  FOR DELETE
  TO authenticated
  USING (false);

-- -----------------------------------------------------------------------------
-- Permission seed (services.view, services.manage)
-- -----------------------------------------------------------------------------

INSERT INTO public.roles_permissions (role, permission_key, is_granted)
VALUES
  ('owner', 'services.view', true),
  ('owner', 'services.manage', true),
  ('administrator', 'services.view', true),
  ('administrator', 'services.manage', true),
  ('doctor', 'services.view', false),
  ('doctor', 'services.manage', false),
  ('receptionist', 'services.view', false),
  ('receptionist', 'services.manage', false),
  ('lab_staff', 'services.view', false),
  ('lab_staff', 'services.manage', false)
ON CONFLICT (role, permission_key) DO UPDATE
SET is_granted = EXCLUDED.is_granted,
    is_deleted = false;

REVOKE ALL ON FUNCTION auth_internal.staff_has_services_read_access() FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION auth_internal.staff_has_services_read_access() TO authenticated;
