-- Enforce invoices.view (or payments.record for payments) at RLS layer for doctor/lab_staff denial.

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

DROP POLICY IF EXISTS invoices_select ON public.invoices;
CREATE POLICY invoices_select ON public.invoices
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND branch_id = ANY (public.jwt_branch_ids())
    AND auth_internal.staff_has_invoices_view_access()
  );

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

REVOKE ALL ON FUNCTION auth_internal.staff_has_invoices_view_access() FROM PUBLIC, authenticated, anon;
REVOKE ALL ON FUNCTION auth_internal.staff_has_payments_read_access() FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION auth_internal.staff_has_invoices_view_access() TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.staff_has_payments_read_access() TO authenticated;
