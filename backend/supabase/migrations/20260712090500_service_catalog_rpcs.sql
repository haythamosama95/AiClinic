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

GRANT EXECUTE ON FUNCTION public.create_service(text, numeric, text, boolean, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_service_branch_assignment(uuid, uuid[], boolean) TO authenticated;
