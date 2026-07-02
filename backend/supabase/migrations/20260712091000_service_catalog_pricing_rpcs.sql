-- =============================================================================
-- Service Catalog (015): pricing, eligibility, and catalog read RPCs (US1+)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- auth_internal.get_service
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_service(p_service_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_service public.services%ROWTYPE;
  v_branches jsonb;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF NOT EXISTS (
    SELECT 1
    FROM public.roles_permissions rp
    JOIN public.staff_members sm ON sm.role = rp.role
    WHERE sm.auth_user_id = auth.uid()
      AND sm.is_deleted = false
      AND sm.is_active = true
      AND rp.permission_key IN ('services.view', 'services.manage')
      AND rp.is_granted = true
      AND rp.is_deleted = false
  ) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view the service catalog.');
  END IF;

  IF p_service_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service ID is required.');
  END IF;

  SELECT *
  INTO v_service
  FROM public.services s
  WHERE s.id = p_service_id
    AND s.organization_id = v_org_id
    AND s.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'The requested service was not found.');
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'service_branch_id', sb.id,
        'branch_id', sb.branch_id,
        'status', sb.status::text,
        'price_override', sb.price_override,
        'promotion_price', sb.promotion_price,
        'promotion_start_date', sb.promotion_start_date,
        'promotion_end_date', sb.promotion_end_date,
        'updated_at', sb.updated_at
      )
      ORDER BY sb.branch_id
    ),
    '[]'::jsonb
  )
  INTO v_branches
  FROM public.service_branches sb
  WHERE sb.service_id = p_service_id
    AND sb.is_deleted = false
    AND sb.branch_id = ANY (public.jwt_branch_ids());

  RETURN public.rpc_success(
    jsonb_build_object(
      'service', jsonb_build_object(
        'id', v_service.id,
        'name', v_service.name,
        'default_price', v_service.default_price,
        'global_status', v_service.global_status::text,
        'created_at', v_service.created_at,
        'updated_at', v_service.updated_at
      ),
      'branches', v_branches
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_service(p_service_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_service(p_service_id);
$$;

GRANT EXECUTE ON FUNCTION public.get_service(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- auth_internal.resolve_effective_service_price (internal helper)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.resolve_effective_service_price(
  p_service_id uuid,
  p_branch_id uuid,
  p_on_date date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_service public.services%ROWTYPE;
  v_branch public.service_branches%ROWTYPE;
  v_unit_price numeric(14, 2);
  v_applied_rule text;
BEGIN
  SELECT *
  INTO v_service
  FROM public.services s
  WHERE s.id = p_service_id
    AND s.is_deleted = false;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'eligible', false,
      'unit_price', NULL,
      'applied_rule', NULL,
      'reason', 'NOT_FOUND'
    );
  END IF;

  IF v_service.global_status <> 'active' THEN
    RETURN jsonb_build_object(
      'eligible', false,
      'unit_price', NULL,
      'applied_rule', NULL,
      'reason', 'GLOBAL_INACTIVE'
    );
  END IF;

  SELECT *
  INTO v_branch
  FROM public.service_branches sb
  WHERE sb.service_id = p_service_id
    AND sb.branch_id = p_branch_id
    AND sb.is_deleted = false;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'eligible', false,
      'unit_price', NULL,
      'applied_rule', NULL,
      'reason', 'NOT_ASSIGNED'
    );
  END IF;

  IF v_branch.status <> 'active' THEN
    RETURN jsonb_build_object(
      'eligible', false,
      'unit_price', NULL,
      'applied_rule', NULL,
      'reason', 'BRANCH_INACTIVE'
    );
  END IF;

  IF v_branch.promotion_price IS NOT NULL
    AND v_branch.promotion_start_date IS NOT NULL
    AND v_branch.promotion_end_date IS NOT NULL
    AND p_on_date BETWEEN v_branch.promotion_start_date AND v_branch.promotion_end_date
  THEN
    v_unit_price := v_branch.promotion_price;
    v_applied_rule := 'promo';
  ELSIF v_branch.price_override IS NOT NULL THEN
    v_unit_price := v_branch.price_override;
    v_applied_rule := 'override';
  ELSE
    v_unit_price := v_service.default_price;
    v_applied_rule := 'default';
  END IF;

  RETURN jsonb_build_object(
    'eligible', true,
    'unit_price', to_char(round(v_unit_price, 2), 'FM9999999990.00'),
    'applied_rule', v_applied_rule,
    'reason', NULL
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.resolve_effective_service_price (public read)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.resolve_effective_service_price_rpc(
  p_service_id uuid,
  p_branch_id uuid,
  p_on_date date DEFAULT current_date
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_resolution jsonb;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF NOT EXISTS (
    SELECT 1
    FROM public.roles_permissions rp
    JOIN public.staff_members sm ON sm.role = rp.role
    WHERE sm.auth_user_id = auth.uid()
      AND sm.is_deleted = false
      AND sm.is_active = true
      AND rp.permission_key IN ('services.view', 'services.manage', 'invoices.create')
      AND rp.is_granted = true
      AND rp.is_deleted = false
  ) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view service pricing.');
  END IF;

  IF p_service_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service ID is required.');
  END IF;

  IF p_branch_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch ID is required.');
  END IF;

  IF NOT (p_branch_id = ANY (public.jwt_branch_ids())) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have access to this branch.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.branches b
    WHERE b.id = p_branch_id
      AND b.organization_id = v_org_id
      AND b.is_deleted = false
  ) THEN
    RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'The branch is not in your organization.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.services s
    WHERE s.id = p_service_id
      AND s.organization_id = v_org_id
      AND s.is_deleted = false
  ) THEN
    RETURN public.rpc_error('NOT_FOUND', 'The requested service was not found.');
  END IF;

  v_resolution := auth_internal.resolve_effective_service_price(p_service_id, p_branch_id, p_on_date);

  RETURN public.rpc_success(v_resolution);
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_effective_service_price(
  p_service_id uuid,
  p_branch_id uuid,
  p_on_date date DEFAULT current_date
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.resolve_effective_service_price_rpc(p_service_id, p_branch_id, p_on_date);
$$;

GRANT EXECUTE ON FUNCTION public.resolve_effective_service_price(uuid, uuid, date) TO authenticated;

-- -----------------------------------------------------------------------------
-- auth_internal.search_eligible_services (invoice selector)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.search_eligible_services(
  p_branch_id uuid,
  p_query text DEFAULT '',
  p_on_date date DEFAULT current_date,
  p_limit int DEFAULT 20
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_limit int;
  v_query text := coalesce(p_query, '');
  v_items jsonb;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF NOT EXISTS (
    SELECT 1
    FROM public.roles_permissions rp
    JOIN public.staff_members sm ON sm.role = rp.role
    WHERE sm.auth_user_id = auth.uid()
      AND sm.is_deleted = false
      AND sm.is_active = true
      AND rp.permission_key IN ('services.view', 'services.manage', 'invoices.create')
      AND rp.is_granted = true
      AND rp.is_deleted = false
  ) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to search services.');
  END IF;

  IF p_branch_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch ID is required.');
  END IF;

  IF NOT (p_branch_id = ANY (public.jwt_branch_ids())) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have access to this branch.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.branches b
    WHERE b.id = p_branch_id
      AND b.organization_id = v_org_id
      AND b.is_deleted = false
  ) THEN
    RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'The branch is not in your organization.');
  END IF;

  v_limit := greatest(1, least(coalesce(p_limit, 20), 50));

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'service_id', ranked.service_id,
        'name', ranked.name,
        'unit_price', ranked.unit_price,
        'applied_rule', ranked.applied_rule,
        'on_promotion', ranked.on_promotion
      )
      ORDER BY ranked.name
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM (
    SELECT
      s.id AS service_id,
      s.name,
      res.resolution ->> 'unit_price' AS unit_price,
      res.resolution ->> 'applied_rule' AS applied_rule,
      (res.resolution ->> 'applied_rule') = 'promo' AS on_promotion
    FROM public.services s
    JOIN public.service_branches sb
      ON sb.service_id = s.id
      AND sb.branch_id = p_branch_id
      AND sb.is_deleted = false
    CROSS JOIN LATERAL (
      SELECT auth_internal.resolve_effective_service_price(s.id, p_branch_id, p_on_date) AS resolution
    ) res
    WHERE s.organization_id = v_org_id
      AND s.is_deleted = false
      AND (res.resolution ->> 'eligible')::boolean = true
      AND s.name ILIKE '%' || v_query || '%'
    ORDER BY s.name
    LIMIT v_limit
  ) AS ranked;

  RETURN public.rpc_success(jsonb_build_object('items', v_items));
END;
$$;

CREATE OR REPLACE FUNCTION public.search_eligible_services(
  p_branch_id uuid,
  p_query text DEFAULT '',
  p_on_date date DEFAULT current_date,
  p_limit int DEFAULT 20
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.search_eligible_services(p_branch_id, p_query, p_on_date, p_limit);
$$;

GRANT EXECUTE ON FUNCTION public.search_eligible_services(uuid, text, date, int) TO authenticated;
