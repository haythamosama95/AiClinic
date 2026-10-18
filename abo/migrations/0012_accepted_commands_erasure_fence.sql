ALTER TABLE billing_contact
  ADD COLUMN erasure_generation INTEGER NOT NULL DEFAULT 0;

CREATE TABLE accepted_operator_command (
  challenge_sha256 TEXT NOT NULL PRIMARY KEY,
  command_id TEXT NOT NULL UNIQUE,
  method TEXT NOT NULL,
  args_json TEXT NOT NULL,
  operation_json TEXT NOT NULL,
  assertion_json TEXT,
  actor_email TEXT NOT NULL,
  target TEXT NOT NULL,
  contract_version INTEGER NOT NULL,
  action_id TEXT NOT NULL UNIQUE,
  command_kind TEXT NOT NULL,
  stage TEXT NOT NULL,
  due_at TEXT,
  lease_until TEXT,
  lease_token TEXT,
  result_json TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX accepted_operator_command_due
  ON accepted_operator_command (stage, due_at, lease_until);

CREATE TABLE org_erasure_fence (
  org_id TEXT NOT NULL PRIMARY KEY,
  generation INTEGER NOT NULL DEFAULT 0 CHECK (generation >= 0),
  updated_at TEXT NOT NULL
);

CREATE TABLE raw_evidence_registry (
  evidence_id TEXT NOT NULL PRIMARY KEY,
  org_id TEXT,
  checkout_id TEXT,
  evidence_kind TEXT NOT NULL,
  generation INTEGER,
  r2_key TEXT NOT NULL UNIQUE,
  raw_sha256 TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('quarantined', 'claimed', 'retained', 'delete_pending', 'deleted')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX raw_evidence_registry_org_state
  ON raw_evidence_registry (org_id, state, generation);

CREATE TABLE raw_evidence_cleanup_outbox (
  r2_key TEXT NOT NULL PRIMARY KEY,
  evidence_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('open', 'done')),
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT NOT NULL,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX raw_evidence_cleanup_due
  ON raw_evidence_cleanup_outbox (state, next_attempt_at);

INSERT INTO org_erasure_fence (org_id, generation, updated_at)
SELECT org_id,
       COALESCE(MAX(erasure_generation), 0) +
         CASE WHEN MAX(CASE WHEN erased_at IS NOT NULL THEN 1 ELSE 0 END) = 1 THEN 1 ELSE 0 END,
       '1970-01-01T00:00:00.000Z'
FROM billing_contact
GROUP BY org_id
ON CONFLICT(org_id) DO NOTHING;

INSERT OR IGNORE INTO raw_evidence_registry (
  evidence_id, org_id, checkout_id, evidence_kind, generation,
  r2_key, raw_sha256, state, created_at, updated_at
)
SELECT n.notification_id, c.org_id, n.checkout_id, 'notification', b.erasure_generation,
       n.body_r2_key, n.body_sha256,
       CASE WHEN c.org_id IS NULL OR b.org_id IS NULL THEN 'quarantined'
            WHEN b.erased_at IS NULL THEN 'retained'
            ELSE 'delete_pending' END,
       '1970-01-01T00:00:00.000Z', '1970-01-01T00:00:00.000Z'
FROM notification n
LEFT JOIN checkout c ON c.checkout_id = n.checkout_id
LEFT JOIN billing_contact b
  ON b.org_id = c.org_id AND b.version = c.billing_contact_version
WHERE n.body_r2_key != '';

INSERT OR IGNORE INTO raw_evidence_registry (
  evidence_id, org_id, checkout_id, evidence_kind, generation,
  r2_key, raw_sha256, state, created_at, updated_at
)
SELECT ir.inquiry_id, c.org_id, c.checkout_id, 'inquiry', b.erasure_generation,
       ir.raw_r2_key, ir.raw_sha256,
       CASE WHEN c.org_id IS NULL OR b.org_id IS NULL THEN 'quarantined'
            WHEN b.erased_at IS NULL THEN 'retained'
            ELSE 'delete_pending' END,
       '1970-01-01T00:00:00.000Z', '1970-01-01T00:00:00.000Z'
FROM inquiry_result ir
LEFT JOIN checkout c ON ir.subject = 'checkout:' || c.checkout_id
LEFT JOIN billing_contact b
  ON b.org_id = c.org_id AND b.version = c.billing_contact_version
WHERE ir.raw_r2_key != '';

INSERT OR IGNORE INTO raw_evidence_cleanup_outbox (
  r2_key, evidence_id, reason, state, attempts, next_attempt_at,
  last_error, created_at, updated_at
)
SELECT r2_key, evidence_id, 'migration_erased_contact', 'open', 0,
       '1970-01-01T00:00:00.000Z', NULL,
       '1970-01-01T00:00:00.000Z', '1970-01-01T00:00:00.000Z'
FROM raw_evidence_registry WHERE state = 'delete_pending';
