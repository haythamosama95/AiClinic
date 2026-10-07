CREATE TABLE scheduled_job_run (
  job TEXT PRIMARY KEY,
  last_run_at TEXT NOT NULL
);

CREATE TABLE seen_operator_credential (
  credential_id TEXT NOT NULL,
  public_key_cose TEXT NOT NULL,
  alg TEXT NOT NULL,
  PRIMARY KEY (credential_id, public_key_cose, alg)
);

CREATE TABLE channel_version_seen (
  channel TEXT NOT NULL,
  contract_version INTEGER NOT NULL,
  received INTEGER NOT NULL,
  unsupported INTEGER NOT NULL,
  PRIMARY KEY (channel, contract_version)
);

ALTER TABLE fact_log ADD COLUMN row_json TEXT;
