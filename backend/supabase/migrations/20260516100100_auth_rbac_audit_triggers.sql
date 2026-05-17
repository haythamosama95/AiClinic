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
BEGIN
  -- Drop if re-running migration (idempotent)
  EXECUTE format(
    'DROP TRIGGER IF EXISTS trg_%1$s_set_updated_at ON %1$s',
    v_table_name
  );
  EXECUTE format(
    'CREATE TRIGGER trg_%1$s_set_updated_at
       BEFORE UPDATE ON %1$s
       FOR EACH ROW
       EXECUTE FUNCTION public.set_updated_at()',
    v_table_name
  );

  EXECUTE format(
    'DROP TRIGGER IF EXISTS trg_%1$s_set_audit_user ON %1$s',
    v_table_name
  );
  EXECUTE format(
    'CREATE TRIGGER trg_%1$s_set_audit_user
       BEFORE INSERT OR UPDATE ON %1$s
       FOR EACH ROW
       EXECUTE FUNCTION public.set_audit_user()',
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
