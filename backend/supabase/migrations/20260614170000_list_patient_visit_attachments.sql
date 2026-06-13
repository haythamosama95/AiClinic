-- Patient-scoped visit attachment listing (avoids N+1 get_visit calls on patient detail).

CREATE OR REPLACE FUNCTION auth_internal.list_patient_visit_attachments(
  p_patient_id uuid,
  p_limit int DEFAULT 100,
  p_offset int DEFAULT 0
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_limit int;
  v_offset int;
  v_items jsonb;
  v_total int;
BEGIN
  PERFORM auth_internal.assert_permission('patients.view');
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  BEGIN
    PERFORM auth_internal.assert_org_patient(p_patient_id, false);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      IF SQLERRM = 'PATIENT_ARCHIVED' THEN
        RETURN public.rpc_error('PATIENT_ARCHIVED', 'This patient is archived.');
      END IF;
      RAISE;
  END;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  WITH filtered AS (
    SELECT
      v.id AS visit_id,
      v.visit_date,
      va.id,
      va.file_type,
      va.label,
      va.uploaded_by,
      uploader.full_name AS uploaded_by_name,
      va.size_bytes,
      va.created_at,
      (
        auth_internal.staff_has_visit_clinical_access()
        OR (
          auth_internal.staff_has_visit_upload_access()
          AND va.uploaded_by = public.jwt_staff_member_id()
        )
      ) AS can_download
    FROM public.visit_attachments va
    JOIN public.visits v ON v.id = va.visit_id
    LEFT JOIN public.staff_members uploader ON uploader.id = va.uploaded_by
    WHERE v.patient_id = p_patient_id
      AND v.is_deleted = false
      AND va.is_deleted = false
      AND v.branch_id = ANY (public.jwt_branch_ids())
  ),
  counted AS (
    SELECT
      f.*,
      count(*) OVER ()::int AS total_count
    FROM filtered f
    ORDER BY f.created_at DESC
    LIMIT v_limit
    OFFSET v_offset
  )
  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'visit_id', c.visit_id,
          'visit_date', c.visit_date,
          'id', c.id,
          'file_type', c.file_type::text,
          'label', c.label,
          'uploaded_by', c.uploaded_by,
          'uploaded_by_name', c.uploaded_by_name,
          'size_bytes', c.size_bytes,
          'created_at', c.created_at,
          'can_download', c.can_download
        )
        ORDER BY c.created_at DESC
      ),
      '[]'::jsonb
    ),
    COALESCE(max(c.total_count), 0)
  INTO v_items, v_total
  FROM counted c;

  RETURN public.rpc_success(
    jsonb_build_object(
      'items', COALESCE(v_items, '[]'::jsonb),
      'total_count', COALESCE(v_total, 0),
      'limit', v_limit,
      'offset', v_offset
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view patient documents.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_patient_visit_attachments(
  p_patient_id uuid,
  p_limit int DEFAULT 100,
  p_offset int DEFAULT 0
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.list_patient_visit_attachments(p_patient_id, p_limit, p_offset);
$$;

GRANT EXECUTE ON FUNCTION auth_internal.list_patient_visit_attachments(uuid, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_patient_visit_attachments(uuid, int, int) TO authenticated;
