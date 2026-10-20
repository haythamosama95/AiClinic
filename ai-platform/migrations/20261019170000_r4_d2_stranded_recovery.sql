CREATE TABLE IF NOT EXISTS stranded_term_recovery (
  action_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  binding_epoch INTEGER NOT NULL,
  target_term_id TEXT NOT NULL UNIQUE,
  source_grant_id TEXT NOT NULL,
  expected_clinic_seq INTEGER NOT NULL,
  reason TEXT NOT NULL,
  request_sha256 TEXT NOT NULL,
  evidence_sha256 TEXT NOT NULL,
  actor_email TEXT NOT NULL,
  credential_id TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL,
  recovered_at TEXT NOT NULL,
  result_json TEXT NOT NULL
);
