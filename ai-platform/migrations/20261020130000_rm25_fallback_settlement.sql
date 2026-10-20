-- RM25: retain the original settlement intent until the DO and D1 usage fact agree.
ALTER TABLE ai_request ADD COLUMN accounting_mode TEXT
  CHECK (accounting_mode IS NULL OR accounting_mode IN ('normal', 'fallback'));
ALTER TABLE ai_request ADD COLUMN accounting_term_id TEXT;
ALTER TABLE ai_request ADD COLUMN accounting_request_id TEXT;
ALTER TABLE ai_request ADD COLUMN accounting_quota_weight INTEGER
  CHECK (accounting_quota_weight IS NULL OR accounting_quota_weight >= 0);
ALTER TABLE ai_request ADD COLUMN accounting_outcome TEXT
  CHECK (accounting_outcome IS NULL OR accounting_outcome IN ('consumed', 'released'));
ALTER TABLE ai_request ADD COLUMN accounting_state TEXT
  CHECK (accounting_state IS NULL OR accounting_state IN ('pending', 'settled'));
ALTER TABLE ai_request ADD COLUMN accounting_receipt_acknowledged INTEGER NOT NULL DEFAULT 0
  CHECK (accounting_receipt_acknowledged IN (0, 1));

CREATE INDEX ai_request_pending_accounting
  ON ai_request (accounting_state, created_at)
  WHERE accounting_state = 'pending';
