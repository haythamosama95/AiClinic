-- =============================================================================
-- MIGRATION 2 of 5: Automatic audit columns on INSERT/UPDATE
-- =============================================================================
--
-- WHAT THIS FILE DOES:
--   Adds PostgreSQL TRIGGERS so `created_by`, `updated_by`, `created_at`, and
--   `updated_at` are filled automatically—you don't rely on the Flutter app
--   to send them correctly.
--
-- KEY CONCEPTS:
--   • TRIGGER = code that runs automatically before/after a row is inserted or updated.
--   • BEFORE UPDATE trigger = can modify NEW row values before they are saved.
--   • auth.uid() = Supabase function returning the logged-in user's UUID from the JWT.
--   • SECURITY DEFINER = function runs with owner's privileges (can read auth.uid() safely).
--   • regclass = internal PostgreSQL type referring to a table by name.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Trigger function: set_updated_at
-- -----------------------------------------------------------------------------
-- On every UPDATE, stamp `updated_at` with the current time.
-- TG_OP and NEW are built-in trigger variables (operation type, new row version).
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;  -- Must return NEW so the row is actually written
END;
$$;

-- -----------------------------------------------------------------------------
-- Trigger function: set_audit_user
-- -----------------------------------------------------------------------------
-- On INSERT: set created_by, updated_by, created_at, updated_at if not already set.
-- On UPDATE: set updated_by to the current login user.
-- SECURITY DEFINER + search_path = safe, predictable resolution of table names.
CREATE OR REPLACE FUNCTION public.set_audit_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := COALESCE(NEW.created_by, auth.uid());
    NEW.updated_by := COALESCE(NEW.updated_by, auth.uid());
    NEW.created_at := COALESCE(NEW.created_at, now());
    NEW.updated_at := COALESCE(NEW.updated_at, now());
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.updated_by := auth.uid();
  END IF;

  RETURN NEW;
END;
$$;

-- -----------------------------------------------------------------------------
-- Helper: apply_standard_audit_triggers
-- -----------------------------------------------------------------------------
-- Attaches both triggers to any table passed in (e.g. 'public.organizations').
-- Uses dynamic SQL (EXECUTE format) so we don't copy-paste trigger DDL six times.
-- Naming: trg_<table>_set_updated_at, trg_<table>_set_audit_user
CREATE OR REPLACE FUNCTION public.apply_standard_audit_triggers(p_table regclass)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_table_name text := p_table::text;
  v_table_only text;
  trg_updated text;
  trg_audit text;
BEGIN
  -- regclass::text may be schema-qualified (e.g. public.organizations); dots are invalid in trigger names.
  IF position('.' IN v_table_name) > 0 THEN
    v_table_only := split_part(v_table_name, '.', 2);
  ELSE
    v_table_only := v_table_name;
  END IF;

  trg_updated := format('trg_%s_set_updated_at', v_table_only);
  trg_audit := format('trg_%s_set_audit_user', v_table_only);

  EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s', trg_updated, v_table_name);
  EXECUTE format(
    'CREATE TRIGGER %I
       BEFORE UPDATE ON %s
       FOR EACH ROW
       EXECUTE FUNCTION public.set_updated_at()',
    trg_updated,
    v_table_name
  );

  EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s', trg_audit, v_table_name);
  EXECUTE format(
    'CREATE TRIGGER %I
       BEFORE INSERT OR UPDATE ON %s
       FOR EACH ROW
       EXECUTE FUNCTION public.set_audit_user()',
    trg_audit,
    v_table_name
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- Apply triggers to all tables that have standard audit columns
-- -----------------------------------------------------------------------------
-- audit_log is intentionally excluded (it IS the audit trail, not audited itself).
SELECT public.apply_standard_audit_triggers('public.organizations'::regclass);
SELECT public.apply_standard_audit_triggers('public.branches'::regclass);
SELECT public.apply_standard_audit_triggers('public.staff_members'::regclass);
SELECT public.apply_standard_audit_triggers('public.staff_branch_assignments'::regclass);
SELECT public.apply_standard_audit_triggers('public.roles_permissions'::regclass);
SELECT public.apply_standard_audit_triggers('public.app_settings'::regclass);
