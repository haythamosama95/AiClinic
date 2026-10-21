-- Distinguish authentic checkout creation timestamps from historical values
-- synthesized by migration 0011. New checkout writes set `recorded` directly.
ALTER TABLE checkout ADD COLUMN created_at_provenance TEXT NOT NULL DEFAULT 'legacy_unknown'
  CHECK (created_at_provenance IN (
    'recorded', 'fact_log', 'opened_event', 'legacy_unknown', 'expiry_inferred'
  ));

DROP TRIGGER checkout_abort_update;
UPDATE checkout
SET created_at_provenance = CASE
  WHEN EXISTS (
    SELECT 1 FROM fact_log fl
    WHERE fl."table" = 'checkout' AND fl.key = checkout.checkout_id
      AND json_valid(fl.row_json)
      AND json_extract(fl.row_json, '$.created_at') = checkout.created_at
  ) THEN 'fact_log'
  WHEN EXISTS (
    SELECT 1 FROM fact_log fl
    WHERE fl."table" = 'checkout' AND fl.key = checkout.checkout_id
      AND fl.created_at = checkout.created_at
  ) THEN 'fact_log'
  WHEN EXISTS (
    SELECT 1 FROM checkout_event ce
    WHERE ce.checkout_id = checkout.checkout_id AND ce.kind = 'opened'
      AND ce.at = checkout.created_at
  ) THEN 'opened_event'
  ELSE 'expiry_inferred'
END;
CREATE TRIGGER checkout_abort_update
BEFORE UPDATE ON checkout
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TABLE rebuild_inquiry_attempt (
  attempt_id TEXT NOT NULL PRIMARY KEY,
  checkout_id TEXT NOT NULL,
  payment_id TEXT,
  provider_txn_ref TEXT,
  outcome TEXT NOT NULL CHECK (
    outcome IN ('confirmed', 'already_recorded', 'deferred', 'unavailable', 'discovery_unavailable', 'unbound')
  ),
  decision TEXT NOT NULL,
  inquiry_id TEXT,
  evidence_sha256 TEXT,
  observed_at TEXT NOT NULL,
  adapter_version INTEGER NOT NULL,
  FOREIGN KEY (checkout_id) REFERENCES checkout(checkout_id)
);

CREATE TRIGGER rebuild_inquiry_attempt_abort_update
BEFORE UPDATE ON rebuild_inquiry_attempt
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER rebuild_inquiry_attempt_abort_delete
BEFORE DELETE ON rebuild_inquiry_attempt
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;
