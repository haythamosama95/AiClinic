CREATE TABLE grant_request (
  grant_id TEXT NOT NULL PRIMARY KEY,
  org_id TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  source_ref TEXT NOT NULL,
  envelope TEXT NOT NULL,
  envelope_sha256 TEXT NOT NULL,
  assertion TEXT
);

CREATE TABLE grant_outcome (
  grant_id TEXT NOT NULL PRIMARY KEY,
  result TEXT NOT NULL,
  abo_kid TEXT,
  abo_signature TEXT,
  receipt TEXT,
  term_ids TEXT,
  at TEXT NOT NULL
);

CREATE TABLE signing_key_gate (
  id INTEGER NOT NULL PRIMARY KEY,
  paused INTEGER NOT NULL,
  checked_at TEXT NOT NULL
);

CREATE TABLE reversal (
  reversal_id TEXT NOT NULL PRIMARY KEY,
  payment_id TEXT NOT NULL,
  reference TEXT NOT NULL,
  amount_minor INTEGER NOT NULL,
  kind TEXT NOT NULL,
  is_full INTEGER NOT NULL
);

CREATE INDEX reversal_payment_id ON reversal (payment_id);

CREATE TRIGGER grant_request_abort_update
BEFORE UPDATE ON grant_request
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER grant_request_abort_delete
BEFORE DELETE ON grant_request
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER grant_outcome_abort_update
BEFORE UPDATE ON grant_outcome
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER grant_outcome_abort_delete
BEFORE DELETE ON grant_outcome
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER reversal_abort_update
BEFORE UPDATE ON reversal
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER reversal_abort_delete
BEFORE DELETE ON reversal
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;
