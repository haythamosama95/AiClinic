-- Restore ai_internal app_settings to B1 / availability migration defaults.
-- Keeps installation_keys intact so the clinic keypair survives a lab reset.

INSERT INTO ai_internal.app_settings (key, value_json, is_deleted)
VALUES
  ('ai.aat.lifetime_minutes', '15'::jsonb, false),
  ('ai.aat.audience', '"ai-platform"'::jsonb, false),
  ('ai.aat.ver', '"1"'::jsonb, false),
  ('ai.issuer.rate_limit.ceiling', '100'::jsonb, false),
  ('ai.issuer.rate_limit.window_seconds', '3600'::jsonb, false),
  (
    'ai.availability',
    '{"enrolled": false, "platform_base_url": null}'::jsonb,
    false
  )
ON CONFLICT (key) DO UPDATE SET
  value_json = EXCLUDED.value_json,
  updated_at = NULL,
  updated_by = NULL,
  is_deleted = false,
  deleted_at = NULL,
  deleted_by = NULL;

DELETE FROM ai_internal.ai_token_issuance;
