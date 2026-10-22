-- FV-M4 (R9-AO2 step 3): operator evidence that one payout refund or chargeback line is the same
-- event as one recorded reversal. Automatic matching in reconciliation is unchanged and still
-- requires a provider identity row; manual evidence is never inferred. The operator action writes
-- the payout_reversal_link row and one payout_reversal_manual_basis row in the same batch, so every
-- manual link has the action and actor that recorded it. Nothing here creates a reversal or a void.
-- Rows are append-only. Historical payout lines without payout_line_reversal evidence stay
-- unmatched (D-5), because the link table references that evidence.
CREATE TABLE payout_reversal_manual_basis (
  import_id TEXT NOT NULL,
  line_no INTEGER NOT NULL,
  action_id TEXT NOT NULL,
  actor_email TEXT NOT NULL,
  recorded_at TEXT NOT NULL,
  PRIMARY KEY (import_id, line_no),
  FOREIGN KEY (import_id, line_no) REFERENCES payout_reversal_link (import_id, line_no)
);

CREATE TRIGGER payout_reversal_manual_basis_abort_update
BEFORE UPDATE ON payout_reversal_manual_basis
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER payout_reversal_manual_basis_abort_delete
BEFORE DELETE ON payout_reversal_manual_basis
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;
