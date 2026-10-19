-- RM18: durable, org-scoped complimentary ceiling reservations and accepted
-- policy commands. Historical contributions are reconciled from retained DO
-- grants on first use; ambiguous histories remain blocked by the existing
-- grant_claim_backfill gate.
CREATE TABLE complimentary_ceiling_claim (
  grant_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  envelope_sha256 TEXT NOT NULL,
  plan_id TEXT NOT NULL,
  plan_version INTEGER NOT NULL CHECK (plan_version > 0),
  allowance_denominator INTEGER NOT NULL CHECK (allowance_denominator > 0),
  day_contribution INTEGER NOT NULL CHECK (day_contribution >= 0),
  allowance_contribution INTEGER NOT NULL CHECK (allowance_contribution >= 0),
  apply_per_grant_caps INTEGER NOT NULL CHECK (apply_per_grant_caps IN (0, 1)),
  source_reconciled INTEGER NOT NULL DEFAULT 0 CHECK (source_reconciled IN (0, 1)),
  override_authorized INTEGER NOT NULL DEFAULT 0 CHECK (override_authorized IN (0, 1)),
  status TEXT NOT NULL CHECK (status IN ('pending', 'applied', 'sealed_no_effect')),
  receipt TEXT,
  applied_at TEXT,
  created_at TEXT NOT NULL,
  CHECK ((status = 'applied' AND receipt IS NOT NULL AND applied_at IS NOT NULL)
      OR (status = 'pending' AND receipt IS NULL AND applied_at IS NULL)
      OR (status = 'sealed_no_effect' AND receipt IS NOT NULL AND applied_at IS NULL))
);

CREATE INDEX complimentary_ceiling_claim_org_status_time
  ON complimentary_ceiling_claim (org_id, status, applied_at);

CREATE TRIGGER complimentary_ceiling_claim_reserve_guard
BEFORE INSERT ON complimentary_ceiling_claim
WHEN NEW.override_authorized = 0 AND NEW.status = 'pending' AND NEW.source_reconciled = 0
BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1
    FROM ceiling_policy policy
    WHERE policy.version = (SELECT MAX(version) FROM ceiling_policy)
      AND (NEW.apply_per_grant_caps = 0 OR (
        NEW.day_contribution <= policy.per_grant_max_days
        AND (CAST(NEW.allowance_contribution AS REAL) / NEW.allowance_denominator)
            <= policy.per_grant_max_allowance_months
      ))
      AND NEW.day_contribution + COALESCE((
        SELECT SUM(existing.day_contribution)
        FROM complimentary_ceiling_claim existing
        WHERE existing.org_id = NEW.org_id
          AND (existing.status = 'pending' OR (
            existing.status = 'applied'
            AND julianday(existing.applied_at) > julianday(NEW.created_at) - policy.window_days
            AND julianday(existing.applied_at) <= julianday(NEW.created_at)
          ))
      ), 0) <= policy.window_max_days
      AND (CAST(NEW.allowance_contribution AS REAL) / NEW.allowance_denominator)
          + COALESCE((
        SELECT SUM(CAST(existing.allowance_contribution AS REAL) / existing.allowance_denominator)
        FROM complimentary_ceiling_claim existing
        WHERE existing.org_id = NEW.org_id
          AND (existing.status = 'pending' OR (
            existing.status = 'applied'
            AND julianday(existing.applied_at) > julianday(NEW.created_at) - policy.window_days
            AND julianday(existing.applied_at) <= julianday(NEW.created_at)
          ))
      ), 0) <= policy.window_max_allowance_months
  ) THEN RAISE(ABORT, 'complimentary_ceiling_exceeded') END;
END;

CREATE TRIGGER complimentary_ceiling_claim_identity_immutable
BEFORE UPDATE ON complimentary_ceiling_claim
WHEN NEW.grant_id <> OLD.grant_id
  OR NEW.org_id <> OLD.org_id
  OR NEW.envelope_sha256 <> OLD.envelope_sha256
  OR NEW.plan_id <> OLD.plan_id
  OR NEW.plan_version <> OLD.plan_version
  OR NEW.allowance_denominator <> OLD.allowance_denominator
  OR NEW.day_contribution <> OLD.day_contribution
  OR NEW.allowance_contribution <> OLD.allowance_contribution
  OR NEW.apply_per_grant_caps <> OLD.apply_per_grant_caps
  OR NEW.source_reconciled <> OLD.source_reconciled
  OR NEW.override_authorized <> OLD.override_authorized
  OR (OLD.status = 'applied' AND (NEW.receipt <> OLD.receipt OR NEW.applied_at <> OLD.applied_at))
  OR (OLD.status = 'sealed_no_effect' AND NEW.status <> OLD.status)
BEGIN
  SELECT RAISE(ABORT, 'complimentary_ceiling_claim identity is immutable');
END;

CREATE TRIGGER complimentary_ceiling_claim_no_delete_guard
BEFORE DELETE ON complimentary_ceiling_claim
BEGIN
  SELECT RAISE(ABORT, 'complimentary_ceiling_claim is append-only');
END;

CREATE TABLE ceiling_policy_command (
  challenge_sha256 TEXT PRIMARY KEY NOT NULL,
  policy_version INTEGER NOT NULL UNIQUE,
  actor TEXT NOT NULL,
  operation_json TEXT NOT NULL,
  contract_version INTEGER NOT NULL,
  result_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE complimentary_ceiling_claim_backfill (
  org_id TEXT PRIMARY KEY NOT NULL,
  completed_at TEXT NOT NULL
);

CREATE TRIGGER ceiling_policy_command_immutable
BEFORE UPDATE ON ceiling_policy_command
BEGIN
  SELECT RAISE(ABORT, 'ceiling_policy_command is immutable');
END;

CREATE TRIGGER ceiling_policy_command_no_delete
BEFORE DELETE ON ceiling_policy_command
BEGIN
  SELECT RAISE(ABORT, 'ceiling_policy_command is append-only');
END;
