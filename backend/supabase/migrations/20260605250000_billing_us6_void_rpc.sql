-- =============================================================================
-- V1-6: Billing US6 — void invoice RPC
-- =============================================================================

CREATE OR REPLACE FUNCTION auth_internal.void_invoice(
  p_invoice_id uuid,
  p_reason text
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
  v_prior_status public.invoice_status;
BEGIN
  v_staff := auth_internal.assert_permission('invoices.void');
  v_org_id := public.jwt_organization_id();

  IF p_invoice_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Invoice ID is required.');
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'A void reason is required.');
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
    RETURN public.rpc_error('INVOICE_VOIDED', 'This invoice is already voided.');
  END IF;

  IF v_invoice.status NOT IN ('issued', 'partially_paid') THEN
    RETURN public.rpc_error(
      'INVOICE_NOT_VOIDABLE',
      'Only issued or partially paid invoices can be voided. Refund paid invoices first.'
    );
  END IF;

  v_prior_status := v_invoice.status;

  UPDATE public.invoices i
  SET
    status = 'voided',
    void_reason = trim(p_reason),
    voided_at = now(),
    voided_by = v_staff.id,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE i.id = p_invoice_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'invoice.void',
    'invoices',
    p_invoice_id,
    jsonb_build_object(
      'invoice_id', p_invoice_id,
      'prior_status', v_prior_status::text,
      'new_status', 'voided',
      'reason', trim(p_reason)
    )
  );

  RETURN public.rpc_success(jsonb_build_object('invoice_id', p_invoice_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to void invoices.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.void_invoice(p_invoice_id uuid, p_reason text)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.void_invoice(p_invoice_id, p_reason);
$$;

GRANT EXECUTE ON FUNCTION public.void_invoice(uuid, text) TO authenticated;

-- Voided invoices report zero balance (US6 / FR-032).
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
        'recorded_by', p.recorded_by,
        'recorded_at', p.recorded_at
      )
      ORDER BY p.recorded_at
    ),
    '[]'::jsonb
  )
  INTO v_payments
  FROM public.payments p
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
