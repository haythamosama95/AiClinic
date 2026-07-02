-- =============================================================================
-- Service Catalog (015): invoice_items extension + add_invoice_item_from_service
-- =============================================================================

ALTER TABLE public.invoice_items
  ADD COLUMN IF NOT EXISTS service_id uuid REFERENCES public.services (id);

CREATE INDEX IF NOT EXISTS invoice_items_service_idx
  ON public.invoice_items (service_id)
  WHERE is_deleted = false;

-- -----------------------------------------------------------------------------
-- auth_internal.add_invoice_item_from_service
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.add_invoice_item_from_service(
  p_invoice_id uuid,
  p_expected_updated_at timestamptz,
  p_service_id uuid
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
  v_org_id uuid;
  v_service public.services%ROWTYPE;
  v_resolution jsonb;
  v_on_date date := current_date;
  v_unit_price numeric(14, 2);
  v_applied_rule text;
  v_item_id uuid;
  v_existing_item public.invoice_items%ROWTYPE;
  v_new_quantity numeric(14, 2);
  v_reason text;
BEGIN
  PERFORM auth_internal.assert_permission('invoices.create');
  v_org_id := public.jwt_organization_id();

  IF p_service_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service ID is required.');
  END IF;

  BEGIN
    v_invoice := auth_internal.lock_draft_invoice(p_invoice_id, p_expected_updated_at);
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

  SELECT *
  INTO v_service
  FROM public.services s
  WHERE s.id = p_service_id
    AND s.organization_id = v_org_id
    AND s.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'The requested service was not found.');
  END IF;

  v_resolution := auth_internal.resolve_effective_service_price(p_service_id, v_invoice.branch_id, v_on_date);

  IF NOT coalesce((v_resolution ->> 'eligible')::boolean, false) THEN
    v_reason := coalesce(v_resolution ->> 'reason', 'UNKNOWN');
    RETURN public.rpc_error(
      'SERVICE_NOT_ELIGIBLE',
      CASE v_reason
        WHEN 'GLOBAL_INACTIVE' THEN 'This service is globally inactive and cannot be added to invoices.'
        WHEN 'NOT_ASSIGNED' THEN 'This service is not assigned to the invoice branch.'
        WHEN 'BRANCH_INACTIVE' THEN 'This service is inactive at the invoice branch.'
        ELSE 'This service is not eligible at the invoice branch.'
      END
    );
  END IF;

  v_unit_price := (v_resolution ->> 'unit_price')::numeric(14, 2);
  v_applied_rule := v_resolution ->> 'applied_rule';

  SELECT ii.*
  INTO v_existing_item
  FROM public.invoice_items ii
  WHERE ii.invoice_id = p_invoice_id
    AND ii.service_id = p_service_id
    AND ii.is_deleted = false
  FOR UPDATE;

  IF FOUND THEN
    v_new_quantity := v_existing_item.quantity + 1;
    v_item_id := v_existing_item.id;

    UPDATE public.invoice_items ii
    SET
      quantity = v_new_quantity,
      line_subtotal = round(v_new_quantity * ii.unit_price, 2),
      line_total = round(v_new_quantity * ii.unit_price, 2) - ii.line_discount_amount,
      updated_at = now(),
      updated_by = auth.uid()
    WHERE ii.id = v_item_id;

    PERFORM auth_internal.recompute_item_line_totals(v_item_id);
  ELSE
    INSERT INTO public.invoice_items (
      invoice_id,
      service_id,
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
      p_service_id,
      v_service.name,
      1,
      v_unit_price,
      round(v_unit_price, 2),
      0.00,
      round(v_unit_price, 2),
      auth.uid(),
      auth.uid()
    )
    RETURNING id INTO v_item_id;

    v_new_quantity := 1;
  END IF;

  PERFORM auth_internal.refresh_invoice_subtotal(p_invoice_id);

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'invoice.item.add_from_service',
    'invoice_items',
    v_item_id,
    jsonb_build_object(
      'invoice_id', p_invoice_id,
      'item_id', v_item_id,
      'service_id', p_service_id,
      'unit_price', v_unit_price,
      'applied_rule', v_applied_rule,
      'on_date', v_on_date,
      'quantity', v_new_quantity
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'item_id', v_item_id,
      'quantity', to_char(v_new_quantity, 'FM9999999990.00'),
      'unit_price', to_char(round(v_unit_price, 2), 'FM9999999990.00'),
      'applied_rule', v_applied_rule
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to edit invoice items.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_invoice_item_from_service(
  p_invoice_id uuid,
  p_expected_updated_at timestamptz,
  p_service_id uuid
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.add_invoice_item_from_service(
    p_invoice_id,
    p_expected_updated_at,
    p_service_id
  );
$$;

GRANT EXECUTE ON FUNCTION public.add_invoice_item_from_service(uuid, timestamptz, uuid) TO authenticated;
