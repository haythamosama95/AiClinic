-- ui/014 visit encounter workspace backend QA test (BE-006).
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/visit_attachment_delete_storage.sql
--
-- Covers delete_visit_attachment(p_attachment_id uuid): soft-deletes metadata
-- and removes the matching storage.objects row (no orphan blob).

BEGIN;

CREATE TEMP TABLE visit_attachment_delete_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.test_appointment_same_day_slot(p_offset_hours int)
RETURNS timestamptz
LANGUAGE plpgsql
AS $$
DECLARE
  v_tz text := 'UTC';
  v_day_start timestamptz;
BEGIN
  IF p_offset_hours < 1 OR p_offset_hours > 23 THEN
    RAISE EXCEPTION 'test_appointment_same_day_slot: offset must be 1..23, got %', p_offset_hours;
  END IF;
  v_day_start := date_trunc('day', now() AT TIME ZONE v_tz) AT TIME ZONE v_tz;
  RETURN v_day_start + make_interval(hours => p_offset_hours);
END;
$$;

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a6700000-0000-4000-8000-000000000001';
  v_owner_staff uuid := 'b6700000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'a6700000-0000-4000-8000-000000000002';
  v_doctor_staff uuid := 'b6700000-0000-4000-8000-000000000002';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_patient_id uuid;
  v_appt_id uuid;
  v_visit_id uuid;
  v_attachment_id uuid;
  v_file_path text;
  v_start timestamptz;
  v_storage_exists boolean;
  v_row_is_deleted boolean;
  v_deleted_at timestamptz;
  v_deleted_by uuid;
  v_audit_count int;
  v_get_visit_count int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE id IN (v_owner_user, v_doctor_user);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'attach-del-owner',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'attach-del-doctor',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('Attach Delete Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'AD', NULL);
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  UPDATE public.branches b
  SET working_schedule = jsonb_build_object(
    'days',
    jsonb_build_array(
      jsonb_build_object('day', 'monday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'tuesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'wednesday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'thursday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'friday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'saturday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59'),
      jsonb_build_object('day', 'sunday', 'is_working_day', true, 'open_time', '00:00', 'close_time', '23:59')
    )
  )
  WHERE b.id = v_branch_id;

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_owner_staff, v_owner_user, 'Attach Delete Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Attach Delete Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_branch_id, true, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_branch_id, false, v_bootstrap_user, v_bootstrap_user);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.create_patient(v_branch_id, 'Attach Delete Patient', '201670000001', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;

  v_start := pg_temp.test_appointment_same_day_slot(6);
  v_result := public.create_appointment(
    v_branch_id, v_patient_id, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'BE-006 setup create_appointment failed: %', COALESCE(v_result.error_code, '?');
  END IF;
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt_id, 'checked_in');
  v_result := public.create_visit(v_appt_id, NULL);
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'BE-006 setup create_visit failed: %', COALESCE(v_result.error_code, '?');
  END IF;
  v_visit_id := (v_result.data ->> 'visit_id')::uuid;

  v_file_path := v_org_id::text || '/' || v_branch_id::text || '/' || v_visit_id::text || '/delete-me.pdf';
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO storage.objects (bucket_id, name, owner, metadata)
  VALUES ('visit-attachments', v_file_path, v_owner_user, jsonb_build_object('mimetype', 'application/pdf'))
  ON CONFLICT (bucket_id, name) DO NOTHING;
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.register_visit_attachment(v_visit_id, v_file_path, 'pdf', 2048, 'Delete me');
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'BE-006 setup register_visit_attachment failed: %', COALESCE(v_result.error_code, '?');
  END IF;
  v_attachment_id := (v_result.data ->> 'attachment_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  SELECT EXISTS (
    SELECT 1
    FROM storage.objects o
    WHERE o.bucket_id = 'visit-attachments' AND o.name = v_file_path
  ) INTO v_storage_exists;
  INSERT INTO visit_attachment_delete_results VALUES (
    'BE_006_precondition_storage_object_exists',
    v_storage_exists,
    'storage_exists=' || v_storage_exists::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- BE-006: delete_visit_attachment(p_attachment_id) soft-deletes metadata and removes storage.
  v_result := public.delete_visit_attachment(v_attachment_id);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_attachment_delete_results VALUES (
    'BE_006_delete_visit_attachment_rpc_success',
    v_result.success
      AND (v_result.data ->> 'attachment_id')::uuid = v_attachment_id,
    COALESCE(v_result.error_code, 'ok')
  );

  SELECT
    va.is_deleted,
    va.deleted_at,
    va.deleted_by
  INTO v_row_is_deleted, v_deleted_at, v_deleted_by
  FROM public.visit_attachments va
  WHERE va.id = v_attachment_id;

  INSERT INTO visit_attachment_delete_results VALUES (
    'BE_006_delete_visit_attachment_soft_deletes_metadata',
    v_row_is_deleted
      AND v_deleted_at IS NOT NULL
      AND v_deleted_by = v_owner_user
      AND NOT EXISTS (
        SELECT 1
        FROM public.visit_attachments va
        WHERE va.id = v_attachment_id AND va.is_deleted = false
      ),
    'is_deleted=' || COALESCE(v_row_is_deleted::text, '<null>')
      || '; deleted_at=' || COALESCE(v_deleted_at::text, '<null>')
  );

  SELECT EXISTS (
    SELECT 1
    FROM storage.objects o
    WHERE o.bucket_id = 'visit-attachments' AND o.name = v_file_path
  ) INTO v_storage_exists;

  INSERT INTO visit_attachment_delete_results VALUES (
    'BE_006_delete_visit_attachment_removes_storage_object',
    NOT v_storage_exists,
    'storage_exists=' || v_storage_exists::text
  );

  SELECT count(*)::int
  INTO v_audit_count
  FROM public.audit_log al
  WHERE al.action = 'visit.attachment.delete'
    AND al.table_name = 'visit_attachments'
    AND al.record_id = v_attachment_id;

  INSERT INTO visit_attachment_delete_results VALUES (
    'BE_006_delete_visit_attachment_audit_logged',
    v_audit_count = 1,
    'audit_count=' || v_audit_count::text
  );

  PERFORM set_config('role', 'authenticated', true);
  v_result := public.get_visit(v_visit_id);
  PERFORM set_config('role', 'postgres', true);
  v_get_visit_count := COALESCE(jsonb_array_length(v_result.data -> 'attachments'), 0);
  INSERT INTO visit_attachment_delete_results VALUES (
    'BE_006_delete_visit_attachment_hidden_from_get_visit',
    v_result.success
      AND NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(COALESCE(v_result.data -> 'attachments', '[]'::jsonb)) item
        WHERE (item ->> 'id')::uuid = v_attachment_id
      ),
    'attachment_count=' || v_get_visit_count::text
  );
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_failed FROM visit_attachment_delete_results WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM visit_attachment_delete_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'visit_attachment_delete_storage: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
