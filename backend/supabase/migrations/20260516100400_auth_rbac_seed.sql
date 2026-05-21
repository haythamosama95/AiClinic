-- =============================================================================
-- MIGRATION 5 of 5: Initial data (permission matrix + bootstrap admin login)
-- =============================================================================
--
-- WHAT THIS FILE DOES:
--   1) Seeds the roles_permissions table with default grants per job title.
--   2) Creates the first login account (bootstrap administrator) if missing.
--
-- KEY CONCEPTS:
--   • SEED data = starting rows for a fresh database, not created by the app UI.
--   • ON CONFLICT ... DO UPDATE = safe to re-run migration; updates existing rows.
--   • Bootstrap admin can log in before any organization exists (see setup_required claim).
--
-- SECURITY NOTE:
--   Default password below is for local/dev only. Change it on first sign-in in production.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Permission matrix: which role gets which permission_key
-- -----------------------------------------------------------------------------
-- permission_key strings are contracts with the Flutter app (see specs/002-auth-rbac).
-- Many keys reference future features (patients, appointments); granted now so roles
-- are complete when those modules ship. is_granted = false rows are not used yet.
INSERT INTO public.roles_permissions (role, permission_key, is_granted)
VALUES
  -- owner: full access across clinic operations
  ('owner', 'settings.manage_staff', true),
  ('owner', 'settings.manage_branches', true),
  ('owner', 'patients.view', true),
  ('owner', 'patients.create', true),
  ('owner', 'patients.edit', true),
  ('owner', 'patients.delete', true),
  ('owner', 'appointments.create', true),
  ('owner', 'appointments.cancel', true),
  ('owner', 'visits.create', true),
  ('owner', 'visits.edit_soap', true),
  ('owner', 'invoices.create', true),
  ('owner', 'invoices.apply_discount', true),
  ('owner', 'invoices.apply_discount_above_threshold', true),
  ('owner', 'shifts.manage', true),
  ('owner', 'analytics.view', true),
  ('owner', 'ai.access', true),
  -- administrator: same clinical/billing grants as owner for V1-1 matrix
  ('administrator', 'settings.manage_staff', true),
  ('administrator', 'settings.manage_branches', true),
  ('administrator', 'patients.view', true),
  ('administrator', 'patients.create', true),
  ('administrator', 'patients.edit', true),
  ('administrator', 'patients.delete', true),
  ('administrator', 'appointments.create', true),
  ('administrator', 'appointments.cancel', true),
  ('administrator', 'visits.create', true),
  ('administrator', 'visits.edit_soap', true),
  ('administrator', 'invoices.create', true),
  ('administrator', 'invoices.apply_discount', true),
  ('administrator', 'invoices.apply_discount_above_threshold', true),
  ('administrator', 'shifts.manage', true),
  ('administrator', 'analytics.view', true),
  ('administrator', 'ai.access', true),
  -- doctor: clinical + AI; no staff/branch settings
  ('doctor', 'patients.view', true),
  ('doctor', 'patients.create', true),
  ('doctor', 'patients.edit', true),
  ('doctor', 'patients.delete', true),
  ('doctor', 'appointments.create', true),
  ('doctor', 'appointments.cancel', true),
  ('doctor', 'visits.create', true),
  ('doctor', 'visits.edit_soap', true),
  ('doctor', 'ai.access', true),
  -- receptionist: front desk + billing discounts
  ('receptionist', 'patients.view', true),
  ('receptionist', 'patients.create', true),
  ('receptionist', 'patients.edit', true),
  ('receptionist', 'patients.delete', true),
  ('receptionist', 'appointments.create', true),
  ('receptionist', 'appointments.cancel', true),
  ('receptionist', 'invoices.create', true),
  ('receptionist', 'invoices.apply_discount', true),
  ('receptionist', 'invoices.apply_discount_above_threshold', true),
  -- lab_staff: read-only patients for V1-1
  ('lab_staff', 'patients.view', true)
ON CONFLICT (role, permission_key) DO UPDATE
SET is_granted = EXCLUDED.is_granted,
    is_deleted = false;

-- -----------------------------------------------------------------------------
-- Bootstrap administrator account (fixed UUIDs for repeatable local installs)
-- -----------------------------------------------------------------------------
-- DO block = anonymous PL/pgSQL script run once during migration.
-- Creates auth.users + auth.identities (login) and staff_members (clinic profile).
DO $$
DECLARE
  v_user_id uuid := 'a0000000-0000-4000-8000-000000000001';   -- Stable auth user id
  v_staff_id uuid := 'b0000000-0000-4000-8000-000000000001';  -- Stable staff_members id
  v_email text := 'admin@admin';
  v_password text := 'admin';
  v_full_name text := 'Clinic Administrator';
BEGIN
  -- Login row in Supabase Auth (skip if already present from prior migration run)
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_user_id) THEN
    INSERT INTO auth.users (
      id,
      instance_id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      confirmation_token,
      recovery_token,
      email_change,
      email_change_token_new,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    )
    VALUES (
      v_user_id,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      v_email,
      extensions.crypt(v_password, extensions.gen_salt('bf')),
      now(),
      '',
      '',
      '',
      '',
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
      jsonb_build_object('full_name', v_full_name),
      now(),
      now()
    );

    -- identities links the user to the "email" sign-in provider
    INSERT INTO auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      provider_id,
      last_sign_in_at,
      created_at,
      updated_at
    )
    VALUES (
      gen_random_uuid(),
      v_user_id,
      jsonb_build_object('sub', v_user_id::text, 'email', v_email),
      'email',
      v_email,
      now(),
      now(),
      now()
    );
  END IF;

  -- Staff profile: administrator role + bootstrap flag (can create org/branch before setup)
  IF NOT EXISTS (SELECT 1 FROM public.staff_members WHERE id = v_staff_id) THEN
    INSERT INTO public.staff_members (
      id,
      auth_user_id,
      full_name,
      role,
      is_bootstrap_admin,
      created_by,
      updated_by
    )
    VALUES (
      v_staff_id,
      v_user_id,
      v_full_name,
      'administrator',
      true,
      v_user_id,
      v_user_id
    );
  END IF;
END;
$$;
