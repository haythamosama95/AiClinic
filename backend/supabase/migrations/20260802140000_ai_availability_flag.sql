-- E4: clinic-side AI availability flag (enrolled + platform base URL).

INSERT INTO ai_internal.app_settings (key, value_json)
VALUES (
  'ai.availability',
  '{"enrolled": false, "platform_base_url": null}'::jsonb
)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION auth_internal.get_ai_availability()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ai_internal
AS $$
  SELECT COALESCE(
    (
      SELECT s.value_json
      FROM ai_internal.app_settings s
      WHERE s.key = 'ai.availability'
        AND s.is_deleted = false
    ),
    '{"enrolled": false, "platform_base_url": null}'::jsonb
  );
$$;

CREATE OR REPLACE FUNCTION public.get_ai_availability()
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_ai_availability();
$$;

REVOKE ALL ON FUNCTION public.get_ai_availability() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ai_availability() TO authenticated;
