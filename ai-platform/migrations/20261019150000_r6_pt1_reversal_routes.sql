-- R6-PT1: durable routing/idempotency control records.
-- These rows contain identifiers, route state, signed request/receipt replay
-- material and tombstone references; they contain no monetary or term snapshot.
-- The quota DO's term state and route seal remain authoritative for value effects.
CREATE TABLE live_value_route (
  grant_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  binding_epoch INTEGER NOT NULL CHECK (binding_epoch > 0),
  generation INTEGER NOT NULL CHECK (generation > 0),
  state TEXT NOT NULL CHECK (state IN ('stable', 'moving', 'voiding', 'retired')),
  transfer_id TEXT,
  reversal_id TEXT,
  updated_at TEXT NOT NULL,
  CHECK ((state = 'moving' AND transfer_id IS NOT NULL)
      OR state <> 'moving'),
  CHECK ((state = 'voiding' AND reversal_id IS NOT NULL)
      OR state <> 'voiding')
);

INSERT OR IGNORE INTO live_value_route (
  grant_id, org_id, installation_id, binding_epoch, generation, state, updated_at
)
SELECT c.grant_id, c.org_id, c.installation_id, c.binding_epoch, c.route_generation,
       CASE WHEN v.grant_id IS NULL THEN 'stable' ELSE 'retired' END, c.created_at
FROM grant_claim c
LEFT JOIN grant_void v ON v.grant_id = c.grant_id;

CREATE INDEX live_value_route_installation
  ON live_value_route (installation_id, state, generation);

CREATE TRIGGER live_value_route_identity_immutable
BEFORE UPDATE ON live_value_route
WHEN NEW.grant_id <> OLD.grant_id OR NEW.org_id <> OLD.org_id
BEGIN
  SELECT RAISE(ABORT, 'live value route identity is immutable');
END;

CREATE TRIGGER live_value_route_no_delete
BEFORE DELETE ON live_value_route
BEGIN
  SELECT RAISE(ABORT, 'live value route is permanent');
END;

CREATE TABLE reversal_command (
  reversal_id TEXT PRIMARY KEY NOT NULL,
  grant_id TEXT NOT NULL UNIQUE,
  request_sha256 TEXT NOT NULL,
  request_body TEXT NOT NULL,
  route_installation_id TEXT,
  route_epoch INTEGER,
  route_generation INTEGER,
  state TEXT NOT NULL CHECK (state IN ('due', 'terminal')),
  receipt TEXT,
  export_payload TEXT,
  export_state TEXT NOT NULL CHECK (export_state IN ('none', 'due', 'shipped')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  CHECK ((state = 'terminal' AND receipt IS NOT NULL AND export_payload IS NOT NULL
          AND export_state IN ('due', 'shipped'))
      OR (state = 'due' AND receipt IS NULL AND export_payload IS NULL
          AND export_state = 'none'))
);

CREATE TRIGGER reversal_command_identity_immutable
BEFORE UPDATE ON reversal_command
WHEN NEW.reversal_id <> OLD.reversal_id
  OR NEW.grant_id <> OLD.grant_id
  OR NEW.request_sha256 <> OLD.request_sha256
  OR NEW.request_body <> OLD.request_body
  OR NEW.created_at <> OLD.created_at
  OR (OLD.state = 'terminal' AND (NEW.receipt <> OLD.receipt
      OR NEW.export_payload <> OLD.export_payload))
BEGIN
  SELECT RAISE(ABORT, 'reversal command identity is immutable');
END;

CREATE TRIGGER reversal_command_no_delete
BEFORE DELETE ON reversal_command
BEGIN
  SELECT RAISE(ABORT, 'reversal command is permanent');
END;

CREATE TABLE grant_tombstone (
  grant_id TEXT PRIMARY KEY NOT NULL,
  reversal_id TEXT NOT NULL UNIQUE,
  request_sha256 TEXT NOT NULL,
  receipt TEXT NOT NULL,
  export_payload TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TRIGGER grant_tombstone_no_update
BEFORE UPDATE ON grant_tombstone
BEGIN
  SELECT RAISE(ABORT, 'grant tombstone is immutable');
END;

CREATE TRIGGER grant_tombstone_no_delete
BEFORE DELETE ON grant_tombstone
BEGIN
  SELECT RAISE(ABORT, 'grant tombstone is permanent');
END;
