-- RM30: keep usage identity across snapshot recovery and journal erasure.
ALTER TABLE usage_event ADD COLUMN origin_request_id TEXT;
ALTER TABLE usage_event ADD COLUMN accounting_seq INTEGER;

UPDATE usage_event
SET origin_request_id = request_id
WHERE request_id IS NOT NULL AND origin_request_id IS NULL;

CREATE UNIQUE INDEX idx_usage_event_accounting_seq
  ON usage_event (installation_id, accounting_seq)
  WHERE accounting_seq IS NOT NULL;
CREATE UNIQUE INDEX idx_usage_event_origin_request
  ON usage_event (installation_id, origin_request_id)
  WHERE origin_request_id IS NOT NULL;

CREATE TABLE usage_term_retention (
  installation_id TEXT NOT NULL,
  term_id TEXT NOT NULL,
  term_state TEXT NOT NULL,
  ended_at TEXT,
  clinic_seq INTEGER NOT NULL,
  snapshot_sha256 TEXT NOT NULL,
  PRIMARY KEY (installation_id, term_id),
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
);
