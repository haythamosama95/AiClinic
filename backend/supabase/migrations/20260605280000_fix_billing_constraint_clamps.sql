-- =============================================================================
-- V1-6: Fix billing CHECK constraint violations on item/discount mutations
-- Issues #1–#3 from BILLING_FEATURE_REVIEW.md
-- =============================================================================

-- -----------------------------------------------------------------------------
-- refresh_invoice_subtotal: recompute discount + clamp insurance after subtotal change
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.refresh_invoice_subtotal(p_invoice_id uuid)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
  v_subtotal numeric(14, 2);
  v_discount_amount numeric(14, 2);
  v_insurance_covered numeric(14, 2);
  v_updated_at timestamptz;
BEGIN
  v_subtotal := auth_internal.compute_invoice_subtotal(p_invoice_id);

  SELECT *
  INTO v_invoice
  FROM public.invoices i
  WHERE i.id = p_invoice_id
    AND i.is_deleted = false;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_invoice.discount_kind IS NULL OR v_invoice.discount_value IS NULL THEN
    v_discount_amount := 0.00;
  ELSIF v_invoice.discount_kind = 'percentage' THEN
    v_discount_amount := round(v_subtotal * v_invoice.discount_value / 100.0, 2);
  ELSE
    v_discount_amount := least(v_invoice.discount_value, v_subtotal);
  END IF;

  v_insurance_covered := least(
    v_invoice.insurance_covered_amount,
    greatest(v_subtotal - v_discount_amount, 0.00)
  );

  UPDATE public.invoices i
  SET
    subtotal = v_subtotal,
    discount_amount = v_discount_amount,
    insurance_covered_amount = v_insurance_covered,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE i.id = p_invoice_id
  RETURNING i.updated_at INTO v_updated_at;

  RETURN v_updated_at;
END;
$$;

-- -----------------------------------------------------------------------------
-- update_invoice_item: zero line discount before recompute to avoid transient bounds violation
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.update_invoice_item(
  p_item_id uuid,
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
  v_item public.invoice_items%ROWTYPE;
  v_invoice public.invoices%ROWTYPE;
  v_org_id uuid;
  v_description text := trim(p_description);
  v_line_subtotal numeric(14, 2);
BEGIN
  PERFORM auth_internal.assert_permission('invoices.create');
  v_org_id := public.jwt_organization_id();

  SELECT ii.*
  INTO v_item
  FROM public.invoice_items ii
  WHERE ii.id = p_item_id
    AND ii.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Invoice item was not found.');
  END IF;

  BEGIN
    v_invoice := auth_internal.lock_draft_invoice(v_item.invoice_id, p_expected_updated_at);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Invoice was not found.');
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

  UPDATE public.invoice_items ii
  SET
    description = v_description,
    quantity = p_quantity,
    unit_price = p_unit_price,
    line_subtotal = v_line_subtotal,
    line_discount_amount = 0,
    line_total = v_line_subtotal,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE ii.id = p_item_id;

  PERFORM auth_internal.recompute_item_line_totals(p_item_id);
  PERFORM auth_internal.refresh_invoice_subtotal(v_item.invoice_id);

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'invoice.item.update',
    'invoice_items',
    p_item_id,
    jsonb_build_object(
      'invoice_id', v_item.invoice_id,
      'item_id', p_item_id,
      'description', v_description,
      'quantity', p_quantity,
      'unit_price', p_unit_price
    )
  );

  RETURN public.rpc_success(jsonb_build_object('item_id', p_item_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to edit invoice items.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- apply_invoice_discount: clamp insurance after discount change
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.apply_invoice_discount(
  p_invoice_id uuid,
  p_expected_updated_at timestamptz,
  p_kind public.discount_kind,
  p_value numeric
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
  v_org_id uuid;
  v_subtotal numeric(14, 2);
  v_line_discount_sum numeric(14, 2);
  v_prior_kind public.discount_kind;
  v_prior_value numeric(14, 2);
  v_prior_amount numeric(14, 2);
  v_new_amount numeric(14, 2);
  v_net_after_discount numeric(14, 2);
BEGIN
  PERFORM auth_internal.assert_permission('invoices.apply_discount');
  v_org_id := public.jwt_organization_id();

  BEGIN
    v_invoice := auth_internal.lock_draft_invoice(p_invoice_id, p_expected_updated_at);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Invoice was not found.');
      ELSIF SQLERRM = 'invoice_not_in_draft' THEN
        RETURN public.rpc_error('INVOICE_NOT_IN_DRAFT', 'Discounts can only be changed on draft invoices.');
      ELSIF SQLERRM = 'STALE_INVOICE' THEN
        RETURN public.rpc_error('STALE_INVOICE', 'This invoice was updated elsewhere. Reload and try again.');
      ELSIF SQLERRM = 'INVALID_INPUT' THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
      END IF;
      RAISE;
  END;

  SELECT COALESCE(SUM(ii.line_discount_amount), 0)
  INTO v_line_discount_sum
  FROM public.invoice_items ii
  WHERE ii.invoice_id = p_invoice_id
    AND ii.is_deleted = false;

  IF v_line_discount_sum > 0 THEN
    RETURN public.rpc_error(
      'DISCOUNT_SCOPE_CONFLICT',
      'Discount scopes are mutually exclusive — clear all line-level discounts first.'
    );
  END IF;

  v_subtotal := auth_internal.compute_invoice_subtotal(p_invoice_id);
  v_prior_kind := v_invoice.discount_kind;
  v_prior_value := v_invoice.discount_value;
  v_prior_amount := v_invoice.discount_amount;

  IF p_kind IS NULL AND p_value IS NULL THEN
    UPDATE public.invoices i
    SET
      discount_kind = NULL,
      discount_value = NULL,
      discount_amount = 0.00,
      updated_at = now(),
      updated_by = auth.uid()
    WHERE i.id = p_invoice_id;
    v_new_amount := 0.00;
  ELSE
    IF p_kind IS NULL OR p_value IS NULL THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Discount kind and value are required.');
    END IF;

    IF p_kind = 'percentage' THEN
      IF p_value < 0 OR p_value > 100 THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Percentage discount must be between 0 and 100.');
      END IF;
      v_new_amount := round(v_subtotal * p_value / 100.0, 2);
    ELSIF p_kind = 'fixed' THEN
      IF p_value < 0 OR p_value > v_subtotal THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Fixed discount cannot exceed the invoice subtotal.');
      END IF;
      v_new_amount := p_value;
    ELSE
      RETURN public.rpc_error('INVALID_INPUT', 'Unsupported discount kind.');
    END IF;

    v_net_after_discount := greatest(v_subtotal - v_new_amount, 0.00);

    UPDATE public.invoices i
    SET
      discount_kind = p_kind,
      discount_value = p_value,
      discount_amount = v_new_amount,
      insurance_covered_amount = least(i.insurance_covered_amount, v_net_after_discount),
      updated_at = now(),
      updated_by = auth.uid()
    WHERE i.id = p_invoice_id;
  END IF;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'invoice.discount.apply',
    'invoices',
    p_invoice_id,
    jsonb_build_object(
      'scope', 'invoice',
      'invoice_id', p_invoice_id,
      'discount_kind', v_prior_kind,
      'discount_value', v_prior_value,
      'discount_amount', v_prior_amount
    ),
    jsonb_build_object(
      'scope', 'invoice',
      'invoice_id', p_invoice_id,
      'discount_kind', p_kind,
      'discount_value', p_value,
      'discount_amount', v_new_amount
    )
  );

  RETURN public.rpc_success(jsonb_build_object('invoice_id', p_invoice_id, 'discount_amount', v_new_amount));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to apply discounts.');
    ELSIF SQLERRM = 'discount_scope_conflict' THEN
      RETURN public.rpc_error(
        'DISCOUNT_SCOPE_CONFLICT',
        'Discount scopes are mutually exclusive — clear all line-level discounts first.'
      );
    END IF;
    RAISE;
END;
$$;
