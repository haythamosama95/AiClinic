-- ui/014 visit encounter workspace backend QA (BE-007).
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/visit_predefined_vital_signs_backfill.sql
--
-- Covers predefined vital signs catalog backfill (20260703120000) via org insert trigger
-- and auth_internal.seed_organization_catalog_defaults idempotency.
-- Catalog seeds match auth_internal.seed_organization_catalog_defaults (Pain Score retired
-- in 20260704120000_simplify_vital_signs.sql).

BEGIN;

CREATE TEMP TABLE visit_predefined_vital_signs_backfill_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_staff_member_id uuid;
  v_admin_user_id uuid;
  v_items jsonb;
  v_seed_count int;
  v_working_schedule jsonb := '{
    "days": [
      {"day":"monday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"tuesday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"wednesday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"thursday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"friday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"saturday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"sunday","is_working_day":false}
    ]
  }'::jsonb;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE email = 'pvs-backfill-admin';

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );

  v_result := public.bootstrap_finish_setup(
    'PVS Backfill Clinic',
    'Main',
    jsonb_build_array(
      jsonb_build_object(
        'username', 'pvs-backfill-admin',
        'password', 'finish-pass-1',
        'full_name', 'PVS Admin',
        'role', 'administrator'
      )
    ),
    '{}'::jsonb,
    NULL,
    'USD',
    'UTC',
    'PVSB',
    '1 Catalog Way',
    '+1-555-0700',
    'https://maps.example/pvs',
    v_working_schedule
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'BE-007 setup bootstrap_finish_setup failed: %', COALESCE(v_result.error_code, '?');
  END IF;

  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;
  v_staff_member_id := (v_result.data -> 'staff_member_ids' ->> 0)::uuid;

  -- Read staff auth_user_id as superuser: JWT still identifies bootstrap admin, so RLS
  -- blocks cross-staff reads and list_predefined_vital_signs would get FORBIDDEN.
  PERFORM set_config('role', 'postgres', true);
  SELECT sm.auth_user_id
  INTO v_admin_user_id
  FROM public.staff_members sm
  WHERE sm.id = v_staff_member_id;
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_user_id::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_staff_member_id::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  -- ---------------------------------------------------------------------------
  -- BE-007 — list_predefined_vital_signs returns catalog seeds after org bootstrap
  -- Migration: 20260703120000_backfill_predefined_vital_signs.sql
  -- ---------------------------------------------------------------------------
  v_result := public.list_predefined_vital_signs();
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_predefined_vital_signs_backfill_results VALUES (
    'BE_007_list_predefined_vital_signs_has_all_catalog_seeds',
    v_result.success
      AND jsonb_array_length(v_items) >= 7
      AND NOT EXISTS (
        SELECT 1
        FROM (
          VALUES
            ('Blood Pressure'),
            ('Heart Rate'),
            ('Temperature'),
            ('Respiratory Rate'),
            ('Oxygen Saturation'),
            ('Weight'),
            ('Height')
        ) AS expected(name)
        WHERE NOT EXISTS (
          SELECT 1
          FROM jsonb_array_elements(v_items) item
          WHERE lower(trim(item ->> 'name')) = lower(trim(expected.name))
        )
      ),
    'count=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ---------------------------------------------------------------------------
  -- BE-007 — catalog seeds include expected default units
  -- ---------------------------------------------------------------------------
  v_result := public.list_predefined_vital_signs();
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_predefined_vital_signs_backfill_results VALUES (
    'BE_007_catalog_seeds_have_expected_default_units',
    v_result.success
      AND NOT EXISTS (
        SELECT 1
        FROM (
          VALUES
            ('Blood Pressure', 'mmHg'),
            ('Heart Rate', 'bpm'),
            ('Temperature', '°C'),
            ('Respiratory Rate', '/min'),
            ('Oxygen Saturation', '%'),
            ('Weight', 'kg'),
            ('Height', 'cm')
        ) AS expected(name, default_unit)
        WHERE NOT EXISTS (
          SELECT 1
          FROM jsonb_array_elements(v_items) item
          WHERE lower(trim(item ->> 'name')) = lower(trim(expected.name))
            AND item ->> 'default_unit' = expected.default_unit
        )
      ),
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ---------------------------------------------------------------------------
  -- BE-007 — seed_organization_catalog_defaults backfills missing catalog rows
  -- ---------------------------------------------------------------------------
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.predefined_vital_signs
  SET is_deleted = true, deleted_at = now()
  WHERE organization_id = v_org_id AND is_deleted = false;

  PERFORM auth_internal.seed_organization_catalog_defaults(v_org_id);

  SELECT count(*)::int
  INTO v_seed_count
  FROM public.predefined_vital_signs pvs
  WHERE pvs.organization_id = v_org_id
    AND pvs.is_deleted = false;

  INSERT INTO visit_predefined_vital_signs_backfill_results VALUES (
    'BE_007_seed_organization_catalog_defaults_backfills_missing',
    v_seed_count = 7,
    'count=' || v_seed_count::text
  );

  -- ---------------------------------------------------------------------------
  -- BE-007 — seed_organization_catalog_defaults is idempotent
  -- ---------------------------------------------------------------------------
  PERFORM auth_internal.seed_organization_catalog_defaults(v_org_id);

  INSERT INTO visit_predefined_vital_signs_backfill_results VALUES (
    'BE_007_seed_organization_catalog_defaults_idempotent',
    (
      SELECT count(*)::int
      FROM public.predefined_vital_signs pvs
      WHERE pvs.organization_id = v_org_id
        AND pvs.is_deleted = false
    ) = v_seed_count,
    'count=' || v_seed_count::text
  );

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_user_id::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_staff_member_id::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_result := public.list_predefined_vital_signs();
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO visit_predefined_vital_signs_backfill_results VALUES (
    'BE_007_list_predefined_vital_signs_after_backfill',
    v_result.success AND jsonb_array_length(v_items) = 7,
    'count=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_failed FROM visit_predefined_vital_signs_backfill_results WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM visit_predefined_vital_signs_backfill_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'visit_predefined_vital_signs_backfill: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
