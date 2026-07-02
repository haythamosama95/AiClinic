-- Allow SECURITY DEFINER attachment delete to remove storage objects (Supabase protect_delete).

CREATE OR REPLACE FUNCTION auth_internal.delete_visit_attachment(p_attachment_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_attachment public.visit_attachments%ROWTYPE;
  v_org_id uuid;
  v_caller_staff_id uuid;
  v_has_clinical boolean;
  v_has_upload boolean;
BEGIN
  v_caller_staff_id := public.jwt_staff_member_id();
  v_has_clinical := auth_internal.staff_has_visit_clinical_access();
  v_has_upload := auth_internal.staff_has_visit_upload_access();

  IF NOT v_has_clinical AND NOT v_has_upload THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to delete visit attachments.');
  END IF;

  SELECT va.*
  INTO v_attachment
  FROM public.visit_attachments va
  WHERE va.id = p_attachment_id
    AND va.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Attachment was not found.');
  END IF;

  BEGIN
    PERFORM auth_internal.assert_visit_branch_scope(v_attachment.visit_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
      END IF;
      RAISE;
  END;

  IF v_has_clinical THEN
    NULL;
  ELSIF v_has_upload AND v_attachment.uploaded_by = v_caller_staff_id THEN
    NULL;
  ELSE
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to delete this attachment.');
  END IF;

  v_org_id := public.jwt_organization_id();
  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  UPDATE public.visit_attachments va
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE va.id = p_attachment_id;

  PERFORM set_config('storage.allow_delete_query', 'true', true);
  DELETE FROM storage.objects o
  WHERE o.bucket_id = 'visit-attachments'
    AND o.name = v_attachment.file_path;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'visit.attachment.delete',
    'visit_attachments',
    p_attachment_id,
    jsonb_build_object(
      'visit_id', v_attachment.visit_id,
      'attachment_id', p_attachment_id,
      'file_path', v_attachment.file_path
    )
  );

  RETURN public.rpc_success(jsonb_build_object('attachment_id', p_attachment_id));
END;
$$;
