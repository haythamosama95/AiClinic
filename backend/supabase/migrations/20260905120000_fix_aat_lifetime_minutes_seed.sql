-- Align default AAT lifetime with the AI platform MAX_AAT_LIFETIME_SECONDS ceiling (600 s).
-- Platform identity guard rejects tokens where exp - iat > 600; seed must be <= 10 minutes.

INSERT INTO ai_internal.app_settings (key, value_json)
VALUES ('ai.aat.lifetime_minutes', '10'::jsonb)
ON CONFLICT (key) DO UPDATE
SET value_json = EXCLUDED.value_json;
