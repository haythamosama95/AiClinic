-- Reset ai_internal operational state to migration defaults.
-- Matches data-journey Stage 2 probe §8.3.1 (empty keystore + default availability).
-- ai.aat.lifetime_minutes must match src/lib/viewer-aat-config.ts (platform max is 10).

DELETE FROM ai_internal.ai_token_issuance;
DELETE FROM ai_internal.installation_keys;

INSERT INTO ai_internal.app_settings (key, value_json, is_deleted)
VALUES
  ('ai.aat.lifetime_minutes', '5'::jsonb, false),
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
