-- V1-5 cross-org and cross-branch denial for visits; lab attachment download rules.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/visit_medical_records_rls.sql

BEGIN;

CREATE TEMP TABLE visit_rls_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_org_a uuid := 'c2500000-0000-4000-8000-0000000000a1';
  v_org_b uuid := 'c2500000-0000-4000-8000-0000000000b2';
  v_branch_a uuid := 'd2500000-0000-4000-8000-0000000000a1';
  v_branch_b uuid := 'd2500000-0000-4000-8000-0000000000b2';
  v_branch_a2 uuid := 'd2500000-0000-4000-8000-0000000000a2';
  v_user_a uuid := 'e2500000-0000-4000-8000-0000000000a1';
  v_user_b uuid := 'e2500000-0000-4000-8000-0000000000b2';
  v_lab_user_a uuid := 'e2500000-0000-4000-8000-0000000000a4';
  v_staff_a uuid := 'f2500000-0000-4000-8000-0000000000a1';
  v_staff_b uuid := 'f2500000-0000-4000-8000-0000000000b2';
  v_lab_staff_a uuid := 'f2500000-0000-4000-8000-0000000000a4';
  v_doctor_a uuid := 'f2500000-0000-4000-8000-0000000000a3';
  v_doctor_user_a uuid := 'e2500000-0000-4000-8000-0000000000a3';
  v_patient_a uuid := 'a2500000-0000-4000-8000-0000000000a1';
  v_patient_a2 uuid := 'a2500000-0000-4000-8000-0000000000a2';
  v_patient_b uuid := 'a2500000-0000-4000-8000-0000000000b2';
  v_appt_a uuid := 'c2500000-0000-4000-8000-00000000aa01';
  v_appt_a2 uuid := 'c2500000-0000-4000-8000-00000000aa02';
  v_appt_b uuid := 'c2500000-0000-4000-8000-00000000bb01';
  v_visit_a uuid := 'f2500000-0000-4000-8000-00000000aa01';
  v_visit_a2 uuid := 'f2500000-0000-4000-8000-00000000aa02';
  v_visit_b uuid := 'f2500000-0000-4000-8000-00000000bb01';
  v_attachment_owner uuid := 'f2500000-0000-4000-8000-000000000a01';
  v_attachment_lab uuid := 'f2500000-0000-4000-8000-000000000a02';
  v_file_owner text;
  v_file_lab text;
  v_result public.rpc_result;
  v_visible_count int;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.visit_attachments;
  DELETE FROM public.soap_notes;
  DELETE FROM public.treatment_plans;
  DELETE FROM public.visits;
  DELETE FROM public.appointments;
  DELETE FROM public.patients;
  DELETE FROM public.staff_branch_assignments;
  DELETE FROM public.staff_members
  WHERE id IN (v_staff_a, v_staff_b, v_doctor_a, v_lab_staff_a);
  DELETE FROM public.branches WHERE id IN (v_branch_a, v_branch_b, v_branch_a2);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM auth.users WHERE id IN (v_user_a, v_user_b, v_doctor_user_a, v_lab_user_a);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_user_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-visit-a',
     extensions.crypt('pw-a', extensions.gen_salt('bf')), now(), now(), now()),
    (v_user_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-visit-b',
     extensions.crypt('pw-b', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-visit-doc-a',
     extensions.crypt('pw-doc-a', extensions.gen_salt('bf')), now(), now(), now()),
    (v_lab_user_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-visit-lab-a',
     extensions.crypt('pw-lab-a', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'RLS Visit Org A', v_user_a, v_user_a),
    (v_org_b, 'RLS Visit Org B', v_user_b, v_user_b);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_a, v_org_a, 'Branch A', 'PA', v_user_a, v_user_a),
    (v_branch_a2, v_org_a, 'Branch A2', 'PA2', v_user_a, v_user_a),
    (v_branch_b, v_org_b, 'Branch B', 'PB', v_user_b, v_user_b);

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
  VALUES
    (v_staff_a, v_user_a, 'Owner A', 'owner', v_user_a, v_user_a),
    (v_staff_b, v_user_b, 'Owner B', 'owner', v_user_b, v_user_b),
    (v_doctor_a, v_doctor_user_a, 'Doctor A', 'doctor', v_user_a, v_user_a),
    (v_lab_staff_a, v_lab_user_a, 'Lab A', 'lab_staff', v_user_a, v_user_a);

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_staff_a, v_branch_a, true, v_user_a, v_user_a),
    (v_staff_a, v_branch_a2, false, v_user_a, v_user_a),
    (v_doctor_a, v_branch_a, true, v_user_a, v_user_a),
    (v_lab_staff_a, v_branch_a, true, v_user_a, v_user_a),
    (v_staff_b, v_branch_b, true, v_user_b, v_user_b);

  INSERT INTO public.patients (id, branch_id, organization_id, full_name, phone, created_by, updated_by)
  VALUES
    (v_patient_a, v_branch_a, v_org_a, 'Patient A', '201111111251', v_user_a, v_user_a),
    (v_patient_a2, v_branch_a2, v_org_a, 'Patient A2', '201111111252', v_user_a, v_user_a),
    (v_patient_b, v_branch_b, v_org_b, 'Patient B', '201234567951', v_user_b, v_user_b);

  INSERT INTO public.appointments (
    id, branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES
    (
      v_appt_a,
      v_branch_a,
      v_patient_a,
      v_doctor_a,
      now(),
      now() + interval '30 minutes',
      'planned',
      'in_progress',
      v_user_a,
      v_user_a
    ),
    (
      v_appt_a2,
      v_branch_a2,
      v_patient_a2,
      v_doctor_a,
      now() + interval '1 hour',
      now() + interval '90 minutes',
      'planned',
      'in_progress',
      v_user_a,
      v_user_a
    ),
    (
      v_appt_b,
      v_branch_b,
      v_patient_b,
      v_staff_b,
      now(),
      now() + interval '30 minutes',
      'planned',
      'in_progress',
      v_user_b,
      v_user_b
    );

  INSERT INTO public.visits (
    id, branch_id, appointment_id, patient_id, doctor_id, visit_date, status, created_by, updated_by
  )
  VALUES
    (
      v_visit_a,
      v_branch_a,
      v_appt_a,
      v_patient_a,
      v_doctor_a,
      current_date,
      'in_progress',
      v_user_a,
      v_user_a
    ),
    (
      v_visit_a2,
      v_branch_a2,
      v_appt_a2,
      v_patient_a2,
      v_doctor_a,
      current_date,
      'in_progress',
      v_user_a,
      v_user_a
    ),
    (
      v_visit_b,
      v_branch_b,
      v_appt_b,
      v_patient_b,
      v_staff_b,
      current_date,
      'in_progress',
      v_user_b,
      v_user_b
    );

  v_file_owner := v_org_a::text || '/' || v_branch_a::text || '/' || v_visit_a::text || '/owner-upload.pdf';
  v_file_lab := v_org_a::text || '/' || v_branch_a::text || '/' || v_visit_a::text || '/lab-upload.pdf';

  INSERT INTO storage.objects (bucket_id, name, owner, metadata)
  VALUES
    ('visit-attachments', v_file_owner, v_user_a, '{}'::jsonb),
    ('visit-attachments', v_file_lab, v_lab_user_a, '{}'::jsonb)
  ON CONFLICT (bucket_id, name) DO NOTHING;

  INSERT INTO public.visit_attachments (
    id, visit_id, file_path, file_type, label, uploaded_by, size_bytes, created_by, updated_by
  )
  VALUES
    (
      v_attachment_owner,
      v_visit_a,
      v_file_owner,
      'pdf',
      'Owner file',
      v_staff_a,
      2048,
      v_user_a,
      v_user_a
    ),
    (
      v_attachment_lab,
      v_visit_a,
      v_file_lab,
      'pdf',
      'Lab file',
      v_lab_staff_a,
      1024,
      v_lab_user_a,
      v_lab_user_a
    );

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_user_a::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_staff_a::text,
      'staff_role', 'owner',
      'setup_required', false
    )::text,
    true
  );

  SELECT count(*)::int
  INTO v_visible_count
  FROM public.visits v
  WHERE v.id = v_visit_b;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_rls_results VALUES (
    'cross_org_visit_direct_select_hidden',
    v_visible_count = 0,
    'count=' || v_visible_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_visit(v_visit_b);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_rls_results VALUES (
    'cross_org_get_visit_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Cross-branch within org: doctor assigned only to branch A cannot access branch A2 visit.
  -- (Owner/administrator have org-wide branch access; see visit_attachment_storage_rls.sql.)
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_doctor_user_a::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_doctor_a::text,
      'staff_role', 'doctor',
      'setup_required', false
    )::text,
    true
  );

  SELECT count(*)::int
  INTO v_visible_count
  FROM public.visits v
  WHERE v.id = v_visit_a2;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_rls_results VALUES (
    'cross_branch_visit_direct_select_hidden',
    v_visible_count = 0,
    'count=' || v_visible_count::text
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_visit(v_visit_a2);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_rls_results VALUES (
    'cross_branch_get_visit_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.save_soap_note(
    v_visit_a2,
    now(),
    'Should not save',
    NULL,
    NULL,
    NULL,
    NULL
  );
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_rls_results VALUES (
    'cross_branch_save_soap_denied',
    NOT v_result.success AND v_result.error_code = 'NOT_FOUND',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Lab staff: own upload download allowed; other uploader denied.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_lab_user_a::text,
      'role', 'authenticated',
      'organization_id', v_org_a::text,
      'branch_ids', v_branch_a::text,
      'staff_member_id', v_lab_staff_a::text,
      'staff_role', 'lab_staff',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.get_visit_attachment_download(v_attachment_lab);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_rls_results VALUES (
    'lab_staff_download_own_upload_allowed',
    v_result.success AND (v_result.data ->> 'file_path') = v_file_lab,
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  v_result := public.get_visit_attachment_download(v_attachment_owner);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_rls_results VALUES (
    'lab_staff_download_other_upload_denied',
    NOT v_result.success AND v_result.error_code = 'ATTACHMENT_DOWNLOAD_DENIED',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'postgres', true);
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  SELECT count(*)::int
  INTO v_failed
  FROM visit_rls_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM visit_rls_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'visit_medical_records_rls: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
