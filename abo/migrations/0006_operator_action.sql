CREATE TABLE operator_action (
  action_id TEXT NOT NULL PRIMARY KEY,
  actor_email TEXT NOT NULL,
  access_jti TEXT NOT NULL,
  action TEXT NOT NULL,
  subject TEXT NOT NULL,
  params_sha256 TEXT NOT NULL,
  assertion_sha256 TEXT,
  result TEXT NOT NULL
);

CREATE TRIGGER operator_action_abort_update
BEFORE UPDATE ON operator_action
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER operator_action_abort_delete
BEFORE DELETE ON operator_action
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;
