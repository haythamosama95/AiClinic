CREATE TABLE checkout (
  checkout_id TEXT NOT NULL PRIMARY KEY,
  reference TEXT NOT NULL,
  org_id TEXT NOT NULL,
  created_by_sub TEXT NOT NULL,
  billing_token_jti TEXT NOT NULL,
  client_request_id TEXT NOT NULL,
  offer_id TEXT NOT NULL,
  offer_version INTEGER NOT NULL,
  plan_id TEXT NOT NULL,
  plan_version INTEGER NOT NULL,
  term_unit TEXT NOT NULL,
  term_count INTEGER NOT NULL,
  allowance_credits INTEGER NOT NULL,
  grace_days INTEGER NOT NULL,
  grace_cap_rule TEXT NOT NULL,
  list_price_minor INTEGER NOT NULL,
  charged_price_minor INTEGER NOT NULL,
  adjustment_id TEXT,
  currency TEXT NOT NULL,
  terms_version INTEGER NOT NULL,
  billing_contact_version INTEGER NOT NULL,
  billing_contact_sha256 TEXT NOT NULL,
  opened_with_coverage_through TEXT,
  coverage_source TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  initiator TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  contract_version INTEGER NOT NULL,
  UNIQUE (org_id, client_request_id)
);

CREATE INDEX checkout_org_id ON checkout (org_id);

CREATE TABLE checkout_event (
  checkout_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  source TEXT NOT NULL,
  ref TEXT NOT NULL,
  actor TEXT NOT NULL,
  at TEXT NOT NULL,
  contract_version INTEGER NOT NULL,
  PRIMARY KEY (checkout_id, kind, at)
);

CREATE TABLE checkout_status (
  checkout_id TEXT NOT NULL PRIMARY KEY,
  state TEXT NOT NULL,
  last_event_at TEXT NOT NULL
);

CREATE TABLE paymob_intention (
  checkout_id TEXT NOT NULL PRIMARY KEY,
  intention_id TEXT NOT NULL,
  order_id TEXT NOT NULL,
  client_secret TEXT NOT NULL,
  special_reference TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

CREATE TABLE coverage_view (
  org_id TEXT NOT NULL PRIMARY KEY,
  binding_epoch INTEGER NOT NULL,
  clinic_seq INTEGER NOT NULL,
  snapshot TEXT NOT NULL
);

CREATE TABLE feed_cursor (
  id INTEGER NOT NULL PRIMARY KEY,
  feed_seq INTEGER NOT NULL
);

INSERT OR IGNORE INTO feed_cursor (id, feed_seq) VALUES (1, 0);

CREATE TRIGGER checkout_abort_update
BEFORE UPDATE ON checkout
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER checkout_abort_delete
BEFORE DELETE ON checkout
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER checkout_event_abort_update
BEFORE UPDATE ON checkout_event
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER checkout_event_abort_delete
BEFORE DELETE ON checkout_event
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;
