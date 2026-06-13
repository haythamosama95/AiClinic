-- V1-3 patient management: advanced search tests.
-- Covers pagination, LIKE injection, empty results, ordering, response schema.
-- Run: psql ... -v ON_ERROR_STOP=1 -f backend/tests/patient_management_search_advanced.sql

BEGIN;

CREATE TEMP TABLE patient_search_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_owner_user uuid := 'a4000000-0000-4000-8000-000000000001';
  v_owner_staff uuid := 'b4000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_main uuid;
  v_branch_second uuid;
  v_items jsonb;
  v_total int;
  v_first_name text;
  v_second_name text;
  v_item jsonb;
  v_patient_underscore uuid;
  v_patient_backslash uuid;
  v_patient_percent uuid;
  v_duplicate_name_first uuid;
  v_duplicate_name_second uuid;
  v_page_one_id uuid;
  v_page_two_id uuid;
  v_repeat_page_one_id uuid;
  v_repeat_page_two_id uuid;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE id = v_owner_user;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES (v_owner_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'search-owner',
    extensions.crypt('pw', extensions.gen_salt('bf')), now(), now(), now())
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bootstrap_user::text, 'role', 'authenticated')::text,
    true
  );
  v_result := public.bootstrap_create_organization('Search Clinic', '{}'::jsonb, NULL, 'USD', 'UTC');
  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'SM', NULL);
  v_branch_main := (v_result.data ->> 'branch_id')::uuid;
  v_result := public.bootstrap_create_branch(v_org_id, 'Second', NULL, NULL, 'S2', NULL);
  v_branch_second := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES (v_owner_staff, v_owner_user, 'Search Owner', 'administrator', false, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES
    (v_owner_staff, v_branch_main, true, v_bootstrap_user, v_bootstrap_user),
    (v_owner_staff, v_branch_second, false, v_bootstrap_user, v_bootstrap_user);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text || ',' || v_branch_second::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  -- ===========================================================================
  -- SEED TEST DATA: Insert patients with specific names for ordering tests
  -- ===========================================================================
  PERFORM public.create_patient(v_branch_main, 'Alpha Patient', '201000000301', NULL, NULL, NULL, NULL, false);
  PERFORM public.create_patient(v_branch_main, 'Bravo Patient', '201000000302', NULL, NULL, NULL, NULL, false);
  PERFORM public.create_patient(v_branch_main, 'Charlie Patient', '201000000303', NULL, NULL, NULL, NULL, false);
  PERFORM public.create_patient(v_branch_main, 'Delta Patient', '201000000304', NULL, NULL, NULL, NULL, false);
  PERFORM public.create_patient(v_branch_main, 'Echo Patient', '201000000305', NULL, NULL, NULL, NULL, false);
  PERFORM public.create_patient(v_branch_second, 'Foxtrot Patient', '201000000306', NULL, NULL, NULL, NULL, false);
  PERFORM public.create_patient(v_branch_second, 'Golf Patient', '201000000307', NULL, NULL, NULL, NULL, false);

  -- Special characters patients for LIKE escape tests.
  v_result := public.create_patient(v_branch_main, 'Test_Under_Score', '201000000308', NULL, NULL, NULL, NULL, false);
  v_patient_underscore := (v_result.data ->> 'patient_id')::uuid;

  v_result := public.create_patient(v_branch_main, 'Back\Slash\Test', '201000000309', NULL, NULL, NULL, NULL, false);
  v_patient_backslash := (v_result.data ->> 'patient_id')::uuid;

  v_result := public.create_patient(v_branch_main, '50% Discount Patient', '201000000310', NULL, NULL, NULL, NULL, false);
  v_patient_percent := (v_result.data ->> 'patient_id')::uuid;

  -- Prefix vs substring ordering: "Alpha" matches start and middle of different names.
  PERFORM public.create_patient(v_branch_main, 'Alpha Prefix Target', '201000000311', NULL, NULL, NULL, NULL, false);
  PERFORM public.create_patient(v_branch_main, 'ZZZ Alpha Middle', '201000000312', NULL, NULL, NULL, NULL, false);

  -- Duplicate full names for stable pagination tiebreaker tests (L1).
  v_result := public.create_patient(v_branch_main, 'Same Name Patient', '201000000313', NULL, NULL, NULL, NULL, false);
  v_duplicate_name_first := (v_result.data ->> 'patient_id')::uuid;
  v_result := public.create_patient(v_branch_main, 'Same Name Patient', '201000000314', NULL, NULL, NULL, NULL, false);
  v_duplicate_name_second := (v_result.data ->> 'patient_id')::uuid;

  -- ===========================================================================
  -- SEARCH ORDERING: results sorted alphabetically by full_name
  -- ===========================================================================

  v_result := public.search_patients(NULL, 'branch', v_branch_main, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  v_first_name := v_items -> 0 ->> 'full_name';
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_results_alphabetical_order',
    v_result.success AND (v_first_name LIKE '50%' OR v_first_name = 'Alpha Patient'),
    'first=' || COALESCE(v_first_name, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- SEARCH RESPONSE SCHEMA: items contain all required fields
  -- ===========================================================================

  v_result := public.search_patients('Alpha', 'branch', v_branch_main, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  v_item := v_items -> 0;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_item_has_id',
    v_item ? 'id',
    'has_id=' || (v_item ? 'id')::text
  );
  INSERT INTO patient_search_results VALUES (
    'search_item_has_full_name',
    v_item ? 'full_name',
    'has_full_name=' || (v_item ? 'full_name')::text
  );
  INSERT INTO patient_search_results VALUES (
    'search_item_has_phone',
    v_item ? 'phone',
    'has_phone=' || (v_item ? 'phone')::text
  );
  INSERT INTO patient_search_results VALUES (
    'search_item_has_branch_name',
    v_item ? 'branch_name',
    'has_branch_name=' || (v_item ? 'branch_name')::text
  );
  INSERT INTO patient_search_results VALUES (
    'search_item_has_branch_id',
    v_item ? 'branch_id',
    'has_branch_id=' || (v_item ? 'branch_id')::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Response has total_count, limit, offset.
  v_result := public.search_patients(NULL, 'organization', NULL, 5, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_response_has_total_count',
    v_result.data ? 'total_count' AND (v_result.data ->> 'total_count')::int >= 7,
    'total=' || COALESCE(v_result.data ->> 'total_count', '<null>')
  );
  INSERT INTO patient_search_results VALUES (
    'search_response_has_limit',
    v_result.data ? 'limit' AND (v_result.data ->> 'limit')::int = 5,
    'limit=' || COALESCE(v_result.data ->> 'limit', '<null>')
  );
  INSERT INTO patient_search_results VALUES (
    'search_response_has_offset',
    v_result.data ? 'offset' AND (v_result.data ->> 'offset')::int = 0,
    'offset=' || COALESCE(v_result.data ->> 'offset', '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- PAGINATION: actual offset behavior
  -- ===========================================================================

  -- First page (limit=3, offset=0).
  v_result := public.search_patients(NULL, 'organization', NULL, 3, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  v_total := (v_result.data ->> 'total_count')::int;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'pagination_first_page_returns_limit_items',
    v_result.success AND jsonb_array_length(v_items) = 3,
    'items=' || jsonb_array_length(v_items)::text
  );
  INSERT INTO patient_search_results VALUES (
    'pagination_total_count_reflects_all',
    v_total >= 10,
    'total=' || v_total::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Second page (limit=3, offset=3) should have different items.
  v_result := public.search_patients(NULL, 'organization', NULL, 3, 3);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'pagination_second_page_has_items',
    v_result.success AND jsonb_array_length(v_items) = 3,
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Offset beyond total returns empty.
  v_result := public.search_patients(NULL, 'organization', NULL, 25, 9999);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'pagination_beyond_total_empty',
    v_result.success AND jsonb_array_length(v_items) = 0,
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Negative offset treated as 0.
  v_result := public.search_patients(NULL, 'organization', NULL, 25, -5);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'pagination_negative_offset_becomes_zero',
    v_result.success AND (v_result.data ->> 'offset')::int = 0,
    'offset=' || COALESCE(v_result.data ->> 'offset', '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- NULL limit defaults to 25.
  v_result := public.search_patients(NULL, 'organization', NULL, NULL, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'pagination_null_limit_defaults_25',
    v_result.success AND (v_result.data ->> 'limit')::int = 25,
    'limit=' || COALESCE(v_result.data ->> 'limit', '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- LIKE INJECTION: underscore escape
  -- ===========================================================================

  v_result := public.search_patients('_Under_', 'organization', NULL, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_underscore_escaped',
    v_result.success
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) item WHERE (item ->> 'id')::uuid = v_patient_underscore
      ),
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Underscore should NOT match single-character wildcard (e.g. "aunder" would match if unescaped).
  v_result := public.search_patients('_Under_', 'organization', NULL, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_underscore_not_wildcard',
    jsonb_array_length(v_items) <= 1,
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- LIKE INJECTION: percent escape
  -- ===========================================================================

  v_result := public.search_patients('50%', 'organization', NULL, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_percent_escaped_finds_target',
    v_result.success
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) item WHERE (item ->> 'id')::uuid = v_patient_percent
      ),
    'items=' || jsonb_array_length(v_items)::text
  );
  INSERT INTO patient_search_results VALUES (
    'search_percent_does_not_match_all',
    jsonb_array_length(v_items) <= 1,
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- LIKE INJECTION: backslash escape
  -- ===========================================================================

  v_result := public.search_patients('k\Sl', 'organization', NULL, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_backslash_escaped',
    v_result.success
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) item WHERE (item ->> 'id')::uuid = v_patient_backslash
      ),
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- EMPTY RESULT SET
  -- ===========================================================================

  v_result := public.search_patients('ZZZZNONEXISTENT', 'organization', NULL, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  v_total := (v_result.data ->> 'total_count')::int;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_no_match_returns_empty_items',
    v_result.success AND jsonb_array_length(v_items) = 0,
    'items=' || jsonb_array_length(v_items)::text
  );
  INSERT INTO patient_search_results VALUES (
    'search_no_match_total_count_zero',
    v_total = 0,
    'total=' || v_total::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- PHONE PREFIX SEARCH: only digits
  -- ===========================================================================

  -- Phone prefix "2010000003" should match multiple seeded patients.
  v_result := public.search_patients('2010000003', 'organization', NULL, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_phone_prefix_matches_multiple',
    v_result.success AND jsonb_array_length(v_items) >= 5,
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Phone prefix that matches exactly one.
  v_result := public.search_patients('201000000301', 'organization', NULL, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_phone_exact_match_one',
    v_result.success AND jsonb_array_length(v_items) = 1,
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- CASE-INSENSITIVE NAME SEARCH
  -- ===========================================================================

  v_result := public.search_patients('ALPHA', 'organization', NULL, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_name_case_insensitive',
    v_result.success AND jsonb_array_length(v_items) >= 1
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) item WHERE lower(item ->> 'full_name') LIKE '%alpha%'
      ),
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Mixed case.
  v_result := public.search_patients('cHaRlIe', 'organization', NULL, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_name_mixed_case',
    v_result.success AND jsonb_array_length(v_items) >= 1,
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- BRANCH SCOPE: unassigned branch rejected
  -- ===========================================================================

  -- Use JWT with only main branch, try to search second branch.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );
  v_result := public.search_patients(NULL, 'branch', v_branch_second, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_branch_unassigned_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Restore full branch access.
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_owner_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_main::text || ',' || v_branch_second::text,
      'staff_member_id', v_owner_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  -- ===========================================================================
  -- ORGANIZATION SCOPE: includes all branches
  -- ===========================================================================

  v_result := public.search_patients('Foxtrot', 'organization', NULL, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_org_scope_finds_other_branch',
    v_result.success AND jsonb_array_length(v_items) >= 1,
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Branch scope of main should NOT find second branch patients.
  v_result := public.search_patients('Foxtrot', 'branch', v_branch_main, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_branch_scope_excludes_other_branch',
    v_result.success AND jsonb_array_length(v_items) = 0,
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- NULL QUERY RETURNS ALL NON-ARCHIVED
  -- ===========================================================================

  v_result := public.search_patients(NULL, 'organization', NULL, 100, 0);
  v_total := (v_result.data ->> 'total_count')::int;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_null_query_returns_all',
    v_result.success AND v_total >= 10,
    'total=' || v_total::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Empty-string query treated same as NULL.
  v_result := public.search_patients('', 'organization', NULL, 100, 0);
  v_total := (v_result.data ->> 'total_count')::int;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_empty_string_query_returns_all',
    v_result.success AND v_total >= 10,
    'total=' || v_total::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Whitespace-only query treated same as NULL.
  v_result := public.search_patients('   ', 'organization', NULL, 100, 0);
  v_total := (v_result.data ->> 'total_count')::int;
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_whitespace_query_returns_all',
    v_result.success AND v_total >= 10,
    'total=' || v_total::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- SCOPE VALIDATION
  -- ===========================================================================

  -- Scope with uppercase.
  v_result := public.search_patients(NULL, 'BRANCH', v_branch_main, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_scope_case_insensitive',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Scope with whitespace.
  v_result := public.search_patients(NULL, ' organization ', NULL, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_scope_trimmed',
    v_result.success,
    COALESCE(v_result.error_code, 'ok')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Invalid scope.
  v_result := public.search_patients(NULL, 'global', NULL, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_invalid_scope_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Empty scope.
  v_result := public.search_patients(NULL, '', NULL, 25, 0);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_empty_scope_rejected',
    NOT v_result.success AND v_result.error_code = 'INVALID_INPUT',
    COALESCE(v_result.error_code, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- SEARCH QUERY: partial name match (contains, not just prefix)
  -- ===========================================================================

  v_result := public.search_patients('Patient', 'organization', NULL, 100, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_contains_not_prefix_only',
    v_result.success AND jsonb_array_length(v_items) >= 7,
    'items=' || jsonb_array_length(v_items)::text
  );
  PERFORM set_config('role', 'authenticated', true);

  -- Prefix matches should appear before substring-only matches.
  v_result := public.search_patients('Alpha', 'branch', v_branch_main, 25, 0);
  v_items := COALESCE(v_result.data -> 'items', '[]'::jsonb);
  v_first_name := v_items -> 0 ->> 'full_name';
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_prefix_matches_rank_before_substring',
    v_result.success
      AND jsonb_array_length(v_items) >= 2
      AND v_first_name IN ('Alpha Patient', 'Alpha Prefix Target')
      AND NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_items) WITH ORDINALITY AS t(item, ord)
        WHERE ord = 1
          AND lower(item ->> 'full_name') NOT LIKE 'alpha%'
      ),
    'first=' || COALESCE(v_first_name, '<null>')
  );
  PERFORM set_config('role', 'authenticated', true);

  -- ===========================================================================
  -- L1: duplicate names paginate with stable id tiebreaker (no overlap/reorder)
  -- ===========================================================================

  v_result := public.search_patients('Same Name Patient', 'branch', v_branch_main, 1, 0);
  v_page_one_id := (COALESCE(v_result.data -> 'items', '[]'::jsonb) -> 0 ->> 'id')::uuid;

  v_result := public.search_patients('Same Name Patient', 'branch', v_branch_main, 1, 1);
  v_page_two_id := (COALESCE(v_result.data -> 'items', '[]'::jsonb) -> 0 ->> 'id')::uuid;

  v_result := public.search_patients('Same Name Patient', 'branch', v_branch_main, 1, 0);
  v_repeat_page_one_id := (COALESCE(v_result.data -> 'items', '[]'::jsonb) -> 0 ->> 'id')::uuid;

  v_result := public.search_patients('Same Name Patient', 'branch', v_branch_main, 1, 1);
  v_repeat_page_two_id := (COALESCE(v_result.data -> 'items', '[]'::jsonb) -> 0 ->> 'id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO patient_search_results VALUES (
    'search_duplicate_name_pages_do_not_overlap',
    v_page_one_id IS NOT NULL
      AND v_page_two_id IS NOT NULL
      AND v_page_one_id <> v_page_two_id
      AND v_page_one_id IN (v_duplicate_name_first, v_duplicate_name_second)
      AND v_page_two_id IN (v_duplicate_name_first, v_duplicate_name_second),
    'page1=' || COALESCE(v_page_one_id::text, '<null>') || ' page2=' || COALESCE(v_page_two_id::text, '<null>')
  );
  INSERT INTO patient_search_results VALUES (
    'search_duplicate_name_pagination_stable_across_requests',
    v_page_one_id = v_repeat_page_one_id AND v_page_two_id = v_repeat_page_two_id,
    'first=' || COALESCE(v_repeat_page_one_id::text, '<null>') || ' second=' || COALESCE(v_repeat_page_two_id::text, '<null>')
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
  SELECT count(*)::int INTO v_failed FROM patient_search_results WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM patient_search_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'patient_management_search_advanced: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
