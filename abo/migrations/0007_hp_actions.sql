CREATE TABLE assertion_used (
  challenge_sha256 TEXT NOT NULL PRIMARY KEY
);

CREATE TABLE payment_release (
  payment_id TEXT NOT NULL PRIMARY KEY,
  operator_action_id TEXT NOT NULL,
  at TEXT NOT NULL
);

CREATE TRIGGER assertion_used_abort_update
BEFORE UPDATE ON assertion_used
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER assertion_used_abort_delete
BEFORE DELETE ON assertion_used
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER payment_release_abort_update
BEFORE UPDATE ON payment_release
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER payment_release_abort_delete
BEFORE DELETE ON payment_release
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;
