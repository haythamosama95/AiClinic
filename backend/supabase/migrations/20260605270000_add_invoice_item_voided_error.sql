-- Return INVOICE_VOIDED (not INVOICE_NOT_IN_DRAFT) when adding items to voided invoices.

CREATE OR REPLACE FUNCTION auth_internal.add_invoice_item(
  p_invoice_id uuid,
  p_expected_updated_at timestamptz,
  p_description text,
  p_quantity numeric,
  p_unit_price numeric
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
  v_org_id uuid;
  v_item_id uuid;
  v_description text := trim(p_description);
  v_line_subtotal numeric(14, 2);
BEGIN
  PERFORM auth_internal.assert_permission('invoices.create');
  v_org_id := public.jwt_organization_id();

  BEGIN
    v_invoice := auth_internal.lock_draft_invoice(p_invoice_id, p_expected_updated_at);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Invoice was not found.');
      ELSIF SQLERRM = 'invoice_voided' THEN
        RETURN public.rpc_error('INVOICE_VOIDED', 'Line items cannot be changed on voided invoices.');
      ELSIF SQLERRM = 'invoice_not_in_draft' THEN
        RETURN public.rpc_error('INVOICE_NOT_IN_DRAFT', 'Line items can only be changed on draft invoices.');
      ELSIF SQLERRM = 'STALE_INVOICE' THEN
        RETURN public.rpc_error('STALE_INVOICE', 'This invoice was updated elsewhere. Reload and try again.');
      ELSIF SQLERRM = 'INVALID_INPUT' THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
      END IF;
      RAISE;
  END;

  IF v_description IS NULL OR v_description = '' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Description is required.');
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Quantity must be greater than zero.');
  END IF;

  IF p_unit_price IS NULL OR p_unit_price < 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Unit price cannot be negative.');
  END IF;

  v_line_subtotal := round(p_quantity * p_unit_price, 2);

  INSERT INTO public.invoice_items (
    invoice_id,
    description,
    quantity,
    unit_price,
    line_subtotal,
    line_discount_amount,
    line_total,
    created_by,
    updated_by
  )
  VALUES (
    p_invoice_id,
    v_description,
    p_quantity,
    p_unit_price,
    v_line_subtotal,
    0.00,
    v_line_subtotal,
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_item_id;

  PERFORM auth_internal.refresh_invoice_subtotal(p_invoice_id);

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'invoice.item.add',
    'invoice_items',
    v_item_id,
    jsonb_build_object(
      'invoice_id', p_invoice_id,
      'item_id', v_item_id,
      'description', v_description,
      'quantity', p_quantity,
      'unit_price', p_unit_price
    )
  );

  RETURN public.rpc_success(jsonb_build_object('item_id', v_item_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to edit invoice items.');
    END IF;
    RAISE;
END;
$$;
