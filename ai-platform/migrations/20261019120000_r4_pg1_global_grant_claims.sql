-- R4-PG1: global, immutable grant identity and mutable route metadata.
-- Existing grants are reconciled from retained DO rows and ledger copies by
-- the first grant request for an org. The dispatcher fails closed until that
-- reconciliation has completed; this migration never chooses a winner.
CREATE TABLE grant_claim (
  grant_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  source_kind TEXT NOT NULL CHECK (source_kind IN ('paid', 'complimentary', 'transfer')),
  envelope TEXT NOT NULL,
  envelope_sha256 TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  binding_epoch INTEGER NOT NULL CHECK (binding_epoch > 0),
  route_generation INTEGER NOT NULL CHECK (route_generation > 0),
  state TEXT NOT NULL CHECK (state IN ('pending', 'completed', 'disputed')),
  receipt TEXT,
  created_at TEXT NOT NULL,
  completed_at TEXT,
  CHECK ((state = 'completed' AND receipt IS NOT NULL AND completed_at IS NOT NULL)
      OR (state = 'pending' AND receipt IS NULL AND completed_at IS NULL)
      OR state = 'disputed')
);

CREATE INDEX grant_claim_org_route ON grant_claim (org_id, installation_id, route_generation);

CREATE TABLE grant_claim_backfill (
  org_id TEXT PRIMARY KEY NOT NULL,
  completed_at TEXT NOT NULL
);

CREATE TABLE grant_claim_dispute (
  grant_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  first_at TEXT NOT NULL,
  last_at TEXT NOT NULL,
  count INTEGER NOT NULL
);

CREATE TRIGGER grant_claim_identity_immutable
BEFORE UPDATE ON grant_claim
WHEN NEW.grant_id <> OLD.grant_id
  OR NEW.org_id <> OLD.org_id
  OR NEW.source_kind <> OLD.source_kind
  OR NEW.envelope <> OLD.envelope
  OR NEW.envelope_sha256 <> OLD.envelope_sha256
  OR (OLD.state = 'completed' AND (NEW.receipt <> OLD.receipt OR NEW.completed_at <> OLD.completed_at))
BEGIN
  SELECT RAISE(ABORT, 'grant_claim identity is immutable');
END;

CREATE TRIGGER grant_claim_no_delete
BEFORE DELETE ON grant_claim
BEGIN
  SELECT RAISE(ABORT, 'grant_claim is append-only');
END;
