-- =============================================================================
-- B1 slice: installation keystore schema, issuance ledger, and AI config keys.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgsodium;

GRANT USAGE ON SCHEMA pgsodium TO postgres;
GRANT pgsodium_keymaker TO postgres;

CREATE SCHEMA IF NOT EXISTS ai_internal;

REVOKE ALL ON SCHEMA ai_internal FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA ai_internal TO postgres, service_role;

-- -----------------------------------------------------------------------------
-- Config keys (global per installation; no org/branch scope).
-- -----------------------------------------------------------------------------
CREATE TABLE ai_internal.app_settings (
  key text PRIMARY KEY,
  value_json jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id)
);

ALTER TABLE ai_internal.app_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY app_settings_deny_all ON ai_internal.app_settings
  FOR ALL
  USING (false);

INSERT INTO ai_internal.app_settings (key, value_json)
VALUES
  ('ai.aat.lifetime_minutes', '15'::jsonb),
  ('ai.aat.audience', '"ai-platform"'::jsonb),
  ('ai.aat.ver', '"1"'::jsonb),
  ('ai.issuer.rate_limit.ceiling', '100'::jsonb),
  ('ai.issuer.rate_limit.window_seconds', '3600'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Installation signing keys (additive rotation; revocation via revoked_at).
-- -----------------------------------------------------------------------------
CREATE TABLE ai_internal.installation_keys (
  kid text PRIMARY KEY,
  installation_id uuid NOT NULL,
  public_key bytea NOT NULL,
  secret_key bytea NOT NULL,
  algorithm text NOT NULL DEFAULT 'EdDSA',
  valid_from timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id)
);

CREATE INDEX installation_keys_installation_id_idx
  ON ai_internal.installation_keys (installation_id)
  WHERE is_deleted = false;

CREATE INDEX installation_keys_active_idx
  ON ai_internal.installation_keys (installation_id, valid_from DESC)
  WHERE revoked_at IS NULL AND is_deleted = false;

ALTER TABLE ai_internal.installation_keys ENABLE ROW LEVEL SECURITY;

CREATE POLICY installation_keys_deny_all ON ai_internal.installation_keys
  FOR ALL
  USING (false);

-- -----------------------------------------------------------------------------
-- Issuance ledger (one row per minted AAT).
-- -----------------------------------------------------------------------------
CREATE TABLE ai_internal.ai_token_issuance (
  issuance_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  installation_id uuid NOT NULL,
  jti uuid NOT NULL UNIQUE,
  actor_staff_id uuid NOT NULL REFERENCES public.staff_members (id),
  iat timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id)
);

CREATE INDEX ai_token_issuance_actor_iat_idx
  ON ai_internal.ai_token_issuance (actor_staff_id, iat DESC)
  WHERE is_deleted = false;

ALTER TABLE ai_internal.ai_token_issuance ENABLE ROW LEVEL SECURITY;

CREATE POLICY ai_token_issuance_deny_all ON ai_internal.ai_token_issuance
  FOR ALL
  USING (false);
