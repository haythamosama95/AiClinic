-- Storage INSERT policy must not depend on visits SELECT RLS (blocked for cross-branch admin JWT).

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

GRANT EXECUTE ON FUNCTION auth_internal.visit_exists_for_attachment_storage(uuid, uuid) TO authenticated;
