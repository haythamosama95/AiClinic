-- =============================================================================
-- MIGRATION 1 of 5: Core database schema (tables, types, indexes)
-- =============================================================================
--
-- WHAT IS A MIGRATION?
--   A migration is a versioned SQL script that changes the database structure.
--   Supabase runs these files in filename order (the timestamp prefix) exactly
--   once when you start the local stack or deploy. Think of it as "git commits"
--   for your database schema.
--
-- WHAT THIS FILE DOES:
--   Creates all tables needed for AiClinic V1-1 authentication and role-based
--   access control (RBAC): clinic organization, branches, staff, permissions,
--   audit trail, settings, and subscription cache.
--
-- KEY CONCEPTS:
--   • PostgreSQL = the database engine Supabase uses.
--   • `public` schema = where our app tables live (vs `auth` for login users).
--   • `auth.users` = Supabase/GoTrue table of login accounts (email + password).
--   • UUID = unique random ID for each row (better than auto-increment numbers).
--   • Soft delete = we set `is_deleted = true` instead of physically removing rows.
--   • RLS (Row Level Security) = turned ON here; actual rules come in migration 3.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Extension: pgcrypto
-- -----------------------------------------------------------------------------
-- Adds cryptographic helpers (e.g. password hashing via `crypt()`).
-- `WITH SCHEMA extensions` keeps Supabase's extension namespace tidy.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- -----------------------------------------------------------------------------
-- ENUM: staff_role
-- -----------------------------------------------------------------------------
-- A fixed list of job titles. PostgreSQL rejects any value not in this list.
-- Used on staff_members and roles_permissions so roles stay consistent app-wide.
CREATE TYPE public.staff_role AS ENUM (
  'owner',           -- Clinic owner; highest privilege
  'administrator',   -- Day-to-day admin (staff, branches, settings)
  'doctor',          -- Clinical staff
  'receptionist',    -- Front desk
  'lab_staff'        -- Lab / limited read access
);

-- -----------------------------------------------------------------------------
-- COMPOSITE TYPE: rpc_result
-- -----------------------------------------------------------------------------
-- Standard shape returned by "RPC" functions (remote procedure calls) that the
-- Flutter app calls via Supabase. One return type instead of ad-hoc JSON.
--   success        → did the operation succeed?
--   data           → payload on success (JSON object)
--   error_code     → machine-readable code for the client (e.g. ORG_ALREADY_EXISTS)
--   error_message  → human-readable explanation
CREATE TYPE public.rpc_result AS (
  success boolean,
  data jsonb,
  error_code text,
  error_message text
);

-- -----------------------------------------------------------------------------
-- TABLE: organizations
-- -----------------------------------------------------------------------------
-- One clinic "tenant" per installation in V1-1. Holds subscription metadata
-- and org-wide settings. Branches and staff belong to an organization indirectly.
CREATE TABLE public.organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),  -- Primary key; auto-generated
  name text NOT NULL,                             -- Display name, e.g. "Sunrise Dental"
  logo_url text,                                  -- Clinic logo (URL or storage path)
  currency_code text,                             -- ISO 4217, e.g. EGP, USD
  timezone text,                                  -- IANA timezone, e.g. Africa/Cairo
  subscription_tier text NOT NULL DEFAULT 'standard',
  subscription_valid_until timestamptz,           -- When paid plan expires (nullable)
  settings_json jsonb NOT NULL DEFAULT '{}'::jsonb, -- Flexible key/value settings
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),     -- Who created (login user id)
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,      -- Soft delete flag
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id)
);

-- -----------------------------------------------------------------------------
-- TABLE: branches
-- -----------------------------------------------------------------------------
-- Physical or logical locations under one organization (e.g. "Main", "North").
-- Staff are assigned to branches via staff_branch_assignments.
CREATE TABLE public.branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id),  -- Parent org
  name text NOT NULL,
  code text,                                      -- Short internal or business branch code
  address text,
  phone text,
  maps_url text,                                  -- GPS / maps link for the branch location
  is_active boolean NOT NULL DEFAULT true,        -- Inactive branches hidden from UI
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id)
);

-- Index speeds up queries like "all branches for this organization"
CREATE INDEX branches_organization_id_idx ON public.branches (organization_id);

-- -----------------------------------------------------------------------------
-- TABLE: staff_members
-- -----------------------------------------------------------------------------
-- Links a Supabase login (auth.users) to clinic identity: name, role, flags.
-- `auth_user_id` is UNIQUE: one login account = one staff row.
-- `is_bootstrap_admin` = the first installer who can create org/branch before setup.
CREATE TABLE public.staff_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id uuid NOT NULL UNIQUE REFERENCES auth.users (id),
  full_name text NOT NULL,
  role public.staff_role NOT NULL,
  phone text,
  is_active boolean NOT NULL DEFAULT true,        -- Deactivated staff cannot log in meaningfully
  is_bootstrap_admin boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id)
);

-- -----------------------------------------------------------------------------
-- TABLE: staff_branch_assignments
-- -----------------------------------------------------------------------------
-- Many-to-many: which branches a staff member may work in.
-- `is_primary` = default branch in the UI branch selector.
-- UNIQUE (staff_member_id, branch_id) prevents duplicate assignments.
CREATE TABLE public.staff_branch_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_member_id uuid NOT NULL REFERENCES public.staff_members (id),
  branch_id uuid NOT NULL REFERENCES public.branches (id),
  is_primary boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  UNIQUE (staff_member_id, branch_id)
);

CREATE INDEX staff_branch_assignments_staff_idx ON public.staff_branch_assignments (staff_member_id);
CREATE INDEX staff_branch_assignments_branch_idx ON public.staff_branch_assignments (branch_id);

-- -----------------------------------------------------------------------------
-- TABLE: roles_permissions
-- -----------------------------------------------------------------------------
-- Permission matrix: for each staff_role, which permission_key is granted.
-- The Flutter app reads this (via API) to show/hide UI; RPCs/RLS enforce server-side.
-- Example keys: 'patients.view', 'settings.manage_staff' (see seed migration).
CREATE TABLE public.roles_permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role public.staff_role NOT NULL,
  permission_key text NOT NULL,
  is_granted boolean NOT NULL,                      -- false = explicitly denied (future use)
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  UNIQUE (role, permission_key)                   -- One row per role + permission pair
);

-- -----------------------------------------------------------------------------
-- TABLE: audit_log
-- -----------------------------------------------------------------------------
-- Append-only history of sensitive actions (who did what, when).
-- Populated by RPC functions and (later) triggers—not by direct client INSERT.
CREATE TABLE public.audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users (id),        -- Actor (nullable for system actions)
  organization_id uuid REFERENCES public.organizations (id),  -- Tenant scope for RLS (nullable pre-org bootstrap)
  action text NOT NULL,                           -- e.g. 'staff.create', 'organization.bootstrap_create'
  table_name text NOT NULL,                       -- Which table was affected
  record_id uuid,                                 -- Primary key of affected row
  old_data_json jsonb,                            -- Snapshot before change (optional)
  new_data_json jsonb,                            -- Snapshot after change (optional)
  ip_address text,                                -- Reserved for future request metadata
  timestamp timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX audit_log_timestamp_idx ON public.audit_log (timestamp DESC);
CREATE INDEX audit_log_organization_id_idx ON public.audit_log (organization_id);

-- -----------------------------------------------------------------------------
-- TABLE: app_settings
-- -----------------------------------------------------------------------------
-- Key/value configuration per branch (branch_id NULL = org-wide default).
-- value_json stores structured data (numbers, objects, arrays) as JSON.
CREATE TABLE public.app_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id),
  branch_id uuid REFERENCES public.branches (id),
  key text NOT NULL,
  value_json jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id)
);

-- -----------------------------------------------------------------------------
-- TABLE: subscription_cache
-- -----------------------------------------------------------------------------
-- Cached copy of subscription status from an external billing system (future).
-- One row per organization. Login must NOT be blocked if this is stale (per spec).
CREATE TABLE public.subscription_cache (
  organization_id uuid PRIMARY KEY REFERENCES public.organizations (id) ON DELETE CASCADE,
  tier text NOT NULL,
  valid_until timestamptz,
  last_checked_at timestamptz NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- Enable Row Level Security (RLS) on all feature tables
-- -----------------------------------------------------------------------------
-- After this, NO row is visible or writable until a POLICY allows it.
-- Policies are defined in migration 20260516100200_auth_rbac_rls.sql.
-- This is defense-in-depth: even if the Flutter app has a bug, the DB still enforces access.
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_branch_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_cache ENABLE ROW LEVEL SECURITY;
