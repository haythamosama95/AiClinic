-- R9-AO2: immutable adapter-owned identity for each refund or chargeback payout line. The reference
-- is opaque (a hash of the provider transaction identity) and is retained beside the original
-- payout_line, which is unchanged. Rows are written only by an accepted payout import, from the same
-- batch that writes the import and its lines. No row here establishes a reversal: matching against
-- recorded reversals is a separate step, and historical payout rows stay unmatched under D-5.
CREATE TABLE payout_line_reversal (
  import_id TEXT NOT NULL,
  line_no INTEGER NOT NULL,
  reversal_ref TEXT NOT NULL,
  amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
  PRIMARY KEY (import_id, line_no),
  FOREIGN KEY (import_id, line_no) REFERENCES payout_line (import_id, line_no)
);

CREATE INDEX payout_line_reversal_ref ON payout_line_reversal (reversal_ref);

CREATE TRIGGER payout_line_reversal_abort_update
BEFORE UPDATE ON payout_line_reversal
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER payout_line_reversal_abort_delete
BEFORE DELETE ON payout_line_reversal
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;
