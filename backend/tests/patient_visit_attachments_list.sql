-- Patient visit attachments listing tests (QA LV-BE-001..004, DV-S-008).
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/patient_visit_attachments_list.sql

BEGIN;

CREATE TEMP TABLE patient_attachments_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.test_appointment_same_day_slot(p_offset_hours int)
RETURNS timestamptz
LANGUAGE plpgsql
AS $$
DECLARE
  v_day_start timestamptz;
BEGIN
  v_day_start := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  RETURN v_day_start + make_interval(hours => GREATEST(1, LEAST(p_offset_hours, 23)));
END;
$$;

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a5200000-0000-4000-8000-000000000001';
  v_owner_staff uuid := 'b5200000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'a5200000-0000-4000-8000-000000000002';
  v_doctor_staff uuid := 'b5200000-0000-4000-8000-000000000002';
  v_lab_user uuid := 'a5200000-0000-4000-8000-000000000003';
  v_lab_staff uuid := 'b5200000-0000-4000-8000-000000000003';
  v_other_owner uuid := 'a5200000-0000-4000-8000-000000000099';
  v_other_staff uuid := 'b5200000-0000-4000-8000-000000000099';
  v_result public.rpc_result;
  v_org_id uuid;
  v_other_org_id uuid := 'c5200000-0000-4000-8000-000000000099';
  v_branch_id uuid;
  v_other_branch_id uuid := 'd5200000-0000-4000-8000-000000000099';
  v_patient_id uuid;
  v_other_org_patient uuid := 'a5200000-0000-4000-8000-000000000099';
  v_visit_id uuid;
  v_start timestamptz;
  v_appt_id uuid;
  v_file_path text;
  v_items jsonb;
  v_i int;
  v_visit_updated_at timestamptz;
  v_soap_updated_at timestamptz;
  v_doctor_can_download boolean;
  v_lab_can_download boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users
  WHERE id IN (v_owner_user, v_doctor_user, v_lab_user, v_other_owner);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'attach-owner',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'attach-doctor',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_lab_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'attach-lab',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_other_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'attach-other',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_create_organization('Attach Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'AT', NULL);
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
    (v_owner_staff, v_owner_user, 'Attach Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Attach Doctor', 'doctor', false, v_bootstrap_user, v_bootstrap_user),
    (v_lab_staff, v_lab_user, 'Attach Lab', 'lab_staff', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  SELECT s.id, v_branch_id, true, v_bootstrap_user, v_bootstrap_user
  FROM (VALUES (v_owner_staff), (v_doctor_staff), (v_lab_staff)) AS s(id);

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

  v_result := public.create_patient(v_branch_id, 'Attach Patient', '201520000001', NULL, NULL, NULL, NULL, false);
  v_patient_id := (v_result.data ->> 'patient_id')::uuid;

  -- One completed visit; LV-BE-001 uses three attachments on it.
  v_start := pg_temp.test_appointment_same_day_slot(5);
  v_result := public.create_appointment(
    v_branch_id, v_patient_id, v_doctor_staff, 'planned', v_start, 20, NULL, NULL
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'create_appointment failed: %', COALESCE(v_result.error_code, '?');
  END IF;
  v_appt_id := (v_result.data ->> 'appointment_id')::uuid;
  v_result := public.update_appointment_status(v_appt_id, 'confirmed');
  v_result := public.update_appointment_status(v_appt_id, 'checked_in');
  v_result := public.create_visit(v_appt_id, NULL);
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'create_visit failed: %', COALESCE(v_result.error_code, '?');
  END IF;
  v_visit_id := (v_result.data ->> 'visit_id')::uuid;
  SELECT v.updated_at INTO v_visit_updated_at FROM public.visits v WHERE v.id = v_visit_id;
  v_result := public.save_soap_note(v_visit_id, v_visit_updated_at, 'Attach note.', NULL, NULL, NULL, NULL);
  v_soap_updated_at := (v_result.data ->> 'updated_at')::timestamptz;
  v_result := public.complete_visit(v_visit_id, v_soap_updated_at);
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'complete_visit failed: %', COALESCE(v_result.error_code, '?');
  END IF;

  PERFORM set_config('role', 'postgres', true);
  FOR v_i IN 1..3 LOOP
    v_file_path := v_org_id::text || '/' || v_branch_id::text || '/' || v_visit_id::text || '/doc-' || v_i || '.pdf';
    INSERT INTO storage.objects (bucket_id, name, owner, metadata)
    VALUES ('visit-attachments', v_file_path, v_owner_user, '{}'::jsonb)
    ON CONFLICT (bucket_id, name) DO NOTHING;
    INSERT INTO public.visit_attachments (
      visit_id, file_path, file_type, label, uploaded_by, size_bytes, created_by, updated_by
    )
    VALUES (
      v_visit_id,
      v_file_path,
      'pdf',
      'Doc ' || v_i,
      v_doctor_staff,
      1024,
      v_owner_user,
      v_owner_user
    );
  END LOOP;
  PERFORM set_config('role', 'authenticated', true);

  -- LV-BE-001: happy path returns attachments with visit_date.
  v_result := public.list_patient_visit_attachments(v_patient_id);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_attachments_results VALUES (
    'LV_BE_001_list_patient_visit_attachments_happy',
    v_result.success
      AND jsonb_array_length(v_items) = 3
      AND NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) item WHERE item ->> 'visit_date' IS NULL
      ),
    'count=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Second org patient for cross-org denial (inserted as postgres).
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.patients WHERE id = v_other_org_patient;
  DELETE FROM public.branches WHERE id = v_other_branch_id;
  DELETE FROM public.organizations WHERE id = v_other_org_id;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES (v_other_org_id, 'Other Attach Org', v_other_owner, v_other_owner);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES (v_other_branch_id, v_other_org_id, 'Other Branch', 'OT', v_other_owner, v_other_owner);

  INSERT INTO public.patients (
    id, branch_id, organization_id, full_name, phone, created_by, updated_by
  )
  VALUES (
    v_other_org_patient, v_other_branch_id, v_other_org_id, 'Other Org Patient', '201520000099', v_other_owner, v_other_owner
  );
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

  -- LV-BE-002: cross-org patient returns NOT_FOUND.
  v_result := public.list_patient_visit_attachments(v_other_org_patient);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_attachments_results VALUES (
    'LV_BE_002_list_patient_visit_attachments_cross_org',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- LV-BE-003: archived patient returns PATIENT_ARCHIVED.
  v_result := public.archive_patient(v_patient_id);
  v_result := public.list_patient_visit_attachments(v_patient_id);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_attachments_results VALUES (
    'LV_BE_003_list_patient_visit_attachments_archived_patient',
    NOT v_result.success AND v_result.error_code = 'PATIENT_ARCHIVED',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Restore patient for pagination test.
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.patients SET is_deleted = false, deleted_at = NULL, deleted_by = NULL WHERE id = v_patient_id;

  -- LV-BE-004: pagination with >100 attachments.
  FOR v_i IN 4..105 LOOP
    INSERT INTO public.visit_attachments (
      visit_id, file_path, file_type, label, uploaded_by, size_bytes, created_at, created_by, updated_by
    )
    VALUES (
      v_visit_id,
      v_org_id::text || '/' || v_branch_id::text || '/' || v_visit_id::text || '/bulk-' || v_i || '.pdf',
      'pdf',
      'Bulk ' || v_i,
      v_doctor_staff,
      512,
      now() - make_interval(secs => v_i),
      v_owner_user,
      v_owner_user
    );
  END LOOP;
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.list_patient_visit_attachments(v_patient_id, 50, 50);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_attachments_results VALUES (
    'LV_BE_004_list_patient_visit_attachments_pagination',
    v_result.success
      AND (v_result.data ->> 'total_count')::int >= 102
      AND (v_result.data ->> 'limit')::int = 50
      AND (v_result.data ->> 'offset')::int = 50
      AND jsonb_array_length(v_items) = 50,
    'total=' || COALESCE(v_result.data ->> 'total_count', '<null>')
      || ' items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- DV-S-008: doctor vs lab_staff can_download ACL.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_doctor_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_doctor_staff::text,
      'staff_role', 'doctor',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.list_patient_visit_attachments(v_patient_id, 10, 0);
  v_doctor_can_download := COALESCE((v_result.data -> 'items' -> 0 ->> 'can_download')::boolean, false);

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_lab_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_lab_staff::text,
      'staff_role', 'lab_staff',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.list_patient_visit_attachments(v_patient_id, 10, 0);
  v_lab_can_download := COALESCE((v_result.data -> 'items' -> 0 ->> 'can_download')::boolean, true);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_attachments_results VALUES (
    'DV_S_008_doctor_can_download_clinical_attachment',
    v_doctor_can_download,
    'doctor_can_download=' || v_doctor_can_download::text
  );
  INSERT INTO patient_attachments_results VALUES (
    'DV_S_008_lab_staff_cannot_download_others_upload',
    NOT v_lab_can_download,
    'lab_can_download=' || v_lab_can_download::text
  );
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_failed FROM patient_attachments_results WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM patient_attachments_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'patient_visit_attachments_list: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
