-- P3.4: usage_event.term_id replaces period; rollup keyed by term_id.

PRAGMA foreign_keys = OFF;

CREATE TABLE usage_event_new (
  usage_event_id TEXT PRIMARY KEY NOT NULL,
  installation_id TEXT NOT NULL,
  term_id TEXT NOT NULL,
  request_id TEXT,
  quota_weight INTEGER NOT NULL,
  tokens INTEGER NOT NULL,
  cost REAL NOT NULL,
  recorded_at TEXT NOT NULL,
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id),
  FOREIGN KEY (request_id) REFERENCES ai_request (request_id) ON DELETE SET NULL
);

INSERT INTO usage_event_new (
  usage_event_id, installation_id, term_id, request_id, quota_weight, tokens, cost, recorded_at
)
SELECT
  usage_event_id, installation_id, period, request_id, quota_weight, tokens, cost, recorded_at
FROM usage_event;

DROP TABLE usage_event;
ALTER TABLE usage_event_new RENAME TO usage_event;

PRAGMA foreign_keys = ON;

DROP INDEX IF EXISTS idx_usage_event_request_id;
CREATE UNIQUE INDEX idx_usage_event_request_id ON usage_event (request_id);
CREATE INDEX IF NOT EXISTS idx_usage_event_installation_id ON usage_event (installation_id);

DELETE FROM usage_rollup;
DROP INDEX IF EXISTS idx_usage_rollup_period;
CREATE INDEX idx_usage_rollup_term_id ON usage_rollup (json_extract(dimensions, '$.term_id'));
