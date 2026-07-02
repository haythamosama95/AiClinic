-- CodeRabbit review fixes (comments 84, 89).

-- -----------------------------------------------------------------------------
-- delete_visit_attachment: save/restore storage.allow_delete_query around privileged DELETE.
-- -----------------------------------------------------------------------------

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
  v_storage_deleted int;
  v_rows_updated int;
  v_prev_allow_delete text;
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
    AND va.is_deleted = false
  FOR UPDATE;

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

  v_prev_allow_delete := current_setting('storage.allow_delete_query', true);
  PERFORM set_config('storage.allow_delete_query', 'true', true);
  BEGIN
    DELETE FROM storage.objects o
    WHERE o.bucket_id = 'visit-attachments'
      AND o.name = v_attachment.file_path;

    GET DIAGNOSTICS v_storage_deleted = ROW_COUNT;
    IF v_storage_deleted = 0 THEN
      RAISE EXCEPTION 'STORAGE_NOT_FOUND';
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM set_config('storage.allow_delete_query', COALESCE(v_prev_allow_delete, ''), true);
      IF SQLERRM = 'STORAGE_NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Attachment file was not found in storage.');
      END IF;
      RAISE;
  END;
  PERFORM set_config('storage.allow_delete_query', COALESCE(v_prev_allow_delete, ''), true);

  UPDATE public.visit_attachments va
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE va.id = p_attachment_id
    AND va.is_deleted = false;

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
  IF v_rows_updated = 0 THEN
    RETURN public.rpc_error('NOT_FOUND', 'Attachment was not found.');
  END IF;

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

-- -----------------------------------------------------------------------------
-- complete_visit: lock visit and appointment rows before status validation.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.complete_visit(
  p_visit_id uuid,
  p_expected_updated_at timestamptz DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
  v_appt public.appointments%ROWTYPE;
  v_note public.visit_clinical_notes%ROWTYPE;
  v_org_id uuid;
  v_rows_updated int;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  SELECT v.*
  INTO v_visit
  FROM public.visits v
  WHERE v.id = p_visit_id
    AND v.is_deleted = false
    AND auth_internal.staff_can_access_branch(v.branch_id)
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
  END IF;

  SELECT a.*
  INTO v_appt
  FROM public.appointments a
  WHERE a.id = v_visit.appointment_id
    AND a.is_deleted = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
  END IF;

  IF v_visit.status <> 'in_progress' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Only in-progress visits can be completed.');
  END IF;

  IF v_appt.status <> 'in_progress' THEN
    RETURN public.rpc_error(
      'APPOINTMENT_NOT_IN_PROGRESS',
      'The linked appointment is no longer in progress.'
    );
  END IF;

  SELECT * INTO v_note
  FROM public.visit_clinical_notes vcn
  WHERE vcn.visit_id = p_visit_id AND vcn.is_deleted = false;

  IF FOUND THEN
    IF p_expected_updated_at IS NOT NULL
       AND v_note.updated_at IS DISTINCT FROM p_expected_updated_at THEN
      RETURN public.rpc_error('STALE_DOCUMENTATION', 'This documentation was updated elsewhere. Reload and try again.');
    END IF;
  END IF;

  IF NOT auth_internal.visit_has_documentation(p_visit_id) THEN
    RETURN public.rpc_error(
      'DOCUMENTATION_REQUIRED_FOR_COMPLETE',
      'Enter at least one documentation field before submitting this visit.'
    );
  END IF;

  UPDATE public.visits v
  SET status = 'completed', updated_at = now(), updated_by = auth.uid()
  WHERE v.id = p_visit_id
    AND v.status = 'in_progress'
    AND v.is_deleted = false;

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
  IF v_rows_updated = 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Only in-progress visits can be completed.');
  END IF;

  UPDATE public.appointments a
  SET status = 'completed', updated_at = now(), updated_by = auth.uid()
  WHERE a.id = v_visit.appointment_id
    AND a.status = 'in_progress'
    AND a.is_deleted = false;

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
  IF v_rows_updated = 0 THEN
    RETURN public.rpc_error(
      'APPOINTMENT_NOT_IN_PROGRESS',
      'The linked appointment is no longer in progress.'
    );
  END IF;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES
    (auth.uid(), v_org_id, 'visit.complete', 'visits', p_visit_id,
     jsonb_build_object('visit_id', p_visit_id, 'status', 'completed')),
    (auth.uid(), v_org_id, 'appointment.status_completed', 'appointments', v_visit.appointment_id,
     jsonb_build_object('old_status', 'in_progress', 'new_status', 'completed'));

  RETURN public.rpc_success(jsonb_build_object(
    'visit_id', p_visit_id,
    'visit_status', 'completed',
    'appointment_id', v_visit.appointment_id,
    'appointment_status', 'completed'
  ));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to complete visits.');
    END IF;
    RAISE;
END;
$$;
