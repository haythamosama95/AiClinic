CREATE TABLE notification (
  notification_id TEXT NOT NULL PRIMARY KEY,
  provider_id TEXT NOT NULL,
  channel TEXT NOT NULL,
  hmac_valid INTEGER NOT NULL,
  body_r2_key TEXT NOT NULL,
  body_sha256 TEXT NOT NULL,
  dedupe_key TEXT NOT NULL,
  checkout_id TEXT,
  disposition TEXT NOT NULL,
  adapter_version INTEGER NOT NULL
);

CREATE TABLE inquiry_result (
  inquiry_id TEXT NOT NULL PRIMARY KEY,
  subject TEXT NOT NULL,
  normalized_state TEXT NOT NULL,
  cumulative_reversed_minor INTEGER NOT NULL,
  raw_r2_key TEXT NOT NULL,
  raw_sha256 TEXT NOT NULL,
  at TEXT NOT NULL,
  adapter_version INTEGER NOT NULL
);

CREATE TABLE payment (
  payment_id TEXT NOT NULL PRIMARY KEY,
  reference TEXT NOT NULL,
  org_id TEXT NOT NULL,
  checkout_id TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  amount_minor INTEGER NOT NULL,
  currency TEXT NOT NULL,
  paid_at TEXT NOT NULL,
  confirmed_at TEXT NOT NULL,
  confirmation_inquiry_id TEXT NOT NULL,
  offer_id TEXT NOT NULL,
  offer_version INTEGER NOT NULL,
  billing_contact_version INTEGER NOT NULL,
  classification TEXT NOT NULL,
  disposition TEXT NOT NULL,
  mismatch_detail TEXT,
  evidence_sha256 TEXT NOT NULL
);

CREATE TABLE work (
  work_id TEXT NOT NULL PRIMARY KEY,
  kind TEXT NOT NULL,
  subject_id TEXT NOT NULL,
  dedupe_key TEXT NOT NULL UNIQUE,
  state TEXT NOT NULL,
  attempts INTEGER NOT NULL,
  next_attempt_at TEXT,
  lease_until TEXT,
  last_error TEXT,
  opened_at TEXT NOT NULL
);

CREATE INDEX work_state_next_attempt ON work (state, next_attempt_at);

CREATE TABLE paymob_txn (
  txn_id TEXT NOT NULL PRIMARY KEY,
  order_id TEXT NOT NULL,
  checkout_id TEXT NOT NULL,
  payment_id TEXT,
  parent_txn_id TEXT,
  last_state_key TEXT
);

CREATE TABLE paymob_state_seen (
  dedupe_key TEXT NOT NULL PRIMARY KEY,
  source TEXT NOT NULL,
  first_seen_at TEXT NOT NULL
);

CREATE TABLE notify_rate (
  ip TEXT NOT NULL PRIMARY KEY,
  window_start_ms INTEGER NOT NULL,
  hits INTEGER NOT NULL
);

CREATE TRIGGER notification_abort_update
BEFORE UPDATE ON notification
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER notification_abort_delete
BEFORE DELETE ON notification
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER inquiry_result_abort_update
BEFORE UPDATE ON inquiry_result
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER inquiry_result_abort_delete
BEFORE DELETE ON inquiry_result
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER payment_abort_update
BEFORE UPDATE ON payment
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER payment_abort_delete
BEFORE DELETE ON payment
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;
