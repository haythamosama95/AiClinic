-- P3.1: operator credentials, assertion replay guard, platform alerts, control_audit extensions.

CREATE TABLE operator_credential (
  credential_id TEXT PRIMARY KEY NOT NULL,
  operator_email TEXT NOT NULL,
  public_key_cose TEXT NOT NULL,
  alg TEXT NOT NULL,
  status TEXT NOT NULL,
  activates_at TEXT NOT NULL,
  approved_by TEXT,
  revoked_by TEXT
);

CREATE TABLE assertion_used (
  challenge_sha256 TEXT PRIMARY KEY NOT NULL,
  credential_id TEXT NOT NULL,
  used_at TEXT NOT NULL
);

CREATE TABLE platform_alert (
  alert_key TEXT PRIMARY KEY NOT NULL,
  code TEXT NOT NULL,
  severity TEXT NOT NULL,
  first_at TEXT NOT NULL,
  last_at TEXT NOT NULL,
  count INTEGER NOT NULL,
  send_state TEXT NOT NULL,
  next_send_at TEXT,
  resolved_at TEXT
);

ALTER TABLE control_audit ADD COLUMN actor TEXT;
ALTER TABLE control_audit ADD COLUMN assertion_sha256 TEXT;
