CREATE TABLE deletion_command (
  assertion_sha256 TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  binding_epoch INTEGER NOT NULL,
  reason TEXT NOT NULL,
  accepted_actor TEXT NOT NULL,
  signer_credential_id TEXT NOT NULL,
  accepted_command TEXT NOT NULL,
  phase TEXT NOT NULL CHECK (phase IN ('accepted', 'frozen', 'completed')),
  freeze_inventory TEXT,
  freeze_ack_at TEXT,
  retained_term_ids TEXT,
  held INTEGER CHECK (held IN (0, 1)),
  alert_due INTEGER NOT NULL DEFAULT 0 CHECK (alert_due IN (0, 1)),
  purge_state TEXT NOT NULL CHECK (purge_state IN ('due', 'completed')),
  completion_detail TEXT,
  due_at TEXT NOT NULL,
  lease_until TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX deletion_command_open_org
  ON deletion_command (org_id)
  WHERE phase <> 'completed';

CREATE INDEX deletion_command_due
  ON deletion_command (phase, due_at, lease_until);
