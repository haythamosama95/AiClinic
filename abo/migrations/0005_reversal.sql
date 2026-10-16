ALTER TABLE reversal ADD COLUMN source TEXT NOT NULL;
ALTER TABLE reversal ADD COLUMN cumulative_reversed_minor INTEGER NOT NULL;
ALTER TABLE reversal ADD COLUMN detected_via TEXT NOT NULL;
ALTER TABLE reversal ADD COLUMN recorded_by TEXT NOT NULL;
ALTER TABLE reversal ADD COLUMN evidence_sha256 TEXT NOT NULL;
ALTER TABLE reversal ADD COLUMN effect TEXT NOT NULL;
ALTER TABLE reversal ADD COLUMN dedupe_key TEXT NOT NULL;

CREATE UNIQUE INDEX reversal_dedupe_key ON reversal (dedupe_key);

CREATE TABLE reversal_outcome (
  reversal_id TEXT NOT NULL PRIMARY KEY,
  result TEXT NOT NULL,
  receipt TEXT NOT NULL,
  at TEXT NOT NULL
);

CREATE TABLE finding (
  finding_id TEXT NOT NULL PRIMARY KEY,
  kind TEXT NOT NULL,
  subject TEXT NOT NULL,
  detail TEXT NOT NULL,
  detected_at TEXT NOT NULL
);

CREATE TABLE inquiry_spend (
  minute_key TEXT NOT NULL PRIMARY KEY,
  spent INTEGER NOT NULL
);

CREATE TRIGGER reversal_outcome_abort_update
BEFORE UPDATE ON reversal_outcome
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER reversal_outcome_abort_delete
BEFORE DELETE ON reversal_outcome
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER finding_abort_update
BEFORE UPDATE ON finding
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER finding_abort_delete
BEFORE DELETE ON finding
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;
