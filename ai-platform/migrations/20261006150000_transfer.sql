CREATE TABLE transfer (
  transfer_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  from_installation_id TEXT NOT NULL,
  to_installation_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL,
  package TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE transfer_step (
  transfer_id TEXT NOT NULL,
  step TEXT NOT NULL,
  receipt TEXT NOT NULL,
  applied_at TEXT NOT NULL,
  PRIMARY KEY (transfer_id, step),
  FOREIGN KEY (transfer_id) REFERENCES transfer (transfer_id)
);
