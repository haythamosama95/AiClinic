-- Upgrade procedure for transfers accepted before this table existed:
-- no preparation is backfilled from the tenant-binding mirror alone. An exact
-- beginTransfer replay may adopt a historical transfer only when its accepted
-- audit, assertion_used row, endpoints, and immutable out package/receipt plus
-- route manifest agree. A transfer that had only been begun is re-fenced at
-- both DOs before adoption. Missing or conflicting evidence is quarantined for
-- operator adjudication; do not infer an actor, package, or moved-value route.
CREATE TABLE transfer_preparation (
  transfer_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  from_installation_id TEXT NOT NULL,
  source_epoch INTEGER NOT NULL,
  to_installation_id TEXT NOT NULL,
  destination_epoch INTEGER NOT NULL,
  reason TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL UNIQUE,
  accepted_actor TEXT NOT NULL,
  accepted_signer_credential_id TEXT NOT NULL,
  accepted_command TEXT NOT NULL,
  phase TEXT NOT NULL CHECK (phase IN (
    'accepted', 'destination_ready', 'source_frozen', 'published', 'completed'
  )),
  due_at TEXT NOT NULL,
  lease_token TEXT,
  lease_until TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX transfer_preparation_open_source_epoch
  ON transfer_preparation (org_id, from_installation_id, source_epoch)
  WHERE phase <> 'completed';

CREATE UNIQUE INDEX transfer_preparation_reserved_epoch
  ON transfer_preparation (org_id, destination_epoch);

CREATE INDEX transfer_preparation_due
  ON transfer_preparation (phase, due_at, lease_until);
