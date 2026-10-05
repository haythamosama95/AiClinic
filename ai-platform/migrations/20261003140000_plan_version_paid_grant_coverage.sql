CREATE TABLE service_key (
  kid TEXT PRIMARY KEY NOT NULL,
  service TEXT NOT NULL,
  public_key TEXT NOT NULL,
  status TEXT NOT NULL,
  not_before TEXT NOT NULL,
  not_after TEXT NOT NULL,
  registered_by TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL
);

CREATE TABLE plan_version (
  plan_id TEXT NOT NULL,
  version INTEGER NOT NULL,
  display_name TEXT NOT NULL,
  capabilities TEXT NOT NULL,
  max_cost_class TEXT NOT NULL,
  concurrency_limit INTEGER NOT NULL,
  max_allowance_per_month INTEGER NOT NULL,
  status TEXT NOT NULL,
  published_by TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL,
  PRIMARY KEY (plan_id, version)
);

CREATE TABLE coverage_event (
  feed_seq INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  event_id TEXT NOT NULL UNIQUE,
  org_id TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  binding_epoch INTEGER NOT NULL,
  clinic_seq INTEGER NOT NULL,
  kind TEXT NOT NULL,
  snapshot TEXT NOT NULL,
  at TEXT NOT NULL
);

CREATE TRIGGER coverage_event_no_update
BEFORE UPDATE ON coverage_event
BEGIN
  SELECT RAISE(ABORT, 'coverage_event is append-only');
END;

CREATE TRIGGER coverage_event_no_delete
BEFORE DELETE ON coverage_event
BEGIN
  SELECT RAISE(ABORT, 'coverage_event is append-only');
END;

CREATE TABLE grant_ledger (
  grant_id TEXT PRIMARY KEY NOT NULL,
  origin_grant_id TEXT NOT NULL,
  org_id TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  operator_credential_id TEXT NOT NULL,
  envelope_sha256 TEXT NOT NULL,
  receipt TEXT NOT NULL,
  applied_at TEXT NOT NULL
);

CREATE INDEX grant_ledger_org_applied_at ON grant_ledger (org_id, applied_at);

CREATE INDEX grant_ledger_origin_grant_id ON grant_ledger (origin_grant_id);

CREATE INDEX grant_ledger_operator_applied_at ON grant_ledger (operator_credential_id, applied_at);

CREATE TRIGGER grant_ledger_no_update
BEFORE UPDATE ON grant_ledger
BEGIN
  SELECT RAISE(ABORT, 'grant_ledger is append-only');
END;

CREATE TRIGGER grant_ledger_no_delete
BEFORE DELETE ON grant_ledger
BEGIN
  SELECT RAISE(ABORT, 'grant_ledger is append-only');
END;

CREATE TABLE coverage_mirror (
  installation_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  binding_epoch INTEGER NOT NULL,
  clinic_seq INTEGER NOT NULL,
  state TEXT NOT NULL,
  suspended INTEGER NOT NULL,
  hard_stop_at TEXT,
  term_snapshot TEXT NOT NULL
);
