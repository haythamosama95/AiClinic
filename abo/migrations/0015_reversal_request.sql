CREATE TABLE reversal_request (
  reversal_id TEXT NOT NULL PRIMARY KEY,
  grant_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  evidence_sha256 TEXT NOT NULL,
  partial INTEGER NOT NULL CHECK (partial = 0),
  contract_version INTEGER NOT NULL,
  canonical_body TEXT NOT NULL,
  body_sha256 TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TRIGGER reversal_request_abort_update
BEFORE UPDATE ON reversal_request
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER reversal_request_abort_delete
BEFORE DELETE ON reversal_request
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;
