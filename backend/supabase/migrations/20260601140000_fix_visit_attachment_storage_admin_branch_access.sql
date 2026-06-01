-- Owner/administrator: org-wide branch access for visit attachments (storage RLS + visit RPC scope).
-- Fixes storage upload RLS when clinic administrators are assigned to one branch but document visits at another.

-- -----------------------------------------------------------------------------
-- auth_internal.staff_can_access_branch
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.staff_can_access_branch(p_branch_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_branch_id IS NOT NULL
    AND (
      p_branch_id = ANY (public.jwt_branch_ids())
      OR (
        public.jwt_staff_role() IN ('owner', 'administrator')
        AND public.jwt_organization_id() IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.branches b
          WHERE b.id = p_branch_id
            AND b.organization_id = public.jwt_organization_id()
            AND b.is_deleted = false
            AND b.is_active = true
        )
      )
    );
$$;

-- -----------------------------------------------------------------------------
-- Storage policy helper: visit existence (bypasses visits SELECT RLS in WITH CHECK)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.visit_exists_for_attachment_storage(
  p_visit_id uuid,
  p_branch_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.visits v
    JOIN public.branches b ON b.id = v.branch_id
    WHERE v.id = p_visit_id
      AND v.branch_id = p_branch_id
      AND v.is_deleted = false
      AND b.is_deleted = false
      AND b.is_active = true
      AND b.organization_id = public.jwt_organization_id()
      AND auth_internal.staff_can_access_branch(v.branch_id)
  );
$$;

-- -----------------------------------------------------------------------------
-- Visit branch scope: allow owner/admin across organization branches
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_visit_branch_scope(p_visit_id uuid)
RETURNS public.visits
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
BEGIN
  SELECT *
  INTO v_visit
  FROM public.visits v
  WHERE v.id = p_visit_id
    AND v.is_deleted = false
    AND auth_internal.staff_can_access_branch(v.branch_id);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND';
  END IF;

  RETURN v_visit;
END;
$$;

-- -----------------------------------------------------------------------------
-- JWT claims: owner/administrator receive all active org branches
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.build_staff_claims(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_org_id uuid;
  v_branch_ids text;
  v_setup_required boolean;
BEGIN
  SELECT *
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.auth_user_id = p_user_id
    AND sm.is_deleted = false
    AND sm.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT o.id
  INTO v_org_id
  FROM public.organizations o
  WHERE o.is_deleted = false
  ORDER BY o.created_at
  LIMIT 1;

  IF v_staff.role IN ('owner', 'administrator') AND v_org_id IS NOT NULL THEN
    SELECT string_agg(b.id::text, ',' ORDER BY b.name)
    INTO v_branch_ids
    FROM public.branches b
    WHERE b.organization_id = v_org_id
      AND b.is_deleted = false
      AND b.is_active = true;
  ELSE
    SELECT string_agg(b.id::text, ',' ORDER BY sba.is_primary DESC, b.name)
    INTO v_branch_ids
    FROM public.staff_branch_assignments sba
    JOIN public.branches b ON b.id = sba.branch_id
    WHERE sba.staff_member_id = v_staff.id
      AND sba.is_deleted = false
      AND b.is_deleted = false
      AND b.is_active = true;
  END IF;

  v_setup_required := v_staff.is_bootstrap_admin AND v_org_id IS NULL;

  RETURN jsonb_strip_nulls(
    jsonb_build_object(
      'staff_member_id', v_staff.id::text,
      'staff_role', v_staff.role::text,
      'organization_id', CASE WHEN v_setup_required THEN NULL ELSE v_org_id::text END,
      'branch_ids', COALESCE(v_branch_ids, ''),
      'setup_required', v_setup_required
    )
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- Storage policies: visit-attachments bucket
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS visit_attachments_storage_insert ON storage.objects;
CREATE POLICY visit_attachments_storage_insert ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'visit-attachments'
    AND array_length(storage.foldername(name), 1) >= 3
    AND (storage.foldername(name))[1] = public.jwt_organization_id()::text
    AND auth_internal.staff_can_access_branch(((storage.foldername(name))[2])::uuid)
    AND auth_internal.staff_has_visit_upload_access()
    AND auth_internal.visit_exists_for_attachment_storage(
      ((storage.foldername(name))[3])::uuid,
      ((storage.foldername(name))[2])::uuid
    )
  );

DROP POLICY IF EXISTS visit_attachments_storage_select ON storage.objects;
CREATE POLICY visit_attachments_storage_select ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'visit-attachments'
    AND (storage.foldername(name))[1] = public.jwt_organization_id()::text
    AND auth_internal.staff_can_access_branch(((storage.foldername(name))[2])::uuid)
    AND (
      auth_internal.staff_has_visit_clinical_access()
      OR (
        auth_internal.staff_has_visit_upload_access()
        AND EXISTS (
          SELECT 1
          FROM public.visit_attachments va
          WHERE va.file_path = name
            AND va.is_deleted = false
            AND va.uploaded_by = public.jwt_staff_member_id()
        )
      )
    )
  );

GRANT EXECUTE ON FUNCTION auth_internal.staff_can_access_branch(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.visit_exists_for_attachment_storage(uuid, uuid) TO authenticated;
