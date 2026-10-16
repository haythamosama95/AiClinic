-- F3: detach ledger FK so journal purge can expire ai_request + ai_attempt at 90d
-- while usage_event survives the ledger horizon; add purge/support indexes.

PRAGMA foreign_keys = OFF;

CREATE TABLE usage_event_new (
  usage_event_id TEXT PRIMARY KEY NOT NULL,
  installation_id TEXT NOT NULL,
  period TEXT NOT NULL,
  request_id TEXT,
  quota_weight INTEGER NOT NULL,
  tokens INTEGER NOT NULL,
  cost REAL NOT NULL,
  recorded_at TEXT NOT NULL,
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id),
  FOREIGN KEY (request_id) REFERENCES ai_request (request_id) ON DELETE SET NULL
);

INSERT INTO usage_event_new (
  usage_event_id, installation_id, period, request_id, quota_weight, tokens, cost, recorded_at
)
SELECT
  usage_event_id, installation_id, period, request_id, quota_weight, tokens, cost, recorded_at
FROM usage_event;

DROP TABLE usage_event;
ALTER TABLE usage_event_new RENAME TO usage_event;

PRAGMA foreign_keys = ON;

CREATE INDEX idx_ai_attempt_request_id ON ai_attempt (request_id);
CREATE INDEX idx_usage_event_request_id ON usage_event (request_id);
CREATE INDEX idx_usage_event_installation_id ON usage_event (installation_id);
CREATE INDEX idx_ai_request_installation_id ON ai_request (installation_id);
CREATE INDEX idx_ai_request_created_at ON ai_request (created_at);
CREATE INDEX idx_usage_rollup_period ON usage_rollup (json_extract(dimensions, '$.period'));
CREATE INDEX idx_platform_counter_installation
  ON platform_counter (json_extract(dimension_set, '$.installation_id'));
