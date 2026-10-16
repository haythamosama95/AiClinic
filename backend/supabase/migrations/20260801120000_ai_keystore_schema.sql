-- =============================================================================
-- B1 slice: installation keystore schema, issuance ledger, and AI config keys.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgsodium;

GRANT USAGE ON SCHEMA pgsodium TO postgres;
-- Enrollment SECURITY DEFINER owner must hold keymaker to call
-- pgsodium.crypto_sign_new_keypair (§4.2.1 enrollment role).
GRANT pgsodium_keymaker TO postgres;

CREATE SCHEMA IF NOT EXISTS ai_internal;

REVOKE ALL ON SCHEMA ai_internal FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA ai_internal TO postgres;

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
-- One installation id per clinic (§4.2 / §8.1).
-- -----------------------------------------------------------------------------
CREATE TABLE ai_internal.installation_keys (
  kid text PRIMARY KEY,
  installation_id uuid NOT NULL,
  public_key bytea NOT NULL,
  secret_key bytea NOT NULL,
  algorithm text NOT NULL DEFAULT 'EdDSA',
  valid_from timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
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
  ON ai_internal.installation_keys (installation_id, valid_from DESC, kid DESC)
  WHERE revoked_at IS NULL AND is_deleted = false;

CREATE OR REPLACE FUNCTION ai_internal.enforce_single_installation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_existing uuid;
BEGIN
  IF NEW.is_deleted THEN
    RETURN NEW;
  END IF;

  SELECT ik.installation_id
  INTO v_existing
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
    AND ik.kid IS DISTINCT FROM NEW.kid
  ORDER BY ik.valid_from ASC, ik.kid ASC
  LIMIT 1;

  IF v_existing IS NOT NULL AND v_existing IS DISTINCT FROM NEW.installation_id THEN
    RAISE EXCEPTION 'SINGLE_INSTALLATION_VIOLATION'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS installation_keys_single_installation
  ON ai_internal.installation_keys;

CREATE TRIGGER installation_keys_single_installation
  BEFORE INSERT OR UPDATE OF installation_id, is_deleted
  ON ai_internal.installation_keys
  FOR EACH ROW
  EXECUTE FUNCTION ai_internal.enforce_single_installation();

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

-- Base64url helpers shared by keypair export and the AAT issuer.
CREATE OR REPLACE FUNCTION auth_internal.base64url_encode(p_bytes bytea)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT rtrim(
    translate(replace(encode(p_bytes, 'base64'), E'\n', ''), '+/', '-_'),
    '='
  );
$$;

CREATE OR REPLACE FUNCTION auth_internal.base64url_decode(p_text text)
RETURNS bytea
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT decode(
    rpad(
      translate(p_text, '-_', '+/'),
      length(p_text) + ((4 - length(p_text) % 4) % 4),
      '='
    ),
    'base64'
  );
$$;

REVOKE EXECUTE ON FUNCTION auth_internal.base64url_encode(bytea) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth_internal.base64url_decode(text) FROM PUBLIC, anon, authenticated;
