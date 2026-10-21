-- R9-AO2 step 2: provider identity of reversals recorded from the provider path, and immutable
-- payout-line links. The reversal table is not changed. Rows in reversal_provider_identity are
-- written only by recordReversalFromProviderTxn, in the same batch as the reversal row. Manual
-- operator reversals write no identity row and therefore can never match a payout line by identity.
-- payout_reversal_link records that one exact payout line matched one recorded reversal. Rows are
-- written only by reconciliation after an exact identity, payment, kind and amount match. Nothing
-- here creates a reversal or a void. Historical payout rows without evidence stay unmatched (D-5).
CREATE TABLE reversal_provider_identity (
  reversal_id TEXT NOT NULL PRIMARY KEY,
  reversal_ref TEXT NOT NULL,
  FOREIGN KEY (reversal_id) REFERENCES reversal (reversal_id)
);

CREATE INDEX reversal_provider_identity_ref ON reversal_provider_identity (reversal_ref);

CREATE TABLE payout_reversal_link (
  import_id TEXT NOT NULL,
  line_no INTEGER NOT NULL,
  reversal_id TEXT NOT NULL,
  PRIMARY KEY (import_id, line_no),
  FOREIGN KEY (import_id, line_no) REFERENCES payout_line_reversal (import_id, line_no),
  FOREIGN KEY (reversal_id) REFERENCES reversal (reversal_id)
);

CREATE INDEX payout_reversal_link_reversal ON payout_reversal_link (reversal_id);

CREATE TRIGGER reversal_provider_identity_abort_update
BEFORE UPDATE ON reversal_provider_identity
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER reversal_provider_identity_abort_delete
BEFORE DELETE ON reversal_provider_identity
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER payout_reversal_link_abort_update
BEFORE UPDATE ON payout_reversal_link
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER payout_reversal_link_abort_delete
BEFORE DELETE ON payout_reversal_link
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;
