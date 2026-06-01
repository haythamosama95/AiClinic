-- visit-attachments paths are org/branch/visit/filename; storage.foldername() returns 3 folder segments.

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
