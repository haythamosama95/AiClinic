-- Billing review items #13–#17 (medium):
-- #14 record_payment audit includes reference and note
-- #16 get_invoice_detail payments.recorded_by includes staff display_name

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
  v_reference text;
  v_note text;
BEGIN
  v_staff := auth_internal.assert_permission('payments.record');
  v_org_id := public.jwt_organization_id();

  IF p_invoice_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Invoice ID is required.');
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Payment amount must be greater than zero.');
  END IF;

  v_reference := nullif(trim(p_reference), '');
  v_note := nullif(trim(p_note), '');

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
    v_reference,
    v_note,
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
      'reference', v_reference,
      'note', v_note,
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

CREATE OR REPLACE FUNCTION auth_internal.get_invoice_detail(p_invoice_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
  v_org_id uuid;
  v_items jsonb;
  v_payments jsonb;
  v_patient jsonb;
  v_branch jsonb;
  v_provider jsonb;
  v_balance numeric(14, 2);
BEGIN
  PERFORM auth_internal.assert_permission('invoices.view');
  v_org_id := public.jwt_organization_id();

  SELECT *
  INTO v_invoice
  FROM public.invoices i
  WHERE i.id = p_invoice_id
    AND i.is_deleted = false
    AND i.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Invoice was not found.');
  END IF;

  IF v_invoice.status = 'voided' THEN
    v_balance := 0::numeric(14, 2);
  ELSE
    v_balance := auth_internal.compute_invoice_balance(p_invoice_id);
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', ii.id,
        'description', ii.description,
        'quantity', ii.quantity,
        'unit_price', ii.unit_price,
        'line_subtotal', ii.line_subtotal,
        'line_discount_kind', ii.line_discount_kind,
        'line_discount_value', ii.line_discount_value,
        'line_discount_amount', ii.line_discount_amount,
        'line_total', ii.line_total
      )
      ORDER BY ii.created_at
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM public.invoice_items ii
  WHERE ii.invoice_id = p_invoice_id
    AND ii.is_deleted = false;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'method', p.method,
        'amount', p.amount,
        'reference', p.reference,
        'note', p.note,
        'recorded_by', jsonb_build_object(
          'id', p.recorded_by,
          'display_name', sm.full_name
        ),
        'recorded_at', p.recorded_at
      )
      ORDER BY p.recorded_at
    ),
    '[]'::jsonb
  )
  INTO v_payments
  FROM public.payments p
  LEFT JOIN public.staff_members sm ON sm.id = p.recorded_by
  WHERE p.invoice_id = p_invoice_id;

  SELECT jsonb_build_object('id', pt.id, 'display_name', pt.full_name)
  INTO v_patient
  FROM public.patients pt
  WHERE pt.id = v_invoice.patient_id;

  SELECT jsonb_build_object('id', b.id, 'code', b.code, 'name', b.name)
  INTO v_branch
  FROM public.branches b
  WHERE b.id = v_invoice.branch_id;

  IF v_invoice.insurance_provider_id IS NOT NULL THEN
    SELECT jsonb_build_object('id', ip.id, 'name', ip.name)
    INTO v_provider
    FROM public.insurance_providers ip
    WHERE ip.id = v_invoice.insurance_provider_id;
  END IF;

  RETURN public.rpc_success(
    jsonb_build_object(
      'invoice', jsonb_build_object(
        'id', v_invoice.id,
        'invoice_number', v_invoice.invoice_number,
        'status', v_invoice.status::text,
        'branch_id', v_invoice.branch_id,
        'patient_id', v_invoice.patient_id,
        'visit_id', v_invoice.visit_id,
        'subtotal', v_invoice.subtotal,
        'discount_kind', v_invoice.discount_kind,
        'discount_value', v_invoice.discount_value,
        'discount_amount', v_invoice.discount_amount,
        'insurance_provider_id', v_invoice.insurance_provider_id,
        'insurance_covered_amount', v_invoice.insurance_covered_amount,
        'currency', v_invoice.currency,
        'issued_at', v_invoice.issued_at,
        'voided_at', v_invoice.voided_at,
        'void_reason', v_invoice.void_reason,
        'balance', v_balance,
        'updated_at', v_invoice.updated_at
      ),
      'items', v_items,
      'payments', v_payments,
      'patient', v_patient,
      'branch', v_branch,
      'insurance_provider', v_provider
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view invoices.');
    END IF;
    RAISE;
END;
$$;
