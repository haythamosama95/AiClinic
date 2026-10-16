CREATE TABLE offer (
  offer_id TEXT NOT NULL PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  contract_version INTEGER NOT NULL
);

CREATE TABLE offer_version (
  offer_id TEXT NOT NULL,
  version INTEGER NOT NULL,
  plan_id TEXT NOT NULL,
  plan_version INTEGER NOT NULL,
  term_unit TEXT NOT NULL,
  term_count INTEGER NOT NULL,
  price_minor INTEGER NOT NULL,
  currency TEXT NOT NULL,
  allowance_credits INTEGER NOT NULL,
  grace_days INTEGER NOT NULL,
  grace_cap_rule TEXT NOT NULL,
  copy TEXT NOT NULL,
  terms_version INTEGER NOT NULL,
  published_by TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL,
  contract_version INTEGER NOT NULL,
  PRIMARY KEY (offer_id, version)
);

CREATE TABLE offer_event (
  offer_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  version INTEGER NOT NULL,
  actor TEXT NOT NULL,
  at TEXT NOT NULL,
  contract_version INTEGER NOT NULL,
  PRIMARY KEY (offer_id, kind, version, at)
);

CREATE TABLE terms_version (
  terms_version INTEGER NOT NULL,
  locale TEXT NOT NULL,
  text_r2_key TEXT NOT NULL,
  text_sha256 TEXT NOT NULL,
  published_by TEXT NOT NULL,
  contract_version INTEGER NOT NULL,
  PRIMARY KEY (terms_version, locale)
);

CREATE TABLE billing_contact (
  org_id TEXT NOT NULL,
  version INTEGER NOT NULL,
  client_request_id TEXT NOT NULL,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT NOT NULL,
  contact_sha256 TEXT NOT NULL,
  created_by_sub TEXT NOT NULL,
  contract_version INTEGER NOT NULL,
  erased_at TEXT,
  erased_by TEXT,
  PRIMARY KEY (org_id, version),
  UNIQUE (org_id, client_request_id)
);

CREATE INDEX billing_contact_org_version ON billing_contact (org_id, version);

CREATE TABLE fact_log (
  fact_seq INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "table" TEXT NOT NULL,
  key TEXT NOT NULL,
  row_sha256 TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE fact_export (
  fact_seq INTEGER NOT NULL PRIMARY KEY,
  exported_at TEXT NOT NULL
);

CREATE TABLE token_use (
  jti TEXT NOT NULL PRIMARY KEY,
  org_id TEXT NOT NULL,
  hits INTEGER NOT NULL
);

CREATE INDEX token_use_org_id ON token_use (org_id);

CREATE TABLE alert (
  alert_key TEXT NOT NULL PRIMARY KEY,
  code TEXT NOT NULL,
  active INTEGER NOT NULL,
  unsent INTEGER NOT NULL,
  last_sent_at TEXT,
  next_send_at TEXT,
  detail_id TEXT NOT NULL
);

CREATE TRIGGER offer_abort_update
BEFORE UPDATE ON offer
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER offer_abort_delete
BEFORE DELETE ON offer
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER offer_version_abort_update
BEFORE UPDATE ON offer_version
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER offer_version_abort_delete
BEFORE DELETE ON offer_version
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER offer_event_abort_update
BEFORE UPDATE ON offer_event
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER offer_event_abort_delete
BEFORE DELETE ON offer_event
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER terms_version_abort_update
BEFORE UPDATE ON terms_version
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER terms_version_abort_delete
BEFORE DELETE ON terms_version
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;
