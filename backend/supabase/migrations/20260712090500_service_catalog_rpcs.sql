-- =============================================================================
-- Service Catalog (015): service management + branch configuration RPCs (US1+)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- auth_internal.create_service
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_service(
  p_name text,
  p_default_price numeric,
  p_global_status text DEFAULT 'active',
  p_assign_all_branches boolean DEFAULT true,
  p_branch_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_name text;
  v_status public.service_global_status;
  v_service_id uuid;
  v_branch_ids uuid[];
  v_branch_id uuid;
  v_existing_id uuid;
  v_assigned_ids uuid[] := '{}'::uuid[];
BEGIN
  PERFORM auth_internal.assert_permission('services.manage');
  v_org_id := public.jwt_organization_id();
  v_name := NULLIF(btrim(p_name), '');

  IF v_name IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service name is required.');
  END IF;

  IF char_length(v_name) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service name cannot exceed 200 characters.');
  END IF;

  IF p_default_price IS NULL OR p_default_price < 0 THEN
    RETURN public.rpc_error('INVALID_PRICE', 'Default price must be a non-negative amount.');
  END IF;

  IF p_default_price <> round(p_default_price, 2) THEN
    RETURN public.rpc_error('INVALID_PRICE', 'Default price must have at most two decimal places.');
  END IF;

  BEGIN
    v_status := p_global_status::public.service_global_status;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Global status must be active or inactive.');
  END;

  IF EXISTS (
    SELECT 1
    FROM public.services s
    WHERE s.organization_id = v_org_id
      AND s.is_deleted = false
      AND lower(btrim(s.name)) = lower(v_name)
  ) THEN
    RETURN public.rpc_error('DUPLICATE_NAME', 'A service with this name already exists in your organization.');
  END IF;

  IF p_assign_all_branches THEN
    SELECT COALESCE(array_agg(b.id ORDER BY b.name), '{}'::uuid[])
    INTO v_branch_ids
    FROM public.branches b
    WHERE b.organization_id = v_org_id
      AND b.is_deleted = false;
  ELSE
    IF p_branch_ids IS NULL OR cardinality(p_branch_ids) = 0 THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Select at least one branch or assign to all branches.');
    END IF;

    IF EXISTS (
      SELECT 1
      FROM unnest(p_branch_ids) AS requested (branch_id)
      LEFT JOIN public.branches b
        ON b.id = requested.branch_id
        AND b.is_deleted = false
        AND b.organization_id = v_org_id
      WHERE b.id IS NULL
    ) THEN
      RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'One or more selected branches are not in your organization.');
    END IF;

    v_branch_ids := p_branch_ids;
  END IF;

  INSERT INTO public.services (
    organization_id,
    name,
    default_price,
    global_status,
    created_by,
    updated_by
  )
  VALUES (
    v_org_id,
    v_name,
    round(p_default_price, 2),
    v_status,
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_service_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'service.create',
    'services',
    v_service_id,
    jsonb_build_object(
      'service_id', v_service_id,
      'name', v_name,
      'default_price', round(p_default_price, 2),
      'global_status', v_status::text
    )
  );

  FOREACH v_branch_id IN ARRAY v_branch_ids LOOP
  BEGIN
    SELECT sb.id
    INTO v_existing_id
    FROM public.service_branches sb
    WHERE sb.service_id = v_service_id
      AND sb.branch_id = v_branch_id
      AND sb.is_deleted = false;

    IF FOUND THEN
      v_assigned_ids := array_append(v_assigned_ids, v_branch_id);
      CONTINUE;
    END IF;

    UPDATE public.service_branches sb
    SET
      is_deleted = false,
      deleted_at = NULL,
      deleted_by = NULL,
      status = 'active',
      price_override = NULL,
      promotion_price = NULL,
      promotion_start_date = NULL,
      promotion_end_date = NULL,
      updated_at = now(),
      updated_by = auth.uid()
    WHERE sb.service_id = v_service_id
      AND sb.branch_id = v_branch_id
      AND sb.is_deleted = true
    RETURNING sb.id INTO v_existing_id;

    IF NOT FOUND THEN
      INSERT INTO public.service_branches (
        service_id,
        branch_id,
        status,
        created_by,
        updated_by
      )
      VALUES (
        v_service_id,
        v_branch_id,
        'active',
        auth.uid(),
        auth.uid()
      );
    END IF;

    v_assigned_ids := array_append(v_assigned_ids, v_branch_id);
  END;
  END LOOP;

  IF cardinality(v_assigned_ids) > 0 THEN
    INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
    VALUES (
      auth.uid(),
      v_org_id,
      'service.branch.assign',
      'service_branches',
      v_service_id,
      jsonb_build_object('service_id', v_service_id, 'assigned_branch_ids', v_assigned_ids)
    );
  END IF;

  RETURN public.rpc_success(
    jsonb_build_object(
      'service_id', v_service_id,
      'assigned_branch_ids', v_assigned_ids
    )
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN public.rpc_error('DUPLICATE_NAME', 'A service with this name already exists in your organization.');
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage the service catalog.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.set_service_branch_assignment
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.set_service_branch_assignment(
  p_service_id uuid,
  p_branch_ids uuid[],
  p_assign boolean
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_service public.services%ROWTYPE;
  v_branch_id uuid;
  v_existing_id uuid;
  v_assigned_ids uuid[] := '{}'::uuid[];
  v_unassigned_ids uuid[] := '{}'::uuid[];
BEGIN
  PERFORM auth_internal.assert_permission('services.manage');
  v_org_id := public.jwt_organization_id();

  IF p_service_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service ID is required.');
  END IF;

  IF p_branch_ids IS NULL OR cardinality(p_branch_ids) = 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'At least one branch ID is required.');
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

  IF EXISTS (
    SELECT 1
    FROM unnest(p_branch_ids) AS requested (branch_id)
    LEFT JOIN public.branches b
      ON b.id = requested.branch_id
      AND b.is_deleted = false
      AND b.organization_id = v_org_id
    WHERE b.id IS NULL
  ) THEN
    RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'One or more selected branches are not in your organization.');
  END IF;

  IF p_assign THEN
    FOREACH v_branch_id IN ARRAY p_branch_ids LOOP
      SELECT sb.id
      INTO v_existing_id
      FROM public.service_branches sb
      WHERE sb.service_id = p_service_id
        AND sb.branch_id = v_branch_id
        AND sb.is_deleted = false;

      IF FOUND THEN
        v_assigned_ids := array_append(v_assigned_ids, v_branch_id);
        CONTINUE;
      END IF;

      UPDATE public.service_branches sb
      SET
        is_deleted = false,
        deleted_at = NULL,
        deleted_by = NULL,
        status = 'active',
        updated_at = now(),
        updated_by = auth.uid()
      WHERE sb.service_id = p_service_id
        AND sb.branch_id = v_branch_id
        AND sb.is_deleted = true
      RETURNING sb.id INTO v_existing_id;

      IF NOT FOUND THEN
        INSERT INTO public.service_branches (
          service_id,
          branch_id,
          status,
          created_by,
          updated_by
        )
        VALUES (
          p_service_id,
          v_branch_id,
          'active',
          auth.uid(),
          auth.uid()
        );
      END IF;

      v_assigned_ids := array_append(v_assigned_ids, v_branch_id);
    END LOOP;

    IF cardinality(v_assigned_ids) > 0 THEN
      INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
      VALUES (
        auth.uid(),
        v_org_id,
        'service.branch.assign',
        'service_branches',
        p_service_id,
        jsonb_build_object('service_id', p_service_id, 'assigned_branch_ids', v_assigned_ids)
      );
    END IF;

    RETURN public.rpc_success(
      jsonb_build_object(
        'service_id', p_service_id,
        'assigned_branch_ids', v_assigned_ids,
        'unassigned_branch_ids', v_unassigned_ids
      )
    );
  END IF;

  WITH unassigned AS (
    UPDATE public.service_branches sb
    SET
      is_deleted = true,
      deleted_at = now(),
      deleted_by = auth.uid(),
      updated_at = now(),
      updated_by = auth.uid()
    WHERE sb.service_id = p_service_id
      AND sb.branch_id = ANY (p_branch_ids)
      AND sb.is_deleted = false
    RETURNING sb.branch_id
  )
  SELECT COALESCE(array_agg(u.branch_id), '{}'::uuid[])
  INTO v_unassigned_ids
  FROM unassigned u;

  IF cardinality(v_unassigned_ids) > 0 THEN
    INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
    VALUES (
      auth.uid(),
      v_org_id,
      'service.branch.unassign',
      'service_branches',
      p_service_id,
      jsonb_build_object('service_id', p_service_id, 'unassigned_branch_ids', v_unassigned_ids)
    );
  END IF;

  RETURN public.rpc_success(
    jsonb_build_object(
      'service_id', p_service_id,
      'assigned_branch_ids', v_assigned_ids,
      'unassigned_branch_ids', v_unassigned_ids
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage the service catalog.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- public wrappers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_service(
  p_name text,
  p_default_price numeric,
  p_global_status text DEFAULT 'active',
  p_assign_all_branches boolean DEFAULT true,
  p_branch_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.create_service(
    p_name,
    p_default_price,
    p_global_status,
    p_assign_all_branches,
    p_branch_ids
  );
$$;

CREATE OR REPLACE FUNCTION public.set_service_branch_assignment(
  p_service_id uuid,
  p_branch_ids uuid[],
  p_assign boolean
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.set_service_branch_assignment(p_service_id, p_branch_ids, p_assign);
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.configure_service_branch
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.configure_service_branch(
  p_service_id uuid,
  p_branch_id uuid,
  p_expected_updated_at timestamptz,
  p_status text,
  p_price_override numeric
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_service public.services%ROWTYPE;
  v_branch public.service_branches%ROWTYPE;
  v_status public.service_branch_status;
  v_effective_price numeric(14, 2);
  v_new_updated_at timestamptz;
BEGIN
  PERFORM auth_internal.assert_permission('services.manage');
  v_org_id := public.jwt_organization_id();

  IF p_service_id IS NULL OR p_branch_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service ID and branch ID are required.');
  END IF;

  IF p_expected_updated_at IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
  END IF;

  IF NOT (p_branch_id = ANY (public.jwt_branch_ids())) THEN
    RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'The selected branch is not in your organization.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.branches b
    WHERE b.id = p_branch_id
      AND b.organization_id = v_org_id
      AND b.is_deleted = false
  ) THEN
    RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'The selected branch is not in your organization.');
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

  SELECT *
  INTO v_branch
  FROM public.service_branches sb
  WHERE sb.service_id = p_service_id
    AND sb.branch_id = p_branch_id
    AND sb.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('BRANCH_NOT_ASSIGNED', 'Configure branch settings only for branches where the service is assigned.');
  END IF;

  IF v_branch.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RETURN public.rpc_error('STALE_SERVICE_BRANCH', 'Branch configuration was updated elsewhere. Reload and try again.');
  END IF;

  BEGIN
    v_status := p_status::public.service_branch_status;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Branch status must be active or inactive.');
  END;

  IF p_price_override IS NOT NULL THEN
    IF p_price_override < 0 THEN
      RETURN public.rpc_error('INVALID_PRICE', 'Price override must be a non-negative amount.');
    END IF;

    IF p_price_override <> round(p_price_override, 2) THEN
      RETURN public.rpc_error('INVALID_PRICE', 'Price override must have at most two decimal places.');
    END IF;
  END IF;

  v_effective_price := COALESCE(p_price_override, v_service.default_price);

  IF v_branch.promotion_price IS NOT NULL AND v_effective_price < v_branch.promotion_price THEN
    RETURN public.rpc_error(
      'PROMO_EXCEEDS_PRICE',
      'Promotion price cannot exceed the effective price. Lower the promotion or raise the default/override price.'
    );
  END IF;

  UPDATE public.service_branches sb
  SET
    status = v_status,
    price_override = CASE
      WHEN p_price_override IS NULL THEN NULL
      ELSE round(p_price_override, 2)
    END,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE sb.id = v_branch.id
  RETURNING sb.updated_at INTO v_new_updated_at;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'service.branch.configure',
    'service_branches',
    v_branch.id,
    jsonb_build_object(
      'service_id', p_service_id,
      'branch_id', p_branch_id,
      'status', v_branch.status::text,
      'price_override', v_branch.price_override
    ),
    jsonb_build_object(
      'service_id', p_service_id,
      'branch_id', p_branch_id,
      'status', v_status::text,
      'price_override', CASE WHEN p_price_override IS NULL THEN NULL ELSE round(p_price_override, 2) END
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'service_branch_id', v_branch.id,
      'updated_at', v_new_updated_at
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage the service catalog.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.set_service_promotion
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.set_service_promotion(
  p_service_id uuid,
  p_branch_id uuid,
  p_expected_updated_at timestamptz,
  p_promotion_price numeric,
  p_start_date date,
  p_end_date date
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_service public.services%ROWTYPE;
  v_branch public.service_branches%ROWTYPE;
  v_effective_price numeric(14, 2);
  v_has_promotion boolean;
  v_new_updated_at timestamptz;
BEGIN
  PERFORM auth_internal.assert_permission('services.manage');
  v_org_id := public.jwt_organization_id();

  IF p_service_id IS NULL OR p_branch_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service ID and branch ID are required.');
  END IF;

  IF p_expected_updated_at IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
  END IF;

  IF NOT (p_branch_id = ANY (public.jwt_branch_ids())) THEN
    RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'The selected branch is not in your organization.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.branches b
    WHERE b.id = p_branch_id
      AND b.organization_id = v_org_id
      AND b.is_deleted = false
  ) THEN
    RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'The selected branch is not in your organization.');
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

  SELECT *
  INTO v_branch
  FROM public.service_branches sb
  WHERE sb.service_id = p_service_id
    AND sb.branch_id = p_branch_id
    AND sb.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('BRANCH_NOT_ASSIGNED', 'Configure branch settings only for branches where the service is assigned.');
  END IF;

  IF v_branch.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RETURN public.rpc_error('STALE_SERVICE_BRANCH', 'Branch configuration was updated elsewhere. Reload and try again.');
  END IF;

  IF p_promotion_price IS NULL AND p_start_date IS NULL AND p_end_date IS NULL THEN
    UPDATE public.service_branches sb
    SET
      promotion_price = NULL,
      promotion_start_date = NULL,
      promotion_end_date = NULL,
      updated_at = now(),
      updated_by = auth.uid()
    WHERE sb.id = v_branch.id
    RETURNING sb.updated_at INTO v_new_updated_at;

    INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
    VALUES (
      auth.uid(),
      v_org_id,
      'service.promotion.clear',
      'service_branches',
      v_branch.id,
      jsonb_build_object(
        'service_id', p_service_id,
        'branch_id', p_branch_id,
        'promotion_price', v_branch.promotion_price,
        'promotion_start_date', v_branch.promotion_start_date,
        'promotion_end_date', v_branch.promotion_end_date
      ),
      jsonb_build_object(
        'service_id', p_service_id,
        'branch_id', p_branch_id,
        'promotion_price', NULL,
        'promotion_start_date', NULL,
        'promotion_end_date', NULL
      )
    );

    RETURN public.rpc_success(
      jsonb_build_object(
        'service_branch_id', v_branch.id,
        'has_promotion', false,
        'updated_at', v_new_updated_at
      )
    );
  END IF;

  IF p_promotion_price IS NULL OR p_start_date IS NULL OR p_end_date IS NULL THEN
    RETURN public.rpc_error('PROMO_INCOMPLETE', 'Promotion requires a price and both start and end dates.');
  END IF;

  IF p_start_date > p_end_date THEN
    RETURN public.rpc_error('PROMO_DATE_RANGE', 'Promotion start date must be on or before the end date.');
  END IF;

  IF p_promotion_price < 0 THEN
    RETURN public.rpc_error('INVALID_PRICE', 'Promotion price must be a non-negative amount.');
  END IF;

  IF p_promotion_price <> round(p_promotion_price, 2) THEN
    RETURN public.rpc_error('INVALID_PRICE', 'Promotion price must have at most two decimal places.');
  END IF;

  v_effective_price := COALESCE(v_branch.price_override, v_service.default_price);

  IF p_promotion_price > v_effective_price THEN
    RETURN public.rpc_error(
      'PROMO_EXCEEDS_PRICE',
      'Promotion price cannot exceed the effective price. Lower the promotion or raise the default/override price.'
    );
  END IF;

  UPDATE public.service_branches sb
  SET
    promotion_price = round(p_promotion_price, 2),
    promotion_start_date = p_start_date,
    promotion_end_date = p_end_date,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE sb.id = v_branch.id
  RETURNING sb.updated_at INTO v_new_updated_at;

  v_has_promotion := true;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'service.promotion.set',
    'service_branches',
    v_branch.id,
    jsonb_build_object(
      'service_id', p_service_id,
      'branch_id', p_branch_id,
      'promotion_price', v_branch.promotion_price,
      'promotion_start_date', v_branch.promotion_start_date,
      'promotion_end_date', v_branch.promotion_end_date
    ),
    jsonb_build_object(
      'service_id', p_service_id,
      'branch_id', p_branch_id,
      'promotion_price', round(p_promotion_price, 2),
      'promotion_start_date', p_start_date,
      'promotion_end_date', p_end_date
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'service_branch_id', v_branch.id,
      'has_promotion', v_has_promotion,
      'updated_at', v_new_updated_at
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage the service catalog.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.configure_service_branch(
  p_service_id uuid,
  p_branch_id uuid,
  p_expected_updated_at timestamptz,
  p_status text,
  p_price_override numeric
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.configure_service_branch(
    p_service_id,
    p_branch_id,
    p_expected_updated_at,
    p_status,
    p_price_override
  );
$$;

CREATE OR REPLACE FUNCTION public.set_service_promotion(
  p_service_id uuid,
  p_branch_id uuid,
  p_expected_updated_at timestamptz,
  p_promotion_price numeric,
  p_start_date date,
  p_end_date date
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.set_service_promotion(
    p_service_id,
    p_branch_id,
    p_expected_updated_at,
    p_promotion_price,
    p_start_date,
    p_end_date
  );
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.update_service
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.update_service(
  p_service_id uuid,
  p_expected_updated_at timestamptz,
  p_name text,
  p_default_price numeric,
  p_global_status text
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_service public.services%ROWTYPE;
  v_name text;
  v_status public.service_global_status;
  v_new_price numeric(14, 2);
  v_new_updated_at timestamptz;
BEGIN
  PERFORM auth_internal.assert_permission('services.manage');
  v_org_id := public.jwt_organization_id();

  IF p_service_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service ID is required.');
  END IF;

  IF p_expected_updated_at IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
  END IF;

  SELECT *
  INTO v_service
  FROM public.services s
  WHERE s.id = p_service_id
    AND s.organization_id = v_org_id
    AND s.is_deleted = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'The requested service was not found.');
  END IF;

  IF v_service.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RETURN public.rpc_error('STALE_SERVICE', 'This service was updated elsewhere. Reload and try again.');
  END IF;

  v_name := NULLIF(btrim(p_name), '');
  IF v_name IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service name is required.');
  END IF;

  IF char_length(v_name) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service name cannot exceed 200 characters.');
  END IF;

  IF p_default_price IS NULL OR p_default_price < 0 THEN
    RETURN public.rpc_error('INVALID_PRICE', 'Default price must be a non-negative amount.');
  END IF;

  IF p_default_price <> round(p_default_price, 2) THEN
    RETURN public.rpc_error('INVALID_PRICE', 'Default price must have at most two decimal places.');
  END IF;

  BEGIN
    v_status := p_global_status::public.service_global_status;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Global status must be active or inactive.');
  END;

  IF lower(btrim(v_name)) <> lower(btrim(v_service.name))
    AND EXISTS (
      SELECT 1
      FROM public.services s
      WHERE s.organization_id = v_org_id
        AND s.is_deleted = false
        AND s.id <> p_service_id
        AND lower(btrim(s.name)) = lower(v_name)
    )
  THEN
    RETURN public.rpc_error('DUPLICATE_NAME', 'A service with this name already exists in your organization.');
  END IF;

  v_new_price := round(p_default_price, 2);

  IF v_new_price < v_service.default_price
    AND EXISTS (
      SELECT 1
      FROM public.service_branches sb
      WHERE sb.service_id = p_service_id
        AND sb.is_deleted = false
        AND sb.price_override IS NULL
        AND sb.promotion_price IS NOT NULL
        AND sb.promotion_price > v_new_price
    )
  THEN
    RETURN public.rpc_error(
      'PROMO_EXCEEDS_PRICE',
      'Promotion price cannot exceed the effective price. Lower the promotion or raise the default/override price.'
    );
  END IF;

  UPDATE public.services s
  SET
    name = v_name,
    default_price = v_new_price,
    global_status = v_status,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE s.id = p_service_id
  RETURNING s.updated_at INTO v_new_updated_at;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'service.update',
    'services',
    p_service_id,
    jsonb_build_object(
      'service_id', p_service_id,
      'name', v_service.name,
      'default_price', v_service.default_price,
      'global_status', v_service.global_status::text
    ),
    jsonb_build_object(
      'service_id', p_service_id,
      'name', v_name,
      'default_price', v_new_price,
      'global_status', v_status::text
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'service_id', p_service_id,
      'updated_at', v_new_updated_at
    )
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN public.rpc_error('DUPLICATE_NAME', 'A service with this name already exists in your organization.');
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage the service catalog.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.set_service_global_status
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.set_service_global_status(
  p_service_id uuid,
  p_expected_updated_at timestamptz,
  p_global_status text
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_service public.services%ROWTYPE;
  v_status public.service_global_status;
  v_new_updated_at timestamptz;
BEGIN
  PERFORM auth_internal.assert_permission('services.manage');
  v_org_id := public.jwt_organization_id();

  IF p_service_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service ID is required.');
  END IF;

  IF p_expected_updated_at IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
  END IF;

  SELECT *
  INTO v_service
  FROM public.services s
  WHERE s.id = p_service_id
    AND s.organization_id = v_org_id
    AND s.is_deleted = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'The requested service was not found.');
  END IF;

  IF v_service.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RETURN public.rpc_error('STALE_SERVICE', 'This service was updated elsewhere. Reload and try again.');
  END IF;

  BEGIN
    v_status := p_global_status::public.service_global_status;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Global status must be active or inactive.');
  END;

  UPDATE public.services s
  SET
    global_status = v_status,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE s.id = p_service_id
  RETURNING s.updated_at INTO v_new_updated_at;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'service.status',
    'services',
    p_service_id,
    jsonb_build_object('service_id', p_service_id, 'global_status', v_service.global_status::text),
    jsonb_build_object('service_id', p_service_id, 'global_status', v_status::text)
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'service_id', p_service_id,
      'global_status', v_status::text,
      'updated_at', v_new_updated_at
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage the service catalog.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.soft_delete_service
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.soft_delete_service(
  p_service_id uuid,
  p_expected_updated_at timestamptz
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_service public.services%ROWTYPE;
BEGIN
  PERFORM auth_internal.assert_permission('services.manage');
  v_org_id := public.jwt_organization_id();

  IF p_service_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service ID is required.');
  END IF;

  IF p_expected_updated_at IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
  END IF;

  SELECT *
  INTO v_service
  FROM public.services s
  WHERE s.id = p_service_id
    AND s.organization_id = v_org_id
    AND s.is_deleted = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'The requested service was not found.');
  END IF;

  IF v_service.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RETURN public.rpc_error('STALE_SERVICE', 'This service was updated elsewhere. Reload and try again.');
  END IF;

  UPDATE public.services s
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE s.id = p_service_id;

  UPDATE public.service_branches sb
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE sb.service_id = p_service_id
    AND sb.is_deleted = false;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'service.delete',
    'services',
    p_service_id,
    jsonb_build_object(
      'service_id', p_service_id,
      'name', v_service.name,
      'default_price', v_service.default_price,
      'global_status', v_service.global_status::text
    ),
    jsonb_build_object('service_id', p_service_id, 'is_deleted', true)
  );

  RETURN public.rpc_success(jsonb_build_object('service_id', p_service_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage the service catalog.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_service(
  p_service_id uuid,
  p_expected_updated_at timestamptz,
  p_name text,
  p_default_price numeric,
  p_global_status text
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_service(
    p_service_id,
    p_expected_updated_at,
    p_name,
    p_default_price,
    p_global_status
  );
$$;

CREATE OR REPLACE FUNCTION public.set_service_global_status(
  p_service_id uuid,
  p_expected_updated_at timestamptz,
  p_global_status text
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.set_service_global_status(p_service_id, p_expected_updated_at, p_global_status);
$$;

CREATE OR REPLACE FUNCTION public.soft_delete_service(p_service_id uuid, p_expected_updated_at timestamptz)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.soft_delete_service(p_service_id, p_expected_updated_at);
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.copy_service_branch_configuration
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.copy_service_branch_configuration(
  p_source_branch_id uuid,
  p_target_branch_id uuid,
  p_mode text,
  p_service_ids uuid[] DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_mode text;
  v_source_row record;
  v_target_exists boolean;
  v_effective_price numeric(14, 2);
  v_affected_ids uuid[] := '{}'::uuid[];
  v_created_count int := 0;
  v_overwritten_count int := 0;
BEGIN
  PERFORM auth_internal.assert_permission('services.manage');
  v_org_id := public.jwt_organization_id();

  IF p_source_branch_id IS NULL OR p_target_branch_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Source and target branch IDs are required.');
  END IF;

  IF p_source_branch_id = p_target_branch_id THEN
    RETURN public.rpc_error('INVALID_COPY_TARGET', 'Source and target branches must differ.');
  END IF;

  IF NOT (p_source_branch_id = ANY (public.jwt_branch_ids()))
    OR NOT (p_target_branch_id = ANY (public.jwt_branch_ids())) THEN
    RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'One or more selected branches are not in your organization.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.branches b
    WHERE b.id = p_source_branch_id
      AND b.organization_id = v_org_id
      AND b.is_deleted = false
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.branches b
    WHERE b.id = p_target_branch_id
      AND b.organization_id = v_org_id
      AND b.is_deleted = false
  ) THEN
    RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'One or more selected branches are not in your organization.');
  END IF;

  v_mode := lower(btrim(p_mode));
  IF v_mode NOT IN ('merge', 'replace') THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Copy mode must be merge or replace.');
  END IF;

  FOR v_source_row IN
    SELECT
      sb.service_id,
      sb.status,
      sb.price_override,
      sb.promotion_price,
      sb.promotion_start_date,
      sb.promotion_end_date,
      s.default_price
    FROM public.service_branches sb
    JOIN public.services s
      ON s.id = sb.service_id
    WHERE sb.branch_id = p_source_branch_id
      AND sb.is_deleted = false
      AND s.organization_id = v_org_id
      AND s.is_deleted = false
      AND (
        p_service_ids IS NULL
        OR cardinality(p_service_ids) = 0
        OR sb.service_id = ANY (p_service_ids)
      )
  LOOP
    SELECT EXISTS (
      SELECT 1
      FROM public.service_branches sb
      WHERE sb.service_id = v_source_row.service_id
        AND sb.branch_id = p_target_branch_id
        AND sb.is_deleted = false
    )
    INTO v_target_exists;

    IF v_mode = 'merge' AND v_target_exists THEN
      CONTINUE;
    END IF;

    v_effective_price := COALESCE(v_source_row.price_override, v_source_row.default_price);

    IF v_source_row.promotion_price IS NOT NULL AND v_effective_price < v_source_row.promotion_price THEN
      RETURN public.rpc_error(
        'PROMO_EXCEEDS_PRICE',
        'Promotion price cannot exceed the effective price. Lower the promotion or raise the default/override price.'
      );
    END IF;

    IF v_target_exists THEN
      UPDATE public.service_branches sb
      SET
        status = v_source_row.status,
        price_override = v_source_row.price_override,
        promotion_price = v_source_row.promotion_price,
        promotion_start_date = v_source_row.promotion_start_date,
        promotion_end_date = v_source_row.promotion_end_date,
        updated_at = now(),
        updated_by = auth.uid()
      WHERE sb.service_id = v_source_row.service_id
        AND sb.branch_id = p_target_branch_id
        AND sb.is_deleted = false;

      v_overwritten_count := v_overwritten_count + 1;
    ELSE
      UPDATE public.service_branches sb
      SET
        is_deleted = false,
        deleted_at = NULL,
        deleted_by = NULL,
        status = v_source_row.status,
        price_override = v_source_row.price_override,
        promotion_price = v_source_row.promotion_price,
        promotion_start_date = v_source_row.promotion_start_date,
        promotion_end_date = v_source_row.promotion_end_date,
        updated_at = now(),
        updated_by = auth.uid()
      WHERE sb.service_id = v_source_row.service_id
        AND sb.branch_id = p_target_branch_id
        AND sb.is_deleted = true;

      IF NOT FOUND THEN
        INSERT INTO public.service_branches (
          service_id,
          branch_id,
          status,
          price_override,
          promotion_price,
          promotion_start_date,
          promotion_end_date,
          created_by,
          updated_by
        )
        VALUES (
          v_source_row.service_id,
          p_target_branch_id,
          v_source_row.status,
          v_source_row.price_override,
          v_source_row.promotion_price,
          v_source_row.promotion_start_date,
          v_source_row.promotion_end_date,
          auth.uid(),
          auth.uid()
        );
      END IF;

      v_created_count := v_created_count + 1;
    END IF;

    v_affected_ids := array_append(v_affected_ids, v_source_row.service_id);
  END LOOP;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'service.branch.copy',
    'service_branches',
    p_target_branch_id,
    jsonb_build_object(
      'source_branch_id', p_source_branch_id,
      'target_branch_id', p_target_branch_id,
      'mode', v_mode,
      'affected_service_ids', v_affected_ids
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'affected_service_ids', v_affected_ids,
      'created_count', v_created_count,
      'overwritten_count', v_overwritten_count
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage the service catalog.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.setup_new_branch_services
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.setup_new_branch_services(
  p_target_branch_id uuid,
  p_method text,
  p_service_ids uuid[] DEFAULT NULL,
  p_source_branch_id uuid DEFAULT NULL,
  p_mode text DEFAULT 'merge'
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_method text;
  v_service_id uuid;
  v_assigned_ids uuid[] := '{}'::uuid[];
  v_copy_result public.rpc_result;
BEGIN
  PERFORM auth_internal.assert_permission('services.manage');
  v_org_id := public.jwt_organization_id();

  IF p_target_branch_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Target branch ID is required.');
  END IF;

  IF NOT (p_target_branch_id = ANY (public.jwt_branch_ids())) THEN
    RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'The selected branch is not in your organization.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.branches b
    WHERE b.id = p_target_branch_id
      AND b.organization_id = v_org_id
      AND b.is_deleted = false
  ) THEN
    RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'The selected branch is not in your organization.');
  END IF;

  v_method := lower(btrim(p_method));
  IF v_method NOT IN ('select', 'copy_all', 'copy_modify') THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Setup method must be select, copy_all, or copy_modify.');
  END IF;

  IF v_method = 'select' THEN
    IF p_service_ids IS NULL OR cardinality(p_service_ids) = 0 THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Select at least one service to assign.');
    END IF;

    FOREACH v_service_id IN ARRAY p_service_ids LOOP
      IF NOT EXISTS (
        SELECT 1
        FROM public.services s
        WHERE s.id = v_service_id
          AND s.organization_id = v_org_id
          AND s.is_deleted = false
      ) THEN
        RETURN public.rpc_error('NOT_FOUND', 'One or more selected services were not found.');
      END IF;

      v_copy_result := auth_internal.set_service_branch_assignment(v_service_id, ARRAY[p_target_branch_id], true);
      IF NOT v_copy_result.success THEN
        RETURN v_copy_result;
      END IF;

      v_assigned_ids := array_append(v_assigned_ids, v_service_id);
    END LOOP;
  ELSE
    IF p_source_branch_id IS NULL THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Source branch ID is required for copy setup.');
    END IF;

    v_copy_result := auth_internal.copy_service_branch_configuration(
      p_source_branch_id,
      p_target_branch_id,
      COALESCE(NULLIF(btrim(p_mode), ''), 'merge'),
      NULL
    );

    IF NOT v_copy_result.success THEN
      RETURN v_copy_result;
    END IF;

    v_assigned_ids := COALESCE(
      ARRAY(
        SELECT jsonb_array_elements_text(v_copy_result.data -> 'affected_service_ids')::uuid
      ),
      '{}'::uuid[]
    );
  END IF;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'service.branch.setup',
    'service_branches',
    p_target_branch_id,
    jsonb_build_object(
      'target_branch_id', p_target_branch_id,
      'method', v_method,
      'assigned_service_ids', v_assigned_ids
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'target_branch_id', p_target_branch_id,
      'assigned_service_ids', v_assigned_ids
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage the service catalog.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.copy_service_branch_configuration(
  p_source_branch_id uuid,
  p_target_branch_id uuid,
  p_mode text,
  p_service_ids uuid[] DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.copy_service_branch_configuration(
    p_source_branch_id,
    p_target_branch_id,
    p_mode,
    p_service_ids
  );
$$;

CREATE OR REPLACE FUNCTION public.setup_new_branch_services(
  p_target_branch_id uuid,
  p_method text,
  p_service_ids uuid[] DEFAULT NULL,
  p_source_branch_id uuid DEFAULT NULL,
  p_mode text DEFAULT 'merge'
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.setup_new_branch_services(
    p_target_branch_id,
    p_method,
    p_service_ids,
    p_source_branch_id,
    p_mode
  );
$$;

GRANT EXECUTE ON FUNCTION public.create_service(text, numeric, text, boolean, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_service_branch_assignment(uuid, uuid[], boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.configure_service_branch(uuid, uuid, timestamptz, text, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_service_promotion(uuid, uuid, timestamptz, numeric, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_service(uuid, timestamptz, text, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_service_global_status(uuid, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.soft_delete_service(uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.copy_service_branch_configuration(uuid, uuid, text, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.setup_new_branch_services(uuid, text, uuid[], uuid, text) TO authenticated;
