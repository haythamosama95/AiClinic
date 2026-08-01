-- record_refund still inserted payments.reference after 20260727140000 removed the column.

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
  v_net numeric(14, 2);
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
  INTO v_net
  FROM public.payments p
  WHERE p.invoice_id = p_invoice_id;

  IF p_amount > v_net THEN
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
    note,
    recorded_by
  )
  VALUES (
    p_invoice_id,
    v_invoice.branch_id,
    p_method,
    -p_amount,
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
