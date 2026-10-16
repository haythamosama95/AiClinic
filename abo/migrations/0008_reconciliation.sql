CREATE TABLE finding_resolution (
  finding_id TEXT NOT NULL PRIMARY KEY,
  resolved_by TEXT NOT NULL,
  note TEXT NOT NULL,
  at TEXT NOT NULL
);

CREATE TABLE payout_import (
  import_id TEXT NOT NULL PRIMARY KEY,
  provider_id TEXT NOT NULL,
  file_sha256 TEXT NOT NULL,
  r2_key TEXT NOT NULL,
  imported_by TEXT NOT NULL,
  period TEXT NOT NULL
);

CREATE INDEX payout_import_period ON payout_import (period);

CREATE TABLE payout_line (
  import_id TEXT NOT NULL,
  line_no INTEGER NOT NULL,
  kind TEXT NOT NULL,
  gross_minor INTEGER NOT NULL,
  fee_minor INTEGER NOT NULL,
  net_minor INTEGER NOT NULL,
  settled_at TEXT NOT NULL,
  payment_id TEXT,
  PRIMARY KEY (import_id, line_no)
);

CREATE INDEX payout_line_payment_id ON payout_line (payment_id);

CREATE TRIGGER finding_resolution_abort_update
BEFORE UPDATE ON finding_resolution
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER finding_resolution_abort_delete
BEFORE DELETE ON finding_resolution
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER payout_import_abort_update
BEFORE UPDATE ON payout_import
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER payout_import_abort_delete
BEFORE DELETE ON payout_import
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER payout_line_abort_update
BEFORE UPDATE ON payout_line
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER payout_line_abort_delete
BEFORE DELETE ON payout_line
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;
