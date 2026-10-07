-- =============================================================================
-- P5.2: Coverage feed puller, projection tables, and availability drop.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T008: Extensions, projection tables, feed state singleton, status refresh
-- -----------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE TABLE ai_internal.clinic_ai_coverage (
  organization_id uuid PRIMARY KEY,
  installation_id uuid NOT NULL,
  binding_epoch bigint NOT NULL,
  clinic_seq bigint NOT NULL,
  state text NOT NULL,
  reason text,
  term_ref text,
  plan_display_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  grace_ends_at timestamptz,
  allowance integer,
  used integer,
  band text,
  queued_count integer NOT NULL,
  held_count integer NOT NULL,
  suspended boolean NOT NULL,
  event_at timestamptz NOT NULL,
  applied_at timestamptz NOT NULL
);

ALTER TABLE ai_internal.clinic_ai_coverage ENABLE ROW LEVEL SECURITY;

CREATE POLICY clinic_ai_coverage_deny_all ON ai_internal.clinic_ai_coverage
  FOR ALL
  USING (false);

REVOKE ALL ON TABLE ai_internal.clinic_ai_coverage FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE ai_internal.feed_state (
  singleton boolean PRIMARY KEY CHECK (singleton),
  cursor bigint NOT NULL,
  pending_request_id bigint,
  pending_since timestamptz,
  last_success_at timestamptz,
  consecutive_failures integer NOT NULL
);

ALTER TABLE ai_internal.feed_state ENABLE ROW LEVEL SECURITY;

CREATE POLICY feed_state_deny_all ON ai_internal.feed_state
  FOR ALL
  USING (false);

REVOKE ALL ON TABLE ai_internal.feed_state FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO ai_internal.feed_state (
  singleton,
  cursor,
  pending_request_id,
  pending_since,
  last_success_at,
  consecutive_failures
)
VALUES (
  true,
  0,
  NULL,
  NULL,
  NULL,
  0
);

CREATE TABLE ai_internal.status_refresh (
  organization_id uuid PRIMARY KEY,
  requested_at timestamptz NOT NULL
);

ALTER TABLE ai_internal.status_refresh ENABLE ROW LEVEL SECURITY;

CREATE POLICY status_refresh_deny_all ON ai_internal.status_refresh
  FOR ALL
  USING (false);

REVOKE ALL ON TABLE ai_internal.status_refresh FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- T009: Drop clinic-written availability flag
-- -----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.set_ai_availability(boolean, text);
DROP FUNCTION IF EXISTS auth_internal.set_ai_availability(boolean, text);
DROP FUNCTION IF EXISTS public.get_ai_availability();
DROP FUNCTION IF EXISTS auth_internal.get_ai_availability();

DELETE FROM ai_internal.app_settings
WHERE key = 'ai.availability';
