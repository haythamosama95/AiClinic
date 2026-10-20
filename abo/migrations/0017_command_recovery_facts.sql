ALTER TABLE accepted_operator_command ADD COLUMN recovery_generation INTEGER;
ALTER TABLE accepted_operator_command ADD COLUMN recovery_scope_max_version INTEGER;
ALTER TABLE accepted_operator_command ADD COLUMN recovery_guard INTEGER NOT NULL DEFAULT 0;

CREATE TABLE command_recovery_fact (
  fact_id TEXT NOT NULL PRIMARY KEY,
  command_id TEXT NOT NULL,
  fact_kind TEXT NOT NULL CHECK (fact_kind IN (
    'command_intent', 'relay_reserved', 'platform_result', 'local_result', 'erasure_ack'
  )),
  payload_json TEXT NOT NULL CHECK (length(payload_json) <= 32768),
  payload_sha256 TEXT NOT NULL CHECK (length(payload_sha256) = 64),
  created_at TEXT NOT NULL,
  UNIQUE (command_id, fact_kind, payload_sha256)
);

CREATE INDEX command_recovery_fact_command
  ON command_recovery_fact (command_id, created_at, fact_id);

CREATE TRIGGER command_recovery_fact_abort_update
BEFORE UPDATE ON command_recovery_fact
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER command_recovery_fact_abort_delete
BEFORE DELETE ON command_recovery_fact
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER accepted_operator_command_validate_erasure_fence
BEFORE INSERT ON accepted_operator_command
WHEN NEW.command_kind = 'local_hp' AND NEW.method = 'erase_contact'
  AND NEW.recovery_guard = 1
BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM org_erasure_fence f
    WHERE f.org_id = NEW.target
      AND f.generation = NEW.recovery_generation
  ) THEN RAISE(ABORT, 'erasure_fence_mismatch') END;
  SELECT CASE WHEN (
    SELECT COALESCE(MAX(version), 0)
    FROM billing_contact
    WHERE org_id = NEW.target
  ) != NEW.recovery_scope_max_version
  THEN RAISE(ABORT, 'erasure_scope_changed') END;
END;

