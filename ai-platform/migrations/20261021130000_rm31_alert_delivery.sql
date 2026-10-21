-- RM31 (R9-PAL1): durable alert bodies, leased delivery and bounded retry state.
-- Forward-only. Existing rows have no recoverable original body, so they are
-- marked body_state = 'incomplete' (explicit evidence gap, never auto-sent).
ALTER TABLE platform_alert ADD COLUMN body_json TEXT;
ALTER TABLE platform_alert ADD COLUMN body_state TEXT NOT NULL DEFAULT 'incomplete'
  CHECK (body_state IN ('stored', 'incomplete'));
ALTER TABLE platform_alert ADD COLUMN channel_version INTEGER;
ALTER TABLE platform_alert ADD COLUMN origin_event_id TEXT;
ALTER TABLE platform_alert ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE platform_alert ADD COLUMN lease_token TEXT;
ALTER TABLE platform_alert ADD COLUMN lease_expires_at TEXT;

CREATE INDEX platform_alert_due_idx
  ON platform_alert (send_state, body_state, next_send_at);
