-- R4-PG3: persist a verified complimentary command with its assertion claims.
ALTER TABLE grant_ledger ADD COLUMN operator_email TEXT;

ALTER TABLE grant_claim ADD COLUMN accepted_command TEXT;
ALTER TABLE grant_claim ADD COLUMN accepted_actor TEXT;
ALTER TABLE grant_claim ADD COLUMN signer_credential_id TEXT;
ALTER TABLE grant_claim ADD COLUMN assertion_sha256 TEXT;
ALTER TABLE grant_claim ADD COLUMN override_assertion_sha256 TEXT;
ALTER TABLE grant_claim ADD COLUMN accepted_contract_version INTEGER;
ALTER TABLE grant_claim ADD COLUMN accepted_ceiling_policy_version INTEGER;
ALTER TABLE grant_claim ADD COLUMN plan_snapshot TEXT;
ALTER TABLE grant_claim ADD COLUMN accepted_at TEXT;
ALTER TABLE grant_claim ADD COLUMN due_at TEXT;
ALTER TABLE grant_claim ADD COLUMN lease_token TEXT;
ALTER TABLE grant_claim ADD COLUMN lease_until TEXT;
ALTER TABLE grant_claim ADD COLUMN dispatch_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE grant_claim ADD COLUMN command_state TEXT NOT NULL DEFAULT 'none'
  CHECK (command_state IN ('none', 'accepted', 'completed', 'rejected'));
ALTER TABLE grant_claim ADD COLUMN terminal_code TEXT;
ALTER TABLE grant_claim ADD COLUMN terminal_detail TEXT;

CREATE INDEX grant_claim_due_commands
  ON grant_claim (due_at, lease_until)
  WHERE command_state = 'accepted' AND state = 'pending';
