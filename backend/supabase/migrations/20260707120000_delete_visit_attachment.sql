-- =============================================================================
-- Delete visit attachments (soft-delete metadata + remove storage object).
-- Expose can_delete on get_visit attachment rows (mirrors can_download rules).
-- =============================================================================

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

CREATE OR REPLACE FUNCTION public.delete_visit_attachment(p_attachment_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.delete_visit_attachment(p_attachment_id);
$$;

GRANT EXECUTE ON FUNCTION auth_internal.delete_visit_attachment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_visit_attachment(uuid) TO authenticated;

-- get_visit: expose can_delete on attachment rows
CREATE OR REPLACE FUNCTION auth_internal.get_visit(p_visit_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
  v_note public.visit_clinical_notes%ROWTYPE;
  v_doctor_name text;
  v_has_clinical boolean;
  v_has_patients_view boolean;
  v_payload jsonb;
  v_documentation jsonb;
  v_vital_signs jsonb;
  v_investigations jsonb;
  v_treatment_plans jsonb;
  v_attachments jsonb;
  v_pending_investigations jsonb;
BEGIN
  BEGIN
    v_visit := auth_internal.assert_visit_branch_scope(p_visit_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
      END IF;
      RAISE;
  END;

  v_has_clinical := auth_internal.staff_has_visit_clinical_access();
  v_has_patients_view := EXISTS (
    SELECT 1
    FROM public.current_staff_member_row() sm
    JOIN public.roles_permissions rp ON rp.role = sm.role
    WHERE rp.permission_key = 'patients.view'
      AND rp.is_granted = true
      AND rp.is_deleted = false
  );

  IF NOT v_has_clinical AND NOT v_has_patients_view THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view this visit.');
  END IF;

  SELECT sm.full_name INTO v_doctor_name
  FROM public.staff_members sm
  WHERE sm.id = v_visit.doctor_id AND sm.is_deleted = false;

  v_payload := jsonb_build_object(
    'id', v_visit.id,
    'branch_id', v_visit.branch_id,
    'appointment_id', v_visit.appointment_id,
    'patient_id', v_visit.patient_id,
    'doctor_id', v_visit.doctor_id,
    'doctor_name', v_doctor_name,
    'visit_date', v_visit.visit_date,
    'status', v_visit.status::text,
    'updated_at', v_visit.updated_at
  );

  IF v_has_clinical THEN
    SELECT * INTO v_note
    FROM public.visit_clinical_notes vcn
    WHERE vcn.visit_id = p_visit_id AND vcn.is_deleted = false;

    IF FOUND THEN
      v_documentation := jsonb_build_object(
        'complaint', v_note.complaint,
        'history', v_note.history,
        'examination', v_note.examination,
        'diagnosis', v_note.diagnosis,
        'plan', v_note.plan,
        'updated_at', v_note.updated_at
      );
    ELSE
      v_documentation := jsonb_build_object(
        'complaint', '',
        'history', '',
        'examination', '',
        'diagnosis', '',
        'plan', '',
        'updated_at', v_visit.updated_at
      );
    END IF;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', vvs.id,
          'name', vvs.name,
          'value', vvs.value,
          'unit', vvs.unit,
          'predefined_vital_sign_id', vvs.predefined_vital_sign_id
        )
        ORDER BY vvs.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_vital_signs
    FROM public.visit_vital_signs vvs
    WHERE vvs.visit_id = p_visit_id AND vvs.is_deleted = false;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', vi.id,
          'name', vi.name,
          'note', vi.note,
          'investigation_id', vi.investigation_id,
          'result', vi.result,
          'result_recorded_at', vi.result_recorded_at
        )
        ORDER BY vi.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_investigations
    FROM public.visit_investigations vi
    WHERE vi.visit_id = p_visit_id AND vi.is_deleted = false;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', vi.id,
          'name', vi.name,
          'note', vi.note,
          'investigation_id', vi.investigation_id,
          'ordered_visit_id', v_prior.id,
          'ordered_visit_date', v_prior.visit_date,
          'result', vi.result,
          'result_recorded_at', vi.result_recorded_at
        )
        ORDER BY v_prior.visit_date DESC, vi.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_pending_investigations
    FROM public.visit_investigations vi
    JOIN public.visits v_prior ON v_prior.id = vi.visit_id
    WHERE v_prior.patient_id = v_visit.patient_id
      AND v_prior.id <> p_visit_id
      AND v_prior.is_deleted = false
      AND vi.is_deleted = false
      AND vi.result IS NULL
      AND auth_internal.staff_can_access_branch(v_prior.branch_id);

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', tp.id,
          'medication_name', tp.medication_name,
          'medication_id', tp.medication_id,
          'dosage', tp.dosage,
          'frequency', tp.frequency,
          'duration', tp.duration,
          'notes', tp.notes
        )
        ORDER BY tp.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_treatment_plans
    FROM public.treatment_plans tp
    WHERE tp.visit_id = p_visit_id AND tp.is_deleted = false;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', va.id,
          'file_type', va.file_type::text,
          'label', va.label,
          'uploaded_by', va.uploaded_by,
          'uploaded_by_name', uploader.full_name,
          'size_bytes', va.size_bytes,
          'created_at', va.created_at,
          'can_download',
            auth_internal.staff_has_visit_clinical_access()
            OR (
              auth_internal.staff_has_visit_upload_access()
              AND va.uploaded_by = public.jwt_staff_member_id()
            ),
          'can_delete',
            auth_internal.staff_has_visit_clinical_access()
            OR (
              auth_internal.staff_has_visit_upload_access()
              AND va.uploaded_by = public.jwt_staff_member_id()
            )
        )
        ORDER BY va.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_attachments
    FROM public.visit_attachments va
    LEFT JOIN public.staff_members uploader ON uploader.id = va.uploaded_by
    WHERE va.visit_id = p_visit_id AND va.is_deleted = false;

    v_payload := v_payload || jsonb_build_object(
      'documentation', v_documentation,
      'vital_signs', COALESCE(v_vital_signs, '[]'::jsonb),
      'investigations', COALESCE(v_investigations, '[]'::jsonb),
      'treatment_plans', COALESCE(v_treatment_plans, '[]'::jsonb),
      'attachments', COALESCE(v_attachments, '[]'::jsonb),
      'pending_investigations', COALESCE(v_pending_investigations, '[]'::jsonb)
    );
  END IF;

  RETURN public.rpc_success(v_payload);
END;
$$;
