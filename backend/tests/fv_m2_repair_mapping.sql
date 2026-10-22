-- FV-M2 (FR02) — role-repair mapping table is created ahead of the repair
-- migration, locked down, and safe to re-apply.
-- Run: psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/fv_m2_repair_mapping.sql

BEGIN;

CREATE TEMP TABLE fv_m2_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_rls boolean;
  v_policy_count int;
  v_policy_qual text;
  v_exposed text[];
  v_role text;
  v_ok boolean;
BEGIN
  SELECT c.relrowsecurity INTO v_rls
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'ai_internal' AND c.relname = 'membership_role_repair_mapping';

  SELECT count(*), max(pg_get_expr(p.polqual, p.polrelid)) INTO v_policy_count, v_policy_qual
  FROM pg_policy p
  WHERE p.polrelid = 'ai_internal.membership_role_repair_mapping'::regclass
    AND p.polname = 'membership_role_repair_mapping_deny_all';

  INSERT INTO fv_m2_results VALUES (
    'FV-M2: mapping table has RLS enabled and the deny-all policy',
    COALESCE(v_rls, false) AND v_policy_count = 1 AND v_policy_qual = 'false',
    'rls=' || COALESCE(v_rls::text, '<missing>') || ' policies=' || v_policy_count
      || ' qual=' || COALESCE(v_policy_qual, '<none>')
  );

  v_exposed := ARRAY[]::text[];
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF has_table_privilege(v_role, 'ai_internal.membership_role_repair_mapping',
         'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
      v_exposed := v_exposed || v_role;
    END IF;
  END LOOP;
  -- PUBLIC grants appear as an ACL entry with grantee 0.
  SELECT EXISTS (
    SELECT 1
    FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
    WHERE c.oid = 'ai_internal.membership_role_repair_mapping'::regclass
      AND a.grantee = 0
  ) INTO v_ok;
  IF v_ok THEN
    v_exposed := v_exposed || 'PUBLIC';
  END IF;

  INSERT INTO fv_m2_results VALUES (
    'FV-M2: mapping table grants nothing to anon, authenticated, service_role or PUBLIC',
    cardinality(v_exposed) = 0,
    'exposed=' || COALESCE(array_to_string(v_exposed, ','), '')
  );
END;
$$;

-- Re-applying the table DDL (as a retry after an aborted repair would) must
-- not fail and must leave a single policy.
DO $$
DECLARE
  v_policy_count int;
BEGIN
  CREATE TABLE IF NOT EXISTS ai_internal.membership_role_repair_mapping (
    user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
    approved_role public.staff_role NOT NULL,
    approved_by text NOT NULL,
    approved_note text,
    approved_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, organization_id),
    CONSTRAINT membership_role_repair_mapping_no_admin_add
      CHECK (approved_role <> 'administrator')
  );
  ALTER TABLE ai_internal.membership_role_repair_mapping ENABLE ROW LEVEL SECURITY;
  DROP POLICY IF EXISTS membership_role_repair_mapping_deny_all ON ai_internal.membership_role_repair_mapping;
  CREATE POLICY membership_role_repair_mapping_deny_all ON ai_internal.membership_role_repair_mapping
    FOR ALL USING (false);

  SELECT count(*) INTO v_policy_count
  FROM pg_policy p
  WHERE p.polrelid = 'ai_internal.membership_role_repair_mapping'::regclass;

  INSERT INTO fv_m2_results VALUES (
    'FV-M2: mapping table DDL is idempotent on re-apply',
    v_policy_count = 1,
    'policies=' || v_policy_count
  );
END;
$$;

-- The mapping can never add administrator authority.
DO $$
DECLARE
  v_blocked boolean := false;
BEGIN
  BEGIN
    INSERT INTO ai_internal.membership_role_repair_mapping (user_id, organization_id, approved_role, approved_by)
    VALUES (gen_random_uuid(), gen_random_uuid(), 'administrator', 'fv-m2-test');
  EXCEPTION
    WHEN check_violation THEN
      v_blocked := true;
  END;
  INSERT INTO fv_m2_results VALUES (
    'FV-M2: mapping rejects approved_role administrator',
    v_blocked,
    CASE WHEN v_blocked THEN 'rejected' ELSE 'accepted' END
  );
END;
$$;

COMMIT;

SELECT test_name, passed, detail
FROM fv_m2_results
ORDER BY test_name;
