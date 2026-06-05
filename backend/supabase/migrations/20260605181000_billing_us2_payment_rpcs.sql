-- =============================================================================
-- V1-6: Billing US2 RPCs (record payment, record refund, read billing settings)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Internal helpers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.lock_payable_invoice(p_invoice_id uuid)
RETURNS public.invoices
LANGUAGE plpgsql
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
    AND i.branch_id = ANY (public.jwt_branch_ids())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND';
  END IF;

  IF v_invoice.status = 'voided' THEN
    RAISE EXCEPTION 'invoice_voided';
  END IF;

  IF v_invoice.status NOT IN ('issued', 'partially_paid') THEN
    RAISE EXCEPTION 'invoice_not_payable';
  END IF;

  RETURN v_invoice;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.invoice_original_due(p_invoice public.invoices)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (
    COALESCE(p_invoice.subtotal, 0)
    - COALESCE(p_invoice.discount_amount, 0)
    - COALESCE(p_invoice.insurance_covered_amount, 0)
  )::numeric(14, 2);
$$;

CREATE OR REPLACE FUNCTION auth_internal.recompute_invoice_status_after_payment(
  p_invoice_id uuid,
  p_prior_status public.invoice_status,
  p_new_balance numeric
)
RETURNS public.invoice_status
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
  v_status public.invoice_status;
  v_original_due numeric(14, 2);
BEGIN
  SELECT *
  INTO v_invoice
  FROM public.invoices i
  WHERE i.id = p_invoice_id;

  v_original_due := auth_internal.invoice_original_due(v_invoice);

  IF p_new_balance <= 0 THEN
    v_status := 'paid';
  ELSIF p_prior_status = 'paid' THEN
    IF p_new_balance >= v_original_due THEN
      v_status := 'issued';
    ELSE
      v_status := 'partially_paid';
    END IF;
  ELSE
    v_status := 'partially_paid';
  END IF;

  UPDATE public.invoices i
  SET
    status = v_status,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE i.id = p_invoice_id;

  RETURN v_status;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.record_payment
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.record_payment(
  p_invoice_id uuid,
  p_method public.payment_method,
  p_amount numeric,
  p_reference text,
  p_note text
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_invoice public.invoices%ROWTYPE;
  v_org_id uuid;
  v_prior_balance numeric(14, 2);
  v_new_balance numeric(14, 2);
  v_allow_partial boolean;
  v_prior_status public.invoice_status;
  v_new_status public.invoice_status;
  v_payment_id uuid;
BEGIN
  v_staff := auth_internal.assert_permission('payments.record');
  v_org_id := public.jwt_organization_id();

  IF p_invoice_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Invoice ID is required.');
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Payment amount must be greater than zero.');
  END IF;

  BEGIN
    v_invoice := auth_internal.lock_payable_invoice(p_invoice_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Invoice was not found.');
      ELSIF SQLERRM = 'invoice_voided' THEN
        RETURN public.rpc_error('INVOICE_VOIDED', 'Payments cannot be recorded on voided invoices.');
      ELSIF SQLERRM = 'invoice_not_payable' THEN
        RETURN public.rpc_error('INVOICE_NOT_PAYABLE', 'Payments can only be recorded on issued or partially paid invoices.');
      END IF;
      RAISE;
  END;

  v_prior_status := v_invoice.status;
  v_prior_balance := auth_internal.compute_invoice_balance(p_invoice_id);

  IF p_amount > v_prior_balance THEN
    RETURN public.rpc_error(
      'OVERPAYMENT',
      'Payment amount exceeds the current balance.'
    );
  END IF;

  SELECT obs.allow_partial_payments
  INTO v_allow_partial
  FROM public.organization_billing_settings obs
  WHERE obs.organization_id = v_org_id;

  IF coalesce(v_allow_partial, false) = false
     AND p_method IN ('cash', 'card', 'bank_transfer')
     AND p_amount < v_prior_balance THEN
    RETURN public.rpc_error(
      'PARTIAL_PAYMENTS_DISABLED',
      'Partial payments are not allowed for this organization; please collect the full balance.'
    );
  END IF;

  INSERT INTO public.payments (
    invoice_id,
    branch_id,
    method,
    amount,
    reference,
    note,
    recorded_by
  )
  VALUES (
    p_invoice_id,
    v_invoice.branch_id,
    p_method,
    p_amount,
    nullif(trim(p_reference), ''),
    nullif(trim(p_note), ''),
    v_staff.id
  )
  RETURNING id INTO v_payment_id;

  v_new_balance := auth_internal.compute_invoice_balance(p_invoice_id);
  v_new_status := auth_internal.recompute_invoice_status_after_payment(
    p_invoice_id,
    v_prior_status,
    v_new_balance
  );

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'payment.record',
    'payments',
    v_payment_id,
    jsonb_build_object(
      'invoice_id', p_invoice_id,
      'payment_id', v_payment_id,
      'method', p_method::text,
      'amount', p_amount,
      'prior_balance', v_prior_balance,
      'new_balance', v_new_balance,
      'prior_status', v_prior_status::text,
      'new_status', v_new_status::text
    )
  );

  RETURN public.rpc_success(jsonb_build_object('payment_id', v_payment_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to record payments.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.record_refund
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.record_refund(
  p_invoice_id uuid,
  p_method public.payment_method,
  p_amount numeric,
  p_note text
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_invoice public.invoices%ROWTYPE;
  v_org_id uuid;
  v_prior_balance numeric(14, 2);
  v_new_balance numeric(14, 2);
  v_net_positive numeric(14, 2);
  v_prior_status public.invoice_status;
  v_new_status public.invoice_status;
  v_payment_id uuid;
BEGIN
  v_staff := auth_internal.assert_permission('payments.refund');
  v_org_id := public.jwt_organization_id();

  IF p_invoice_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Invoice ID is required.');
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Refund amount must be greater than zero.');
  END IF;

  IF p_note IS NULL OR length(trim(p_note)) = 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'A refund reason is required.');
  END IF;

  SELECT *
  INTO v_invoice
  FROM public.invoices i
  WHERE i.id = p_invoice_id
    AND i.is_deleted = false
    AND i.branch_id = ANY (public.jwt_branch_ids())
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Invoice was not found.');
  END IF;

  IF v_invoice.status = 'voided' THEN
    RETURN public.rpc_error('INVOICE_VOIDED', 'Refunds cannot be recorded on voided invoices.');
  END IF;

  IF v_invoice.status NOT IN ('issued', 'partially_paid', 'paid') THEN
    RETURN public.rpc_error('INVOICE_NOT_PAYABLE', 'Refunds cannot be recorded on draft invoices.');
  END IF;

  SELECT COALESCE(sum(p.amount), 0)
  INTO v_net_positive
  FROM public.payments p
  WHERE p.invoice_id = p_invoice_id
    AND p.amount > 0;

  IF p_amount > v_net_positive THEN
    RETURN public.rpc_error(
      'INVALID_INPUT',
      'Refund amount exceeds net payments on this invoice.'
    );
  END IF;

  v_prior_status := v_invoice.status;
  v_prior_balance := auth_internal.compute_invoice_balance(p_invoice_id);

  INSERT INTO public.payments (
    invoice_id,
    branch_id,
    method,
    amount,
    reference,
    note,
    recorded_by
  )
  VALUES (
    p_invoice_id,
    v_invoice.branch_id,
    p_method,
    -p_amount,
    NULL,
    trim(p_note),
    v_staff.id
  )
  RETURNING id INTO v_payment_id;

  v_new_balance := auth_internal.compute_invoice_balance(p_invoice_id);
  v_new_status := auth_internal.recompute_invoice_status_after_payment(
    p_invoice_id,
    v_prior_status,
    v_new_balance
  );

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'payment.refund',
    'payments',
    v_payment_id,
    jsonb_build_object(
      'invoice_id', p_invoice_id,
      'payment_id', v_payment_id,
      'method', p_method::text,
      'amount', -p_amount,
      'note', trim(p_note),
      'prior_balance', v_prior_balance,
      'new_balance', v_new_balance,
      'prior_status', v_prior_status::text,
      'new_status', v_new_status::text
    )
  );

  RETURN public.rpc_success(jsonb_build_object('payment_id', v_payment_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to record refunds.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.get_billing_settings (read-only; US2 UI needs partial-payment flag)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_billing_settings()
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_allow_partial boolean;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF NOT (
    auth_internal.staff_has_invoices_view_access()
    OR EXISTS (
      SELECT 1
      FROM public.roles_permissions rp
      JOIN public.staff_members sm ON sm.role = rp.role
      WHERE sm.auth_user_id = auth.uid()
        AND sm.is_deleted = false
        AND sm.is_active = true
        AND rp.permission_key = 'payments.record'
        AND rp.is_granted = true
        AND rp.is_deleted = false
    )
  ) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view billing settings.');
  END IF;

  SELECT obs.allow_partial_payments
  INTO v_allow_partial
  FROM public.organization_billing_settings obs
  WHERE obs.organization_id = v_org_id;

  IF NOT FOUND THEN
    v_allow_partial := false;
  END IF;

  RETURN public.rpc_success(
    jsonb_build_object('allow_partial_payments', coalesce(v_allow_partial, false))
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- public RPC wrappers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_payment(
  p_invoice_id uuid,
  p_method public.payment_method,
  p_amount numeric,
  p_reference text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.record_payment(p_invoice_id, p_method, p_amount, p_reference, p_note);
$$;

CREATE OR REPLACE FUNCTION public.record_refund(
  p_invoice_id uuid,
  p_method public.payment_method,
  p_amount numeric,
  p_note text
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.record_refund(p_invoice_id, p_method, p_amount, p_note);
$$;

CREATE OR REPLACE FUNCTION public.get_billing_settings()
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_billing_settings();
$$;

GRANT EXECUTE ON FUNCTION public.record_payment(uuid, public.payment_method, numeric, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_refund(uuid, public.payment_method, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_billing_settings() TO authenticated;
