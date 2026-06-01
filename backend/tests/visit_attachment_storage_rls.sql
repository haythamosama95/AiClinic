-- Visit attachment storage INSERT RLS: owner/administrator org-wide branch access.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/visit_attachment_storage_rls.sql

BEGIN;

CREATE TEMP TABLE visit_storage_rls_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_org_id uuid := 'c2600000-0000-4000-8000-0000000000a1';
  v_branch_primary uuid := 'd2600000-0000-4000-8000-0000000000a1';
  v_branch_other uuid := 'd2600000-0000-4000-8000-0000000000a2';
  v_admin_user uuid := 'e2600000-0000-4000-8000-0000000000a1';
  v_admin_staff uuid := 'f2600000-0000-4000-8000-0000000000a1';
  v_doctor_user uuid := 'e2600000-0000-4000-8000-0000000000a2';
  v_doctor_staff uuid := 'f2600000-0000-4000-8000-0000000000a2';
  v_patient_id uuid := 'a2600000-0000-4000-8000-0000000000a1';
  v_appt_id uuid := 'c2610000-0000-4000-8000-0000000000a1';
  v_visit_id uuid := 'b2610000-0000-4004-8000-0000000000a1';
  v_file_path text;
  v_result public.rpc_result;
  v_inserted boolean;
  v_insert_detail text;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  DELETE FROM public.visit_attachments WHERE visit_id = v_visit_id;
  DELETE FROM public.visits WHERE id = v_visit_id;
  DELETE FROM public.appointments WHERE id = v_appt_id;
  DELETE FROM public.patients WHERE id = v_patient_id;
  DELETE FROM public.staff_branch_assignments
  WHERE staff_member_id IN (v_admin_staff, v_doctor_staff);
  DELETE FROM public.staff_members WHERE id IN (v_admin_staff, v_doctor_staff);
  DELETE FROM public.branches WHERE id IN (v_branch_primary, v_branch_other);
  DELETE FROM public.organizations WHERE id = v_org_id;
  DELETE FROM auth.users WHERE id IN (v_admin_user, v_doctor_user);

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES (v_org_id, 'Storage RLS Clinic', v_bootstrap_user, v_bootstrap_user);

  INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
  VALUES
    (v_branch_primary, v_org_id, 'Primary', 'PRI', v_bootstrap_user, v_bootstrap_user),
    (v_branch_other, v_org_id, 'Satellite', 'SAT', v_bootstrap_user, v_bootstrap_user);

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
  WHERE b.id IN (v_branch_primary, v_branch_other);

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_admin_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'storage-admin',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now()),
    (v_doctor_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'storage-doctor',
     extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES
    (v_admin_staff, v_admin_user, 'Clinic Admin', 'administrator', false, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_doctor_user, 'Dr Visit', 'doctor', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  -- Administrator assigned only to primary; visit lives at satellite branch.
  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_admin_staff, v_branch_primary, true, v_bootstrap_user, v_bootstrap_user),
    (v_doctor_staff, v_branch_other, true, v_bootstrap_user, v_bootstrap_user);

  INSERT INTO public.patients (id, branch_id, organization_id, full_name, phone, created_by, updated_by)
  VALUES (
    v_patient_id,
    v_branch_other,
    v_org_id,
    'Satellite Patient',
    '201111111301',
    v_bootstrap_user,
    v_bootstrap_user
  );

  INSERT INTO public.appointments (
    id, branch_id, patient_id, doctor_id, start_time, end_time, type, status, created_by, updated_by
  )
  VALUES (
    v_appt_id,
    v_branch_other,
    v_patient_id,
    v_doctor_staff,
    now(),
    now() + interval '30 minutes',
    'planned',
    'in_progress',
    v_bootstrap_user,
    v_bootstrap_user
  );

  INSERT INTO public.visits (
    id, branch_id, appointment_id, patient_id, doctor_id, visit_date, status, created_by, updated_by
  )
  VALUES (
    v_visit_id,
    v_branch_other,
    v_appt_id,
    v_patient_id,
    v_doctor_staff,
    current_date,
    'in_progress',
    v_bootstrap_user,
    v_bootstrap_user
  );

  v_file_path := v_org_id::text || '/' || v_branch_other::text || '/' || v_visit_id::text || '/admin-cross-branch.pdf';

  -- JWT lists only the primary branch (legacy claims before org-wide branch expansion).
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_primary::text,
      'staff_member_id', v_admin_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_inserted := false;
  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner, metadata)
    VALUES ('visit-attachments', v_file_path, v_admin_user, jsonb_build_object('mimetype', 'application/pdf'));
    v_inserted := true;
    v_insert_detail := 'ok';
  EXCEPTION
    WHEN OTHERS THEN
      v_inserted := false;
      v_insert_detail := SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_storage_rls_results VALUES (
    'administrator_storage_insert_other_branch',
    v_inserted,
    v_insert_detail
  );

  PERFORM set_config('role', 'authenticated', true);

  v_result := public.register_visit_attachment(v_visit_id, v_file_path, 'pdf', 1024, 'Cross branch');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_storage_rls_results VALUES (
    'administrator_register_attachment_other_branch',
    v_result.success,
    COALESCE(v_result.error_code, '<null>')
  );

  INSERT INTO visit_storage_rls_results VALUES (
    'staff_can_access_branch_admin_other_branch',
    auth_internal.staff_can_access_branch(v_branch_other),
    'can_access=' || auth_internal.staff_can_access_branch(v_branch_other)::text
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM visit_storage_rls_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'visit_attachment_storage_rls failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ') FROM visit_storage_rls_results WHERE NOT passed
    );
  END IF;
END;
$$;

ROLLBACK;
