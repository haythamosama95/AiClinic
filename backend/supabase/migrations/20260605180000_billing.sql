-- =============================================================================
-- V1-6: Billing (schema, RLS, helpers, permission seed, settings trigger)
-- =============================================================================

DO $$
BEGIN
  CREATE TYPE public.invoice_status AS ENUM ('draft', 'issued', 'partially_paid', 'paid', 'voided');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
  CREATE TYPE public.payment_method AS ENUM ('cash', 'card', 'bank_transfer', 'insurance_settlement');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
  CREATE TYPE public.discount_kind AS ENUM ('percentage', 'fixed');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

-- -----------------------------------------------------------------------------
-- insurance_providers (org-scoped; referenced by invoices)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.insurance_providers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id),
  name text NOT NULL,
  contact_info text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT insurance_providers_name_length CHECK (char_length(name) <= 200)
);

CREATE UNIQUE INDEX IF NOT EXISTS insurance_providers_org_name_unique
  ON public.insurance_providers (organization_id, lower(name))
  WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS insurance_providers_org_active_idx
  ON public.insurance_providers (organization_id)
  WHERE is_deleted = false AND is_active = true;

-- -----------------------------------------------------------------------------
-- invoices
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id),
  branch_id uuid NOT NULL REFERENCES public.branches (id),
  patient_id uuid NOT NULL REFERENCES public.patients (id),
  visit_id uuid NOT NULL REFERENCES public.visits (id),
  invoice_number text,
  status public.invoice_status NOT NULL DEFAULT 'draft',
  subtotal numeric(14, 2) NOT NULL DEFAULT 0.00,
  discount_kind public.discount_kind,
  discount_value numeric(14, 2),
  discount_amount numeric(14, 2) NOT NULL DEFAULT 0.00,
  insurance_provider_id uuid REFERENCES public.insurance_providers (id),
  insurance_covered_amount numeric(14, 2) NOT NULL DEFAULT 0.00,
  currency text NOT NULL DEFAULT 'USD',
  issued_at timestamptz,
  void_reason text,
  voided_at timestamptz,
  voided_by uuid REFERENCES public.staff_members (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT invoices_amounts_non_negative CHECK (
    subtotal >= 0
    AND discount_amount >= 0
    AND insurance_covered_amount >= 0
  ),
  CONSTRAINT invoices_discount_kind_value_pair CHECK (
    (discount_kind IS NULL) = (discount_value IS NULL)
  ),
  CONSTRAINT invoices_discount_percentage_bounds CHECK (
    discount_kind <> 'percentage'
    OR (discount_value BETWEEN 0 AND 100)
  ),
  CONSTRAINT invoices_insurance_covered_bounds CHECK (
    insurance_covered_amount <= subtotal - discount_amount
  ),
  CONSTRAINT invoices_void_fields_consistency CHECK (
    (status = 'voided') = (voided_at IS NOT NULL)
    AND ((status = 'voided') = (void_reason IS NOT NULL))
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS invoices_visit_active_unique
  ON public.invoices (visit_id)
  WHERE status <> 'voided' AND is_deleted = false;

CREATE UNIQUE INDEX IF NOT EXISTS invoices_branch_number_unique
  ON public.invoices (branch_id, invoice_number)
  WHERE invoice_number IS NOT NULL;

CREATE INDEX IF NOT EXISTS invoices_branch_created_idx
  ON public.invoices (branch_id, created_at DESC)
  WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS invoices_patient_created_idx
  ON public.invoices (patient_id, created_at DESC)
  WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS invoices_visit_idx
  ON public.invoices (visit_id)
  WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS invoices_status_branch_idx
  ON public.invoices (status, branch_id)
  WHERE is_deleted = false;

-- -----------------------------------------------------------------------------
-- invoice_items
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.invoice_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL REFERENCES public.invoices (id) ON DELETE CASCADE,
  description text NOT NULL,
  quantity numeric(14, 2) NOT NULL,
  unit_price numeric(14, 2) NOT NULL,
  line_subtotal numeric(14, 2) NOT NULL,
  line_discount_kind public.discount_kind,
  line_discount_value numeric(14, 2),
  line_discount_amount numeric(14, 2) NOT NULL DEFAULT 0.00,
  line_total numeric(14, 2) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT invoice_items_description_length CHECK (char_length(description) <= 500),
  CONSTRAINT invoice_items_quantity_positive CHECK (quantity > 0),
  CONSTRAINT invoice_items_unit_price_non_negative CHECK (unit_price >= 0),
  CONSTRAINT invoice_items_line_subtotal_formula CHECK (line_subtotal = quantity * unit_price),
  CONSTRAINT invoice_items_line_discount_kind_value_pair CHECK (
    (line_discount_kind IS NULL) = (line_discount_value IS NULL)
  ),
  CONSTRAINT invoice_items_line_discount_amount_bounds CHECK (
    line_discount_amount <= line_subtotal
    AND line_total = line_subtotal - line_discount_amount
  )
);

CREATE INDEX IF NOT EXISTS invoice_items_invoice_idx
  ON public.invoice_items (invoice_id)
  WHERE is_deleted = false;

-- -----------------------------------------------------------------------------
-- payments (append-only)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL REFERENCES public.invoices (id),
  branch_id uuid NOT NULL REFERENCES public.branches (id),
  method public.payment_method NOT NULL,
  amount numeric(14, 2) NOT NULL,
  reference text,
  note text,
  recorded_by uuid NOT NULL REFERENCES public.staff_members (id),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  CONSTRAINT payments_amount_non_zero CHECK (amount <> 0),
  CONSTRAINT payments_refund_requires_note CHECK (
    amount > 0
    OR (amount < 0 AND note IS NOT NULL AND length(trim(note)) > 0)
  )
);

CREATE INDEX IF NOT EXISTS payments_invoice_recorded_idx
  ON public.payments (invoice_id, recorded_at);

CREATE INDEX IF NOT EXISTS payments_branch_recorded_idx
  ON public.payments (branch_id, recorded_at DESC);

REVOKE UPDATE, DELETE ON public.payments FROM PUBLIC, authenticated, anon;

-- -----------------------------------------------------------------------------
-- organization_billing_settings
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.organization_billing_settings (
  organization_id uuid PRIMARY KEY REFERENCES public.organizations (id),
  allow_partial_payments boolean NOT NULL DEFAULT false,
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id)
);

-- -----------------------------------------------------------------------------
-- invoice_number_sequences (RPC-internal)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.invoice_number_sequences (
  branch_id uuid PRIMARY KEY REFERENCES public.branches (id),
  last_value bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- Audit triggers
-- -----------------------------------------------------------------------------

SELECT public.apply_standard_audit_triggers('public.insurance_providers'::regclass);
SELECT public.apply_standard_audit_triggers('public.invoices'::regclass);
SELECT public.apply_standard_audit_triggers('public.invoice_items'::regclass);

-- payments: created_at/created_by only (append-only; no updated_at/updated_by)
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
CREATE TRIGGER trg_payments_set_created_by
  BEFORE INSERT ON public.payments
  FOR EACH ROW
  EXECUTE FUNCTION public.set_payment_created_by();

-- organization_billing_settings: updated_at/updated_by only (no created_by column)
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

DROP TRIGGER IF EXISTS trg_organization_billing_settings_set_updated_at ON public.organization_billing_settings;
CREATE TRIGGER trg_organization_billing_settings_set_updated_at
  BEFORE UPDATE ON public.organization_billing_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_organization_billing_settings_set_audit_user ON public.organization_billing_settings;
CREATE TRIGGER trg_organization_billing_settings_set_audit_user
  BEFORE INSERT OR UPDATE ON public.organization_billing_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.set_billing_settings_audit_user();

-- -----------------------------------------------------------------------------
-- Permission-aware RLS helpers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.staff_has_invoices_view_access()
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
    WHERE rp.permission_key = 'invoices.view'
      AND rp.is_granted = true
      AND rp.is_deleted = false
  );
$$;

CREATE OR REPLACE FUNCTION auth_internal.staff_has_payments_read_access()
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
    WHERE rp.permission_key IN ('invoices.view', 'payments.record')
      AND rp.is_granted = true
      AND rp.is_deleted = false
  );
$$;

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------

ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insurance_providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_billing_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_number_sequences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS invoices_select ON public.invoices;
CREATE POLICY invoices_select ON public.invoices
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND branch_id = ANY (public.jwt_branch_ids())
    AND auth_internal.staff_has_invoices_view_access()
  );

DROP POLICY IF EXISTS invoices_insert ON public.invoices;
CREATE POLICY invoices_insert ON public.invoices
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS invoices_update ON public.invoices;
CREATE POLICY invoices_update ON public.invoices
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS invoices_delete ON public.invoices;
CREATE POLICY invoices_delete ON public.invoices
  FOR DELETE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS invoice_items_select ON public.invoice_items;
CREATE POLICY invoice_items_select ON public.invoice_items
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND auth_internal.staff_has_invoices_view_access()
    AND EXISTS (
      SELECT 1
      FROM public.invoices i
      WHERE i.id = invoice_items.invoice_id
        AND i.is_deleted = false
        AND i.branch_id = ANY (public.jwt_branch_ids())
    )
  );

DROP POLICY IF EXISTS invoice_items_insert ON public.invoice_items;
CREATE POLICY invoice_items_insert ON public.invoice_items
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS invoice_items_update ON public.invoice_items;
CREATE POLICY invoice_items_update ON public.invoice_items
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS invoice_items_delete ON public.invoice_items;
CREATE POLICY invoice_items_delete ON public.invoice_items
  FOR DELETE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS payments_select ON public.payments;
CREATE POLICY payments_select ON public.payments
  FOR SELECT
  TO authenticated
  USING (
    auth_internal.staff_has_payments_read_access()
    AND EXISTS (
      SELECT 1
      FROM public.invoices i
      WHERE i.id = payments.invoice_id
        AND i.is_deleted = false
        AND i.branch_id = ANY (public.jwt_branch_ids())
    )
  );

DROP POLICY IF EXISTS payments_insert ON public.payments;
CREATE POLICY payments_insert ON public.payments
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS payments_update ON public.payments;
CREATE POLICY payments_update ON public.payments
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS payments_delete ON public.payments;
CREATE POLICY payments_delete ON public.payments
  FOR DELETE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS insurance_providers_select ON public.insurance_providers;
CREATE POLICY insurance_providers_select ON public.insurance_providers
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND organization_id = public.jwt_organization_id()
  );

DROP POLICY IF EXISTS insurance_providers_insert ON public.insurance_providers;
CREATE POLICY insurance_providers_insert ON public.insurance_providers
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS insurance_providers_update ON public.insurance_providers;
CREATE POLICY insurance_providers_update ON public.insurance_providers
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS insurance_providers_delete ON public.insurance_providers;
CREATE POLICY insurance_providers_delete ON public.insurance_providers
  FOR DELETE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS organization_billing_settings_select ON public.organization_billing_settings;
CREATE POLICY organization_billing_settings_select ON public.organization_billing_settings
  FOR SELECT
  TO authenticated
  USING (organization_id = public.jwt_organization_id());

DROP POLICY IF EXISTS organization_billing_settings_insert ON public.organization_billing_settings;
CREATE POLICY organization_billing_settings_insert ON public.organization_billing_settings
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS organization_billing_settings_update ON public.organization_billing_settings;
CREATE POLICY organization_billing_settings_update ON public.organization_billing_settings
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS organization_billing_settings_delete ON public.organization_billing_settings;
CREATE POLICY organization_billing_settings_delete ON public.organization_billing_settings
  FOR DELETE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS invoice_number_sequences_deny ON public.invoice_number_sequences;
CREATE POLICY invoice_number_sequences_deny ON public.invoice_number_sequences
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);

-- -----------------------------------------------------------------------------
-- Auto-provision billing settings on organization insert + backfill
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.provision_organization_billing_settings()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.organization_billing_settings (organization_id, allow_partial_payments)
  VALUES (NEW.id, false)
  ON CONFLICT (organization_id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_organizations_provision_billing_settings ON public.organizations;
CREATE TRIGGER trg_organizations_provision_billing_settings
  AFTER INSERT ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.provision_organization_billing_settings();

INSERT INTO public.organization_billing_settings (organization_id, allow_partial_payments)
SELECT o.id, false
FROM public.organizations o
ON CONFLICT (organization_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Discount scope mutual-exclusion trigger (D3)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.trg_enforce_discount_scope_exclusive()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_invoice_id uuid;
  v_invoice_discount numeric(14, 2);
  v_line_discount_sum numeric(14, 2);
BEGIN
  IF TG_TABLE_NAME = 'invoice_items' THEN
    v_invoice_id := COALESCE(NEW.invoice_id, OLD.invoice_id);
  ELSE
    v_invoice_id := COALESCE(NEW.id, OLD.id);
  END IF;

  SELECT COALESCE(i.discount_amount, 0)
  INTO v_invoice_discount
  FROM public.invoices i
  WHERE i.id = v_invoice_id
    AND i.is_deleted = false;

  SELECT COALESCE(SUM(ii.line_discount_amount), 0)
  INTO v_line_discount_sum
  FROM public.invoice_items ii
  WHERE ii.invoice_id = v_invoice_id
    AND ii.is_deleted = false;

  IF v_invoice_discount > 0 AND v_line_discount_sum > 0 THEN
    RAISE EXCEPTION 'discount_scope_conflict';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_invoices_discount_scope_exclusive ON public.invoices;
CREATE TRIGGER trg_invoices_discount_scope_exclusive
  AFTER INSERT OR UPDATE OF discount_amount, discount_kind, discount_value
  ON public.invoices
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_enforce_discount_scope_exclusive();

DROP TRIGGER IF EXISTS trg_invoice_items_discount_scope_exclusive ON public.invoice_items;
CREATE TRIGGER trg_invoice_items_discount_scope_exclusive
  AFTER INSERT OR UPDATE OF line_discount_amount, line_discount_kind, line_discount_value
  ON public.invoice_items
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_enforce_discount_scope_exclusive();

-- -----------------------------------------------------------------------------
-- Permission seed (FR-021)
-- -----------------------------------------------------------------------------

INSERT INTO public.roles_permissions (role, permission_key, is_granted)
VALUES
  ('owner', 'invoices.view', true),
  ('owner', 'invoices.create', true),
  ('owner', 'invoices.apply_discount', true),
  ('owner', 'invoices.void', true),
  ('owner', 'payments.record', true),
  ('owner', 'payments.refund', true),
  ('owner', 'insurance.manage', true),
  ('owner', 'settings.billing.manage', true),
  ('administrator', 'invoices.view', true),
  ('administrator', 'invoices.create', true),
  ('administrator', 'invoices.apply_discount', true),
  ('administrator', 'invoices.void', true),
  ('administrator', 'payments.record', true),
  ('administrator', 'payments.refund', true),
  ('administrator', 'insurance.manage', true),
  ('administrator', 'settings.billing.manage', true),
  ('receptionist', 'invoices.view', true),
  ('receptionist', 'invoices.create', true),
  ('receptionist', 'payments.record', true),
  ('doctor', 'invoices.view', false),
  ('doctor', 'invoices.create', false),
  ('doctor', 'payments.record', false),
  ('lab_staff', 'invoices.view', false),
  ('lab_staff', 'invoices.create', false),
  ('lab_staff', 'payments.record', false)
ON CONFLICT (role, permission_key) DO UPDATE
SET is_granted = EXCLUDED.is_granted,
    is_deleted = false;

-- Non-delegable settings.billing.manage in role-permission RPC (D10)
CREATE OR REPLACE FUNCTION auth_internal.update_role_permission(
  p_role public.staff_role,
  p_permission_key text,
  p_is_granted boolean
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_old boolean;
  v_row public.roles_permissions%ROWTYPE;
  v_key text := trim(p_permission_key);
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();

  IF NULLIF(v_key, '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Permission key is required.');
  END IF;

  IF v_key = 'settings.billing.manage'
     AND p_is_granted = true
     AND p_role NOT IN ('owner', 'administrator') THEN
    RETURN public.rpc_error(
      'PERMISSION_NOT_DELEGABLE',
      'settings.billing.manage cannot be granted to this role.'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.roles_permissions rp
    WHERE rp.permission_key = v_key
      AND rp.is_deleted = false
  ) THEN
    RETURN public.rpc_error('INVALID_PERMISSION', 'Permission key is not in the catalog.');
  END IF;

  SELECT rp.is_granted
  INTO v_old
  FROM public.roles_permissions rp
  WHERE rp.role = p_role
    AND rp.permission_key = v_key
    AND rp.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('PERMISSION_NOT_FOUND', 'Permission row was not found for this role.');
  END IF;

  UPDATE public.roles_permissions rp
  SET
    is_granted = p_is_granted,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE rp.role = p_role
    AND rp.permission_key = v_key
    AND rp.is_deleted = false
  RETURNING * INTO v_row;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'role_permission.update',
    'roles_permissions',
    v_row.id,
    jsonb_build_object('role', p_role::text, 'permission_key', v_key, 'is_granted', v_old),
    jsonb_build_object('role', p_role::text, 'permission_key', v_key, 'is_granted', p_is_granted)
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'role', p_role::text,
      'permission_key', v_key,
      'is_granted', p_is_granted
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only owners and administrators may update the permission matrix.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal billing helpers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_invoice_branch_scope(p_invoice_id uuid)
RETURNS public.invoices
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
BEGIN
  SELECT *
  INTO v_invoice
  FROM public.invoices i
  WHERE i.id = p_invoice_id
    AND i.is_deleted = false
    AND i.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND';
  END IF;

  RETURN v_invoice;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.assert_invoice_in_draft(p_invoice public.invoices)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
BEGIN
  IF p_invoice.status <> 'draft' THEN
    RAISE EXCEPTION 'invoice_not_in_draft';
  END IF;

  IF p_invoice.status = 'voided' THEN
    RAISE EXCEPTION 'invoice_voided';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.assert_one_active_invoice_per_visit(p_visit_id uuid, p_exclude_invoice_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.invoices i
    WHERE i.visit_id = p_visit_id
      AND i.is_deleted = false
      AND i.status <> 'voided'
      AND (p_exclude_invoice_id IS NULL OR i.id <> p_exclude_invoice_id)
  ) THEN
    RAISE EXCEPTION 'active_invoice_exists';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.assert_discount_scope_exclusive(p_invoice_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice_discount numeric(14, 2);
  v_line_discount_sum numeric(14, 2);
BEGIN
  SELECT COALESCE(i.discount_amount, 0)
  INTO v_invoice_discount
  FROM public.invoices i
  WHERE i.id = p_invoice_id
    AND i.is_deleted = false;

  SELECT COALESCE(SUM(ii.line_discount_amount), 0)
  INTO v_line_discount_sum
  FROM public.invoice_items ii
  WHERE ii.invoice_id = p_invoice_id
    AND ii.is_deleted = false;

  IF v_invoice_discount > 0 AND v_line_discount_sum > 0 THEN
    RAISE EXCEPTION 'discount_scope_conflict';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.compute_invoice_subtotal(p_invoice_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(SUM(ii.line_total), 0)::numeric(14, 2)
  FROM public.invoice_items ii
  WHERE ii.invoice_id = p_invoice_id
    AND ii.is_deleted = false;
$$;

CREATE OR REPLACE FUNCTION auth_internal.compute_invoice_balance(p_invoice_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (
    COALESCE(i.subtotal, 0)
    - COALESCE(i.discount_amount, 0)
    - COALESCE(i.insurance_covered_amount, 0)
    - COALESCE((
        SELECT SUM(p.amount)
        FROM public.payments p
        WHERE p.invoice_id = i.id
      ), 0)
  )::numeric(14, 2)
  FROM public.invoices i
  WHERE i.id = p_invoice_id
    AND i.is_deleted = false;
$$;

CREATE OR REPLACE FUNCTION auth_internal.assign_invoice_number(p_branch_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch_code text;
  v_next bigint;
BEGIN
  SELECT NULLIF(trim(b.code), '')
  INTO v_branch_code
  FROM public.branches b
  WHERE b.id = p_branch_id
    AND b.is_deleted = false;

  IF v_branch_code IS NULL THEN
    RAISE EXCEPTION 'branch_code_missing';
  END IF;

  INSERT INTO public.invoice_number_sequences (branch_id, last_value, updated_at)
  VALUES (p_branch_id, 0, now())
  ON CONFLICT (branch_id) DO NOTHING;

  UPDATE public.invoice_number_sequences s
  SET
    last_value = s.last_value + 1,
    updated_at = now()
  WHERE s.branch_id = p_branch_id
  RETURNING s.last_value INTO v_next;

  RETURN format('INV-%s-%s', v_branch_code, lpad(v_next::text, 6, '0'));
END;
$$;

-- Restrict helper execution to postgres/service role (RPCs grant as needed in later phases)
REVOKE ALL ON FUNCTION auth_internal.assert_invoice_branch_scope(uuid) FROM PUBLIC, authenticated, anon;
REVOKE ALL ON FUNCTION auth_internal.assert_invoice_in_draft(public.invoices) FROM PUBLIC, authenticated, anon;
REVOKE ALL ON FUNCTION auth_internal.assert_one_active_invoice_per_visit(uuid, uuid) FROM PUBLIC, authenticated, anon;
REVOKE ALL ON FUNCTION auth_internal.assert_discount_scope_exclusive(uuid) FROM PUBLIC, authenticated, anon;
REVOKE ALL ON FUNCTION auth_internal.compute_invoice_subtotal(uuid) FROM PUBLIC, authenticated, anon;
REVOKE ALL ON FUNCTION auth_internal.compute_invoice_balance(uuid) FROM PUBLIC, authenticated, anon;
REVOKE ALL ON FUNCTION auth_internal.assign_invoice_number(uuid) FROM PUBLIC, authenticated, anon;
REVOKE ALL ON FUNCTION auth_internal.staff_has_invoices_view_access() FROM PUBLIC, authenticated, anon;
REVOKE ALL ON FUNCTION auth_internal.staff_has_payments_read_access() FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION auth_internal.staff_has_invoices_view_access() TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.staff_has_payments_read_access() TO authenticated;
