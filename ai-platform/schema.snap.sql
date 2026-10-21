CREATE TABLE ai_attempt (
  attempt_id TEXT PRIMARY KEY NOT NULL,
  request_id TEXT NOT NULL,
  attempt_no INTEGER NOT NULL,
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  outcome TEXT NOT NULL,
  latency_ms INTEGER NOT NULL,
  tokens_in INTEGER NOT NULL,
  tokens_out INTEGER NOT NULL,
  cost REAL NOT NULL,
  provider_request_id TEXT,
  error_code TEXT,
  FOREIGN KEY (request_id) REFERENCES ai_request (request_id)
);

CREATE TABLE ai_request (
  request_id TEXT PRIMARY KEY NOT NULL,
  
  request_reference TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  actor_id TEXT NOT NULL,
  branch_id TEXT,
  capability_id TEXT NOT NULL,
  capability_version TEXT NOT NULL,
  prompt_artifact_hash TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  state TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT,
  terminal_error_code TEXT,
  trace_id TEXT NOT NULL,
  payload_pointer TEXT,
  routing_tier TEXT,
  routing_decision TEXT,
  conversation_id TEXT,
  turn_ordinal INTEGER, request_fingerprint TEXT, accounting_mode TEXT
  CHECK (accounting_mode IS NULL OR accounting_mode IN ('normal', 'fallback')), accounting_term_id TEXT, accounting_request_id TEXT, accounting_quota_weight INTEGER
  CHECK (accounting_quota_weight IS NULL OR accounting_quota_weight >= 0), accounting_outcome TEXT
  CHECK (accounting_outcome IS NULL OR accounting_outcome IN ('consumed', 'released')), accounting_state TEXT
  CHECK (accounting_state IS NULL OR accounting_state IN ('pending', 'settled')), accounting_receipt_acknowledged INTEGER NOT NULL DEFAULT 0
  CHECK (accounting_receipt_acknowledged IN (0, 1)),
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
);

CREATE TABLE assertion_used (
  challenge_sha256 TEXT PRIMARY KEY NOT NULL,
  credential_id TEXT NOT NULL,
  used_at TEXT NOT NULL
);

CREATE TABLE capability_grant (
  grant_id TEXT PRIMARY KEY NOT NULL,
  scope TEXT NOT NULL,
  capability_id TEXT NOT NULL,
  capability_version TEXT NOT NULL,
  granted_at TEXT NOT NULL,
  revoked_at TEXT,
  changed_at TEXT NOT NULL,
  changed_by TEXT NOT NULL
, lifecycle_state TEXT, successor_id TEXT, deprecated_at TEXT, retire_after TEXT);

CREATE TABLE ceiling_policy (
  version INTEGER PRIMARY KEY NOT NULL,
  per_grant_max_days INTEGER NOT NULL,
  per_grant_max_allowance_months INTEGER NOT NULL,
  window_days INTEGER NOT NULL,
  window_max_days INTEGER NOT NULL,
  window_max_allowance_months INTEGER NOT NULL,
  max_paid_grace_days INTEGER NOT NULL,
  paid_cap_rule TEXT NOT NULL,
  set_by TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL
);

CREATE TABLE ceiling_policy_command (
  challenge_sha256 TEXT PRIMARY KEY NOT NULL,
  policy_version INTEGER NOT NULL UNIQUE,
  actor TEXT NOT NULL,
  operation_json TEXT NOT NULL,
  contract_version INTEGER NOT NULL,
  result_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);

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

CREATE TABLE complimentary_ceiling_claim_backfill (
  org_id TEXT PRIMARY KEY NOT NULL,
  completed_at TEXT NOT NULL
);

CREATE TABLE control_audit (
  audit_id TEXT PRIMARY KEY NOT NULL,
  operator_id TEXT NOT NULL,
  action TEXT NOT NULL,
  target TEXT NOT NULL,
  before_pointer TEXT,
  after_pointer TEXT,
  recorded_at TEXT NOT NULL
, actor TEXT, assertion_sha256 TEXT);

CREATE TABLE coverage_event (
  feed_seq INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  event_id TEXT NOT NULL UNIQUE,
  org_id TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  binding_epoch INTEGER NOT NULL,
  clinic_seq INTEGER NOT NULL,
  kind TEXT NOT NULL,
  snapshot TEXT NOT NULL,
  at TEXT NOT NULL
);

CREATE TABLE coverage_mirror (
  installation_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  binding_epoch INTEGER NOT NULL,
  clinic_seq INTEGER NOT NULL,
  state TEXT NOT NULL,
  suspended INTEGER NOT NULL,
  hard_stop_at TEXT,
  term_snapshot TEXT NOT NULL
);

CREATE TABLE deletion_command (
  assertion_sha256 TEXT PRIMARY KEY NOT NULL,
  freeze_id TEXT NOT NULL,
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

CREATE TABLE fallback_admission (
  installation_id TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  term_id TEXT NOT NULL,
  request_id TEXT NOT NULL,
  weight INTEGER NOT NULL,
  admitted_at TEXT NOT NULL,
  state TEXT NOT NULL, jti TEXT, actor_id TEXT, branch_id TEXT, capability_id TEXT, request_fingerprint TEXT, plan_snapshot TEXT,
  PRIMARY KEY (installation_id, idempotency_key),
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
);

CREATE TABLE feed_consumer (
  consumer TEXT PRIMARY KEY NOT NULL,
  last_pull_at TEXT,
  last_cursor INTEGER
);

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
  completed_at TEXT, accepted_command TEXT, accepted_actor TEXT, signer_credential_id TEXT, assertion_sha256 TEXT, override_assertion_sha256 TEXT, accepted_contract_version INTEGER, accepted_ceiling_policy_version INTEGER, plan_snapshot TEXT, accepted_at TEXT, due_at TEXT, lease_token TEXT, lease_until TEXT, dispatch_attempts INTEGER NOT NULL DEFAULT 0, command_state TEXT NOT NULL DEFAULT 'none'
  CHECK (command_state IN ('none', 'accepted', 'completed', 'rejected')), terminal_code TEXT, terminal_detail TEXT,
  CHECK ((state = 'completed' AND receipt IS NOT NULL AND completed_at IS NOT NULL)
      OR (state = 'pending' AND receipt IS NULL AND completed_at IS NULL)
      OR state = 'disputed')
);

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

CREATE TABLE grant_ledger (
  grant_id TEXT PRIMARY KEY NOT NULL,
  origin_grant_id TEXT NOT NULL,
  org_id TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  operator_credential_id TEXT NOT NULL,
  envelope_sha256 TEXT NOT NULL,
  receipt TEXT NOT NULL,
  applied_at TEXT NOT NULL
, operator_email TEXT);

CREATE TABLE grant_tombstone (
  grant_id TEXT PRIMARY KEY NOT NULL,
  reversal_id TEXT NOT NULL UNIQUE,
  request_sha256 TEXT NOT NULL,
  receipt TEXT NOT NULL,
  export_payload TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE grant_void (
  grant_id TEXT PRIMARY KEY NOT NULL,
  reason TEXT NOT NULL,
  source TEXT NOT NULL,
  evidence_sha256 TEXT NOT NULL,
  at TEXT NOT NULL
);

CREATE TABLE installation (
  installation_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  status TEXT NOT NULL,
  region TEXT NOT NULL,
  enrolled_at TEXT NOT NULL
);

CREATE TABLE issuer_key (
  kid TEXT PRIMARY KEY NOT NULL,
  issuer TEXT NOT NULL,
  public_key TEXT NOT NULL,
  status TEXT NOT NULL,
  not_before TEXT NOT NULL,
  not_after TEXT NOT NULL,
  registered_by TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL
);

CREATE TABLE kill_switch (
  scope TEXT NOT NULL,
  target TEXT NOT NULL,
  active INTEGER NOT NULL,
  changed_at TEXT NOT NULL,
  changed_by TEXT NOT NULL,
  PRIMARY KEY (scope, target)
);

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

CREATE TABLE operator_credential (
  credential_id TEXT PRIMARY KEY NOT NULL,
  operator_email TEXT NOT NULL,
  public_key_cose TEXT NOT NULL,
  alg TEXT NOT NULL,
  status TEXT NOT NULL,
  activates_at TEXT NOT NULL,
  approved_by TEXT,
  revoked_by TEXT
);

CREATE TABLE plan_version (
  plan_id TEXT NOT NULL,
  version INTEGER NOT NULL,
  display_name TEXT NOT NULL,
  capabilities TEXT NOT NULL,
  max_cost_class TEXT NOT NULL,
  concurrency_limit INTEGER NOT NULL,
  max_allowance_per_month INTEGER NOT NULL,
  status TEXT NOT NULL,
  published_by TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL,
  PRIMARY KEY (plan_id, version)
);

CREATE TABLE platform_alert (
  alert_key TEXT PRIMARY KEY NOT NULL,
  code TEXT NOT NULL,
  severity TEXT NOT NULL,
  first_at TEXT NOT NULL,
  last_at TEXT NOT NULL,
  count INTEGER NOT NULL,
  send_state TEXT NOT NULL,
  next_send_at TEXT,
  resolved_at TEXT
);

CREATE TABLE platform_counter (
  counter_id TEXT PRIMARY KEY NOT NULL,
  dimension_set TEXT NOT NULL,
  time_bucket TEXT NOT NULL,
  count INTEGER NOT NULL
);

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

CREATE TABLE routing_policy (
  policy_id TEXT NOT NULL,
  version TEXT NOT NULL,
  content_pointer TEXT NOT NULL,
  active_from TEXT NOT NULL,
  activated_by TEXT NOT NULL, canary_installation_ids TEXT, status TEXT NOT NULL DEFAULT 'published',
  PRIMARY KEY (policy_id, version)
);

CREATE TABLE service_key (
  kid TEXT PRIMARY KEY NOT NULL,
  service TEXT NOT NULL,
  public_key TEXT NOT NULL,
  status TEXT NOT NULL,
  not_before TEXT NOT NULL,
  not_after TEXT NOT NULL,
  registered_by TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL
);

CREATE TABLE stranded_term_recovery (
  action_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  binding_epoch INTEGER NOT NULL,
  target_term_id TEXT NOT NULL UNIQUE,
  source_grant_id TEXT NOT NULL,
  expected_clinic_seq INTEGER NOT NULL,
  reason TEXT NOT NULL,
  request_sha256 TEXT NOT NULL,
  evidence_sha256 TEXT NOT NULL,
  actor_email TEXT NOT NULL,
  credential_id TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL,
  recovered_at TEXT NOT NULL,
  result_json TEXT NOT NULL
);

CREATE TABLE tenant_binding (
  org_id TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  epoch INTEGER NOT NULL,
  status TEXT NOT NULL,
  retired_at TEXT,
  reason TEXT,
  created_at TEXT NOT NULL,
  PRIMARY KEY (org_id, epoch),
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
);

CREATE TABLE token_contract (
  ver TEXT PRIMARY KEY NOT NULL,
  added_at TEXT NOT NULL,
  retired_at TEXT,
  changed_by TEXT NOT NULL
);

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

CREATE TABLE transfer_route_manifest (
  transfer_id TEXT NOT NULL,
  grant_id TEXT NOT NULL,
  source_epoch INTEGER NOT NULL CHECK (source_epoch > 0),
  source_generation INTEGER NOT NULL CHECK (source_generation > 0),
  PRIMARY KEY (transfer_id, grant_id),
  FOREIGN KEY (transfer_id) REFERENCES transfer (transfer_id),
  FOREIGN KEY (grant_id) REFERENCES live_value_route (grant_id)
);

CREATE TABLE transfer_route_quarantine (
  transfer_id TEXT NOT NULL,
  grant_id TEXT NOT NULL DEFAULT '',
  reason TEXT NOT NULL CHECK (reason IN (
    'invalid_export_package',
    'missing_origin_route',
    'route_not_at_authorized_source',
    'receipt_export_mismatch'
  )),
  created_at TEXT NOT NULL,
  PRIMARY KEY (transfer_id, grant_id),
  FOREIGN KEY (transfer_id) REFERENCES transfer (transfer_id)
);

CREATE TABLE transfer_step (
  transfer_id TEXT NOT NULL,
  step TEXT NOT NULL,
  receipt TEXT NOT NULL,
  applied_at TEXT NOT NULL,
  PRIMARY KEY (transfer_id, step),
  FOREIGN KEY (transfer_id) REFERENCES transfer (transfer_id)
);

CREATE TABLE "usage_event" (
  usage_event_id TEXT PRIMARY KEY NOT NULL,
  installation_id TEXT NOT NULL,
  term_id TEXT NOT NULL,
  request_id TEXT,
  quota_weight INTEGER NOT NULL,
  tokens INTEGER NOT NULL,
  cost REAL NOT NULL,
  recorded_at TEXT NOT NULL, origin_request_id TEXT, accounting_seq INTEGER,
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id),
  FOREIGN KEY (request_id) REFERENCES ai_request (request_id) ON DELETE SET NULL
);

CREATE TABLE usage_rollup (
  rollup_id TEXT PRIMARY KEY NOT NULL,
  dimensions TEXT NOT NULL,
  request_count INTEGER NOT NULL,
  tokens INTEGER NOT NULL,
  cost REAL NOT NULL
, quota_weight INTEGER NOT NULL DEFAULT 0);

CREATE TABLE usage_term_retention (
  installation_id TEXT NOT NULL,
  term_id TEXT NOT NULL,
  term_state TEXT NOT NULL,
  ended_at TEXT,
  clinic_seq INTEGER NOT NULL,
  snapshot_sha256 TEXT NOT NULL,
  PRIMARY KEY (installation_id, term_id),
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
);
